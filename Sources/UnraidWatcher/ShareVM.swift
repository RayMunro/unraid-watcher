// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import Foundation
import SwiftUI

// MARK: - Share models

struct ShareForm {
    var name = ""; var comment = ""; var useCache = "no"; var allocator = "highwater"
    var split = ""; var floor = "0"; var include = ""; var exclude = ""
    var export = true; var security = "public"

    init() {}
    init(name: String, cfg: [String: String]) {
        self.name = name
        comment = cfg["shareComment"] ?? ""; useCache = cfg["shareUseCache"] ?? "no"; allocator = cfg["shareAllocator"] ?? "highwater"
        split = cfg["shareSplitLevel"] ?? ""; floor = cfg["shareFloor"] ?? "0"; include = cfg["shareInclude"] ?? ""
        exclude = cfg["shareExclude"] ?? ""; export = (cfg["shareExport"] ?? "e") != "-"; security = cfg["shareSecurity"] ?? "public"
    }
    var fields: [String: String] {
        ["shareComment": comment, "shareUseCache": useCache, "shareAllocator": allocator, "shareSplitLevel": split, "shareFloor": floor,
         "shareInclude": include, "shareExclude": exclude, "shareExport": export ? "e" : "-", "shareSecurity": security]
    }
}
struct ShareTarget: Identifiable { let id = UUID(); let name: String? }
struct ShareDist: Identifiable { var id: String { disk }; let disk: String; let kb: Double }

func validShareName(_ s: String) -> Bool { s.range(of: #"^[A-Za-z0-9][A-Za-z0-9 _.-]{0,60}$"#, options: .regularExpression) != nil }

// MARK: - Store: shares

extension Store {
    func parseCfg(_ text: String) -> [String: String] {
        var d: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "="), !line.hasPrefix("#") else { continue }
            let k = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var v = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
            d[k] = v
        }
        return d
    }

    func loadShareConfigs() async {
        guard sshEnabled else { return }
        let script = #"for f in /boot/config/shares/*.cfg; do [ -f "$f" ] || continue; echo "===SHARE $(basename "$f" .cfg)"; cat "$f"; done"#
        guard let out = await ssh(script, allowFailure: true) else { return }
        var r: [String: [String: String]] = [:]
        for chunk in out.components(separatedBy: "===SHARE ").dropFirst() {
            let parts = chunk.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first.map({ String($0).trimmingCharacters(in: .whitespaces) }) else { continue }
            r[name] = parseCfg(parts.count > 1 ? String(parts[1]) : "")
        }
        shareCfgs = r
    }

    func analyzeShare(_ name: String) async {
        let n = shq(name)
        let script = "du -sk /mnt/*/\(n) 2>/dev/null"
        guard let out = await ssh(script, allowFailure: true) else { return }
        var rows: [ShareDist] = []
        for line in out.split(separator: "\n") {
            let p = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard p.count == 2, let kb = Double(p[0]) else { continue }
            let comps = p[1].split(separator: "/").map(String.init)   // ["mnt", "disk1", "Share"]
            guard comps.count >= 3, !["user", "user0", "disks", "remotes", "addons", "rootshare"].contains(comps[1]) else { continue }
            rows.append(ShareDist(disk: comps[1], kb: kb))
        }
        shareDist[name] = rows.sorted { $0.disk < $1.disk }
    }

    /// Posts a form to Unraid's own emhttp endpoint from the server itself (the way the web UI applies changes).
    private func emhttpPost(_ pairs: [(String, String)]) async -> String? {
        let data = pairs.map { "--data-urlencode \(shq("\($0.0)=\($0.1)"))" }.joined(separator: " ")
        let script = """
        csrf=$(grep -m1 '^csrf_token=' /var/local/emhttp/var.ini | cut -d'"' -f2)
        if [ -S /var/run/emhttpd.socket ]; then T="--unix-socket /var/run/emhttpd.socket http://localhost/update.htm"; else T="http://localhost/update.htm"; fi
        curl -s -o /dev/null -w 'HTTP %{http_code}' \(data) --data-urlencode "csrf_token=$csrf" $T
        """
        return await ssh(script, allowFailure: true)
    }

    @discardableResult
    func saveShare(_ f: ShareForm, original: String?) async -> Bool {
        guard validShareName(f.name) else { show("Share names can use letters, numbers, spaces, _ - . (max 61 chars).", error: true); return false }
        if original == nil, shareCfgs[f.name] != nil || shares.contains(where: { $0.name == f.name }) {
            show("A share called \(f.name) already exists.", error: true); return false
        }
        var fields = original.flatMap { shareCfgs[$0] } ?? [:]      // keep settings we don't edit
        for (k, v) in f.fields { fields[k] = v }
        var pairs: [(String, String)] = [("shareName", f.name), ("shareNameOrig", original ?? "")]
        for (k, v) in fields.sorted(by: { $0.key < $1.key }) where k.hasPrefix("share") && k != "shareName" && k != "shareNameOrig" { pairs.append((k, v)) }
        pairs.append(("cmdEditShare", "Apply"))
        guard let out = await emhttpPost(pairs) else { return false }
        await loadShareConfigs(); await refresh()
        if !out.contains("200"), shareCfgs[f.name] == nil {
            show("The server didn't accept the change (\(out.isEmpty ? "no response" : out)). Try it in the Unraid web UI to check.", error: true); return false
        }
        show(original == nil ? "Created share \(f.name)" : "Saved share \(f.name)")
        return true
    }

    func deleteShare(_ name: String) async {
        guard validShareName(name) else { return }
        // Refuse unless every disk copy of the share is empty.
        let check = "find /mnt/*/\(shq(name)) -mindepth 1 -not -path '/mnt/user*' 2>/dev/null | head -1"
        guard let found = await ssh(check, allowFailure: true) else { return }
        if !found.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            show("\(name) still contains files, so it wasn't deleted. Empty it first.", error: true); return
        }
        guard let out = await emhttpPost([("shareName", name), ("cmdDeleteShare", "Delete")]) else { return }
        await loadShareConfigs(); await refresh()
        if shareCfgs[name] != nil { show("The server didn't delete \(name) (\(out)).", error: true) } else { show("Deleted share \(name)") }
    }

    // MARK: VMs (virsh over SSH)

    func vmReport(_ name: String) async -> String {
        let n = shq(name)
        let script = """
        virsh dominfo \(n) 2>&1
        echo ===DISKS; virsh domblklist \(n) --details 2>&1
        echo ===NICS; virsh domiflist \(n) 2>&1
        echo ===VNC; virsh vncdisplay \(n) 2>&1
        echo ===LOG; tail -n 60 /var/log/libvirt/qemu/\(n).log 2>&1
        """
        return await ssh(script, allowFailure: true) ?? "Couldn't reach the server over SSH."
    }
    func setVMAutostart(_ name: String, on: Bool) async {
        await ssh("virsh autostart \(shq(name))\(on ? "" : " --disable")", ok: "\(name) will \(on ? "" : "not ")start with the array", allowFailure: true)
    }
}

// MARK: - Share editor

struct ShareEditor: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    let target: ShareTarget
    @State private var f = ShareForm()
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(target.name == nil ? "New share" : "Edit \(target.name!)").font(.title3.bold())
            Form {
                TextField("Name", text: $f.name).disabled(target.name != nil)
                TextField("Comment", text: $f.comment)
                Picker("Use cache pool", selection: $f.useCache) {
                    Text("No - array only").tag("no"); Text("Yes - write to cache, mover moves to array").tag("yes")
                    Text("Only - cache only").tag("only"); Text("Prefer - array → cache").tag("prefer")
                }
                Picker("Allocation method", selection: $f.allocator) {
                    Text("High-water").tag("highwater"); Text("Most-free").tag("mostfree"); Text("Fill-up").tag("fillup")
                }
                TextField("Split level", text: $f.split, prompt: Text("empty = any level"))
                TextField("Minimum free space (KB)", text: $f.floor)
                TextField("Included disks", text: $f.include, prompt: Text("e.g. disk1,disk2 - empty = all"))
                TextField("Excluded disks", text: $f.exclude)
                Toggle("Export over SMB", isOn: $f.export)
                Picker("SMB security", selection: $f.security) { Text("Public").tag("public"); Text("Secure").tag("secure"); Text("Private").tag("private") }
                    .disabled(!f.export)
            }.formStyle(.grouped)
            Text("Changes are applied through Unraid's own web interface endpoint, the same way the web UI saves a share.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(target.name == nil ? "Create" : "Save") {
                    saving = true
                    Task { let ok = await s.saveShare(f, original: target.name); saving = false; if ok { dismiss() } }
                }.keyboardShortcut(.defaultAction).disabled(saving || f.name.isEmpty)
            }
        }
        .padding().frame(width: 520)
        .onAppear { if let n = target.name { f = ShareForm(name: n, cfg: s.shareCfgs[n] ?? [:]) } }
    }
}

// MARK: - Shares view

struct SharesView: View {
    @EnvironmentObject var s: Store
    @State private var editing: ShareTarget?
    @State private var deleteTarget: String?

    func cacheLabel(_ v: String?) -> String {
        switch v { case "no": "No (array only)"; case "yes": "Yes (cache, then mover)"; case "only": "Only (cache)"; case "prefer": "Prefer (array → cache)"; default: v ?? "-" }
    }
    func line(_ k: String, _ v: String?) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text((v ?? "").isEmpty ? "-" : v!).textSelection(.enabled) }.font(.callout)
    }

    var body: some View {
        HStack {
            Text(s.sshEnabled ? "Share settings come from the server's config files over SSH." : "Turn on SSH in Settings to see share settings and manage shares.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("New share…") { editing = ShareTarget(name: nil) }.disabled(!s.sshEnabled)
        }
        Card(title: "Shares (\(s.shares.count))") {
            ForEach(s.shares) { sh in
                let name = sh.name ?? ""
                let cfg = s.shareCfgs[name]
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        if let c = cfg {
                            line("Cache", cacheLabel(c["shareUseCache"])); line("Allocation", c["shareAllocator"]); line("Split level", c["shareSplitLevel"])
                            line("Min free space", c["shareFloor"].map { "\($0) KB" }); line("Included disks", c["shareInclude"]); line("Excluded disks", c["shareExclude"])
                            line("SMB export", (c["shareExport"] ?? "e") == "-" ? "Off" : "On"); line("SMB security", c["shareSecurity"])
                        } else if s.sshEnabled { Text("No custom settings file (defaults).").font(.caption).foregroundStyle(.secondary) }
                        if let d = s.shareDist[name] {
                            Text("Disk usage").font(.caption.bold()).padding(.top, 4)
                            if d.isEmpty { Text("Not found on any disk").font(.caption).foregroundStyle(.secondary) }
                            let total = d.map(\.kb).reduce(0, +)
                            ForEach(d) { r in
                                HStack { Text(r.disk).frame(width: 70, alignment: .leading); UsageBar(fraction: total > 0 ? r.kb / total : 0)
                                    Text(bytes(r.kb)).font(.caption.monospacedDigit()).frame(width: 80, alignment: .trailing) }.font(.caption)
                            }
                        }
                        HStack {
                            Button("Analyze disk usage") { Task { await s.analyzeShare(name) } }
                            Button("Edit…") { editing = ShareTarget(name: name) }
                            Spacer()
                            Button("Delete…", role: .destructive) { deleteTarget = name }.disabled((sh.used?.value ?? 0) > 0)
                                .help((sh.used?.value ?? 0) > 0 ? "Only empty shares can be deleted here" : "Delete this empty share")
                        }.controlSize(.small).disabled(!s.sshEnabled).padding(.top, 4)
                    }.padding(.top, 6)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(name).font(.body.weight(.medium)); Spacer()
                            Text("\(bytes(sh.used?.value ?? 0)) used · \(bytes(sh.free?.value ?? 0)) free").font(.caption).foregroundStyle(.secondary) }
                        let total = (sh.used?.value ?? 0) + (sh.free?.value ?? 0)
                        if total > 0 { UsageBar(fraction: (sh.used?.value ?? 0) / total) }
                        if let c = sh.comment, !c.isEmpty { Text(c).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Divider()
            }
        }
        .task { await s.loadShareConfigs() }
        .sheet(item: $editing) { ShareEditor(target: $0) }
        .confirmationDialog("Delete share \(deleteTarget ?? "")?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Delete share", role: .destructive) { if let n = deleteTarget { Task { await s.deleteShare(n) } } }
        } message: { Text("Removes the share definition. It's refused if any disk still has files in it.") }
    }
}

// MARK: - VM details

struct VMDetailSheet: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    let vm: VM
    @State private var report = ""
    @State private var loading = true

    var sections: [(String, String)] {
        var out: [(String, String)] = []; var title = "Summary"; var buf: [String] = []
        for l in report.components(separatedBy: "\n") {
            if l.hasPrefix("===") { out.append((title, buf.joined(separator: "\n"))); title = String(l.dropFirst(3)).capitalized; buf = [] }
            else { buf.append(l) }
        }
        out.append((title, buf.joined(separator: "\n"))); return out
    }
    var autostart: Bool? {
        report.components(separatedBy: "\n").first { $0.hasPrefix("Autostart:") }.map { $0.contains("enable") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(vm.name ?? vm.id).font(.title3.bold()); Pill(text: vm.state ?? "-", color: stateColor(vm.state)); Spacer()
                if let a = autostart {
                    Toggle("Start with array", isOn: Binding(get: { a }, set: { v in Task { await s.setVMAutostart(vm.name ?? vm.id, on: v); await load() } }))
                }
                Button("Refresh") { Task { await load() } }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if loading { ProgressView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, sec in
                        if !sec.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sec.0).font(.headline).foregroundStyle(.secondary)
                                Text(sec.1).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(10).background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }.padding().frame(width: 760, height: 560)
        .task { await load() }
    }
    func load() async { loading = true; report = await s.vmReport(vm.name ?? vm.id); loading = false }
}
