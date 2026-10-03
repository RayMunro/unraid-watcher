// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import Foundation
import SwiftUI

// MARK: - SMART models

enum Health: String { case ok = "Healthy", warning = "Warning", failing = "Failing", standby = "Standby", unknown = "Unknown"
    var color: Color { switch self { case .ok: .green; case .warning: .orange; case .failing: .red; default: .secondary } }
}
struct SmartAttr: Identifiable { let id: Int; let name: String; let value: Int; let worst: Int; let thresh: Int; let raw: String; let failed: Bool }
struct KV: Identifiable { var id: String { k }; let k: String; let v: String }
struct SmartInfo {
    var dev: String
    var model: String?, serial: String?, firmware: String?
    var capacity: Double?, rotation: Int?
    var passed: Bool?, temp: Double?, hours: Double?, cycles: Double?, errorCount: Double?
    var selfTest: String?
    var attrs: [SmartAttr] = []
    var nvme: [KV] = []
    var concerns: [String] = []
    var standby = false
    var health: Health = .unknown
}

enum Smart {
    static func parse(_ json: String, dev: String) -> SmartInfo {
        var i = SmartInfo(dev: dev)
        guard let d = json.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return i }
        func dict(_ k: String, in x: [String: Any]? = nil) -> [String: Any]? { (x ?? o)[k] as? [String: Any] }
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        let msgs = (dict("smartctl")?["messages"] as? [[String: Any]]) ?? []
        i.standby = msgs.contains { ($0["string"] as? String)?.uppercased().contains("STANDBY") == true }
        i.model = o["model_name"] as? String; i.serial = o["serial_number"] as? String; i.firmware = o["firmware_version"] as? String
        i.capacity = num(dict("user_capacity")?["bytes"]); i.rotation = (o["rotation_rate"] as? NSNumber)?.intValue
        i.passed = dict("smart_status")?["passed"] as? Bool
        i.temp = num(dict("temperature")?["current"]); i.hours = num(dict("power_on_time")?["hours"]); i.cycles = num(o["power_cycle_count"])
        i.errorCount = num(dict("summary", in: dict("ata_smart_error_log"))?["count"])
        i.selfTest = dict("status", in: dict("self_test", in: dict("ata_smart_data")))?["string"] as? String
        var failedAttr = false
        for a in (dict("ata_smart_attributes")?["table"] as? [[String: Any]]) ?? [] {
            guard let id = (a["id"] as? NSNumber)?.intValue else { continue }
            let raw = dict("raw", in: a)
            let rawV = num(raw?["value"]) ?? 0
            let wf = (a["when_failed"] as? String) ?? ""
            let failed = !wf.isEmpty && wf != "-"
            let name = (a["name"] as? String)?.replacingOccurrences(of: "_", with: " ") ?? "Attribute \(id)"
            i.attrs.append(SmartAttr(id: id, name: name, value: (a["value"] as? NSNumber)?.intValue ?? 0, worst: (a["worst"] as? NSNumber)?.intValue ?? 0,
                                     thresh: (a["thresh"] as? NSNumber)?.intValue ?? 0, raw: (raw?["string"] as? String) ?? "\(Int(rawV))", failed: failed))
            if failed { failedAttr = true; i.concerns.append("\(name) has failed (\(wf))") }
            else if [5, 187, 196, 197, 198].contains(id), rawV > 0 { i.concerns.append("\(name): \(Int(rawV))") }
        }
        if let n = dict("nvme_smart_health_information_log") {
            let labels = [("critical_warning", "Critical warning"), ("available_spare", "Available spare %"), ("percentage_used", "Wear used %"),
                          ("data_units_read", "Data units read"), ("data_units_written", "Data units written"), ("power_cycles", "Power cycles"),
                          ("power_on_hours", "Power-on hours"), ("unsafe_shutdowns", "Unsafe shutdowns"), ("media_errors", "Media errors"),
                          ("num_err_log_entries", "Error log entries")]
            for (k, l) in labels { if let v = num(n[k]) { i.nvme.append(KV(k: l, v: String(Int(v)))) } }
            if let v = num(n["critical_warning"]), v > 0 { i.concerns.append("Critical warning flags set (\(Int(v)))") }
            if let v = num(n["media_errors"]), v > 0 { i.concerns.append("Media errors: \(Int(v))") }
            if let v = num(n["percentage_used"]), v >= 90 { i.concerns.append("SSD wear at \(Int(v))%") }
            if let s = num(n["available_spare"]), let t = num(n["available_spare_threshold"]), s < t { i.concerns.append("Available spare below threshold") }
            if i.temp == nil { i.temp = num(n["temperature"]) }
        }
        if i.passed == false || failedAttr { i.health = .failing }
        else if !i.concerns.isEmpty { i.health = .warning }
        else if i.passed == true { i.health = .ok }
        else if i.standby { i.health = .standby }
        return i
    }
}

struct ParityStatus: Decodable { let running: Bool?; let paused: Bool?; let progress: Flex?; let errors: Flex?; let status: LStr? }
struct Banner: Identifiable { let id = UUID(); let text: String; let isError: Bool }

func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func validDev(_ s: String) -> Bool { s.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil }

// MARK: - Store actions

extension Store {
    func show(_ text: String, error: Bool = false) {
        let b = Banner(text: text, isError: error)
        banner = b
        Task { try? await Task.sleep(for: .seconds(error ? 10 : 5)); if banner?.id == b.id { banner = nil } }
    }

    var client: UnraidClient? {
        guard let u = URL(string: normalizedURL) else { return nil }
        return UnraidClient(baseURL: u, apiKey: apiKey, allowInsecure: allowInsecure)
    }

    /// GraphQL mutation. Needs an API key with the right permissions.
    func mutate(_ q: String, ok: String) async {
        guard let c = client else { return }
        do { _ = try await c.query(q, as: MutationResult.self); show(ok) }
        catch { show("\(ok) - failed: \(error.localizedDescription) (mutations need an Admin API key)", error: true) }
        await refresh()
    }

    /// Run a shell command on the server over SSH.
    @discardableResult
    func ssh(_ cmd: String, ok: String? = nil, allowFailure: Bool = false) async -> String? {
        guard sshEnabled, let h = host else { show("Turn on SSH in Settings first.", error: true); return nil }
        do {
            let out = try await Remote.exec(host: h, user: sshUser, password: sshPassword, script: cmd, allowFailure: allowFailure)
            if let ok { show(ok) }
            return out
        } catch is CancellationError { return nil }      // stopped on purpose, so no error banner
        catch { show("SSH command failed: \(error.localizedDescription)", error: true); return nil }
    }

    // Docker
    func containerAction(_ c: Container, _ verb: String) async {
        busyContainers.insert(c.id); defer { busyContainers.remove(c.id) }
        if verb == "restart" {
            if sshEnabled { await ssh("docker restart \(shq(c.displayName))", ok: "Restarted \(c.displayName)") }
            else { await mutate("mutation { docker { stop(id: \"\(c.id)\") { id } } }", ok: "Stopped \(c.displayName)")
                   await mutate("mutation { docker { start(id: \"\(c.id)\") { id } } }", ok: "Restarted \(c.displayName)") }
        } else {
            await mutate("mutation { docker { \(verb)(id: \"\(c.id)\") { id state } } }", ok: "\(verb.capitalized) \(c.displayName)")
        }
        await refresh()
    }
    func containerLogs(_ c: Container) async -> String {
        await ssh("docker logs --tail 300 \(shq(c.displayName)) 2>&1", allowFailure: true) ?? "Couldn't fetch logs."
    }

    // VMs
    func vmAction(_ v: VM, _ verb: String, label: String) async {
        await mutate("mutation { vm { \(verb)(id: \"\(v.id)\") } }", ok: "\(label) \(v.name ?? v.id)")
    }

    // Array & parity
    func setArray(start: Bool) async {
        await mutate("mutation { array { setState(input: { desiredState: \(start ? "START" : "STOP") }) { state } } }", ok: start ? "Starting array" : "Stopping array")
    }
    func parity(_ verb: String) async {
        let args = verb == "start" ? "(correct: false)" : ""
        await mutate("mutation { parityCheck { \(verb)\(args) } }", ok: "Parity check: \(verb)")
    }
    func startParity(correcting: Bool) async {
        await mutate("mutation { parityCheck { start(correct: \(correcting)) } }", ok: correcting ? "Started correcting parity check" : "Started read-only parity check")
    }

    // Disks (SSH)
    func spin(_ devs: [String], up: Bool) async {
        let ds = devs.filter(validDev)
        guard !ds.isEmpty else { return }
        let cmd = ds.map { up ? "dd if=/dev/\($0) of=/dev/null bs=512 count=1 iflag=direct 2>/dev/null" : "hdparm -y /dev/\($0) >/dev/null 2>&1" }.joined(separator: "; ")
        await ssh(cmd, ok: up ? "Spinning up \(ds.joined(separator: ", "))" : "Spinning down \(ds.joined(separator: ", "))", allowFailure: true)
        await refresh()
    }
    func selfTest(_ dev: String, kind: String) async {
        guard validDev(dev) else { return }
        _ = await ssh("smartctl -t \(kind) /dev/\(dev)", ok: "Started \(kind) SMART self-test on \(dev)", allowFailure: true)
    }

    // Mover & power
    func mover(_ verb: String) async { await ssh("mover \(verb)", ok: "Mover \(verb)", allowFailure: true) }
    func power(reboot: Bool) async {
        await ssh("(sleep 1; powerdown\(reboot ? " -r" : "")) >/dev/null 2>&1 &", ok: reboot ? "Reboot requested" : "Shutdown requested", allowFailure: true)
    }

    // Notifications
    func archive(_ n: NotificationItem) async {
        await mutate("mutation { archiveNotification(id: \"\(n.id)\") { id } }", ok: "Archived notification")
    }
    func archiveAll() async {
        for n in notifications { await mutate("mutation { archiveNotification(id: \"\(n.id)\") { id } }", ok: "Archived \(notifications.count) notifications") }
    }

    // Console
    func runConsole(_ cmd: String) async {
        consoleRunning = true; defer { consoleRunning = false }
        let out = await ssh(cmd, allowFailure: true)
        consoleOutput = "$ \(cmd)\n" + (out ?? "(no output - see error banner)")
    }

    // SMART
    func loadSMART() async {
        guard sshEnabled, let h = host, !smartLoading else { return }
        let devs = allDisks.compactMap(\.device).filter(validDev)
        guard !devs.isEmpty else { return }
        smartLoading = true; defer { smartLoading = false }
        let script = devs.map { "echo '===SMART \($0)'; smartctl -j -a -n standby /dev/\($0) 2>/dev/null" }.joined(separator: "\n")
        do {
            let out = try await Remote.exec(host: h, user: sshUser, password: sshPassword, script: script, allowFailure: true)
            var result: [String: SmartInfo] = [:]
            for chunk in out.components(separatedBy: "===SMART ").dropFirst() {
                let lines = chunk.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                guard let dev = lines.first.map({ String($0).trimmingCharacters(in: .whitespaces) }) else { continue }
                var info = Smart.parse(lines.count > 1 ? String(lines[1]) : "", dev: dev)
                // keep last known data for spun-down disks rather than blanking it
                if info.health == .standby || info.health == .unknown, var old = smart[dev], old.health != .unknown {
                    old.standby = info.standby; info = old
                }
                result[dev] = info
            }
            for (dev, info) in result {
                let prev = smart[dev]?.health
                if (info.health == .failing || info.health == .warning), prev != info.health {
                    let name = allDisks.first { $0.device == dev }?.name ?? dev
                    sendNotification(info.health == .failing ? "❌ SMART failure: \(name)" : "⚠️ SMART warning: \(name)",
                                     info.concerns.first ?? "Check the SMART tab", id: "smart-\(dev)-\(info.health.rawValue)")
                }
            }
            smart = result; lastSmart = Date()
        } catch is CancellationError { }
        catch { show("SMART read failed: \(error.localizedDescription)", error: true) }
    }
}
struct MutationResult: Decodable {}
