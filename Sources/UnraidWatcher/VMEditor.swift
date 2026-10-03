// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import Foundation
import SwiftUI

// MARK: - Spec & XML generation

struct VMSpec {
    enum OS: String, CaseIterable, Identifiable { case linux = "Linux", windows = "Windows 10 / Server"; var id: String { rawValue } }
    var name = ""
    var os: OS = .linux
    var uefi = true
    var vcpus = 2
    var memGiB = 4
    var diskDir = "/mnt/user/domains"
    var diskGB = 30
    var existingDisk = ""            // when set, no new image is created
    var diskBus = "virtio"
    var iso = ""
    var driverISO = ""
    var bridge = "br0"
    var nic = "virtio-net"
    var autostart = false
    var startAfter = false
    var diskPath: String { existingDisk.isEmpty ? "\(diskDir)/\(name)/vdisk1.img" : existingDisk }
}

func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "'", with: "&apos;").replacingOccurrences(of: "\"", with: "&quot;")
}
func validPath(_ s: String) -> Bool { s.range(of: #"^/[A-Za-z0-9 _./+-]+$"#, options: .regularExpression) != nil && !s.contains("..") }

func domainXML(_ v: VMSpec, uuid: String) -> String {
    let win = v.os == .windows
    let kib = v.memGiB * 1024 * 1024
    let name = xmlEscape(v.name)
    let osAttrs = win ? "name=\"Windows 10\" icon=\"windows.png\" os=\"windows10\"" : "name=\"Linux\" icon=\"linux.png\" os=\"linux\""
    let firmware = v.uefi ? """
        <loader readonly='yes' type='pflash'>/usr/share/qemu/ovmf-x64/OVMF_CODE-pure-efi.fd</loader>
        <nvram template='/usr/share/qemu/ovmf-x64/OVMF_VARS-pure-efi.fd'>/etc/libvirt/qemu/nvram/\(uuid)_VARS-pure-efi.fd</nvram>
    """ : ""
    let features = win ? """
      <features>
        <acpi/><apic/>
        <hyperv mode='custom'><relaxed state='on'/><vapic state='on'/><spinlocks state='on' retries='8191'/><vendor_id state='on' value='none'/></hyperv>
      </features>
    """ : "  <features><acpi/><apic/></features>"
    let clock = win ? """
      <clock offset='localtime'>
        <timer name='hypervclock' present='yes'/><timer name='hpet' present='no'/>
      </clock>
    """ : """
      <clock offset='utc'>
        <timer name='rtc' tickpolicy='catchup'/><timer name='pit' tickpolicy='delay'/><timer name='hpet' present='no'/>
      </clock>
    """
    let isoXML = v.iso.isEmpty ? "" : """
        <disk type='file' device='cdrom'>
          <driver name='qemu' type='raw'/><source file='\(xmlEscape(v.iso))'/><target dev='hda' bus='sata'/><readonly/><boot order='1'/>
        </disk>
    """
    let driverXML = v.driverISO.isEmpty ? "" : """
        <disk type='file' device='cdrom'>
          <driver name='qemu' type='raw'/><source file='\(xmlEscape(v.driverISO))'/><target dev='hdb' bus='sata'/><readonly/>
        </disk>
    """
    let dev = v.diskBus == "virtio" ? "vda" : "hdc"
    return """
    <domain type='kvm'>
      <name>\(name)</name>
      <uuid>\(uuid)</uuid>
      <metadata><vmtemplate xmlns="unraid" \(osAttrs) webui=""/></metadata>
      <memory unit='KiB'>\(kib)</memory>
      <currentMemory unit='KiB'>\(kib)</currentMemory>
      <vcpu placement='static'>\(v.vcpus)</vcpu>
      <os>
        <type arch='x86_64' machine='q35'>hvm</type>
    \(firmware)
      </os>
    \(features)
      <cpu mode='host-passthrough' check='none'>
        <topology sockets='1' dies='1' cores='\(v.vcpus)' threads='1'/>
        <cache mode='passthrough'/>
      </cpu>
    \(clock)
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>restart</on_crash>
      <devices>
        <emulator>/usr/local/sbin/qemu</emulator>
        <disk type='file' device='disk'>
          <driver name='qemu' type='raw' cache='writeback'/>
          <source file='\(xmlEscape(v.diskPath))'/>
          <target dev='\(dev)' bus='\(v.diskBus)'/>
          <boot order='\(v.iso.isEmpty ? 1 : 2)'/>
        </disk>
    \(isoXML)
    \(driverXML)
        <interface type='bridge'>
          <source bridge='\(xmlEscape(v.bridge))'/>
          <model type='\(xmlEscape(v.nic))'/>
        </interface>
        <serial type='pty'><target type='isa-serial' port='0'><model name='isa-serial'/></target></serial>
        <console type='pty'><target type='serial' port='0'/></console>
        <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>
        <input type='tablet' bus='usb'/>
        <input type='mouse' bus='ps2'/>
        <input type='keyboard' bus='ps2'/>
        <graphics type='vnc' port='-1' autoport='yes' websocket='-1' listen='0.0.0.0' keymap='en-us'>
          <listen type='address' address='0.0.0.0'/>
        </graphics>
        <video><model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/></video>
        <memballoon model='virtio'/>
      </devices>
    </domain>
    """
}


func createScript(_ v: VMSpec) -> String {
        let n = shq(v.name), xml = domainXML(v, uuid: UUID().uuidString.lowercased())
        let dir = shq("\(v.diskDir)/\(v.name)"), img = shq(v.diskPath)
        let makeDisk = v.existingDisk.isEmpty ? """
        mkdir -p \(dir) || exit 5
        if [ -e \(img) ]; then
          # an image that was never written to is a leftover from a failed attempt, so it's safe to replace
          [ "$(du -k \(img) | cut -f1)" = "0" ] && rm -f \(img) || { echo "A disk image already exists at \(v.diskPath)"; exit 3; }
        fi
        qemu-img create -f raw \(img) \(v.diskGB)G 2>&1 || exit 6
        NEWDISK=1
        chown -R nobody:users \(dir) 2>/dev/null
        """ : #"[ -e \#(img) ] || { echo "Disk image not found"; exit 3; }"#
        let rollback = v.existingDisk.isEmpty ? "[ \"$NEWDISK\" = 1 ] && { rm -f \(img); rmdir \(dir) 2>/dev/null; }" : ""
        let script = """
        virsh dominfo \(n) >/dev/null 2>&1 && { echo "A VM named \(v.name) already exists"; exit 4; }
        \(makeDisk)
        cat > /tmp/uw-newvm.xml <<'UWXML'
        \(xml)
        UWXML
        virsh define /tmp/uw-newvm.xml 2>&1 || { rm -f /tmp/uw-newvm.xml; \(rollback); exit 7; }
        rm -f /tmp/uw-newvm.xml
        \(v.autostart ? "virsh autostart \(n) 2>&1" : "")
        \(v.startAfter ? "virsh start \(n) 2>&1" : "")
        echo UW_OK
        """
    return script
}

// MARK: - Store

extension Store {
    private func runVMScript(_ script: String) async -> (ok: Bool, output: String) {
        guard let out = await ssh(script + "\n", allowFailure: true) else { return (false, "") }
        return (out.contains("UW_OK"), out.replacingOccurrences(of: "UW_OK", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func listISOs() async -> [String] {
        let out = await ssh("ls -1 /mnt/user/isos 2>/dev/null", allowFailure: true) ?? ""
        return out.split(separator: "\n").map(String.init).filter { $0.lowercased().hasSuffix(".iso") || $0.lowercased().hasSuffix(".img") }
            .map { "/mnt/user/isos/\($0)" }
    }

    func listBridges() async -> [String] {
        let out = await ssh(#"for d in /sys/class/net/*/bridge; do [ -d "$d" ] && basename "$(dirname "$d")"; done; [ -d /sys/class/net/virbr0 ] && echo virbr0"#, allowFailure: true) ?? ""
        let b = out.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("docker") && !$0.hasPrefix("br-") }
        return Array(NSOrderedSet(array: b)) as? [String] ?? b
    }

    func createVM(_ v: VMSpec) async -> Bool {
        guard validShareName(v.name) else { show("VM names can use letters, numbers, spaces, _ - . (max 61 chars).", error: true); return false }
        guard validPath(v.diskPath), v.iso.isEmpty || validPath(v.iso), v.driverISO.isEmpty || validPath(v.driverISO), validPath(v.diskDir) else {
            show("A path contains characters that aren't allowed.", error: true); return false
        }
        guard v.bridge.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else { show("Bad network bridge name.", error: true); return false }
        let script = createScript(v)
        let r = await runVMScript(script)
        await refresh()
        if r.ok { show("Created VM \(v.name)\(v.startAfter ? " and started it" : "")") }
        else { show("Couldn't create the VM: \(r.output.isEmpty ? "unknown error" : r.output)", error: true) }
        return r.ok
    }

    func vmXML(_ name: String) async -> String? {
        let out = await ssh("virsh dumpxml --inactive \(shq(name)) 2>&1", allowFailure: true)
        guard let out, out.contains("<domain") else { show("Couldn't read the VM definition: \(out ?? "no SSH")", error: true); return nil }
        return out
    }

    func defineVM(xml: String, label: String) async -> Bool {
        guard !xml.contains("UWXML") else { show("XML contains a reserved word.", error: true); return false }
        let script = """
        cat > /tmp/uw-edit.xml <<'UWXML'
        \(xml)
        UWXML
        virsh define /tmp/uw-edit.xml 2>&1 && echo UW_OK
        rm -f /tmp/uw-edit.xml
        """
        let r = await runVMScript(script)
        await refresh()
        if r.ok { show("\(label) saved - restart the VM for it to take effect") }
        else { show("libvirt rejected the change: \(r.output)", error: true) }
        return r.ok
    }

    func removeVM(_ name: String) async -> Bool {
        let n = shq(name)
        let r = await runVMScript("""
        st=$(virsh domstate \(n) 2>&1)
        case "$st" in "shut off"*) ;; *) echo "VM is $st - shut it down first"; exit 2;; esac
        virsh undefine \(n) --nvram 2>&1 && echo UW_OK
        """)
        await refresh()
        if r.ok { show("Removed VM \(name). Its disk images were kept.") } else { show("Couldn't remove \(name): \(r.output)", error: true) }
        return r.ok
    }
}

// MARK: - Create sheet

struct VMCreateSheet: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    @State private var v = VMSpec()
    @State private var isos: [String] = []
    @State private var bridges: [String] = []
    @State private var busy = false
    @State private var useExisting = false

    var maxCPUs: Int { max(s.overview?.info?.cpu?.threads ?? 16, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New virtual machine").font(.title3.bold())
            Form {
                TextField("Name", text: $v.name)
                Picker("Operating system", selection: $v.os) { ForEach(VMSpec.OS.allCases) { Text($0.rawValue).tag($0) } }
                    .onChange(of: v.os) { _, os in v.diskBus = os == .windows ? "sata" : "virtio"; v.nic = os == .windows ? "e1000" : "virtio-net" }
                Picker("Firmware", selection: $v.uefi) { Text("OVMF (UEFI)").tag(true); Text("SeaBIOS (legacy)").tag(false) }
                Stepper("vCPUs: \(v.vcpus)", value: $v.vcpus, in: 1...maxCPUs)
                Stepper("Memory: \(v.memGiB) GiB", value: $v.memGiB, in: 1...512)
                Toggle("Use an existing disk image", isOn: $useExisting).onChange(of: useExisting) { _, on in if !on { v.existingDisk = "" } }
                if useExisting { TextField("Disk image path", text: $v.existingDisk, prompt: Text("/mnt/user/domains/…/vdisk1.img")) }
                else {
                    TextField("Disk folder", text: $v.diskDir)
                    Stepper("New disk size: \(v.diskGB) GB (sparse)", value: $v.diskGB, in: 1...4000, step: 5)
                }
                Picker("Disk bus", selection: $v.diskBus) { Text("VirtIO (fastest, needs drivers on Windows)").tag("virtio"); Text("SATA (works everywhere)").tag("sata") }
                Picker("Install ISO", selection: $v.iso) { Text("None").tag(""); ForEach(isos, id: \.self) { Text(($0 as NSString).lastPathComponent).tag($0) } }
                if v.os == .windows { Picker("VirtIO drivers ISO", selection: $v.driverISO) { Text("None").tag(""); ForEach(isos, id: \.self) { Text(($0 as NSString).lastPathComponent).tag($0) } } }
                Picker("Network bridge", selection: $v.bridge) {
                    ForEach(bridges.isEmpty ? [v.bridge] : bridges, id: \.self) { Text($0).tag($0) }
                }
                Picker("Network adapter", selection: $v.nic) { Text("VirtIO").tag("virtio-net"); Text("Intel e1000").tag("e1000") }
                Toggle("Start with the array", isOn: $v.autostart)
                Toggle("Start the VM now", isOn: $v.startAfter)
            }.formStyle(.grouped)
            Text("Creates a standard KVM VM with VNC graphics. GPU/USB passthrough, TPM (Windows 11) and other extras can be added afterwards in the XML editor.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create VM") { busy = true; Task { let ok = await s.createVM(v); busy = false; if ok { dismiss() } } }
                    .keyboardShortcut(.defaultAction).disabled(busy || v.name.isEmpty)
            }
        }
        .padding().frame(width: 600)
        .task {
            isos = await s.listISOs(); bridges = await s.listBridges()
            if let b = bridges.first(where: { $0 == "br0" }) ?? bridges.first { v.bridge = b }
        }
    }
}

// MARK: - Edit sheet

struct VMEditSheet: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    let vm: VM
    @State private var xml = ""
    @State private var original = ""
    @State private var tab = 0
    @State private var vcpus = 1
    @State private var memGiB = 1
    @State private var busy = false
    @State private var confirmRemove = false

    var name: String { vm.name ?? vm.id }

    func firstInt(_ pattern: String, in text: String) -> Int? {
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Int(text[r].filter(\.isNumber))
    }
    func parse() {
        vcpus = firstInt(#"(?<=<vcpu[^>]{0,80}>)\d+"#, in: xml) ?? firstInt(#"<vcpu[^>]*>\d+"#, in: xml) ?? 1
        let kib = firstInt(#"<memory[^>]*>\d+"#, in: xml) ?? 1_048_576
        memGiB = max(1, Int((Double(kib) / 1_048_576).rounded()))
    }
    func edited() -> String? {
        var x = xml
        func sub(_ pattern: String, _ template: String) { x = x.replacingOccurrences(of: pattern, with: template, options: .regularExpression) }
        let kib = memGiB * 1_048_576
        sub(#"(<vcpu[^>]*>)\d+(</vcpu>)"#, "$1\(vcpus)$2")
        sub(#"(<memory[^>]*>)\d+(</memory>)"#, "$1\(kib)$2")
        sub(#"(<currentMemory[^>]*>)\d+(</currentMemory>)"#, "$1\(kib)$2")
        sub(#"(<memory )unit='[A-Za-z]+'"#, "$1unit='KiB'"); sub(#"(<currentMemory )unit='[A-Za-z]+'"#, "$1unit='KiB'")
        if x.contains("<topology") {
            guard x.range(of: #"sockets='1'[^>]*threads='1'|threads='1'[^>]*sockets='1'"#, options: .regularExpression) != nil else {
                s.show("This VM has a custom CPU topology - change vCPUs in the XML tab instead.", error: true); return nil
            }
            sub(#"(<topology[^>]*cores=')\d+(')"#, "$1\(vcpus)$2")
        }
        // pins for CPUs that no longer exist would make libvirt reject the definition
        if x.contains("<vcpupin") {
            x = x.replacingOccurrences(of: #"\s*<vcpupin vcpu='(\d+)'[^>]*/>"#, with: "", options: .regularExpression)
            x = x.replacingOccurrences(of: #"\s*<emulatorpin[^>]*/>"#, with: "", options: .regularExpression)
        }
        return x
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Edit \(name)").font(.title3.bold()); Pill(text: vm.state ?? "-", color: stateColor(vm.state)); Spacer()
                Picker("", selection: $tab) { Text("Basics").tag(0); Text("Media").tag(2); Text("XML").tag(1) }.pickerStyle(.segmented).frame(width: 240)
            }
            if tab == 0 {
                Form {
                    Stepper("vCPUs: \(vcpus)", value: $vcpus, in: 1...max(s.overview?.info?.cpu?.threads ?? 64, 1))
                    Stepper("Memory: \(memGiB) GiB", value: $memGiB, in: 1...512)
                }.formStyle(.grouped).frame(height: 130)
                Text("Applied to the saved definition; a running VM picks the change up after it's shut down and started again. Rename, disks, GPU, USB and network changes are in the XML tab.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                GroupBox("Remove") {
                    HStack {
                        Text("Deletes the VM definition only - disk images are kept. The VM must be shut off.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove VM…", role: .destructive) { confirmRemove = true }
                    }.padding(4)
                }
            } else if tab == 2 {
                VMMediaTab(name: name)
            } else {
                TextEditor(text: $xml).font(.system(size: 11, design: .monospaced)).padding(4)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                Text("libvirt validates the XML when you save; a bad edit is rejected and the VM stays as it was.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Button("Reload") { Task { await load() } }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if tab != 2 { Button(tab == 0 ? "Apply" : "Save XML") {
                    guard let out = tab == 0 ? edited() : xml else { return }
                    busy = true
                    Task { let ok = await s.defineVM(xml: out, label: name); busy = false; if ok { await load() } }
                }.keyboardShortcut(.defaultAction).disabled(busy || xml.isEmpty || (tab == 1 && xml == original)) }
            }
        }
        .padding().frame(width: 760, height: 580)
        .task { await load() }
        .confirmationDialog("Remove \(name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove VM definition", role: .destructive) { Task { if await s.removeVM(name) { dismiss() } } }
        } message: { Text("Disk images stay on the array. This can't be undone, but you can re-create the VM against the same disk.") }
    }
    func load() async {
        if let x = await s.vmXML(name) { xml = x; original = x; parse() }
    }
}
