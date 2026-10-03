// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import SwiftUI

// MARK: - Logic (pure, so it can be tested against a fake pool)

/// A folder tree that contains no files at all, anywhere inside it.
struct EmptyRoot: Identifiable, Hashable {
    let pool: String
    let rel: String          // "./media/old", relative to the pool
    let dirs: Int            // how many folders the tree holds, itself included
    let newest: Double       // most recent change anywhere in the tree (epoch seconds)
    var id: String { pool + "|" + rel }
    var top: String { String(rel.dropFirst(2).split(separator: "/").first ?? "") }
    var isTopLevel: Bool { !rel.dropFirst(2).contains("/") }
    func ageDays(now: Date = Date()) -> Double { max(0, (now.timeIntervalSince1970 - newest) / 86400) }
}

/// Top-level folder names that are safe to hand to the shell: no slashes, quotes, or control characters.
func validSkipName(_ s: String) -> Bool { s.range(of: #"^[A-Za-z0-9][A-Za-z0-9 ._-]*$"#, options: .regularExpression) != nil }

/// Finds empty folder trees. Uses only commands common to GNU and BSD systems, and never changes anything.
/// Folders named in `skip` are not even entered, which also keeps the scan fast. It runs at low priority with a time limit.
func cleanupScanScript(pool: String, skip: [String] = [], mnt: String = "/mnt") -> String {
    let prune = skip.filter(validSkipName).map { "-path " + shq("./" + $0) }.joined(separator: " -o ")
    let pruneExpr = prune.isEmpty ? "" : "\\( \(prune) \\) -prune -o"
    return #"""
    P=\#(shq("\(mnt)/\(pool)"))
    [ -d "$P" ] || { echo "ERR no such pool"; exit 1; }
    cd "$P" || exit 1
    W=$(mktemp -d) || exit 1
    trap 'rm -rf "$W"' EXIT
    trap 'exit 1' HUP INT TERM PIPE
    export LC_ALL=C
    # low priority, and a time limit when the tools exist
    L=""; command -v ionice >/dev/null 2>&1 && L="ionice -c3"; command -v nice >/dev/null 2>&1 && L="$L nice -n 19"
    command -v timeout >/dev/null 2>&1 && L="timeout 1500 $L"
    # every folder, and every folder that has at least one file or link somewhere beneath it
    $L find . -xdev -mindepth 1 \#(pruneExpr) -type d -print 2>/dev/null | sort > "$W/all"
    $L find . -xdev -mindepth 1 \#(pruneExpr) ! -type d -exec dirname {} + 2>/dev/null | sort -u | awk '{ p=$0; while (p != "." && p != "" && !(p in s)) { s[p]=1; sub(/\/[^\/]*$/, "", p) } } END { for (k in s) print k }' | sort > "$W/used"
    comm -23 "$W/all" "$W/used" > "$W/empty"
    # keep only the top of each empty tree: folders whose parent is not itself empty
    awk 'NR==FNR { e[$0]=1; next } { p=$0; sub(/\/[^\/]*$/, "", p); if (!(p in e)) print $0 }' "$W/empty" "$W/empty" | head -n 2000 > "$W/roots"
    cnt=$(wc -l < "$W/roots" | tr -d ' ')
    while IFS= read -r r; do
      n=$(find "$r" -xdev -type d 2>/dev/null | wc -l | tr -d ' ')
      newest=$(find "$r" -xdev -type d -exec sh -c 'stat -c %Y "$@" 2>/dev/null || stat -f %m "$@"' _ {} + 2>/dev/null | sort -n | tail -1)
      printf 'ROOT\t%s\t%s\t%s\t%s\n' \#(shq(pool)) "$n" "$newest" "$r"
    done < "$W/roots"
    [ "$cnt" -ge 2000 ] && echo TRUNCATED
    echo DONE
    """#
}

/// True when the scan stopped at its limit of 2000 trees per pool, so more exist than were listed.
func scanWasTruncated(_ output: String) -> Bool { output.split(separator: "\n").contains("TRUNCATED") }

func parseEmptyRoots(_ output: String) -> [EmptyRoot] {
    output.split(separator: "\n").compactMap { line in
        let f = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        guard f.count == 5, f[0] == "ROOT", let n = Int(f[2]), let t = Double(f[3]), validCleanupPath(f[4]) else { return nil }
        return EmptyRoot(pool: f[1], rel: f[4], dirs: n, newest: t)
    }
}

/// Only paths inside a pool, never the pool itself and never anything that climbs out of it.
func validCleanupPath(_ rel: String) -> Bool {
    guard rel.hasPrefix("./"), rel.count > 2, !rel.contains("\n"), !rel.contains("\0") else { return false }
    let parts = rel.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    return parts[0] == "." && parts.dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
}
func validPoolName(_ s: String) -> Bool { s.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil }

/// Removes only folders that are empty at the moment they are visited, deepest first. A folder that gained a file is left alone.
func cleanupDeleteScript(pool: String, rels: [String], mnt: String = "/mnt") -> String {
    "cd \(shq("\(mnt)/\(pool)")) || exit 1\n" + rels.map { "find \(shq($0)) -xdev -depth -type d -empty -print -delete 2>/dev/null" }.joined(separator: "\n") + "\necho DONE"
}
func parseRemovedCount(_ output: String) -> Int { output.split(separator: "\n").filter { $0.hasPrefix("./") }.count }

// MARK: - Store

extension Store {
    /// Pools are mounted at /mnt/<name>. Array disks, the merged views, and unassigned devices are not pools.
    var cachePools: [String] {
        mounts.compactMap { m -> String? in
            let parts = m.path.split(separator: "/").map(String.init)
            guard parts.count == 2, parts[0] == "mnt" else { return nil }
            let n = parts[1]
            if n.range(of: #"^disk\d+$"#, options: .regularExpression) != nil { return nil }
            if ["user", "user0", "disks", "remotes", "addons", "rootshare"].contains(n) { return nil }
            return validPoolName(n) ? n : nil
        }.sorted()
    }

    /// Returns the empty trees found, and the pools where the list was cut off at its limit.
    func scanEmptyFolders(pools: [String], skip: [String] = []) async -> (roots: [EmptyRoot], truncated: [String])? {
        var all: [EmptyRoot] = []
        var truncated: [String] = []
        for p in pools where validPoolName(p) {
            if Task.isCancelled { return nil }
            guard let out = await ssh(cleanupScanScript(pool: p, skip: skip), allowFailure: true) else { return nil }
            if out.contains("ERR no such pool") { show("The pool \(p) isn't mounted on this server.", error: true); return nil }
            guard out.contains("DONE") else { show("The scan of \(p) didn't finish.", error: true); return nil }
            all += parseEmptyRoots(out)
            if scanWasTruncated(out) { truncated.append(p) }
        }
        return (all, truncated)
    }

    func deleteEmptyFolders(_ roots: [EmptyRoot]) async -> Int {
        var removed = 0
        for (pool, group) in Dictionary(grouping: roots, by: \.pool) {
            let rels = group.map(\.rel).filter(validCleanupPath)
            guard validPoolName(pool), !rels.isEmpty else { continue }
            guard let out = await ssh(cleanupDeleteScript(pool: pool, rels: rels), allowFailure: true) else { return removed }
            removed += parseRemovedCount(out)
        }
        return removed
    }
}

// MARK: - Sheet

struct CacheCleanupSheet: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cleanupDays") private var days = 7
    @AppStorage("cleanupSkip") private var skip = "appdata,system,domains"
    @AppStorage("cleanupIncludeTop") private var includeTop = false
    @AppStorage("cleanupMinAgeMinutes") private var minAge = 60
    @AppStorage("cleanupFullCompare") private var fullCompare = false
    @State private var pools: Set<String> = []
    // empty folders
    @State private var results: [EmptyRoot] = []
    @State private var checked: Set<String> = []
    @State private var truncatedPools: [String] = []
    @State private var confirming = false
    @State private var deleting = false
    // files already on the array
    @State private var stray: StrayScan?
    @State private var strayChecked: Set<String> = []
    @State private var confirmingFiles = false
    @State private var deletingFiles = false
    // shared
    @State private var scanning = false
    @State private var step = ""
    @State private var scanned = false
    @State private var task: Task<Void, Never>?

    var skipNames: [String] { skip.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    var skipSet: Set<String> { Set(skipNames.map { $0.lowercased() }) }

    // empty folders
    var visible: [EmptyRoot] {
        results.filter { r in !skipSet.contains(r.top.lowercased()) && (includeTop || !r.isTopLevel) && r.ageDays() >= Double(days) }
            .sorted { ($0.pool, $0.rel) < ($1.pool, $1.rel) }
    }
    var selected: [EmptyRoot] { visible.filter { checked.contains($0.id) } }
    var selectedDirs: Int { selected.map(\.dirs).reduce(0, +) }

    // files already on the array
    var identical: [StrayFile] { (stray?.files ?? []).filter(\.identical) }
    var differing: [StrayFile] { (stray?.files ?? []).filter { !$0.identical } }
    var selectedFiles: [StrayFile] { identical.filter { strayChecked.contains($0.id) } }
    var selectedBytes: Double { selectedFiles.map(\.size).reduce(0, +) }
    /// How the share this file belongs to treats the cache. Only a "yes" share has the mover move files from cache to array.
    func mode(_ top: String) -> (text: String, color: Color, mover: Bool) {
        switch s.shareCfgs[top]?["shareUseCache"] {
        case "yes": return ("Mover share", .green, true)
        case "prefer": return ("Prefers cache", .orange, false)
        case "only": return ("Cache only", .orange, false)
        case "no": return ("No cache", .gray, false)
        default: return ("No settings", .gray, false)
        }
    }

    func scan() {
        task?.cancel()
        scanning = true; scanned = false; results = []; checked = []; stray = nil; strayChecked = []; truncatedPools = []
        task = Task {
            step = "Looking for empty folders…"
            let r = await s.scanEmptyFolders(pools: pools.sorted(), skip: skipNames)
            if Task.isCancelled { scanning = false; return }
            results = r?.roots ?? []; truncatedPools = r?.truncated ?? []
            checked = Set(visible.map(\.id))
            step = fullCompare ? "Comparing cache files with the array, byte for byte…" : "Comparing cache files with the array…"
            let st = await s.scanStrayFiles(pools: pools.sorted(), skip: skipNames, minAgeMinutes: minAge, fullCompare: fullCompare)
            if Task.isCancelled { scanning = false; return }
            stray = st
            strayChecked = Set(identical.filter { mode($0.top).mover }.map(\.id))
            scanned = r != nil || st != nil
            scanning = false
        }
    }
    func age(_ r: EmptyRoot) -> String {
        let d = r.ageDays()
        return d >= 365 ? "unchanged for \(Int(d / 365)) y" : d >= 1 ? "unchanged for \(Int(d)) days" : "changed today"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) { Text("Clean up the cache").font(.title3.bold()); Text("On \(s.profile.name)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Close") { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            GroupBox("What to look at") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pools:")
                        ForEach(s.cachePools, id: \.self) { p in
                            Toggle(p, isOn: Binding(get: { pools.contains(p) }, set: { if $0 { pools.insert(p) } else { pools.remove(p) } })).toggleStyle(.checkbox)
                        }
                        if s.cachePools.isEmpty { Text("No cache pools found").foregroundStyle(.secondary) }
                    }
                    HStack { Text("Never touch these top-level folders:"); TextField("appdata,system,domains", text: $skip).textFieldStyle(.roundedBorder) }
                    Divider()
                    Text("Files left behind by the mover").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Stepper("Leave files changed in the last \(minAge) minute\(minAge == 1 ? "" : "s") alone", value: $minAge, in: 0...10080, step: 15)
                    Picker("Decide a file is the same as its array copy by", selection: $fullCompare) {
                        Text("Size and date (quick)").tag(false); Text("Every byte (slow, thorough)").tag(true)
                    }.pickerStyle(.segmented)
                    Text("Either way, each file is compared byte for byte with its array copy again just before it is deleted.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Empty folders").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Stepper("Only trees unchanged for \(days) day\(days == 1 ? "" : "s") or more", value: $days, in: 0...365)
                    Toggle("Also remove empty top-level folders (the folder for a share)", isOn: $includeTop).toggleStyle(.checkbox)
                    HStack {
                        Button(scanning ? "Scanning…" : "Scan the cache") { scan() }.disabled(scanning || pools.isEmpty).keyboardShortcut(.defaultAction)
                        if scanning { ProgressView().controlSize(.small); Text(step).font(.caption).foregroundStyle(.secondary); Button("Stop") { task?.cancel(); scanning = false } }
                        Spacer()
                        if !scanning { Text("Scanning only reads; nothing is deleted until you confirm.").font(.caption).foregroundStyle(.secondary) }
                    }
                }.padding(6)
            }
            if scanned {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        strayFilesSection
                        emptyFoldersSection
                    }.padding(.trailing, 8)
                }
            }
        }
        .padding().frame(width: 820, height: 760, alignment: .top)
        .onAppear { if pools.isEmpty { pools = Set(s.cachePools) } }
        .task { await s.loadShareConfigs() }
        .onDisappear { task?.cancel() }
        .confirmationDialog("Delete \(selectedFiles.count) file\(selectedFiles.count == 1 ? "" : "s") from the cache on \(s.profile.name)?", isPresented: $confirmingFiles, titleVisibility: .visible) {
            Button("Delete files from the cache", role: .destructive) {
                let todo = selectedFiles
                deletingFiles = true
                Task {
                    let r = await s.deleteStrayFiles(todo)
                    deletingFiles = false
                    if let r {
                        let sizes = Dictionary(uniqueKeysWithValues: todo.map { ($0.rel, $0.size) })
                        let freed = r.deleted.compactMap { sizes[$0] }.reduce(0, +)
                        var msg = "Removed \(r.deleted.count) file\(r.deleted.count == 1 ? "" : "s") (\(bytes(freed, unitKB: false))) from the cache"
                        if !r.skipped.isEmpty { msg += ". Kept \(r.skipped.count) that failed a check: " + Set(r.skipped.map(\.reason)).sorted().joined(separator: ", ") }
                        s.show(msg)
                    }
                    scan()
                }
            }
        } message: { Text("These are copies of files that are also on the array. Each one is checked again, byte for byte against its array copy, right before it is deleted. A file that has changed, or whose array copy is missing or different, is kept. The array copy is never touched.") }
        .confirmationDialog("Delete \(selectedDirs) empty folder\(selectedDirs == 1 ? "" : "s") on \(s.profile.name)?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete empty folders", role: .destructive) {
                let todo = selected
                deleting = true
                Task {
                    let n = await s.deleteEmptyFolders(todo)
                    deleting = false
                    s.show("Removed \(n) empty folder\(n == 1 ? "" : "s") from \(Set(todo.map(\.pool)).sorted().joined(separator: ", "))")
                    scan()
                }
            }
        } message: { Text("Only folders with no files anywhere inside are removed, and each is checked again at the moment it is deleted. A folder that has gained a file since the scan is left alone.") }
    }

    // MARK: sections

    @ViewBuilder var strayFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files left behind by the mover").font(.headline)
            if let st = stray {
                if st.moverRunning { Label("The mover is running right now, so deleting is switched off until it finishes. Scan again afterwards.", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                if st.timedOut { Label("The comparison ran out of time and only covers part of the cache. Try the quick comparison, or more skipped folders.", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.orange) }
                Text(st.sameCount == 0 ? "No cache file has an identical copy on the array." :
                     "\(st.sameCount) file\(st.sameCount == 1 ? "" : "s") (\(bytes(st.sameBytes, unitKB: false))) on the cache also exist, identically, on the array." +
                     (st.diffCount > 0 ? " \(st.diffCount) more differ from their array copy and are kept." : ""))
                    .font(.callout.weight(.medium))
                if st.truncated { Label("Showing the biggest 5000 files only. Delete these and scan again for the rest.", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                if !identical.isEmpty {
                    HStack {
                        Text("Ticked by default: files in shares that use the mover. Other shares are listed but not ticked.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Select all") { strayChecked = Set(identical.map(\.id)) }
                        Button("Select none") { strayChecked = [] }
                    }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(identical) { f in
                                let m = mode(f.top)
                                HStack(spacing: 10) {
                                    Toggle("", isOn: Binding(get: { strayChecked.contains(f.id) }, set: { if $0 { strayChecked.insert(f.id) } else { strayChecked.remove(f.id) } })).toggleStyle(.checkbox).labelsHidden()
                                    Pill(text: f.pool, color: .orange)
                                    Text(String(f.rel.dropFirst(1))).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Pill(text: m.text, color: m.color)
                                    Text("on \(f.disk)").font(.caption).foregroundStyle(.secondary)
                                    Text(bytes(f.size, unitKB: false)).monospacedDigit().frame(width: 80, alignment: .trailing)
                                }.padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }.frame(maxHeight: 230)
                    HStack {
                        Text("\(selectedFiles.count) selected, \(bytes(selectedBytes, unitKB: false)) to free").foregroundStyle(.secondary)
                        Spacer()
                        if deletingFiles { ProgressView().controlSize(.small) }
                        Button("Delete selected files…", role: .destructive) { confirmingFiles = true }.disabled(selectedFiles.isEmpty || deletingFiles || st.moverRunning)
                    }
                }
                if !differing.isEmpty {
                    DisclosureGroup("\(differing.count) file\(differing.count == 1 ? "" : "s") differ from the array copy (kept, never offered)") {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(differing.prefix(200)) { f in
                                HStack { Pill(text: f.pool, color: .gray); Text(String(f.rel.dropFirst(1))).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle); Spacer(); Text("on \(f.disk)").font(.caption2).foregroundStyle(.secondary) }
                            }
                            if differing.count > 200 { Text("and \(differing.count - 200) more").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.top, 4)
                    }.font(.callout)
                }
            } else {
                Text("The comparison with the array didn't complete.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder var emptyFoldersSection: some View {
        let hidden = results.count - visible.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Empty folders").font(.headline)
                Spacer()
                Button("Select all") { checked = Set(visible.map(\.id)) }
                Button("Select none") { checked = [] }
            }
            Text("\(visible.count) empty folder tree\(visible.count == 1 ? "" : "s") found" + (hidden > 0 ? " (\(hidden) hidden by your settings)" : "")).font(.callout.weight(.medium))
            Text("After deleting files above, scan again: the folders they leave empty show up here.").font(.caption).foregroundStyle(.secondary)
            if !truncatedPools.isEmpty {
                Label("The list stopped at 2000 trees in \(truncatedPools.joined(separator: ", ")), and there are more. Delete these and scan again to find the rest.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            if visible.isEmpty { Text("Nothing to clean up with these settings.").foregroundStyle(.secondary).padding(.vertical, 8) }
            else {
                ScrollView {
                    LazyVStack(spacing: 0) {      // only the visible rows are drawn, so thousands of results stay fast
                        ForEach(visible) { r in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(get: { checked.contains(r.id) }, set: { if $0 { checked.insert(r.id) } else { checked.remove(r.id) } })).toggleStyle(.checkbox).labelsHidden()
                                Pill(text: r.pool, color: .orange)
                                Text(String(r.rel.dropFirst(1))).font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(r.dirs) folder\(r.dirs == 1 ? "" : "s")").foregroundStyle(.secondary).monospacedDigit()
                                Text(age(r)).font(.caption).foregroundStyle(.secondary).frame(width: 130, alignment: .trailing)
                            }.padding(.vertical, 5)
                            Divider()
                        }
                    }
                }.frame(maxHeight: 230)
                HStack {
                    Text("\(selected.count) selected, \(selectedDirs) empty folder\(selectedDirs == 1 ? "" : "s") in total").foregroundStyle(.secondary)
                    Spacer()
                    if deleting { ProgressView().controlSize(.small) }
                    Button("Delete selected folders…", role: .destructive) { confirming = true }.disabled(selected.isEmpty || deleting)
                }
            }
        }
    }
}
