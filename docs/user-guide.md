<p align="center"><img src="assets/icon.png" width="96" alt="Unraid Watcher icon"></p>

# User guide

## Working with several servers

Every server you add in Settings is monitored in the background at the same time, so alerts keep working for all of them whichever one you are looking at.

- **Server picker:** the box at the top of the sidebar shows the server you are viewing, with a dot that is green when connected, red when it cannot be reached, and grey when it has not been set up. Click it to switch servers, or choose **Manage servers** to open Settings.
- **Keyboard:** the **Servers** menu in the menu bar lists your servers. Press Cmd+1 to Cmd+9 to jump to one, and Cmd+0 for the all-servers overview.
- **All servers overview:** choose **All servers** in the picker for one card per server showing its status, array state and usage, CPU and memory, Docker and VM counts, hottest disk, and unread alerts. Click a card to open that server. **Refresh all** updates every server at once.
- **Which server am I changing?** Everything in the tabs below applies to the server named in the picker and at the top of the window. Confirmations for the array, reboot, and shutdown controls repeat the server's name, so you can check before you confirm.

The rest of this guide describes the tabs for one server.

The window has a sidebar on the left and a detail area on the right. A footer at the bottom of the sidebar shows the app name and copyright. Click it to open the About window.

The **refresh button** in the toolbar updates everything immediately. The app also refreshes on its own every few seconds (see [Settings](settings.md)).

Features marked **SSH** need SSH turned on in Settings. Features marked **Admin** need an API key with Admin rights.

## Overview

A summary of the whole server:

- **Array operation:** appears only while the array is rebuilding a disk, building parity, running a parity check, or clearing a new disk. It shows what is running, a progress bar with the percentage on it, how much has been done out of the total, the speed, and about how long is left. Rebuilds and parity builds add a note on what they mean for your data, for example that a disk is being emulated from parity and the array cannot survive another disk failure. The percentage also appears beside Overview in the sidebar and, in the menu bar, next to the app's icon, and each server's card in the all-servers overview and the menu bar panel shows its own bar. When the operation ends you get a notification saying whether it finished, was cancelled, or ended with an error.
- **Array problems:** appears only when Unraid reports a disk as disabled or invalid, shown in red. Such a disk is being emulated from parity, so check the array in the Unraid web interface.
- **Temperature alerts:** appears only when a disk is at or above your warning temperature.
- **System:** hostname, Unraid version, CPU model, core and thread counts, and boot time.
- **CPU and Memory:** current load with a graph of the last 60 refreshes. With SSH on, the CPU card also shows the CPU temperature.
- **Array:** state, used and free space, and the hottest disk.
- **Docker:** running containers out of the total.
- **VMs:** running VMs out of the total.
- **Alerts:** unread notification counts split into alert, warning, and info.

## System & Power

- **Hardware:** system and motherboard make and model, CPU socket and speed, architecture.
- **Software:** Unraid, kernel, and API versions.
- **License & server:** license type and expiry, flash drive vendor and product, time zone, array disk count, share count, and safe mode.
- **Services:** whether each Unraid service is online.
- **UPS:** status, battery charge, estimated runtime, load, and voltages. If no UPS is attached, the card says "No UPS detected".

## Network & Temps (SSH)

- **CPU temperature:** a large reading, a history graph, and each core or package sensor. The reading turns orange above 70 C and red above 80 C.
- **Other sensors:** NVMe and any other temperature sensors the server reports.
- **Network traffic:** combined download and upload rates, a graph, and a per-interface breakdown. Virtual interfaces such as `lo`, `veth*`, `docker*`, and `virbr*` are hidden. Rates need two samples, so they appear after the second refresh.

## Performance (SSH)

- **Load and uptime:** 1, 5, and 15 minute load averages and uptime.
- **CPU cores:** a usage bar for every core.
- **Memory:** usage with a breakdown of in-use, cache and buffers, available, shared, and dirty memory, plus swap if configured.
- **Disk I/O:** read and write speed for every physical disk, labeled with the Unraid disk name.
- **Fans:** fan speeds reported by the motherboard.
- **Top processes:** the busiest processes by CPU.

## SMART Health (SSH)

One card per disk showing:

- A health badge: **Healthy**, **Warning**, **Failing**, **Standby**, or **Unknown**
- Temperature, model, serial, firmware, capacity, drive type, power-on time, power cycles, last self-test result, and error log entries
- Any concerns found (see below)
- A full table of SMART attributes (NVMe drives show wear, spare capacity, media errors, and unsafe shutdowns instead)

Buttons per disk: **Short self-test**, **Extended self-test** (asks first, can take hours), **Spin down**, and **Spin up**.

How health is decided:

- **Failing:** the drive reports an overall SMART failure, or any attribute has failed.
- **Warning:** reallocated, pending, offline-uncorrectable, or reallocation-event sector counts above zero; NVMe media errors; critical warning flags; SSD wear of 90 percent or more; or spare capacity below its threshold.
- **Healthy:** the drive passes with no concerns.

Disks that are spun down are never woken for a SMART check. Their last known data is kept and they show a "Spun down" badge. The tab checks automatically every 30 minutes, or when you click **Check now**.

## Controls (SSH and Admin, depending on the action)

- **Array:** shows the state with **Start array** and **Stop array**. During any array operation it shows progress with **Pause**, **Resume**, and **Cancel** (which asks first, because progress is lost). When idle you can start a read-only check or a correcting check.
- **Disks and mover (SSH):** spin all disks up or down, and start or stop the mover.
- **Power (SSH):** **Reboot** and **Shut down**. Both ask for confirmation and use Unraid's clean powerdown, which stops the array first. A shut-down server cannot be turned back on from the app.
- **Cache clean-up (SSH):** checks your cache pools for two kinds of leftovers and lets you remove them. Press **Clean up the cache…**, pick the pools, then **Scan the cache**. The scan only reads. Results appear in two sections, each with checkboxes and its own delete button.
  - **Files left behind by the mover.** These are files on a cache pool that also exist, at the same path, on an array disk. They are what an interrupted or blocked mover leaves behind. Each is listed with the array disk that holds the copy, its size, and how its share uses the cache. Files in shares that use the mover are ticked for you. Files in other shares are listed but not ticked.
  - **Empty folders.** Folder trees with no files, and no links, anywhere inside them. After you delete files above, scan again: the folders they leave empty show up here.
  - **Never touch these top-level folders** (default `appdata,system,domains`) are not even entered during the scan, which also makes it much faster.
  - **Leave files changed in the last N minutes alone** (default 60) protects files that are still being written.
  - **Decide a file is the same as its array copy by** is either *Size and date* (quick, and what the mover preserves) or *Every byte* (slow and thorough, it reads both copies). Either way, each file is compared byte for byte with its array copy again, just before it is deleted.
  - **Only trees unchanged for N days or more** (default 7) and **Also remove empty top-level folders** (off by default) apply to empty folders.
  - A file whose array copy differs is listed under "differ from the array copy" and is never offered for deletion.
  - Deleting files is switched off while the mover is running.
- **Console (SSH):** run any command on the server and see its output. Recent commands are kept as shortcuts.

## Array & Disks

- **Array card:** state and total capacity, then each parity, data, and cache disk with its status, temperature, usage bar, and details (filesystem, spinning or spun down, HDD or SSD, read and write counts, and error count).
- **Mounted filesystems (SSH):** the flash drive, Docker image, log, and `/mnt` mounts with usage.
- **Parity check history:** the last 10 checks with date, duration, speed, and errors.

Disk temperatures use the warning and critical thresholds from Settings.

## Docker

Every container with its image, state, ports, auto-start badge, and created date.

- **Play and stop buttons:** start a stopped container, or stop a running one (asks first). Admin.
- **Menu (the three dots):**
  - **Restart:** uses SSH if enabled, otherwise stops and starts through the API.
  - **Pause** and **Resume**.
  - **View logs (SSH):** the last 300 lines, with a refresh button.

## VMs

Every VM with its state. The three-dot menu on each VM offers:

- **Details (SSH):** CPU and memory summary, disks, network interfaces, VNC display, the last 60 lines of the VM log, and a **Start with array** switch.
- **Edit (SSH):** three tabs.
  - **Basics:** change vCPUs and memory.
  - **Media:** see each CD or DVD drive, eject a disc, or insert an ISO from `/mnt/user/isos`.
  - **XML:** edit the full libvirt definition. libvirt validates every save, and a bad edit is rejected.
  - **Remove VM:** deletes the definition only. Disk images are kept, and the VM must be shut off.
- **Clone (SSH):** copy a shut-off VM and its disks under a new name. See below.
- **Eject install media:** one click to eject every disc.
- **Start, Shut down, Pause, Resume, Reboot, Force stop:** power actions. Reboot and force stop ask first. Admin.
- **Open console (Screen Sharing)** and **Open console in browser:** for running VMs.

### Creating a VM

Click **New VM** above the list. Choose:

- Name, operating system (Linux or Windows 10 / Server), and firmware (UEFI or legacy BIOS)
- vCPUs and memory
- A new disk (folder and size) or an existing disk image
- Disk bus: VirtIO (fastest, but Windows needs drivers) or SATA (works everywhere)
- An install ISO, and for Windows a VirtIO drivers ISO
- Network bridge and adapter type
- Whether to start with the array and whether to start the VM now

Choosing Windows switches to a SATA disk and an Intel network adapter so the installer works without extra drivers. The VM is created as a standard KVM VM with VNC graphics. GPU and USB passthrough and a TPM (needed for Windows 11) can be added afterwards in the XML editor.

If defining the VM fails, any disk image the app just created is removed. An untouched empty image left by an earlier failed attempt is replaced automatically.

### Cloning a VM

The source VM must be shut off. The clone gets:

- A new name and a new unique ID
- Copies of every file-backed disk, made sparse so unused space is not copied
- A new network address (MAC addresses are removed so libvirt generates new ones)
- Its own copy of the UEFI variable store

VMs that use a physical disk device cannot be cloned automatically. Passthrough devices are copied as-is, and two VMs cannot use the same device at once. Large disks can take a long time, so keep the window open while it runs.

### Opening the console

- **Screen Sharing** opens the VM in the built-in macOS Screen Sharing app using the VM's VNC port. This is the most reliable option.
- **Browser** opens Unraid's built-in web VNC page for the VM.

The VM must be running.

## Deluge

A **Deluge** tab appears in the sidebar when the server runs Deluge, found by looking for a Docker container whose image or name contains "deluge" (for example the linuxserver.io image). If Deluge runs some other way, enter its address in Settings, Servers and the tab appears anyway.

It talks to Deluge's own Web UI, so the Web UI must be enabled and reachable from your Mac. It needs the Web UI password. The default is `deluge`, which the app uses when no password is saved. Set yours under **Deluge Web UI password** in Settings, Servers.

The panel shows:

- **Download and Upload:** current speeds with a short history graph and any speed limit.
- **Torrents:** the total, how many are downloading, seeding, paused, or in error, plus connections, DHT nodes, and free disk space.
- **The torrent list:** each torrent with its state, a progress bar, size, speeds, ETA, ratio, seeds and peers, and tracker. Errors show Deluge's message. Filter by state, sort by date added, name, progress, speed, ratio, or size, and search by name.

Actions:

- **Pause all** and **Resume all**.
- **Add magnet** adds a magnet link with Deluge's default settings.
- **The three-dot menu on a torrent:** pause or resume it, force a recheck, copy its name, or remove it. Removing asks whether to keep the downloaded files or delete them too.

The panel refreshes every few seconds, but only while it is open, so it adds no load on the server the rest of the time.

## Shares

A list of shares with used and free space. Click a share to expand it.

- **Settings (SSH):** cache use, allocation method, split level, minimum free space, included and excluded disks, and SMB export and security.
- **Show spread across drives:** opens a view of how that share is spread over your disks and pools. It measures one disk at a time so you can watch progress and stop it, then shows a stacked bar and a table with each disk's size and its percentage of the share, a summary such as "1.2 TB across 4 array disks and 1 pool", and the disks the share is not on. **Scan again** repeats it and **Copy** puts the table on the clipboard. Measuring reads the folder listing on every disk that holds the share, so it can wake spun-down disks and takes a while for a large share the first time (the server remembers listings, so a repeat is much faster). **Stop** ends the measurement at once. The measurement already running on the server for the current disk finishes by itself at idle priority, and is limited to 10 minutes.
- **New share:** a form for name, comment, cache use, allocation, split level, minimum free space, disk include and exclude lists, and SMB export and security.
- **Edit:** the same form for an existing share. Settings that the form does not cover are preserved.
- **Delete:** only for empty shares. The app checks every disk first and refuses if any files remain.

Unraid reports the whole pool's used and free space for every share on it, so many shares show identical figures. When three or more shares report the same numbers, the list leaves out the per-share bar and says so, because those figures are not the share's own size. Expand a share and use **Show spread across drives** to see how much it really holds, and where.

Share changes are submitted to Unraid's own web interface endpoint from the server itself, the same way the web interface saves them. If the server does not accept a change, a banner says so.

## Notifications

Unread Unraid notifications with their importance, message, and time. Archive one with the archive button, or use **Archive all**. Admin.

## Logs (SSH)

The last 250 lines of the system log, with errors in red and warnings in orange. The text can be selected and copied.

The log also records every SSH login, including the app's own connections. **Hide SSH login lines** (on by default) removes those so the useful messages are visible. Turn it off to see everything.

## Menu bar

With **Launch at login** turned on in Settings, the app starts with your Mac and can stay in the menu bar only, so alerts keep working without a window. The menu bar panel lists every server with a status dot, array state, CPU and memory, Docker count, and unread notifications. Click a server to open it in the dashboard. You can also open the dashboard, open Settings, open the About window, or quit. The icon changes to a crossed-out drive when any server cannot be reached.

## Banners

Results of actions appear in a banner at the top of the window. Green means success, red means a failure with the server's message. Use the copy button on the banner to copy the text.

## About window

Choose **About Unraid Watcher** from the app menu, the menu bar panel, or the sidebar footer. It shows the version and the copyright notice.

© 2026 Ray Munro. Licensed under the GNU General Public License v3.0 or later.
