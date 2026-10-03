// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class Store: ObservableObject {
    @AppStorage("serverURL") var serverURL = ""
    @AppStorage("allowInsecure") var allowInsecure = true
    @AppStorage("notifyEnabled") var notifyEnabled = true
    @AppStorage("diskWarnTemp") var diskWarnTemp = 45
    @AppStorage("diskCritTemp") var diskCritTemp = 55
    @AppStorage("cpuWarnTemp") var cpuWarnTemp = 80
    @AppStorage("sshEnabled") var sshEnabled = false
    @AppStorage("sshUser") var sshUser = "root"
    @AppStorage("refreshSeconds") var refreshSeconds = 10
    @Published var sshPassword = Keychain.get("sshPassword") { didSet { Keychain.set("sshPassword", sshPassword) } }
    @Published var apiKey = Keychain.get("apiKey") { didSet { Keychain.set("apiKey", apiKey) } }

    @Published var overview: Overview?
    @Published var array: ArrayInfo?
    @Published var containers: [Container] = []
    @Published var vms: [VM] = []
    @Published var shares: [Share] = []
    @Published var notifications: [NotificationItem] = []
    @Published var notificationCounts: NotificationCounts?
    @Published var cpuHistory: [Double] = []
    @Published var memHistory: [Double] = []
    @Published var errors: [String: String] = [:]
    @Published var lastUpdated: Date?
    @Published var connected = false
    @Published var details: SystemDetails?
    @Published var diskExtras: [String: DiskExtra] = [:]
    @Published var containerExtras: [String: ContainerExtra] = [:]
    @Published var upsDevices: [UPS] = []
    @Published var parityHistory: [ParityCheck] = []
    @Published var temps: [TempSensor] = []
    @Published var netRates: [NetRate] = []
    @Published var rxHistory: [Double] = []
    @Published var txHistory: [Double] = []
    @Published var tempHistory: [Double] = []
    private var lastNet: (time: Date, counters: [String: NetCounters])?
    @Published var fans: [Fan] = []
    @Published var load: [Double] = []
    @Published var uptimeSeconds: Double = 0
    @Published var mem: [String: Double] = [:]
    @Published var cores: [Double] = []
    @Published var mounts: [Mount] = []
    @Published var diskIO: [DiskIO] = []
    @Published var procs: [Proc] = []
    @Published var logLines: [String] = []
    @Published var registration: Registration?
    @Published var services: [Service] = []
    @Published var flash: Flash?
    @Published var serverVars: ServerVars?
    private var lastCPU: [String: [Double]] = [:]
    private var lastDisks: (time: Date, c: [String: DiskCounters])?
    private var diskAlertLevel: [String: Int] = [:]
    private var cpuAlerted = false
    private var seenNotifs: Set<String>?
    @Published var shareCfgs: [String: [String: String]] = [:]
    @Published var shareDist: [String: [ShareDist]] = [:]
    @Published var banner: Banner?
    @Published var smart: [String: SmartInfo] = [:]
    @Published var smartLoading = false
    @Published var lastSmart: Date?
    @Published var parityStatus: ParityStatus?
    @Published var consoleOutput = ""
    @Published var consoleRunning = false
    @Published var busyContainers: Set<String> = []
    private var task: Task<Void, Never>?


    var configured: Bool { URL(string: normalizedURL) != nil && !serverURL.isEmpty && !apiKey.isEmpty }
    var host: String? { URL(string: normalizedURL)?.host }
    var normalizedURL: String {
        var s = serverURL.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty && !s.contains("://") { s = "http://" + s }
        return s
    }

    func start() {
        requestNotificationPermission()
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(max(2, self?.refreshSeconds ?? 10)))
            }
        }
    }

    func refresh() async {
        guard configured, let url = URL(string: normalizedURL) else { connected = false; return }
        let c = UnraidClient(baseURL: url, apiKey: apiKey, allowInsecure: allowInsecure)
        var errs: [String: String] = [:]
        var ok = false

        async let o = attempt { try await c.query("""
            { info { os { hostname distro release uptime } cpu { brand cores threads } }
              metrics { cpu { percentTotal } memory { total used percentTotal } } }
            """, as: Overview.self) }
        async let a = attempt { try await c.query("""
            { array { state capacity { kilobytes { free used total } }
              parities { name device size temp status }
              disks { name device size temp status fsSize fsUsed fsFree }
              caches { name device size temp status fsSize fsUsed fsFree } } }
            """, as: ArrayWrap.self).array }
        async let d = attempt { try await c.query(
            "{ docker { containers { id names state status image } } }", as: DockerWrap.self).docker.containers }
        async let v = attempt { try await c.query(
            "{ vms { domains { id name state } } }", as: VMWrap.self).vms.domains }
        async let s = attempt { try await c.query(
            "{ shares { name free used size comment } }", as: SharesWrap.self).shares }
        async let n = attempt { try await c.query("""
            { notifications { overview { unread { info warning alert total } }
              list(filter: { type: UNREAD, offset: 0, limit: 20 }) { id title subject description importance timestamp } } }
            """, as: NotifWrap.self).notifications }

        async let x1 = attempt { try await c.query("""
            { info { baseboard { manufacturer model version } system { manufacturer model version }
              os { kernel arch platform } cpu { manufacturer speed speedmax socket }
              versions { core { unraid kernel api } } } }
            """, as: SystemDetails.self) }
        async let x2 = attempt { () -> [DiskExtra] in
            let f = "name fsType numErrors isSpinning numReads numWrites rotational"
            let r = try await c.query("{ array { parities { \(f) } disks { \(f) } caches { \(f) } } }", as: DiskExtraWrap.self)
            return (r.array.parities ?? []) + (r.array.disks ?? []) + (r.array.caches ?? []) }
        async let x3 = attempt { try await c.query(
            "{ docker { containers { id autoStart created ports { ip privatePort publicPort type } } } }",
            as: DockerExtraWrap.self).docker.containers }
        async let x4 = attempt { try await c.query("""
            { upsDevices { id name model status battery { chargeLevel estimatedRuntime }
              power { loadPercentage inputVoltage outputVoltage } } }
            """, as: UPSWrap.self).upsDevices }
        async let x5 = attempt { try await c.query(
            "{ parityHistory { date duration speed status errors } }", as: ParityWrap.self).parityHistory }

        async let y1 = attempt { try await c.query("{ registration { type state expiration updateExpiration } }", as: RegWrap.self).registration }
        async let y2 = attempt { try await c.query("{ services { name online version } }", as: ServicesWrap.self).services }
        async let y3 = attempt { try await c.query("{ flash { vendor product } }", as: FlashWrap.self).flash }
        async let y4 = attempt { try await c.query(
            "{ vars { name version regTy regState timeZone mdNumDisks fsState safeMode shareCount } }", as: VarsWrap.self).vars }

        let (o1, a1, d1, v1, s1, n1) = await (o, a, d, v, s, n)
        async let y5 = attempt { try await c.query("{ array { parityCheckStatus { running paused progress errors status } } }", as: ParityStatusWrap.self).array.parityCheckStatus }
        let (g1, g2, g3, g4) = await (y1, y2, y3, y4)
        let g5 = await y5
        let (e1, e2, e3, e4, e5) = await (x1, x2, x3, x4, x5)
        func unwrap<T>(_ name: String, _ r: Result<T, Error>) -> T? {
            switch r { case .success(let v): return v
            case .failure(let e): errs[name] = e.localizedDescription; return nil }
        }
        let ro = unwrap("Overview", o1), ra = unwrap("Array", a1), rd = unwrap("Docker", d1)
        let rv = unwrap("VMs", v1), rs = unwrap("Shares", s1), rn = unwrap("Notifications", n1)
        if let ro { overview = ro; ok = true
            if let p = ro.metrics?.cpu?.percentTotal { cpuHistory = Array((cpuHistory + [p]).suffix(60)) }
            if let p = ro.metrics?.memory?.percentTotal { memHistory = Array((memHistory + [p]).suffix(60)) } }
        if let ra { array = ra; ok = true }
        if let rd { containers = rd.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }; ok = true }
        if let rv { vms = rv; ok = true }
        if let rs { shares = rs; ok = true }
        if let rn { notifications = rn.list ?? []; notificationCounts = rn.overview?.unread; ok = true }
        if let r = unwrap("System details", e1) { details = r }
        if let r = unwrap("Disk details", e2) { diskExtras = Dictionary(r.compactMap { e in e.name.map { ($0, e) } }, uniquingKeysWith: { a, _ in a }) }
        if let r = unwrap("Container details", e3) { containerExtras = Dictionary(r.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
        if let r = unwrap("Parity status", g5) { parityStatus = r }
        if let r = unwrap("License", g1) { registration = r }
        if let r = unwrap("Services", g2) { services = r }
        if let r = unwrap("Flash", g3) { flash = r }
        if let r = unwrap("Server", g4) { serverVars = r }
        if case .failure(let e) = e4, ["apcaccess", "No UPS"].contains(where: { e.localizedDescription.contains($0) }) {
            upsDevices = []   // no UPS attached isn't an error
        } else if let r = unwrap("UPS", e4) { upsDevices = r }
        if let r = unwrap("Parity history", e5) { parityHistory = r }
        await refreshRemote(into: &errs)
        errors = errs; connected = ok
        checkAlerts()
        if sshEnabled, !smartLoading, lastSmart.map({ Date().timeIntervalSince($0) > 1800 }) ?? true { Task { await loadSMART() } }
        if ok { lastUpdated = Date() }
    }

    private func refreshRemote(into errs: inout [String: String]) async {
        guard sshEnabled, let host = URL(string: normalizedURL)?.host else { return }
        do {
            let r = try await Remote.run(host: host, user: sshUser, password: sshPassword)
            let now = Date()
            temps = r.temps; fans = r.fans; load = r.load; uptimeSeconds = r.uptime; mem = r.mem
            mounts = r.mounts.sorted { $0.path < $1.path }; procs = r.procs; logLines = r.log
            if let cpu = r.temps.filter(\.isCPU).map(\.celsius).max() { tempHistory = Array((tempHistory + [cpu]).suffix(60)) }
            // per-core CPU %
            var pct: [(Int, Double)] = []
            for (k, v) in r.cpu where k != "cpu" && v.count >= 5 {
                guard let old = lastCPU[k], old.count == v.count, let n = Int(k.dropFirst(3)) else { continue }
                let total = zip(v, old).prefix(8).map { $0 - $1 }.reduce(0, +)
                let idle = (v[3] + v[4]) - (old[3] + old[4])
                if total > 0 { pct.append((n, max(0, min(100, 100 * (1 - idle / total))))) }
            }
            if !pct.isEmpty { cores = pct.sorted { $0.0 < $1.0 }.map(\.1) }
            lastCPU = r.cpu
            // network
            if let last = lastNet {
                let dt = now.timeIntervalSince(last.time)
                if dt > 0.5 {
                    netRates = r.net.compactMap { k, v in
                        last.counters[k].map { NetRate(iface: k, rx: max(0, (v.rx - $0.rx) / dt), tx: max(0, (v.tx - $0.tx) / dt)) }
                    }.sorted { $0.iface < $1.iface }
                    rxHistory = Array((rxHistory + [netRates.map(\.rx).reduce(0, +)]).suffix(60))
                    txHistory = Array((txHistory + [netRates.map(\.tx).reduce(0, +)]).suffix(60))
                }
            }
            lastNet = (now, r.net)
            // disk I/O (sectors are 512 bytes)
            if let last = lastDisks {
                let dt = now.timeIntervalSince(last.time)
                if dt > 0.5 {
                    diskIO = r.disks.compactMap { k, v in
                        last.c[k].map { DiskIO(dev: k, read: max(0, (v.read - $0.read) * 512 / dt), write: max(0, (v.write - $0.write) * 512 / dt)) }
                    }.sorted { $0.dev < $1.dev }
                }
            }
            lastDisks = (now, r.disks)
        } catch { errs["SSH"] = error.localizedDescription }
    }

    // MARK: Alerts

    var allDisks: [Disk] { (array?.parities ?? []) + (array?.disks ?? []) + (array?.caches ?? []) }
    /// Disks currently at or above the warning temperature, hottest first.
    var hotDisks: [(disk: Disk, level: Int)] {
        allDisks.compactMap { d in
            guard let t = d.temp else { return nil }
            let l = t >= Double(diskCritTemp) ? 2 : t >= Double(diskWarnTemp) ? 1 : 0
            return l > 0 ? (d, l) : nil
        }.sorted { ($0.disk.temp ?? 0) > ($1.disk.temp ?? 0) }
    }
    func tempColor(_ t: Double) -> Color {
        t >= Double(diskCritTemp) ? .red : t >= Double(diskWarnTemp) ? .orange : .secondary
    }

    func sendNotification(_ title: String, _ body: String, id: String = UUID().uuidString) {
        guard notifyEnabled, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    func requestNotificationPermission() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkAlerts() {
        // Disk temperatures, with 3° hysteresis so a disk hovering at the limit doesn't spam.
        for d in allDisks {
            guard let t = d.temp, let name = d.name else { continue }
            let level = t >= Double(diskCritTemp) ? 2 : t >= Double(diskWarnTemp) ? 1 : 0
            let prev = diskAlertLevel[name] ?? 0
            if level > prev {
                diskAlertLevel[name] = level
                sendNotification(level == 2 ? "🔥 Disk \(name) critical" : "🌡️ Disk \(name) running hot",
                                 "\(Int(t))°C (limit \(level == 2 ? diskCritTemp : diskWarnTemp)°C)", id: "disk-\(name)-\(level)")
            } else if level < prev {
                let limit = prev == 2 ? diskCritTemp : diskWarnTemp
                if t < Double(limit - 3) { diskAlertLevel[name] = level }
            }
        }
        if let t = temps.filter(\.isCPU).map(\.celsius).max() {
            if t >= Double(cpuWarnTemp), !cpuAlerted {
                cpuAlerted = true
                sendNotification("🌡️ CPU running hot", "\(Int(t))°C (limit \(cpuWarnTemp)°C)", id: "cpu-hot")
            } else if t < Double(cpuWarnTemp - 3) { cpuAlerted = false }
        }
        // New Unraid alerts/warnings (the first poll only records what already exists).
        guard errors["Notifications"] == nil else { return }
        let ids = Set(notifications.map(\.id))
        if let seen = seenNotifs {
            for n in notifications where !seen.contains(n.id) {
                let imp = n.importance?.uppercased()
                if imp == "ALERT" || imp == "WARNING" {
                    sendNotification(imp == "ALERT" ? "⛔️ Unraid alert" : "⚠️ Unraid warning",
                                     n.subject ?? n.title ?? n.description ?? "", id: "unraid-\(n.id)")
                }
            }
        }
        if !ids.isEmpty || seenNotifs == nil { seenNotifs = (seenNotifs ?? []).union(ids) }
    }

    private nonisolated func attempt<T>(_ f: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await f()) } catch { return .failure(error) }
    }

    // wrappers
    struct ArrayWrap: Decodable { let array: ArrayInfo }
    struct DockerWrap: Decodable { struct D: Decodable { let containers: [Container] }; let docker: D }
    struct VMWrap: Decodable { struct V: Decodable { let domains: [VM] }; let vms: V }
    struct DiskExtraWrap: Decodable {
        struct A: Decodable { let parities: [DiskExtra]?; let disks: [DiskExtra]?; let caches: [DiskExtra]? }
        let array: A
    }
    struct DockerExtraWrap: Decodable { struct D: Decodable { let containers: [ContainerExtra] }; let docker: D }
    struct UPSWrap: Decodable { let upsDevices: [UPS] }
    struct ParityWrap: Decodable { let parityHistory: [ParityCheck] }
    struct ParityStatusWrap: Decodable { struct A: Decodable { let parityCheckStatus: ParityStatus? }; let array: A }
    struct RegWrap: Decodable { let registration: Registration? }
    struct ServicesWrap: Decodable { let services: [Service] }
    struct FlashWrap: Decodable { let flash: Flash? }
    struct VarsWrap: Decodable { let vars: ServerVars? }
    struct SharesWrap: Decodable { let shares: [Share] }
    struct NotifWrap: Decodable {
        struct N: Decodable { struct O: Decodable { let unread: NotificationCounts? }; let overview: O?; let list: [NotificationItem]? }
        let notifications: N
    }
}

func bytes(_ kb: Double, unitKB: Bool = true) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(unitKB ? kb * 1024 : kb), countStyle: .decimal)
}
