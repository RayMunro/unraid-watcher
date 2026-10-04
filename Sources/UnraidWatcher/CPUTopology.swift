// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import SwiftUI

// MARK: - Model (pure, so it can be tested with made-up CPUs)

enum CoreKind: Int, Comparable {
    case performance, efficiency, lowPowerEfficiency, standard
    static func < (a: CoreKind, b: CoreKind) -> Bool { a.rawValue < b.rawValue }

    var short: String {
        switch self { case .performance: "P-core"; case .efficiency: "E-core"; case .lowPowerEfficiency: "LP E-core"; case .standard: "Core" }
    }
    var groupTitle: String {
        switch self {
        case .performance: "Performance cores"; case .efficiency: "Efficiency cores"
        case .lowPowerEfficiency: "Low-power efficiency cores"; case .standard: "Cores"
        }
    }
    var color: Color {
        switch self { case .performance: .blue; case .efficiency: .teal; case .lowPowerEfficiency: .mint; case .standard: .blue }
    }
}

/// One logical CPU, as the kernel numbers it, with what kind of core it belongs to.
struct CoreInfo: Identifiable, Equatable {
    let cpu: Int
    let kind: CoreKind
    let ordinal: Int        // which core of that kind it is, counting from 1
    let thread: Int         // 1 for the first hardware thread of a core, 2 for the second
    let threadsPerCore: Int
    var id: Int { cpu }
    /// "P-core 3, thread 2", "E-core 5", or "Core 1" on an ordinary CPU.
    var label: String { threadsPerCore > 1 ? "\(kind.short) \(ordinal), thread \(thread)" : "\(kind.short) \(ordinal)" }
}

struct CPURecord: Equatable {
    var cpu: Int
    var siblings: [Int]         // hardware threads that share this core, itself included
    var maxKHz: Double?
    var capacity: Int?          // the kernel's relative performance figure, where it has one
}

struct CPUSets: Equatable { var core: Set<Int>?; var atom: Set<Int>? }

/// "0-7,16,18-19" -> [0,1,2,3,4,5,6,7,16,18,19]
func parseCPUList(_ s: String) -> [Int] {
    var out: [Int] = []
    for part in s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",") {
        let ends = part.split(separator: "-").compactMap { Int($0) }
        if ends.count == 2, ends[0] <= ends[1], ends[1] - ends[0] < 4096 { out += Array(ends[0]...ends[1]) }
        else if ends.count == 1 { out.append(ends[0]) }
    }
    return out
}

/// Decides what kind of core each logical CPU is.
/// 1. Intel hybrid CPUs list their performance and efficiency cores separately (`cpu_core` and `cpu_atom`).
/// 2. Otherwise a spread of kernel capacity values means mixed cores (as on some ARM chips).
/// 3. Among efficiency cores, a clearly lower top speed marks the low-power ones (Meteor Lake and later).
/// 4. With none of that, every core is an ordinary core.
func classifyCores(_ records: [CPURecord], sets: CPUSets) -> [CoreInfo] {
    guard !records.isEmpty else { return [] }
    var kind: [Int: CoreKind] = [:]

    if let p = sets.core, let a = sets.atom, !p.isEmpty, !a.isEmpty {
        for r in records { kind[r.cpu] = p.contains(r.cpu) ? .performance : a.contains(r.cpu) ? .efficiency : .standard }
    } else {
        let caps = records.compactMap(\.capacity)
        if caps.count == records.count, let hi = caps.max(), let lo = caps.min(), Double(hi) / Double(max(lo, 1)) > 1.25 {
            for r in records { kind[r.cpu] = Double(r.capacity!) >= Double(hi) * 0.85 ? .performance : .efficiency }
        } else {
            for r in records { kind[r.cpu] = .standard }
        }
    }

    // Split off the low-power efficiency cores: a separate, slower group among the efficiency cores.
    let eff = records.filter { kind[$0.cpu] == .efficiency }
    if eff.count >= 2 {
        let speeds = eff.map { $0.maxKHz ?? 0 }
        let useSpeed = speeds.allSatisfy { $0 > 0 }
        let measure: (CPURecord) -> Double = { useSpeed ? ($0.maxKHz ?? 0) : Double($0.capacity ?? 0) }
        let top = eff.map(measure).max() ?? 0
        if top > 0 {
            let slow = eff.filter { measure($0) < top * 0.8 }
            if !slow.isEmpty, slow.count < eff.count { for r in slow { kind[r.cpu] = .lowPowerEfficiency } }
        }
    }

    // Group threads into physical cores, in order, and number the cores within each kind.
    var coreKey: [Int: [Int]] = [:]
    for r in records { coreKey[r.cpu] = (r.siblings.isEmpty ? [r.cpu] : r.siblings).sorted() }
    var seen: Set<[Int]> = []
    var ordinalOfCore: [[Int]: Int] = [:]
    var counters: [CoreKind: Int] = [:]
    for r in records.sorted(by: { $0.cpu < $1.cpu }) {
        let key = coreKey[r.cpu]!
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        let k = kind[r.cpu] ?? .standard
        counters[k, default: 0] += 1
        ordinalOfCore[key] = counters[k]!
    }
    return records.sorted(by: { $0.cpu < $1.cpu }).map { r in
        let key = coreKey[r.cpu]!
        return CoreInfo(cpu: r.cpu, kind: kind[r.cpu] ?? .standard, ordinal: ordinalOfCore[key] ?? 1,
                        thread: (key.firstIndex(of: r.cpu) ?? 0) + 1, threadsPerCore: key.count)
    }
}

enum CPUTopology {
    /// Read once per server, because the layout never changes while it is running.
    static let script = """
    for p in /sys/devices/system/cpu/cpu[0-9]*; do
      n=${p##*cpu}
      echo "CPU|$n|$(cat $p/topology/thread_siblings_list 2>/dev/null)|$(cat $p/cpufreq/cpuinfo_max_freq 2>/dev/null)|$(cat $p/cpu_capacity 2>/dev/null)"
    done
    echo "PMU|core|$(cat /sys/devices/cpu_core/cpus 2>/dev/null)"
    echo "PMU|atom|$(cat /sys/devices/cpu_atom/cpus 2>/dev/null)"
    """

    static func parse(_ text: String) -> [CoreInfo] {
        var records: [CPURecord] = []
        var sets = CPUSets()
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if f.count >= 5, f[0] == "CPU", let n = Int(f[1]) {
                records.append(CPURecord(cpu: n, siblings: parseCPUList(f[2]), maxKHz: Double(f[3].trimmingCharacters(in: .whitespaces)), capacity: Int(f[4].trimmingCharacters(in: .whitespaces))))
            } else if f.count >= 3, f[0] == "PMU" {
                let list = parseCPUList(f[2])
                if !list.isEmpty { if f[1] == "core" { sets.core = Set(list) } else if f[1] == "atom" { sets.atom = Set(list) } }
            }
        }
        return classifyCores(records, sets: sets)
    }
}

// MARK: - Store

extension Store {
    /// Learns the core layout the first time it is needed. A failure is quietly ignored: the bars then say "CPU 0", "CPU 1" and so on.
    func loadCPUTopology() async {
        guard sshEnabled, cpuTopology.isEmpty, !cpuTopologyTried, let h = host else { return }
        cpuTopologyTried = true
        if let out = try? await Remote.exec(host: h, user: sshUser, password: sshPassword, script: CPUTopology.script, allowFailure: true) {
            cpuTopology = CPUTopology.parse(out)
        }
    }
}

// MARK: - View

struct CoreBars: View {
    @EnvironmentObject var s: Store

    var body: some View {
        if s.coreUsage.isEmpty { Text("Collecting a second sample…").foregroundStyle(.secondary) }
        else if s.cpuTopology.isEmpty {
            // layout unknown: plain numbered bars
            grid(s.coreUsage.keys.sorted().map { ($0, "CPU \($0)", CoreKind.standard) })
        } else {
            let known = Dictionary(uniqueKeysWithValues: s.cpuTopology.map { ($0.cpu, $0) })
            let groups = Dictionary(grouping: s.cpuTopology.filter { s.coreUsage[$0.cpu] != nil }, by: \.kind)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups.keys.sorted(), id: \.self) { kind in
                    let cores = groups[kind]!.sorted { $0.cpu < $1.cpu }
                    let physical = Set(cores.map { "\($0.ordinal)" }).count
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if groups.count > 1 { Circle().fill(kind.color).frame(width: 9, height: 9) }
                            Text(groups.count > 1 ? kind.groupTitle : "Cores").font(.subheadline.weight(.semibold))
                            Text("\(physical) core\(physical == 1 ? "" : "s"), \(cores.count) thread\(cores.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                        }
                        grid(cores.map { ($0.cpu, $0.label, kind) })
                    }
                }
                // CPUs that reported usage but are missing from the layout (a CPU that came online later)
                let extra = s.coreUsage.keys.filter { known[$0] == nil }.sorted()
                if !extra.isEmpty { grid(extra.map { ($0, "CPU \($0)", CoreKind.standard) }) }
            }
        }
    }

    func grid(_ items: [(cpu: Int, label: String, kind: CoreKind)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 10) {
            ForEach(items, id: \.cpu) { it in
                let v = s.coreUsage[it.cpu] ?? 0
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(it.label).font(.caption); Spacer(); Text("\(Int(v))%").font(.caption.monospacedDigit()) }
                    TorrentBar(fraction: v / 100, color: v > 90 ? .red : v > 75 ? .orange : it.kind.color, height: 8)
                }.help("Logical CPU \(it.cpu)")
            }
        }
    }
}
