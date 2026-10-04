// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import SwiftUI

// MARK: - Model (pure, so it can be tested without a server)

/// A neural processing unit (an "AI accelerator"). Linux shows Intel's through the `intel_vpu` driver, in `/sys/class/accel`.
struct NPUReading: Equatable {
    var node: String            // "accel0"
    var vendor: String          // PCI vendor id, such as "8086"
    var device: String          // PCI device id, such as "7d1d"
    var driver: String
    var busyMicros: Double?     // total time it has spent busy, in microseconds, counting up
    var currentMHz: Double?
    var maxMHz: Double?
    var memoryBytes: Double?
    var name: String { npuName(vendor: vendor, device: device) }
}

/// An NPU that exists on the PCI bus but has no driver, so nothing can be measured.
struct NPUPresent: Equatable { var address: String; var vendor: String; var device: String; var driver: String
    var name: String { npuName(vendor: vendor, device: device) } }

struct NPUState: Equatable {
    var readings: [NPUReading] = []
    var present: [NPUPresent] = []      // processing accelerators found on the PCI bus
    var isEmpty: Bool { readings.isEmpty && present.isEmpty }
}

func npuName(vendor: String, device: String) -> String {
    let v = vendor.lowercased().replacingOccurrences(of: "0x", with: ""), d = device.lowercased().replacingOccurrences(of: "0x", with: "")
    guard v == "8086" else { return v.isEmpty ? "NPU" : "NPU (\(v):\(d))" }
    switch d {
    case "7d1d": return "Intel AI Boost NPU (Meteor Lake)"
    case "ad1d": return "Intel AI Boost NPU (Arrow Lake)"
    case "643e": return "Intel AI Boost NPU (Lunar Lake)"
    default: return "Intel NPU (device \(d))"
    }
}

/// What the busy time says about how hard it is working: the share of the time between two readings that it spent busy.
func npuBusyPercent(previous: (t: Date, busyMicros: Double)?, now: (t: Date, busyMicros: Double)) -> Double? {
    guard let p = previous else { return nil }
    let wall = now.t.timeIntervalSince(p.t) * 1_000_000
    guard wall >= 500_000, now.busyMicros >= p.busyMicros else { return nil }       // too soon, or the counter reset
    return min(100, max(0, (now.busyMicros - p.busyMicros) / wall * 100))
}

enum NPUProbe {
    /// Added to the batch the app reads on every refresh. Prints nothing on a server without an NPU.
    static let script = """
    for a in /sys/class/accel/accel*; do
      [ -e "$a" ] || continue
      d=$(readlink -f "$a/device" 2>/dev/null)
      [ -n "$d" ] || continue
      echo "NPU|$(basename "$a")|$(cat "$d/vendor" 2>/dev/null)|$(cat "$d/device" 2>/dev/null)|$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)|$(cat "$d/npu_busy_time_us" 2>/dev/null)|$(cat "$d/npu_current_frequency_mhz" 2>/dev/null)|$(cat "$d/npu_max_frequency_mhz" 2>/dev/null)|$(cat "$d/npu_memory_utilization" 2>/dev/null)"
    done
    for p in /sys/bus/pci/devices/*; do
      [ "$(cat "$p/class" 2>/dev/null | cut -c1-6)" = "0x1200" ] || continue
      echo "NPUPCI|$(basename "$p")|$(cat "$p/vendor" 2>/dev/null)|$(cat "$p/device" 2>/dev/null)|$(basename "$(readlink -f "$p/driver" 2>/dev/null)" 2>/dev/null)"
    done
    """

    static func parse(_ lines: [String]) -> NPUState {
        var s = NPUState()
        func num(_ x: String) -> Double? { Double(x.trimmingCharacters(in: .whitespacesAndNewlines)) }
        for l in lines {
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if f.first == "NPU", f.count >= 9 {
                s.readings.append(NPUReading(node: f[1], vendor: f[2], device: f[3], driver: f[4], busyMicros: num(f[5]), currentMHz: num(f[6]), maxMHz: num(f[7]), memoryBytes: num(f[8])))
            } else if f.first == "NPUPCI", f.count >= 5 {
                s.present.append(NPUPresent(address: f[1], vendor: f[2], device: f[3], driver: f[4]))
            }
        }
        // a device that has a driver node appears in both lists, so keep the PCI entry only for the ones that have no node
        let withNode = Set(s.readings.map { $0.device.lowercased() })
        s.present = s.present.filter { !withNode.contains($0.device.lowercased()) }
        return s
    }
}

// MARK: - Store

extension Store {
    func updateNPU(_ state: NPUState) {
        if state != npu { npu = state }
        guard let r = state.readings.first, let busy = r.busyMicros else { npuUtilisation = nil; npuSample = nil; return }
        let now = (t: Date(), busyMicros: busy)
        if let u = npuBusyPercent(previous: npuSample, now: now) { npuUtilisation = u; npuHistory = Array((npuHistory + [u]).suffix(60)) }
        npuSample = now
    }
}

// MARK: - View

struct NPUCard: View {
    @EnvironmentObject var s: Store
    var body: some View {
        if let r = s.npu.readings.first {
            Card(title: "NPU") {
                HStack(alignment: .firstTextBaseline) {
                    Text(r.name).font(.body.weight(.medium))
                    Spacer()
                    if let u = s.npuUtilisation { Text(String(format: "%.0f%%", u)).font(.title3.bold().monospacedDigit()) }
                    else { Text("measuring…").font(.callout).foregroundStyle(.secondary) }
                }
                TorrentBar(fraction: (s.npuUtilisation ?? 0) / 100, color: (s.npuUtilisation ?? 0) > 75 ? .orange : .purple, height: 14,
                           label: s.npuUtilisation.map { String(format: "%.0f%%", $0) })
                if s.npuHistory.count > 1 { Spark(data: s.npuHistory, color: .purple) }
                HStack(spacing: 16) {
                    if let c = r.currentMHz { Text(r.maxMHz.map { "\(Int(c)) of \(Int($0)) MHz" } ?? "\(Int(c)) MHz") }
                    if let m = r.memoryBytes, m > 0 { Text("\(bytes(m, unitKB: false)) in use") }
                    if !r.driver.isEmpty { Text("driver \(r.driver)") }
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if r.busyMicros == nil { Text("This driver version does not report how busy the NPU is.").font(.caption).foregroundStyle(.secondary) }
            }
        } else if let p = s.npu.present.first {
            Card(title: "NPU") {
                Text(p.name).font(.body.weight(.medium))
                Text(p.driver.isEmpty ? "Found on the PCI bus, but no driver is loaded for it, so its activity can't be read. On Unraid the Intel NPU driver (intel_vpu) needs to be present in the kernel." : "Found on the PCI bus with the \(p.driver) driver, but it does not offer a device to read.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
