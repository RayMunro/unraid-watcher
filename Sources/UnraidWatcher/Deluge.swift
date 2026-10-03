// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import AppKit
import Charts
import Foundation
import SwiftUI

// MARK: - Models

struct Torrent: Identifiable, Hashable {
    let id: String
    var name = "", state = "", savePath = "", tracker = "", message = ""
    var progress = 0.0, downRate = 0.0, upRate = 0.0, eta = 0.0, ratio = 0.0
    var size = 0.0, done = 0.0, uploaded = 0.0, added = 0.0
    var seeds = 0, peers = 0, totalSeeds = 0, totalPeers = 0, queue = 0

    var isPaused: Bool { state == "Paused" }
    var isError: Bool { state == "Error" }
    var isActive: Bool { downRate > 0 || upRate > 0 }
}

struct DelugeStats {
    var down = 0.0, up = 0.0, connections = 0, dht = 0
    var freeSpace: Double?
    var maxDown = -1.0, maxUp = -1.0     // KiB/s, negative means unlimited
}

struct DelugeSnapshot {
    var torrents: [Torrent]
    var stats: DelugeStats
    var fetched = Date()

    func count(_ state: String) -> Int { torrents.filter { $0.state == state }.count }
}

enum DelugeError: LocalizedError {
    case badPassword, noDaemon, rpc(String), http(Int), badResponse
    var errorDescription: String? {
        switch self {
        case .badPassword: return "Deluge rejected the Web UI password. Set it in Settings, Servers (the default is \"deluge\")."
        case .noDaemon: return "The Deluge Web UI is running but has no Deluge daemon to connect to."
        case .rpc(let m): return "Deluge said: \(m)"
        case .http(let c): return "The Deluge Web UI answered with HTTP \(c). Check the address."
        case .badResponse: return "That address answered, but it doesn't look like the Deluge Web UI."
        }
    }
}

// MARK: - Parsing

enum DelugeParse {
    static let keys = ["name", "state", "progress", "download_payload_rate", "upload_payload_rate", "eta", "ratio", "total_size", "total_done",
                       "total_uploaded", "num_seeds", "num_peers", "total_seeds", "total_peers", "save_path", "time_added", "tracker_host",
                       "message", "queue"]

    static func num(_ v: Any?) -> Double {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String, let d = Double(s) { return d }
        return 0
    }

    static func snapshot(_ result: [String: Any]) -> DelugeSnapshot {
        var list: [Torrent] = []
        for (id, raw) in (result["torrents"] as? [String: Any]) ?? [:] {
            guard let t = raw as? [String: Any] else { continue }
            var x = Torrent(id: id)
            x.name = t["name"] as? String ?? id
            x.state = t["state"] as? String ?? ""
            x.savePath = t["save_path"] as? String ?? ""
            x.tracker = t["tracker_host"] as? String ?? ""
            x.message = t["message"] as? String ?? ""
            x.progress = num(t["progress"]); x.downRate = num(t["download_payload_rate"]); x.upRate = num(t["upload_payload_rate"])
            x.eta = num(t["eta"]); x.ratio = num(t["ratio"])
            x.size = num(t["total_size"]); x.done = num(t["total_done"]); x.uploaded = num(t["total_uploaded"]); x.added = num(t["time_added"])
            x.seeds = Int(num(t["num_seeds"])); x.peers = Int(num(t["num_peers"]))
            x.totalSeeds = Int(num(t["total_seeds"])); x.totalPeers = Int(num(t["total_peers"])); x.queue = Int(num(t["queue"]))
            list.append(x)
        }
        let s = (result["stats"] as? [String: Any]) ?? [:]
        var st = DelugeStats()
        st.down = num(s["download_rate"]); st.up = num(s["upload_rate"])
        st.connections = Int(num(s["num_connections"])); st.dht = Int(num(s["dht_nodes"]))
        if s["free_space"] != nil { st.freeSpace = num(s["free_space"]) }
        st.maxDown = s["max_download"] == nil ? -1 : num(s["max_download"]); st.maxUp = s["max_upload"] == nil ? -1 : num(s["max_upload"])
        return DelugeSnapshot(torrents: list, stats: st)
    }
}

// MARK: - Client (Deluge Web UI JSON-RPC)

final class DelugeClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    let endpoint: URL, password: String, allowInsecure: Bool
    private var nextID = 0
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.httpCookieAcceptPolicy = .always      // the Web UI keeps your login in a session cookie
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    init(endpoint: URL, password: String, allowInsecure: Bool) {
        self.endpoint = endpoint; self.password = password; self.allowInsecure = allowInsecure
    }

    func urlSession(_ s: URLSession, didReceive ch: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if allowInsecure, ch.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = ch.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else { completionHandler(.performDefaultHandling, nil) }
    }

    @discardableResult
    func rpc(_ method: String, _ params: [Any] = [], retryAuth: Bool = true) async throws -> Any? {
        nextID += 1
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["method": method, "params": params, "id": nextID] as [String: Any])
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw DelugeError.http(h.statusCode) }
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw DelugeError.badResponse }
        if let e = o["error"] as? [String: Any] {
            let msg = e["message"] as? String ?? "unknown error"
            if retryAuth, method != "auth.login", (e["code"] as? NSNumber)?.intValue == 1 || msg == "Not authenticated" {
                try await login()
                return try await rpc(method, params, retryAuth: false)
            }
            throw DelugeError.rpc(msg)
        }
        return o["result"]
    }

    func login() async throws {
        guard try await rpc("auth.login", [password], retryAuth: false) as? Bool == true else { throw DelugeError.badPassword }
    }

    func snapshot() async throws -> DelugeSnapshot {
        func fetch() async throws -> [String: Any] {
            guard let r = try await rpc("web.update_ui", [DelugeParse.keys, [String: Any]()]) as? [String: Any] else { throw DelugeError.badResponse }
            return r
        }
        var r = try await fetch()
        if (r["connected"] as? Bool) == false {            // the Web UI is not attached to a daemon yet
            guard let hosts = try await rpc("web.get_hosts") as? [[Any]], let id = hosts.first?.first as? String else { throw DelugeError.noDaemon }
            try await rpc("web.connect", [id])
            r = try await fetch()
        }
        return DelugeParse.snapshot(r)
    }

    /// Newer Deluge versions renamed some calls, so try the new name and fall back to the old one.
    private func either(_ new: String, _ old: String, _ params: [Any]) async throws {
        do { try await rpc(new, params) } catch DelugeError.rpc { try await rpc(old, params) }
    }
    func pause(_ ids: [String]) async throws { try await either("core.pause_torrents", "core.pause_torrent", [ids]) }
    func resume(_ ids: [String]) async throws { try await either("core.resume_torrents", "core.resume_torrent", [ids]) }
    func pauseAll() async throws { try await either("core.pause_session", "core.pause_all_torrents", []) }
    func resumeAll() async throws { try await either("core.resume_session", "core.resume_all_torrents", []) }
    func recheck(_ ids: [String]) async throws { try await rpc("core.force_recheck", [ids]) }
    func remove(_ id: String, deleteData: Bool) async throws { try await rpc("core.remove_torrent", [id, deleteData]) }
    func addMagnet(_ uri: String) async throws { try await rpc("core.add_torrent_magnet", [uri, [String: Any]()]) }
}

// MARK: - Store integration

extension Store {
    /// A container that looks like Deluge, running or not.
    var delugeContainer: Container? {
        containers.first { ($0.image ?? "").lowercased().contains("deluge") || $0.displayName.lowercased().contains("deluge") }
    }
    var delugeAvailable: Bool { delugeContainer != nil || !profile.delugeURL.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The address given in Settings, or the server plus the port Docker publishes for the Web UI (8112 by default).
    var delugeEndpoint: URL? {
        let custom = profile.delugeURL.trimmingCharacters(in: .whitespaces)
        var base: String
        if !custom.isEmpty { base = custom.contains("://") ? custom : "http://" + custom }
        else {
            guard let h = host else { return nil }
            let port = delugeContainer.flatMap { containerExtras[$0.id]?.ports?.first { $0.privatePort == 8112 }?.publicPort } ?? 8112
            base = "http://\(h):\(port)"
        }
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base.hasSuffix("/json") ? base : base + "/json")
    }

    private func delugeClientForCurrentSettings() -> DelugeClient? {
        guard let url = delugeEndpoint else { return nil }
        let pw = delugePassword.isEmpty ? "deluge" : delugePassword
        let key = "\(url.absoluteString)|\(pw)|\(allowInsecure)"
        if let c = delugeClient, delugeClientKey == key { return c }
        let c = DelugeClient(endpoint: url, password: pw, allowInsecure: allowInsecure)
        delugeClient = c; delugeClientKey = key
        return c
    }

    func refreshDeluge() async {
        guard let c = delugeClientForCurrentSettings() else { delugeError = "No server address to reach Deluge on."; return }
        do {
            let snap = try await c.snapshot()
            delugeSnapshot = snap; delugeError = nil
            delugeDownHistory = Array((delugeDownHistory + [snap.stats.down]).suffix(60))
            delugeUpHistory = Array((delugeUpHistory + [snap.stats.up]).suffix(60))
        } catch {
            delugeError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delugeDo(_ ok: String, _ op: (DelugeClient) async throws -> Void) async {
        guard let c = delugeClientForCurrentSettings() else { return }
        do { try await op(c); show(ok) }
        catch { show("Deluge: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)", error: true) }
        await refreshDeluge()
    }
}

// MARK: - Panel

struct DelugeView: View {
    @EnvironmentObject var s: Store
    @AppStorage("refreshSeconds") private var refreshSeconds = 10
    @State private var filter = "All"
    @State private var search = ""
    @State private var sort = "Added"
    @State private var addingMagnet = false
    @State private var removeTarget: Torrent?

    static let filters = ["All", "Downloading", "Seeding", "Paused", "Queued", "Checking", "Error"]
    static let sorts = ["Added", "Name", "Progress", "Download speed", "Upload speed", "Ratio", "Size"]

    func eta(_ t: Torrent) -> String {
        guard t.state == "Downloading", t.eta > 0, t.eta < 86400 * 365 else { return "" }
        let h = Int(t.eta) / 3600, m = Int(t.eta) % 3600 / 60
        return h >= 24 ? "\(h / 24)d \(h % 24)h" : h > 0 ? "\(h)h \(m)m" : m > 0 ? "\(m)m" : "\(Int(t.eta))s"
    }
    func color(_ state: String) -> Color {
        switch state { case "Downloading": .blue; case "Seeding": .green; case "Paused": .gray; case "Error": .red; case "Checking", "Allocating", "Moving": .purple; default: .orange }
    }
    var shown: [Torrent] {
        var l = s.delugeSnapshot?.torrents ?? []
        if filter != "All" { l = l.filter { $0.state == filter } }
        if !search.isEmpty { l = l.filter { $0.name.localizedCaseInsensitiveContains(search) } }
        switch sort {
        case "Name": l.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "Progress": l.sort { $0.progress > $1.progress }
        case "Download speed": l.sort { $0.downRate > $1.downRate }
        case "Upload speed": l.sort { $0.upRate > $1.upRate }
        case "Ratio": l.sort { $0.ratio > $1.ratio }
        case "Size": l.sort { $0.size > $1.size }
        default: l.sort { $0.added > $1.added }
        }
        return l
    }

    var body: some View {
        let snap = s.delugeSnapshot
        Group {
            if let e = s.delugeError {
                Card(title: "Deluge") {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).textSelection(.enabled)
                    if let c = s.delugeContainer {
                        Text("Found the container \(c.displayName) (\(c.image ?? "unknown image"), \(c.isRunning ? "running" : "not running")).").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Trying \(s.delugeEndpoint?.absoluteString ?? "no address"). You can change the address and Web UI password in Settings, Servers.")
                        .font(.caption).foregroundStyle(.secondary)
                    SettingsLink { Text("Open Settings") }
                }
            }
            if let snap {
                HStack(alignment: .top, spacing: 16) {
                    Card(title: "Download") {
                        Text(rate(snap.stats.down)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.green)
                        Chart(Array(s.delugeDownHistory.enumerated()), id: \.offset) { i, v in LineMark(x: .value("t", i), y: .value("B/s", v)).foregroundStyle(.green) }
                            .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 50)
                        if snap.stats.maxDown >= 0 { Text("Limit \(Int(snap.stats.maxDown)) KiB/s").font(.caption).foregroundStyle(.secondary) }
                    }
                    Card(title: "Upload") {
                        Text(rate(snap.stats.up)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.blue)
                        Chart(Array(s.delugeUpHistory.enumerated()), id: \.offset) { i, v in LineMark(x: .value("t", i), y: .value("B/s", v)).foregroundStyle(.blue) }
                            .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 50)
                        if snap.stats.maxUp >= 0 { Text("Limit \(Int(snap.stats.maxUp)) KiB/s").font(.caption).foregroundStyle(.secondary) }
                    }
                    Card(title: "Torrents") {
                        Text("\(snap.torrents.count)").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("\(snap.count("Downloading")) downloading · \(snap.count("Seeding")) seeding").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text("\(snap.count("Paused")) paused ·").foregroundStyle(.secondary)
                            Text("\(snap.count("Error")) error\(snap.count("Error") == 1 ? "" : "s")").foregroundStyle(snap.count("Error") > 0 ? .red : .secondary)
                        }.font(.caption)
                        Text("\(snap.stats.connections) connections · \(snap.stats.dht) DHT nodes").font(.caption).foregroundStyle(.secondary)
                        if let f = snap.stats.freeSpace { Text("\(bytes(f, unitKB: false)) free").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                HStack {
                    Picker("Show", selection: $filter) { ForEach(Self.filters, id: \.self) { Text($0 == "All" ? "All (\(snap.torrents.count))" : "\($0) (\(snap.count($0)))").tag($0) } }
                        .frame(width: 210)
                    Picker("Sort", selection: $sort) { ForEach(Self.sorts, id: \.self) { Text($0).tag($0) } }.frame(width: 180)
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    Spacer()
                    Button("Pause all") { Task { await s.delugeDo("Paused all torrents") { try await $0.pauseAll() } } }
                    Button("Resume all") { Task { await s.delugeDo("Resumed all torrents") { try await $0.resumeAll() } } }
                    Button("Add magnet…") { addingMagnet = true }
                }
                Card(title: "Torrents (\(shown.count))") {
                    if shown.isEmpty { Text(snap.torrents.isEmpty ? "No torrents yet" : "Nothing matches").foregroundStyle(.secondary) }
                    ForEach(shown) { t in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(t.name).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Pill(text: t.state, color: color(t.state))
                                Menu {
                                    if t.isPaused { Button("Resume") { Task { await s.delugeDo("Resumed \(t.name)") { try await $0.resume([t.id]) } } } }
                                    else { Button("Pause") { Task { await s.delugeDo("Paused \(t.name)") { try await $0.pause([t.id]) } } } }
                                    Button("Force recheck") { Task { await s.delugeDo("Rechecking \(t.name)") { try await $0.recheck([t.id]) } } }
                                    Button("Copy name") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t.name, forType: .string) }
                                    Divider()
                                    Button("Remove…", role: .destructive) { removeTarget = t }
                                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 28)
                            }
                            TorrentBar(fraction: t.progress / 100, color: color(t.state))
                            HStack(spacing: 12) {
                                Text("\(String(format: "%.1f", t.progress))% of \(bytes(t.size, unitKB: false))")
                                if t.downRate > 0 { Text("↓ \(rate(t.downRate))").foregroundStyle(.green) }
                                if t.upRate > 0 { Text("↑ \(rate(t.upRate))").foregroundStyle(.blue) }
                                if !eta(t).isEmpty { Text("ETA \(eta(t))") }
                                Text("Ratio \(String(format: "%.2f", t.ratio))")
                                Text("\(t.seeds)/\(t.totalSeeds) seeds · \(t.peers)/\(t.totalPeers) peers")
                                if !t.tracker.isEmpty { Text(t.tracker).lineLimit(1) }
                            }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            if t.isError, !t.message.isEmpty, t.message != "OK" { Text(t.message).font(.caption).foregroundStyle(.red) }
                        }
                        Divider()
                    }
                }
            } else if s.delugeError == nil {
                ProgressView("Connecting to Deluge…")
            }
        }
        .task(id: s.profile.id) {
            while !Task.isCancelled {
                await s.refreshDeluge()
                try? await Task.sleep(for: .seconds(Double(max(2, min(refreshSeconds, 5)))))
            }
        }
        .sheet(isPresented: $addingMagnet) { AddMagnetSheet() }
        .confirmationDialog("Remove \(removeTarget?.name ?? "torrent")?", isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }), titleVisibility: .visible) {
            Button("Remove torrent, keep files") { if let t = removeTarget { Task { await s.delugeDo("Removed \(t.name)") { try await $0.remove(t.id, deleteData: false) } } } }
            Button("Remove torrent and delete files", role: .destructive) { if let t = removeTarget { Task { await s.delugeDo("Removed \(t.name) and its files") { try await $0.remove(t.id, deleteData: true) } } } }
        } message: { Text("Deleting files cannot be undone.") }
    }
}

/// Progress toward completion, coloured by the torrent's state. (UsageBar turns red when nearly full, which is wrong for progress.)
struct TorrentBar: View {
    let fraction: Double
    let color: Color
    var body: some View {
        let f = min(max(fraction, 0), 1)
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color.opacity(0.85)).frame(width: g.size.width * f)
            }
        }.frame(height: 8)
    }
}

struct AddMagnetSheet: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var busy = false
    var valid: Bool { link.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("magnet:?") }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a magnet link").font(.title3.bold())
            TextField("magnet:?xt=urn:btih:…", text: $link).textFieldStyle(.roundedBorder)
            Text("The torrent is added to \(s.profile.name)'s Deluge with its default settings.").font(.caption).foregroundStyle(.secondary)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    busy = true
                    Task { await s.delugeDo("Added the magnet link") { try await $0.addMagnet(link.trimmingCharacters(in: .whitespacesAndNewlines)) }; busy = false; dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(!valid || busy)
            }
        }.padding().frame(width: 520)
    }
}
