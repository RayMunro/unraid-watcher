<p align="center"><img src="assets/icon.png" width="96" alt="Unraid Watcher icon"></p>

# Data sources

This page lists everything Unraid Watcher asks of your server, so you can see exactly what it does and audit it. There are two channels: the Unraid GraphQL API and SSH.

## GraphQL API

All requests go to `<server>/graphql` over HTTP or HTTPS with the API key in the `x-api-key` header.

### Queries (read only)

| Panel | Data requested |
|-------|----------------|
| Overview | `info` (OS hostname, distribution, release, uptime; CPU brand, cores, threads) and `metrics` (CPU percent, memory total, used, percent) |
| Array | `array` (state, capacity, parities, disks, caches with name, device, size, temperature, status, filesystem usage) |
| Docker | `docker.containers` (id, names, state, status, image) |
| Container details | `docker.containers` (id, auto-start, created, ports) |
| VMs | `vms.domains` (id, name, state) |
| Shares | `shares` (name, free, used, size, comment) |
| Notifications | `notifications` (unread counts and the 20 newest unread items) |
| System details | `info` (baseboard, system, OS kernel and architecture, CPU manufacturer, speed, socket, versions) |
| Disk details | `array` disks (filesystem type, errors, spinning state, reads, writes, rotational) |
| UPS | `upsDevices` (name, model, status, battery, power) |
| Parity history | `parityHistory` (date, duration, speed, status, errors) |
| Parity status | `array.parityCheckStatus` (running, paused, progress, errors, status) |
| License | `registration` (type, state, expiration) |
| Services | `services` (name, online, version) |
| Flash | `flash` (vendor, product) |
| Array operation (without SSH) | `vars` (the `mdResync` values: action, position, size, speed window, correcting) |
| Server | `vars` (name, version, registration, time zone, disk and share counts, array filesystem state, safe mode) |

Each query runs independently and concurrently on every refresh, so a failure in one does not affect the others.

### Mutations (changes, need Admin)

| Action | Mutation |
|--------|----------|
| Start, stop, pause, resume a container | `docker { start, stop, pause, unpause }` |
| VM power | `vm { start, stop, pause, resume, forceStop, reboot }` |
| Start or stop the array | `array { setState(desiredState: START or STOP) }` |
| Parity check | `parityCheck { start(correct), pause, resume, cancel }` |
| Archive a notification | `archiveNotification(id)` |

## SSH

Commands run as the SSH user through `sh -s`, with the script sent on standard input.

The app keeps one SSH connection open and reuses it for every command (OpenSSH connection sharing). It logs in once, rather than once per refresh, so the server's log is not filled with a login for every refresh and each refresh is faster. The connection closes by itself two minutes after its last use. Its control socket lives in a private folder, `/tmp/uw-<your user id>`, and nothing else is shared.

### Polled on every refresh (when SSH is on)

A single connection reads, in one batch:

- `/proc/net/dev` for network counters
- `/sys/class/hwmon` for temperatures and fan speeds
- the array state in `/var/local/emhttp/var.ini` (the `mdResync` values that describe a rebuild, parity build, or check)
- `/proc/loadavg` and `/proc/uptime`
- `/proc/meminfo` for memory detail
- `/proc/stat` for per-core CPU
- `df` for mounted filesystems
- `/sys/class/accel` for the NPU: its busy time, clock speed, and memory in use (the `intel_vpu` driver), plus a scan of the PCI bus for processing accelerators
- `/sys/class/drm` for each GPU: clock speed and idle time (Intel `i915` and `xe`), busy percent and memory (AMD), and `nvidia-smi` for NVIDIA cards when it is installed
- `/sys/kernel/debug/dri` for an Intel GPU's core count, when the kernel's debug files are readable
- `/proc/diskstats` for disk I/O
- `ps` for the top processes
- the last 250 lines of `/var/log/syslog`

### On demand

| Feature | Commands |
|---------|----------|
| SMART check | `smartctl -j -a -n standby /dev/<device>` for each disk (the standby option leaves sleeping disks alone) |
| SMART self-test | `smartctl -t short` or `smartctl -t long` |
| Spin down | `hdparm -y /dev/<device>` |
| Spin up | a single-sector direct read with `dd` |
| Mover | `mover start`, `mover stop` |
| Power | `powerdown` or `powerdown -r`, started in the background |
| Container logs and restart | `docker logs --tail 300`, `docker restart` |
| Console | whatever you type |
| Share settings | reading `/boot/config/shares/*.cfg` |
| Share disk usage | `du -sk /mnt/*/<share>` |
| Share create, edit, delete | a request to Unraid's own web interface endpoint on the server (`/update.htm`, over its local socket when available), authenticated with the server's own token |
| CPU core layout | Read once per server: `/sys/devices/system/cpu/cpu*` (thread siblings, top speed, capacity) and `/sys/devices/cpu_core` and `cpu_atom`, which list the performance and efficiency cores on a hybrid Intel CPU |
| Share spread | A listing of `/mnt/*/<share>` to find where the share lives, then `du -sk` on each location, one at a time, at idle priority (`nice`, `ionice`) with a 10 minute `timeout` when those exist |
| Cache clean-up scan | `find`, `sort`, `awk`, `comm` and `stat` over the pool, read-only, at low priority (`nice`, `ionice`) and with a `timeout` when those exist |
| Cache clean-up: files already on the array, scan | `find` over the pool (skipping your skipped folders), then for each file a check of `/mnt/disk*` for the same path, comparing size and date (`stat`) or every byte (`cmp`). Read-only, at idle priority with a 15 minute limit |
| Cache clean-up: files already on the array, delete | For each file: `stat` and `cmp` against the copy on an array disk, then `rm -f` of that single file only if they match. Refuses if the mover (`pgrep`) is running |
| Cache clean-up delete | `find <folder> -depth -type d -empty -delete`, so only folders that are empty at that moment are removed |
| Share delete safety check | `find` over the share's folders on each disk |
| VM details | `virsh dominfo`, `domblklist`, `domiflist`, `vncdisplay`, and the libvirt VM log |
| VM autostart | `virsh autostart` |
| VM create | `virsh dominfo` (name check), `qemu-img create`, `virsh define`, optional `virsh autostart` and `virsh start` |
| VM edit | `virsh dumpxml --inactive`, `virsh define` |
| VM remove | `virsh domstate`, `virsh undefine --nvram` |
| VM media | `virsh domblklist --details`, `virsh change-media` |
| VM console | `virsh dumpxml` to read the VNC and websocket ports |
| VM clone | `virsh dominfo`, `virsh domstate`, `cp --sparse=always`, `virsh define` |
| ISO and bridge lists | `ls /mnt/user/isos`, and the bridge devices under `/sys/class/net` |

Values that come from you or from the server (names, paths, device names) are validated and shell-quoted before they are used in a command.

## Deluge

When a server has a Deluge tab open, the app talks straight to Deluge's Web UI over HTTP (or HTTPS, if you gave an `https` address), on the Web UI port, at the path `/json`. This does not go through the Unraid API or SSH. Requests are JSON-RPC calls, and the Web UI keeps your login in a session cookie that the app holds in memory only.

| Purpose | Calls |
|---------|-------|
| Log in | `auth.login` |
| Torrent list and speeds | `web.update_ui` (one call returns every torrent plus session statistics) |
| Attach the Web UI to the Deluge daemon if it is not attached | `web.get_hosts`, `web.connect` |
| Pause and resume | `core.pause_torrents`, `core.resume_torrents` (older Deluge: `core.pause_torrent`, `core.resume_torrent`) |
| Pause all and resume all | `core.pause_session`, `core.resume_session` (older Deluge: `core.pause_all_torrents`, `core.resume_all_torrents`) |
| Recheck | `core.force_recheck` |
| Remove, with or without files | `core.remove_torrent` |
| Add a magnet link | `core.add_torrent_magnet` |

The Deluge password travels to the Web UI in clear text if you use plain HTTP, like the Unraid API key. Use a trusted local network or an `https` address.

## What stays on your Mac

- Fetched data is held in memory only. Nothing is written to disk except your settings and the Keychain items.
- The app contacts no server other than the ones you add.
- Each server has its own Keychain items, and nothing is shared between servers.

© 2026 Ray Munro. Licensed under the GNU General Public License v3.0 or later.
