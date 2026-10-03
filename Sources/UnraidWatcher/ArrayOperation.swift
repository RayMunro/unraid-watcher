// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import SwiftUI

// MARK: - Model (pure, so it can be tested without a server)

/// A long-running job on the array: a data rebuild, a parity build, a parity check, or clearing a new disk.
/// Unraid reports it in the `mdResync*` values of its state file. Sizes and positions are in kilobytes.
struct ArrayOperation: Equatable {
    enum Kind { case rebuildDisks([String]), buildParity, parityCheck, clearDisk, other }

    var action: String              // raw, such as "recon D8", "check", "check P", "clear"
    var posKB: Double
    var sizeKB: Double
    var windowKB: Double            // kilobytes handled in the last reporting window (mdResyncDb)
    var windowSeconds: Double       // length of that window (mdResyncDt), 0 while paused
    var correcting: Bool            // writes corrections to parity (mdResyncCorr)

    var progress: Double { sizeKB > 0 ? min(1, max(0, posKB / sizeKB)) : 0 }
    var paused: Bool { windowSeconds <= 0 }
    var remainingKB: Double { max(0, sizeKB - posKB) }
    /// Speed as Unraid itself reports it, used until the app has taken two readings of its own.
    var reportedSpeedKBps: Double? { windowSeconds > 0 && windowKB > 0 ? windowKB / windowSeconds : nil }

    var kind: Kind {
        let t = action.split(separator: " ").map(String.init)
        switch t.first?.lowercased() {
        case "recon":
            let disks = t.dropFirst().compactMap { x -> String? in
                guard x.count > 1, x.first == "D", Int(x.dropFirst()) != nil else { return nil }
                return String(x.dropFirst())
            }
            return disks.isEmpty ? .buildParity : .rebuildDisks(disks)
        case "check": return .parityCheck
        case "clear": return .clearDisk
        default: return .other
        }
    }

    var title: String {
        switch kind {
        case .rebuildDisks(let d): return d.count == 1 ? "Rebuilding disk \(d[0])" : "Rebuilding disks \(d.joined(separator: " and "))"
        case .buildParity: return "Building parity"
        case .parityCheck: return correcting ? "Parity check (correcting)" : "Parity check (read-only)"
        case .clearDisk: return "Clearing a new disk"
        case .other: return action.isEmpty ? "Array operation" : action
        }
    }

    /// For notifications: what finished.
    var doneName: String {
        switch kind {
        case .rebuildDisks(let d): return d.count == 1 ? "Rebuild of disk \(d[0])" : "Rebuild of disks \(d.joined(separator: " and "))"
        case .buildParity: return "Parity build"
        case .parityCheck: return "Parity check"
        case .clearDisk: return "Clearing of the new disk"
        case .other: return "Array operation"
        }
    }

    /// What this means for your data while it runs.
    var note: String? {
        switch kind {
        case .rebuildDisks(let d):
            return "Until it finishes, \(d.count == 1 ? "disk \(d[0])" : "those disks") \(d.count == 1 ? "is" : "are") being emulated from parity, and the array cannot survive another disk failure."
        case .buildParity: return "The array has no parity protection until this finishes."
        case .parityCheck: return correcting ? "Differences found are corrected by rewriting parity." : "Nothing is changed. Differences are only counted."
        default: return nil
        }
    }

    /// Reads the state values. Returns nil when no operation is running.
    static func from(_ kv: [String: String]) -> ArrayOperation? {
        func num(_ k: String) -> Double? { kv[k].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } }
        guard let size = num("mdResyncSize") ?? num("mdResync"), size > 0, (num("mdResync") ?? size) > 0, let pos = num("mdResyncPos"), pos >= 0 else { return nil }
        return ArrayOperation(action: (kv["mdResyncAction"] ?? "").trimmingCharacters(in: .whitespaces), posKB: pos, sizeKB: size,
                              windowKB: num("mdResyncDb") ?? 0, windowSeconds: num("mdResyncDt") ?? 0, correcting: (num("mdResyncCorr") ?? 0) > 0)
    }
}

/// "about 6 days 3 hours", "4 hours 20 minutes", "35 minutes".
func durationText(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    let d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60
    func u(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n == 1 ? "" : "s")" }
    if d > 0 { return h > 0 ? "\(u(d, "day")) \(u(h, "hour"))" : u(d, "day") }
    if h > 0 { return m > 0 ? "\(u(h, "hour")) \(u(m, "minute"))" : u(h, "hour") }
    return u(max(1, m), "minute")
}

/// What to say when an operation is no longer reported. `exit` is Unraid's exit code for the last one ("0" is success, "-4" is cancelled).
func operationFinishedText(_ op: ArrayOperation, exit: String?) -> (title: String, body: String, failed: Bool) {
    switch exit?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) {
    case nil, "", "0": return ("\(op.doneName) finished", "It completed.", false)
    case "-4": return ("\(op.doneName) was cancelled", "It stopped before finishing.", true)
    case let code?: return ("\(op.doneName) stopped", "It ended with an error (code \(code)). Check the array in the Unraid web interface.", true)
    }
}

// MARK: - Store

extension Store {
    /// Called with each fresh reading (or nil when nothing is running). Works out speed and time left from the app's own readings,
    /// which are steadier than the short window Unraid reports, and sends a notification when an operation ends.
    func updateArrayOperation(_ new: ArrayOperation?, exit: String?) {
        let old = arrayOp
        if let n = new {
            if let last = opSamples.last, n.posKB < last.pos { opSamples = [] }          // it restarted
            opSamples.append((Date(), n.posKB))
            opSamples = Array(opSamples.suffix(40))
            var speed = n.reportedSpeedKBps
            if let first = opSamples.first, let last = opSamples.last, last.t.timeIntervalSince(first.t) >= 20, last.pos > first.pos {
                speed = (last.pos - first.pos) / last.t.timeIntervalSince(first.t)
            }
            opSpeedKBps = n.paused ? nil : speed
            opSecondsLeft = (n.paused || (speed ?? 0) <= 0) ? nil : n.remainingKB / speed!
        } else {
            opSamples = []; opSpeedKBps = nil; opSecondsLeft = nil
        }
        if new != arrayOp { arrayOp = new }
        if let old, new == nil {
            let r = operationFinishedText(old, exit: exit)
            sendNotification(r.failed ? "⚠️ \(r.title)" : "✅ \(r.title)", r.body, id: "array-operation-done")
        }
    }
}
