import Foundation
import SwiftUI
import AppKit

// MARK: - Clone planning (pure, testable)

struct ClonePlan {
    var xml: String
    var copies: [(from: String, to: String)]
    var nvram: (from: String, to: String)?
}
enum CloneError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

func planClone(xml: String, old: String, new: String, uuid: String) throws -> ClonePlan {
    var x = xml
    func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators]) }
    func matches(_ p: String, _ s: String) -> [NSTextCheckingResult] { rx(p).matches(in: s, range: NSRange(s.startIndex..., in: s)) }
    func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String { Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }

    // Disks
    var copies: [(String, String)] = []
    for m in matches(#"<disk [^>]*device='disk'[^>]*>.*?</disk>"#, x) {
        let block = group(m, 0, in: x)
        if block.contains("type='block'") { throw CloneError.message("This VM uses a physical disk device, which can't be cloned automatically.") }
        guard let sm = matches(#"<source file='([^']+)'"#, block).first else { continue }
        let from = group(sm, 1, in: block)
        guard validPath(from) else { throw CloneError.message("Disk path has characters that aren't allowed: \(from)") }
        let url = URL(fileURLWithPath: from)
        let dir = url.deletingLastPathComponent(), base = url.lastPathComponent
        let to = dir.lastPathComponent == old ? dir.deletingLastPathComponent().appendingPathComponent(new).appendingPathComponent(base).path
                                              : dir.appendingPathComponent("\(new)_\(base)").path
        guard validPath(to) else { throw CloneError.message("Can't build a safe path for the cloned disk.") }
        if !copies.contains(where: { $0.0 == from }) { copies.append((from, to)) }
    }
    for (from, to) in copies { x = x.replacingOccurrences(of: "'\(from)'", with: "'\(to)'") }

    // Identity
    x = x.replacingOccurrences(of: "<name>\(xmlEscape(old))</name>", with: "<name>\(xmlEscape(new))</name>")
    if x.contains("<uuid>") { x = x.replacingOccurrences(of: #"<uuid>[^<]*</uuid>"#, with: "<uuid>\(uuid)</uuid>", options: .regularExpression) }
    else { x = x.replacingOccurrences(of: "</name>", with: "</name>\n  <uuid>\(uuid)</uuid>") }
    x = x.replacingOccurrences(of: #"\s*<mac address='[^']*'/>"#, with: "", options: .regularExpression)

    // UEFI variable store
    var nvram: (String, String)?
    if let m = matches(#"<nvram[^>]*>([^<]+)</nvram>"#, x).first {
        let from = group(m, 1, in: x)
        let to = "/etc/libvirt/qemu/nvram/\(uuid)_VARS-pure-efi.fd"
        if validPath(from) { nvram = (from, to); x = x.replacingOccurrences(of: ">\(from)</nvram>", with: ">\(to)</nvram>") }
    }
    return ClonePlan(xml: x, copies: copies, nvram: nvram)
}

struct CDDrive: Identifiable { var id: String { target }; let target: String; let source: String? }

// MARK: - Store

extension Store {
    private func runScript(_ script: String) async -> (ok: Bool, output: String) {
        guard let out = await ssh(script + "\n", allowFailure: true) else { return (false, "") }
        return (out.contains("UW_OK"), out.replacingOccurrences(of: "UW_OK", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // Media
    func cdDrives(_ name: String) async -> [CDDrive] {
        let out = await ssh("virsh domblklist \(shq(name)) --details 2>&1", allowFailure: true) ?? ""
        return out.split(separator: "\n").compactMap { line in
            let c = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard c.count >= 3, c[1] == "cdrom" else { return nil }
            let src = c.count >= 4 ? c[3...].joined(separator: " ") : "-"
            return CDDrive(target: c[2], source: src == "-" ? nil : src)
        }
    }
    private func mediaFlags(_ n: String) -> String {
        "st=$(virsh domstate \(n) 2>&1); F=\"--config\"; [ \"$st\" = running ] && F=\"--live --config\""
    }
    func ejectMedia(_ name: String, target: String? = nil) async {
        let drives = await cdDrives(name).filter { $0.source != nil && (target == nil || $0.target == target) && validDev($0.target) }
        guard !drives.isEmpty else { show("\(name) has no install media inserted."); return }
        let n = shq(name)
        let cmds = drives.map { "virsh change-media \(n) \($0.target) --eject --force $F 2>&1" }.joined(separator: "\n")
        let r = await runScript("\(mediaFlags(n))\n\(cmds)\necho UW_OK")
        if r.ok && !r.output.lowercased().contains("error") { show("Ejected \(drives.count == 1 ? "the disc" : "\(drives.count) discs") from \(name)") }
        else { show("Couldn't eject: \(r.output)", error: true) }
    }
    func insertMedia(_ name: String, target: String, iso: String) async {
        guard validDev(target), validPath(iso) else { show("Bad drive or ISO path.", error: true); return }
        let n = shq(name)
        let r = await runScript("\(mediaFlags(n))\nvirsh change-media \(n) \(target) \(shq(iso)) --update $F 2>&1\necho UW_OK")
        if r.ok && !r.output.lowercased().contains("error") { show("Inserted \((iso as NSString).lastPathComponent) into \(name)") }
        else { show("Couldn't insert the ISO: \(r.output)", error: true) }
    }

    // Console
    func openConsole(_ name: String, browser: Bool) async {
        guard let out = await ssh("virsh dumpxml \(shq(name)) 2>&1", allowFailure: true),
              let g = out.range(of: #"<graphics type='vnc'[^>]*>"#, options: .regularExpression) else { show("Couldn't read the VM's display settings.", error: true); return }
        let tag = String(out[g])
        func attr(_ k: String) -> Int? { tag.range(of: "\(k)='(\\d+)'", options: .regularExpression).flatMap { Int(tag[$0].filter(\.isNumber)) } }
        guard let port = attr("port") else { show("\(name) isn't running, so it has no console yet. Start it first.", error: true); return }
        guard let h = host else { return }
        if browser {
            guard let ws = attr("websocket") else { show("This VM has no websocket port; use Screen Sharing instead.", error: true); return }
            let u = URL(string: normalizedURL)
            let scheme = u?.scheme ?? "http"
            let webPort = u?.port ?? (scheme == "https" ? 443 : 80)
            let url = "\(scheme)://\(h):\(webPort)/plugins/dynamix.vm.manager/vnc.html?autoconnect=true&host=\(h)&port=\(webPort)&path=/wsproxy/\(ws)/"
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        } else if let url = URL(string: "vnc://\(h):\(port)") {
            NSWorkspace.shared.open(url)
            show("Opening \(name) in Screen Sharing (\(h):\(port))")
        }
    }

    // Clone
    func cloneVM(_ name: String, as newName: String) async -> Bool {
        guard validShareName(newName), newName != name else { show("Pick a different, valid name for the clone.", error: true); return false }
        guard let xml = await vmXML(name) else { return false }
        let plan: ClonePlan
        do { plan = try planClone(xml: xml, old: name, new: newName, uuid: UUID().uuidString.lowercased()) }
        catch { show(error.localizedDescription, error: true); return false }
        guard !plan.xml.contains("UWXML") else { show("XML contains a reserved word.", error: true); return false }
        let o = shq(name), n = shq(newName)
        let created = (plan.copies.map { shq($0.to) } + (plan.nvram.map { [shq($0.to)] } ?? [])).joined(separator: " ")
        let dirs = Set(plan.copies.map { shq(URL(fileURLWithPath: $0.to).deletingLastPathComponent().path) })
        var s = """
        virsh dominfo \(n) >/dev/null 2>&1 && { echo "A VM named \(newName) already exists"; exit 4; }
        st=$(virsh domstate \(o) 2>&1)
        case "$st" in "shut off"*) ;; *) echo "\(name) is $st - shut it down first so the disk copy is consistent"; exit 2;; esac
        cleanup() { rm -f \(created.isEmpty ? "/dev/null" : created); \(dirs.map { "rmdir \($0) 2>/dev/null" }.joined(separator: "; ")); }

        """
        for c in plan.copies {
            s += "mkdir -p \(shq(URL(fileURLWithPath: c.to).deletingLastPathComponent().path))\n"
            s += "[ -e \(shq(c.to)) ] && { echo \"\(c.to) already exists\"; exit 3; }\n"
            s += "cp --sparse=always \(shq(c.from)) \(shq(c.to)) 2>&1 || { cleanup; exit 6; }\n"
        }
        if let nv = plan.nvram { s += "cp \(shq(nv.from)) \(shq(nv.to)) 2>&1 || true\n" }
        s += "cat > /tmp/uw-clone.xml <<'UWXML'\n\(plan.xml)\nUWXML\n"
        s += "virsh define /tmp/uw-clone.xml 2>&1 || { rm -f /tmp/uw-clone.xml; cleanup; exit 7; }\nrm -f /tmp/uw-clone.xml\necho UW_OK"
        let r = await runScript(s)
        await refresh()
        if r.ok { show("Cloned \(name) → \(newName)") } else { show("Clone failed: \(r.output)", error: true) }
        return r.ok
    }
}

// MARK: - Sheets

struct VMCloneSheet: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    let vm: VM
    @State private var newName = ""
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clone \(vm.name ?? vm.id)").font(.title3.bold())
            TextField("Name for the clone", text: $newName).textFieldStyle(.roundedBorder)
            Text("Copies the VM's disks (sparse) and settings, gives the clone a new identity and network address, and keeps UEFI settings. The VM must be shut off. Large disks can take a long time. Don't close this window while it runs.")
                .font(.caption).foregroundStyle(.secondary)
            Text("GPU and USB passthrough devices are copied as-is, and two VMs can't use the same device at once.").font(.caption).foregroundStyle(.secondary)
            HStack {
                if busy { ProgressView().controlSize(.small); Text("Copying…").font(.caption) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                Button("Clone") { busy = true; Task { let ok = await s.cloneVM(vm.name ?? vm.id, as: newName); busy = false; if ok { dismiss() } } }
                    .keyboardShortcut(.defaultAction).disabled(busy || newName.isEmpty)
            }
        }.padding().frame(width: 480)
        .onAppear { newName = "\(vm.name ?? vm.id)-clone" }
    }
}

struct VMMediaTab: View {
    @EnvironmentObject var s: Store
    let name: String
    @State private var drives: [CDDrive] = []
    @State private var isos: [String] = []
    @State private var pick: [String: String] = [:]
    @State private var loading = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if loading { ProgressView() }
            else if drives.isEmpty { Text("This VM has no CD/DVD drives. Add one in the XML tab, or create VMs with an install ISO.").foregroundStyle(.secondary) }
            ForEach(drives) { d in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(d.target, systemImage: "opticaldisc").font(.body.weight(.medium))
                        Text(d.source.map { ($0 as NSString).lastPathComponent } ?? "Empty").foregroundStyle(d.source == nil ? .secondary : .primary)
                        Spacer()
                        Button("Eject") { Task { await s.ejectMedia(name, target: d.target); await load() } }.disabled(d.source == nil)
                    }
                    HStack {
                        Picker("Insert", selection: Binding(get: { pick[d.target] ?? "" }, set: { pick[d.target] = $0 })) {
                            Text("Choose an ISO…").tag(""); ForEach(isos, id: \.self) { Text(($0 as NSString).lastPathComponent).tag($0) }
                        }
                        Button("Insert") { if let p = pick[d.target], !p.isEmpty { Task { await s.insertMedia(name, target: d.target, iso: p); await load() } } }
                            .disabled((pick[d.target] ?? "").isEmpty)
                    }
                }.padding(10).background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Changes apply immediately to a running VM and are saved to its definition.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.task { await load() }
    }
    func load() async { loading = true; drives = await s.cdDrives(name); isos = await s.listISOs(); loading = false }
}
