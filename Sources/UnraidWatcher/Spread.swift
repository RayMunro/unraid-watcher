// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import AppKit
import SwiftUI

// MARK: - Logic (pure, so it can be tested without a server)

struct SpreadRow: Identifiable {
    var id: String { location }
    let location: String      // "disk3", "cache", "second-cache"
    var kb: Double
    var isArrayDisk: Bool { location.range(of: #"^disk\d+$"#, options: .regularExpression) != nil }
}

/// Folders of a share on every disk and pool, excluding the merged views (user, user0) and unrelated mounts.
func spreadLocationsScript(share: String, mnt: String = "/mnt") -> String {
    "for d in \(mnt)/*/\(shq(share)); do [ -d \"$d\" ] && echo \"$d\"; done"
}

func parseSpreadLocations(_ output: String) -> [String] {
    let skip: Set<String> = ["user", "user0", "disks", "remotes", "addons", "rootshare"]
    var seen: [String] = []
    for line in output.split(separator: "\n") {
        let parts = line.split(separator: "/").map(String.init)      // ["mnt", "disk1", "Media"]
        guard parts.count >= 3 else { continue }
        let loc = parts[parts.count - 2]
        guard !skip.contains(loc), loc.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil, !seen.contains(loc) else { continue }
        seen.append(loc)
    }
    return seen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

/// `du` can take a long time on a big share. It runs at idle priority with a 10 minute limit (when those tools exist),
/// so even if you stop a measurement, the one already running on the server stays gentle and ends by itself.
func spreadSizeScript(share: String, location: String, mnt: String = "/mnt") -> String {
    #"""
    L=""; command -v ionice >/dev/null 2>&1 && L="ionice -c3"; command -v nice >/dev/null 2>&1 && L="$L nice -n 19"
    command -v timeout >/dev/null 2>&1 && L="timeout 600 $L"
    $L du -sk \#(shq("\(mnt)/\(location)/\(share)")) 2>/dev/null | tail -1
    """#
}

func parseDuKB(_ output: String) -> Double? {
    output.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" }).first.flatMap { Double($0) }
}

// MARK: - Store

extension Store {
    func shareLocations(_ name: String) async -> [String]? {
        guard !name.isEmpty, !name.contains("\n") else { return nil }
        guard let out = await ssh(spreadLocationsScript(share: name), allowFailure: true) else { return nil }
        return parseSpreadLocations(out)
    }

    func shareSize(_ name: String, on location: String) async -> Double? {
        guard let out = await ssh(spreadSizeScript(share: name, location: location), allowFailure: true) else { return nil }
        return parseDuKB(out)
    }
}

// MARK: - Sheet

struct SpreadTarget: Identifiable { let id: String }

struct ShareSpreadSheet: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    let name: String
    @State private var rows: [SpreadRow] = []
    @State private var scanning: String?
    @State private var finished = false
    @State private var stopped = false
    @State private var failure: String?
    @State private var started = Date()
    @State private var took = 0.0
    @State private var task: Task<Void, Never>?

    static let palette: [Color] = [.blue, .teal, .green, .orange, .purple, .pink, .indigo, .mint, .yellow, .cyan, .brown, .red]

    var sorted: [SpreadRow] { rows.sorted { $0.location.localizedStandardCompare($1.location) == .orderedAscending } }
    var total: Double { rows.map(\.kb).reduce(0, +) }
    func color(_ r: SpreadRow) -> Color { Self.palette[(sorted.firstIndex { $0.id == r.id } ?? 0) % Self.palette.count] }

    /// Data disks and pools that exist on this server, so we can say where the share is not.
    var allPlaces: [String] { ((s.array?.disks ?? []) + (s.array?.caches ?? [])).compactMap(\.name) }
    var missing: [String] { allPlaces.filter { p in !rows.contains { $0.location == p } && !(rows.isEmpty) } }

    var summary: String {
        let arr = rows.filter(\.isArrayDisk).count, pool = rows.count - arr
        var parts: [String] = []
        if arr > 0 { parts.append("\(arr) array disk\(arr == 1 ? "" : "s")") }
        if pool > 0 { parts.append("\(pool) pool\(pool == 1 ? "" : "s")") }
        return "\(bytes(total)) across \(parts.joined(separator: " and "))"
    }

    func run() {
        task?.cancel()
        rows = []; finished = false; stopped = false; failure = nil; started = Date()
        task = Task { await scan() }
    }
    func scan() async {
        guard let locations = await s.shareLocations(name) else {
            failure = "Couldn't list this share's folders. Check the SSH connection in Settings."
            return
        }
        if locations.isEmpty { finished = true; return }
        for (i, loc) in locations.enumerated() {
            if Task.isCancelled { return }
            scanning = "\(loc) (\(i + 1) of \(locations.count))"
            if let kb = await s.shareSize(name, on: loc) { rows.append(SpreadRow(location: loc, kb: kb)) }
        }
        if Task.isCancelled { return }
        scanning = nil; finished = true; took = Date().timeIntervalSince(started)
    }
    func stop() { task?.cancel(); scanning = nil; stopped = true }

    var plainText: String {
        "Spread of \(name) on \(s.profile.name)\n" + sorted.map { "\($0.location): \(bytes($0.kb)) (\(String(format: "%.1f", total > 0 ? $0.kb / total * 100 : 0))%)" }.joined(separator: "\n") + "\nTotal: \(bytes(total))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) { Text(name).font(.title3.bold()); Text("Spread across drives on \(s.profile.name)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if scanning != nil { Button("Stop", role: .cancel) { stop() } } else { Button("Scan again") { run() } }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let scanning {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Measuring \(scanning)…").foregroundStyle(.secondary) }
            }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            if stopped { Text("Stopped. Only the disks measured so far are shown.").font(.caption).foregroundStyle(.orange) }
            if finished && rows.isEmpty { Text("This share has no folder on any disk or pool.").foregroundStyle(.secondary) }

            if !rows.isEmpty {
                GeometryReader { g in
                    HStack(spacing: 1) {
                        ForEach(sorted) { r in
                            Rectangle().fill(color(r)).frame(width: max(2, g.size.width * (total > 0 ? r.kb / total : 0)))
                                .help("\(r.location): \(bytes(r.kb))")
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 6))
                }.frame(height: 22)
                Text(summary + (finished ? String(format: "  ·  measured in %.0f s", took) : "")).font(.callout.weight(.medium))
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sorted) { r in
                            HStack(spacing: 10) {
                                Circle().fill(color(r)).frame(width: 10, height: 10)
                                Text(r.location).font(.body.weight(.medium)).frame(width: 120, alignment: .leading)
                                Pill(text: r.isArrayDisk ? "Array" : "Pool", color: r.isArrayDisk ? .blue : .orange)
                                TorrentBar(fraction: total > 0 ? r.kb / (sorted.map(\.kb).max() ?? 1) : 0, color: color(r))
                                Text(bytes(r.kb)).monospacedDigit().frame(width: 90, alignment: .trailing)
                                Text(String(format: "%.1f%%", total > 0 ? r.kb / total * 100 : 0)).monospacedDigit().foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                            }.padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
                if finished, !missing.isEmpty {
                    Text("Not on: \(missing.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Measuring reads the folder listing on each disk that holds the share. That can wake spun-down disks and takes a while for large shares.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(plainText, forType: .string) }.disabled(rows.isEmpty)
            }
        }
        .padding().frame(width: 720, height: 620, alignment: .top)
        .task { run() }
        .onDisappear { task?.cancel() }
    }
}
