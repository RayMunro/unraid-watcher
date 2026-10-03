import Foundation

struct NetCounters { let rx: Double; let tx: Double }
struct TempSensor: Identifiable { var id: String { chip + label }; let chip: String; let label: String; let celsius: Double
    var isCPU: Bool { ["coretemp", "k10temp", "zenpower", "cpu_thermal"].contains(chip) } }
struct NetRate: Identifiable { var id: String { iface }; let iface: String; let rx: Double; let tx: Double }
struct Fan: Identifiable { var id: String { name }; let name: String; let rpm: Double }
struct Mount: Identifiable { var id: String { path }; let path: String; let device: String; let type: String; let size: Double; let used: Double }
struct Proc: Identifiable { let id: Int; let cpu: Double; let mem: Double; let name: String }
struct DiskIO: Identifiable { var id: String { dev }; let dev: String; let read: Double; let write: Double }
struct DiskCounters { let read: Double; let write: Double }

struct RemoteSample {
    var net: [String: NetCounters] = [:]
    var temps: [TempSensor] = []
    var fans: [Fan] = []
    var load: [Double] = []
    var uptime: Double = 0
    var mem: [String: Double] = [:]        // kB
    var cpu: [String: [Double]] = [:]      // cpuN -> jiffies
    var mounts: [Mount] = []
    var disks: [String: DiskCounters] = [:] // sectors
    var procs: [Proc] = []
    var log: [String] = []
}

enum Remote {
    static let script = """
    echo ===NET; cat /proc/net/dev
    echo ===TEMP
    for h in /sys/class/hwmon/hwmon*; do
      n=$(cat $h/name 2>/dev/null)
      for t in $h/temp*_input; do
        [ -f "$t" ] || continue
        l=$(cat "${t%_input}_label" 2>/dev/null)
        echo "$n|$l|$(cat "$t" 2>/dev/null)"
      done
    done
    echo ===FAN
    for h in /sys/class/hwmon/hwmon*; do
      n=$(cat $h/name 2>/dev/null)
      for t in $h/fan*_input; do
        [ -f "$t" ] || continue
        l=$(cat "${t%_input}_label" 2>/dev/null)
        echo "$n|$l|$(cat "$t" 2>/dev/null)"
      done
    done
    echo ===LOAD; cat /proc/loadavg; cat /proc/uptime
    echo ===MEM; grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Dirty|Shmem):' /proc/meminfo
    echo ===CPU; grep '^cpu' /proc/stat
    echo ===DF; df -PTk 2>/dev/null
    echo ===DISKIO; cat /proc/diskstats
    echo ===PS; ps -eo pid,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -11
    echo ===LOG; tail -n 60 /var/log/syslog 2>/dev/null
    """

    static func run(host: String, user: String, password: String) async throws -> RemoteSample {
        parse(try await exec(host: host, user: user, password: password, script: script))
    }

    static func exec(host: String, user: String, password: String, script: String, allowFailure: Bool = false) async throws -> String {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            var args = ["-o", "ServerAliveInterval=15", "-o", "ConnectTimeout=8", "-o", "StrictHostKeyChecking=accept-new"]
            if password.isEmpty {
                args += ["-o", "BatchMode=yes"]
            } else {
                // Feed the password to ssh via an askpass helper; it reads it from the environment, never from disk.
                let helper = NSTemporaryDirectory() + "unraidmonitor-askpass.sh"
                if !FileManager.default.fileExists(atPath: helper) {
                    FileManager.default.createFile(atPath: helper, contents: Data("#!/bin/sh\nprintf '%s\\n' \"$UNRAID_SSH_PW\"\n".utf8),
                                                   attributes: [.posixPermissions: 0o700])
                }
                var env = ProcessInfo.processInfo.environment
                env["SSH_ASKPASS"] = helper; env["SSH_ASKPASS_REQUIRE"] = "force"; env["DISPLAY"] = env["DISPLAY"] ?? ":0"
                env["UNRAID_SSH_PW"] = password
                p.environment = env
                args += ["-o", "BatchMode=no", "-o", "NumberOfPasswordPrompts=1",
                         "-o", "PreferredAuthentications=publickey,password,keyboard-interactive"]
            }
            p.arguments = args + ["\(user)@\(host)", "sh -s"]
            let i = Pipe(), o = Pipe(), e = Pipe()
            p.standardInput = i; p.standardOutput = o; p.standardError = e
            try p.run()
            i.fileHandleForWriting.write(Data(script.utf8)); try? i.fileHandleForWriting.close()
            // drain stderr concurrently so a chatty command can't deadlock on a full pipe
            var errData = Data()
            let t = Thread { errData = e.fileHandleForReading.readDataToEndOfFile() }
            t.start()
            let data = o.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            while !t.isFinished { usleep(1000) }
            let out = String(data: data, encoding: .utf8) ?? ""
            if p.terminationStatus != 0 && !(allowFailure && p.terminationStatus != 255) {
                let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw UnraidError.graphql(msg.isEmpty ? "ssh exited with \(p.terminationStatus)" : msg)
            }
            return out
        }.value
    }

    static func parse(_ text: String) -> RemoteSample {
        var r = RemoteSample()
        var mode = ""
        var loadLines = 0
        func sensor(_ l: String) -> (String, String, Double)? {
            let p = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard p.count == 3, let v = Double(p[2].trimmingCharacters(in: .whitespaces)) else { return nil }
            return (p[0], p[1].isEmpty ? "sensor" : p[1], v)
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let l = String(line)
            if l.hasPrefix("===") { mode = l; continue }
            let f = l.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            switch mode {
            case "===NET":
                if let c = l.firstIndex(of: ":") {
                    let iface = l[..<c].trimmingCharacters(in: .whitespaces)
                    let n = l[l.index(after: c)...].split(separator: " ").compactMap { Double($0) }
                    let skip = iface == "lo" || ["veth", "docker", "virbr", "vnet", "br-"].contains { iface.hasPrefix($0) }
                    if n.count >= 9, !skip { r.net[iface] = NetCounters(rx: n[0], tx: n[8]) }
                }
            case "===TEMP":
                if let (c, lb, v) = sensor(l), v > 0, v < 150_000 { r.temps.append(TempSensor(chip: c, label: lb, celsius: v / 1000)) }
            case "===FAN":
                if let (c, lb, v) = sensor(l) { r.fans.append(Fan(name: "\(c) \(lb)", rpm: v)) }
            case "===LOAD":
                if loadLines == 0 { r.load = f.prefix(3).compactMap { Double($0) } }
                else if let u = f.first.flatMap(Double.init) { r.uptime = u }
                loadLines += 1
            case "===MEM":
                if f.count >= 2, let v = Double(f[1]) { r.mem[f[0].replacingOccurrences(of: ":", with: "")] = v }
            case "===CPU":
                if f.first?.hasPrefix("cpu") == true { r.cpu[f[0]] = f.dropFirst().compactMap { Double($0) } }
            case "===DF":
                guard f.count >= 7, f[0] != "Filesystem", let size = Double(f[2]), let used = Double(f[3]) else { break }
                let mnt = f[6...].joined(separator: " ")
                let keep = mnt == "/boot" || mnt == "/var/log" || mnt == "/var/lib/docker" || mnt.hasPrefix("/mnt/")
                if keep, size > 0 { r.mounts.append(Mount(path: mnt, device: f[0], type: f[1], size: size, used: used)) }
            case "===DISKIO":
                if f.count >= 10, let rs = Double(f[5]), let ws = Double(f[9]) {
                    let n = f[2]
                    let whole = n.range(of: #"^(sd[a-z]+|nvme\d+n\d+|vd[a-z]+)$"#, options: .regularExpression) != nil
                    if whole { r.disks[n] = DiskCounters(read: rs, write: ws) }
                }
            case "===PS":
                if f.count >= 4, let pid = Int(f[0]), let c = Double(f[1]), let m = Double(f[2]) {
                    r.procs.append(Proc(id: pid, cpu: c, mem: m, name: f[3...].joined(separator: " ")))
                }
            case "===LOG": r.log.append(l)
            default: break
            }
        }
        return r
    }
}

func rate(_ bytesPerSec: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .decimal) + "/s"
}
