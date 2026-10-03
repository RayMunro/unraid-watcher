// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ray Munro

import Foundation

// MARK: - Logic (pure, so it can be tested against a fake pool and fake array)

/// A file on a cache pool that also exists, at the same path, on an array disk. These are what an interrupted or blocked
/// mover leaves behind. Only files whose array copy matches are ever offered for removal.
struct StrayFile: Identifiable, Hashable {
    let pool: String
    let rel: String          // "./media/film.mkv", relative to the pool
    let disk: String         // the array disk that holds the copy, such as "disk3"
    let size: Double         // bytes
    let mtime: Double        // epoch seconds, as seen at scan time
    let identical: Bool      // false when the array copy differs
    var id: String { pool + "|" + rel }
    var top: String { String(rel.dropFirst(2).split(separator: "/").first ?? "") }
}

struct StrayScan {
    var files: [StrayFile] = []
    var sameCount = 0
    var sameBytes = 0.0
    var diffCount = 0
    var truncated = false
    var moverRunning = false
    var timedOut = false
}

/// Finds files on the pool that also exist, at the same path, on a real array disk (`/mnt/disk1`, `/mnt/disk2`, and so on).
/// Read-only. `fullCompare` reads both files and compares
/// every byte; otherwise size and modified time are compared, which is quick and is what the mover preserves.
func strayScanScript(pool: String, skip: [String] = [], minAgeMinutes: Int = 60, fullCompare: Bool = false, mnt: String = "/mnt") -> String {
    let names = skip.filter(validSkipName).map { "-path " + shq("./" + $0) } + ["-path './lost+found'", "-name '.Trash-*'"]
    let prune = names.joined(separator: " -o ")
    // -mindepth would switch off the skip rule for top-level folders, so root-level files are excluded with -path instead.
    let ageClause = minAgeMinutes > 0 ? "-mmin +\(minAgeMinutes) " : ""
    return #"""
    MNT=\#(shq(mnt))
    P="$MNT"/\#(shq(pool))
    [ -d "$P" ] || { echo "ERR no such pool"; exit 1; }
    ls -d "$MNT"/disk[0-9]* >/dev/null 2>&1 || { echo "ERR no array view"; exit 1; }
    cd "$P" || exit 1
    W=$(mktemp -d) || exit 1
    trap 'rm -rf "$W"' EXIT
    trap 'exit 1' HUP INT TERM PIPE
    export LC_ALL=C
    FULL=\#(fullCompare ? 1 : 0)
    T=$(printf '\t')
    L=""; command -v ionice >/dev/null 2>&1 && L="ionice -c3"; command -v nice >/dev/null 2>&1 && L="$L nice -n 19"
    command -v timeout >/dev/null 2>&1 && L="timeout 1800 $L"
    sz() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1"; }
    mt() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
    pgrep -f '[s]bin/mover' >/dev/null 2>&1 && echo MOVER
    $L find . -xdev -mindepth 1 \( \#(prune) \) -prune -o -type f -path './*/*' \#(ageClause)-print 2>/dev/null > "$W/files"
    END=$(( $(date +%s) + 900 ))
    : > "$W/found"
    while IFS= read -r f; do
      r=${f#./}
      a=""
      for d in "$MNT"/disk[0-9]*; do [ -f "$d/$r" ] && { a="$d/$r"; break; }; done
      [ -n "$a" ] || continue
      if [ "$(date +%s)" -ge "$END" ]; then echo TIMEOUT; break; fi
      s=$(sz "$f"); t=$(mt "$f"); as=$(sz "$a"); st=DIFF
      if [ "$s" = "$as" ]; then
        if [ "$FULL" = 1 ]; then $L cmp -s "$f" "$a" && st=SAME
        else [ "$t" = "$(mt "$a")" ] && st=SAME; fi
      fi
      disk=${a#"$MNT"/}; disk=${disk%%/*}
      printf 'FILE\t%s\t%s\t%s\t%s\t%s\t%s\n' "$st" \#(shq(pool)) "$s" "$t" "$disk" "$f" >> "$W/found"
    done < "$W/files"
    awk -F "$T" '$2=="SAME" { c++; b+=$4 } $2=="DIFF" { d++ } END { printf "TOTALS\t%d\t%.0f\t%d\n", c, b, d }' "$W/found"
    sort -t "$T" -k4,4nr "$W/found" | head -n 5000
    [ "$(wc -l < "$W/found" | tr -d ' ')" -gt 5000 ] && echo TRUNCATED
    echo DONE
    """#
}

func parseStrayScan(_ output: String) -> StrayScan {
    var r = StrayScan()
    for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
        if line == "MOVER" { r.moverRunning = true; continue }
        if line == "TIMEOUT" { r.timedOut = true; continue }
        if line == "TRUNCATED" { r.truncated = true; continue }
        let f = line.split(separator: "\t", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
        if f.count == 4, f[0] == "TOTALS" { r.sameCount = Int(f[1]) ?? 0; r.sameBytes = Double(f[2]) ?? 0; r.diffCount = Int(f[3]) ?? 0; continue }
        guard f.count == 7, f[0] == "FILE", f[1] == "SAME" || f[1] == "DIFF", let size = Double(f[3]), let mt = Double(f[4]),
              validCleanupPath(f[6]), f[5].range(of: #"^disk\d+$"#, options: .regularExpression) != nil else { continue }
        r.files.append(StrayFile(pool: f[2], rel: f[6], disk: f[5], size: size, mtime: mt, identical: f[1] == "SAME"))
    }
    return r
}

/// Removes cache files, but only after checking each one again, right then: it must still exist, still be the size and age it
/// was at the scan, still have a copy on an array disk, and that copy must match it byte for byte. The mover must not be running.
/// Anything that fails a check is skipped and reported. Only regular files are removed, never folders.
func strayDeleteScript(pool: String, files: [(rel: String, size: Int, mtime: Int)], mnt: String = "/mnt") -> String {
    let calls = files.filter { validCleanupPath($0.rel) }.map { "chk \(shq($0.rel)) \($0.size) \($0.mtime)" }.joined(separator: "\n")
    return #"""
    MNT=\#(shq(mnt))
    P="$MNT"/\#(shq(pool))
    [ -d "$P" ] || { echo "ERR no such pool"; exit 1; }
    if pgrep -f '[s]bin/mover' >/dev/null 2>&1; then echo "ERR mover running"; exit 1; fi
    cd "$P" || exit 1
    export LC_ALL=C
    T=$(printf '\t')
    sz() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1"; }
    mt() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
    chk() {
      f=$1; es=$2; et=$3; r=${f#./}
      if [ ! -f "$f" ] || [ -L "$f" ]; then printf 'SKIP\t%s\tmissing\n' "$f"; return; fi
      a=""
      for d in "$MNT"/disk[0-9]*; do [ -f "$d/$r" ] && [ ! -L "$d/$r" ] && { a="$d/$r"; break; }; done
      if [ -z "$a" ]; then printf 'SKIP\t%s\tnot on the array\n' "$f"; return; fi
      if [ "$(sz "$f")" != "$es" ] || [ "$(mt "$f")" != "$et" ]; then printf 'SKIP\t%s\tchanged since the scan\n' "$f"; return; fi
      if ! cmp -s "$f" "$a"; then printf 'SKIP\t%s\tdiffers from the array copy\n' "$f"; return; fi
      if rm -f -- "$f"; then printf 'DEL\t%s\n' "$f"; else printf 'SKIP\t%s\tcould not be removed\n' "$f"; fi
    }
    \#(calls)
    echo DONE
    """#
}

struct StrayDeleteResult {
    var deleted: [String] = []
    var skipped: [(rel: String, reason: String)] = []
    var refusal: String?
}

func parseStrayDelete(_ output: String) -> StrayDeleteResult {
    var r = StrayDeleteResult()
    for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
        let f = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        if f.first == "DEL", f.count >= 2 { r.deleted.append(f[1]) }
        else if f.first == "SKIP", f.count == 3 { r.skipped.append((f[1], f[2])) }
        else if line.hasPrefix("ERR ") { r.refusal = String(line.dropFirst(4)) }
    }
    return r
}

// MARK: - Store

extension Store {
    func scanStrayFiles(pools: [String], skip: [String], minAgeMinutes: Int, fullCompare: Bool) async -> StrayScan? {
        var total = StrayScan()
        for p in pools where validPoolName(p) {
            if Task.isCancelled { return nil }
            guard let out = await ssh(strayScanScript(pool: p, skip: skip, minAgeMinutes: minAgeMinutes, fullCompare: fullCompare), allowFailure: true) else { return nil }
            if out.contains("ERR no such pool") { show("The pool \(p) isn't mounted on this server.", error: true); return nil }
            if out.contains("ERR no array view") { show("This check needs the array to be started.", error: true); return nil }
            guard out.contains("DONE") else { show("The comparison of \(p) with the array didn't finish.", error: true); return nil }
            let r = parseStrayScan(out)
            total.files += r.files; total.sameCount += r.sameCount; total.sameBytes += r.sameBytes; total.diffCount += r.diffCount
            total.truncated = total.truncated || r.truncated; total.moverRunning = total.moverRunning || r.moverRunning; total.timedOut = total.timedOut || r.timedOut
        }
        return total
    }

    /// Removes the chosen files after re-verifying each one on the server. Returns nil if the server refused (for example, the mover is running).
    func deleteStrayFiles(_ files: [StrayFile]) async -> StrayDeleteResult? {
        var all = StrayDeleteResult()
        for (pool, group) in Dictionary(grouping: files, by: \.pool) {
            guard validPoolName(pool) else { continue }
            let items = group.map { (rel: $0.rel, size: Int($0.size), mtime: Int($0.mtime)) }
            guard let out = await ssh(strayDeleteScript(pool: pool, files: items), allowFailure: true) else { return nil }
            let r = parseStrayDelete(out)
            if let why = r.refusal { show(why == "mover running" ? "The mover is running, so nothing was deleted. Try again when it has finished." : "The server refused: \(why)", error: true); return nil }
            all.deleted += r.deleted; all.skipped += r.skipped
        }
        return all
    }
}
