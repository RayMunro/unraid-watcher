// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import SwiftUI

// MARK: - Model (pure, so it can be tested without a server)

/// A graphics processor, read from the Linux graphics (DRM) devices, or from `nvidia-smi` for NVIDIA cards.
struct GPUReading: Equatable, Identifiable {
    var card: String                // "card0", or "nvidia0"
    var vendor: String              // "0x8086"
    var device: String              // "0x7d55"
    var driver: String              // "i915", "xe", "amdgpu", "nvidia"
    var currentMHz: Double?
    var maxMHz: Double?
    var idleMillis: Double?         // time spent in the lowest power state, counting up (Intel)
    var busyPercent: Double?        // reported directly (AMD, NVIDIA)
    var memoryUsed: Double?         // bytes
    var memoryTotal: Double?        // bytes
    var tempC: Double?
    var euTotal: Int?               // execution units (Intel)
    var subsliceTotal: Int?         // Xe-cores on recent Intel GPUs
    var smiName: String?            // the name nvidia-smi reports
    var id: String { card }

    var name: String { smiName ?? gpuName(vendor: vendor, device: device) }
    var coresText: String? {
        switch (subsliceTotal, euTotal) {
        case (let d?, let e?): return "\(d) \(coreWord) · \(e) execution units"
        case (let d?, nil): return "\(d) \(coreWord)"
        case (nil, let e?): return "\(e) execution units"
        default: return nil
        }
    }
    /// What Intel calls a block of execution units: "Xe-core" on Meteor Lake and later, "subslice" before.
    var coreWord: String { vendor.lowercased().contains("8086") && device.lowercased().replacingOccurrences(of: "0x", with: "").hasPrefix("7d") ? "Xe-cores" : "subslices" }
}

struct GPUState: Equatable {
    var readings: [GPUReading] = []
    var isEmpty: Bool { readings.isEmpty }
}

func gpuName(vendor: String, device: String) -> String {
    let v = vendor.lowercased().replacingOccurrences(of: "0x", with: ""), d = device.lowercased().replacingOccurrences(of: "0x", with: "")
    switch v {
    case "8086":
        switch d {
        case "7d55", "7d45", "7d40", "7d60", "7dd5": return "Intel Arc Graphics (Meteor Lake)"
        case "64a0", "64b0": return "Intel Arc Graphics (Lunar Lake)"
        default: return "Intel Graphics (device \(d))"
        }
    case "1002": return "AMD graphics (device \(d))"
    case "10de": return "NVIDIA graphics (device \(d))"
    default: return v.isEmpty ? "Graphics" : "Graphics (\(v):\(d))"
    }
}

/// How active an Intel GPU is, from how much of the time between two readings it did NOT spend in its lowest power state (RC6).
/// That is "not asleep", which slightly overstates real work but follows it closely.
func gpuActivePercent(previous: (t: Date, idleMillis: Double)?, now: (t: Date, idleMillis: Double)) -> Double? {
    guard let p = previous else { return nil }
    let wall = now.t.timeIntervalSince(p.t) * 1000
    guard wall >= 500, now.idleMillis >= p.idleMillis else { return nil }
    return min(100, max(0, 100 - (now.idleMillis - p.idleMillis) / wall * 100))
}

enum GPUProbe {
    /// Added to the batch read on every refresh. Prints nothing on a server with no graphics device.
    /// Intel: clock and idle time from sysfs (the `i915` and `xe` drivers). AMD: busy percent and memory from sysfs.
    /// NVIDIA: from `nvidia-smi` when it is installed. Core counts come from the kernel's debug files, when they are mounted.
    static let script = """
    for c in /sys/class/drm/card[0-9]*; do
      case "${c##*/}" in *-*) continue;; esac       # skip connectors such as card0-HDMI-A-1
      [ -e "$c/device" ] || continue
      d=$(readlink -f "$c/device" 2>/dev/null)
      [ "$(cat "$d/class" 2>/dev/null | cut -c1-4)" = "0x03" ] || continue
      n=$(basename "$c")
      cur=""; max=""; idle=""
      for g in "$c/gt/gt0" "$c"; do
        [ -z "$cur" ] && cur=$(cat "$g/rps_cur_freq_mhz" 2>/dev/null || cat "$g/gt_cur_freq_mhz" 2>/dev/null)
        [ -z "$max" ] && max=$(cat "$g/rps_max_freq_mhz" 2>/dev/null || cat "$g/gt_max_freq_mhz" 2>/dev/null)
        [ -z "$idle" ] && idle=$(cat "$g/rc6_residency_ms" 2>/dev/null || cat "$g/power/rc6_residency_ms" 2>/dev/null)
      done
      x="$d/tile0/gt0"
      [ -z "$cur" ] && cur=$(cat "$x/freq0/cur_freq" 2>/dev/null)
      [ -z "$max" ] && max=$(cat "$x/freq0/max_freq" 2>/dev/null)
      [ -z "$idle" ] && idle=$(cat "$x/gtidle/idle_residency_ms" 2>/dev/null)
      echo "GPU|$n|$(cat "$d/vendor" 2>/dev/null)|$(cat "$d/device" 2>/dev/null)|$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)|$cur|$max|$idle|$(cat "$d/gpu_busy_percent" 2>/dev/null)|$(cat "$d/mem_info_vram_used" 2>/dev/null)|$(cat "$d/mem_info_vram_total" 2>/dev/null)"
      i=${n#card}
      for f in /sys/kernel/debug/dri/$i/i915_sseu_status /sys/kernel/debug/dri/$i/gt*/sseu_status /sys/kernel/debug/dri/$i/gt/sseu_status; do
        [ -r "$f" ] || continue
        eu=$(grep -m1 -E 'EU Total' "$f" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
        ss=$(grep -m1 -E '(Subslice|DSS|Xe-?core)[^:]*Total' "$f" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
        [ -n "$eu$ss" ] && { echo "GPUCORES|$n|$eu|$ss"; break; }
      done
    done
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,clocks.gr,clocks.max.gr --format=csv,noheader,nounits 2>/dev/null | sed 's/, */|/g; s/^/GPUNV|/'
    fi
    """

    static func parse(_ lines: [String]) -> GPUState {
        var cards: [GPUReading] = []
        var nvidia: [GPUReading] = []
        var cores: [String: (eu: Int?, ss: Int?)] = [:]
        func num(_ x: String) -> Double? { Double(x.trimmingCharacters(in: .whitespacesAndNewlines)) }
        for l in lines {
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            switch f.first {
            case "GPU" where f.count >= 11:
                cards.append(GPUReading(card: f[1], vendor: f[2], device: f[3], driver: f[4], currentMHz: num(f[5]), maxMHz: num(f[6]), idleMillis: num(f[7]),
                                        busyPercent: num(f[8]), memoryUsed: num(f[9]), memoryTotal: num(f[10])))
            case "GPUCORES" where f.count >= 4:
                cores[f[1]] = (Int(f[2]), Int(f[3]))
            case "GPUNV" where f.count >= 9:
                nvidia.append(GPUReading(card: "nvidia\(f[1])", vendor: "0x10de", device: "", driver: "nvidia", currentMHz: num(f[7]), maxMHz: num(f[8]), busyPercent: num(f[3]),
                                         memoryUsed: num(f[4]).map { $0 * 1_048_576 }, memoryTotal: num(f[5]).map { $0 * 1_048_576 }, tempC: num(f[6]), smiName: f[2]))
            default: break
            }
        }
        // nvidia-smi knows more than the generic device node, so it replaces that card
        if !nvidia.isEmpty { cards.removeAll { $0.vendor.lowercased().contains("10de") } }
        cards = cards.map { var c = $0; if let k = cores[c.card] { c.euTotal = k.eu; c.subsliceTotal = k.ss }; return c }
        return GPUState(readings: cards + nvidia)
    }
}

// MARK: - Store

extension Store {
    func updateGPU(_ state: GPUState) {
        if state != gpu { gpu = state }
        let now = Date()
        for r in state.readings {
            var pct: Double? = r.busyPercent
            if pct == nil, let idle = r.idleMillis {
                pct = gpuActivePercent(previous: gpuSamples[r.card], now: (now, idle))
                gpuSamples[r.card] = (now, idle)
            }
            if let pct {
                gpuActivity[r.card] = pct
                gpuHistory[r.card] = Array(((gpuHistory[r.card] ?? []) + [pct]).suffix(60))
            }
        }
        let live = Set(state.readings.map(\.card))
        gpuActivity = gpuActivity.filter { live.contains($0.key) }
        gpuSamples = gpuSamples.filter { live.contains($0.key) }
    }
}

// MARK: - View

struct GPUCards: View {
    @EnvironmentObject var s: Store
    var body: some View {
        ForEach(s.gpu.readings) { r in
            Card(title: s.gpu.readings.count > 1 ? "GPU \(r.card)" : "GPU") {
                let pct = s.gpuActivity[r.card]
                HStack(alignment: .firstTextBaseline) {
                    Text(r.name).font(.body.weight(.medium))
                    Spacer()
                    if let pct { Text(String(format: "%.0f%%", pct)).font(.title3.bold().monospacedDigit()) }
                    else if r.idleMillis != nil || r.busyPercent != nil { Text("measuring…").font(.callout).foregroundStyle(.secondary) }
                }
                if r.idleMillis != nil || r.busyPercent != nil {
                    TorrentBar(fraction: (pct ?? 0) / 100, color: (pct ?? 0) > 75 ? .orange : .indigo, height: 14, label: pct.map { String(format: "%.0f%%", $0) })
                    if let h = s.gpuHistory[r.card], h.count > 1 { Spark(data: h, color: .indigo) }
                }
                if let cores = r.coresText { Label(cores, systemImage: "square.grid.3x3").font(.callout) }
                HStack(spacing: 16) {
                    if let c = r.currentMHz { Text(r.maxMHz.map { "\(Int(c)) of \(Int($0)) MHz" } ?? "\(Int(c)) MHz") }
                    if let u = r.memoryUsed, let t = r.memoryTotal, t > 0 { Text("\(bytes(u, unitKB: false)) of \(bytes(t, unitKB: false)) memory") }
                    if let t = r.tempC { Text("\(Int(t))°C") }
                    if !r.driver.isEmpty { Text("driver \(r.driver)") }
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(note(for: r)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func note(for r: GPUReading) -> String {
        var parts: [String] = []
        if r.idleMillis != nil && r.busyPercent == nil { parts.append("Activity is the share of time the GPU was awake, so it follows real work closely but slightly overstates it.") }
        if r.coresText == nil && r.vendor.lowercased().contains("8086") { parts.append("The core count isn't available: the kernel's debug files aren't readable on this server.") }
        parts.append("Linux does not report load for individual GPU cores, so this is the whole GPU.")
        return parts.joined(separator: " ")
    }
}
