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

### Polled on every refresh (when SSH is on)

A single connection reads, in one batch:

- `/proc/net/dev` for network counters
- `/sys/class/hwmon` for temperatures and fan speeds
- `/proc/loadavg` and `/proc/uptime`
- `/proc/meminfo` for memory detail
- `/proc/stat` for per-core CPU
- `df` for mounted filesystems
- `/proc/diskstats` for disk I/O
- `ps` for the top processes
- the last 60 lines of `/var/log/syslog`

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

## What stays on your Mac

- Fetched data is held in memory only. Nothing is written to disk except your settings and the Keychain items.
- The app contacts no server other than the ones you add.
- Each server has its own Keychain items, and nothing is shared between servers.

© 2026 Ray Munro. Licensed under the GNU General Public License v3.0 or later.
