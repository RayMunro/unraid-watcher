<p align="center"><img src="assets/icon.png" width="96" alt="Unraid Watcher icon"></p>

# Troubleshooting

Every page shows problems as orange messages at the top. Problems with optional extras (license, services, UPS, parity history, and per-disk or per-container details) are grouped into one grey, collapsed line so they do not clutter the page. Click **Copy all errors** to copy every message at once.

## Several servers

- **One server shows Offline in the all-servers overview:** only that server has a problem. Open it and read the orange messages, or check its address and key in Settings, Servers.
- **A server I expect is missing after upgrading:** servers from a single-server version become one server named after its address. If the list is empty, add it again with **+** in Settings, Servers.
- **Notifications do not say which server:** the name is added only when you have two or more servers.
- **I changed a server's settings and nothing happened:** click **Save & Connect**. Edits are applied only when you click it, and switching to another server in the list discards unsaved edits.

## Connection problems

### "A server with the specified hostname could not be found"

The **Server URL** for that server in Settings, Servers is wrong, or your Mac cannot resolve the name. Use the same address you type in a browser to reach Unraid, for example `http://192.168.1.10`. Try the IP address instead of a name if `tower.local` does not resolve.

### "Unauthorized (HTTP 401)" or "(HTTP 403)"

The API key is wrong, expired, or lacks permission. Create a new key in Unraid under **Settings, Management Access, API Keys**, paste it into Settings, and click **Save & Connect**.

### Timeouts or "could not connect"

- Check that the server is on and reachable: open its web interface from your Mac.
- Confirm the address, and the port if you changed it (for example `http://192.168.1.10:8080`).
- If you use HTTPS with a self-signed certificate, make sure **Allow self-signed certificate** is on.

### The window just says "Connect to your server"

No URL or API key is saved yet. Open Settings and fill in both.

## Unexpected messages that are not real problems

| Message | Meaning |
|---------|---------|
| "No UPS data returned from apcaccess" | No UPS is attached. The app shows "No UPS detected" instead of an error. |
| Optional details unavailable | Your Unraid version does not offer one of the extra data fields. Everything else keeps working. |

## API data errors

Each panel fetches its data separately, so one failing field affects only its own panel.

### "Cannot return null for non-nullable field ..."

Your server returned nothing for a field that the API says must always exist. This is a server-side quirk with that field. The app has been adjusted to avoid the fields known to do this (for example the flash drive GUID). If you see another one, copy the message and report it.

### A panel says a field "doesn't exist" or the query is invalid

The Unraid API changes between versions, and a few panels use fields that older or newer versions may not offer. Update Unraid to 7.2 or later if you can. Copy the message so the query can be adjusted.

### Actions fail with a red banner

Actions that go through the API (container start and stop, VM power, array, parity check, archive notification) need an **Admin** API key. A Viewer key can read but not change anything. The banner shows the server's own message, and the copy button on the banner copies it.

## SSH problems

- **The server's log is full of SSH logins:** older versions logged in again on every refresh. Current versions reuse one connection. The Logs tab also hides these lines by default.
- **A refresh pauses for a moment after the server restarts or you change its SSH password:** the shared connection has to be made again. It recovers by itself.

The SSH error message is shown exactly as `ssh` reported it.

| Message | Fix |
|---------|-----|
| `Could not resolve hostname` | The Server URL is wrong. SSH uses the same host. |
| `Permission denied` | Wrong user or password. Check the SSH user and password in Settings. |
| `Connection refused` | SSH is off on the server. Turn on **Use SSH** in Unraid, Settings, Management Access. |
| `Connection timed out` | The server is unreachable or a firewall blocks port 22. |
| `Host key verification failed` | The server was rebuilt and its key changed. Remove the old entry from `~/.ssh/known_hosts` on your Mac. |

To test SSH outside the app:

```sh
ssh root@your-server-address
```

If that works in Terminal but not in the app, check that the user and password in Settings match.

## Keychain prompts

macOS asks for your login keychain password when the app reads a saved secret for the first time after it was rebuilt or renamed. Enter it and choose **Always Allow**. If you build the app yourself, signing with a stable certificate (the build script does this automatically when an Apple Development certificate is installed) stops the prompt from coming back after each rebuild. Ad-hoc signed builds look like a different app every time.

## Notifications

If nothing appears:

1. Click **Send test notification** in Settings.
2. Check **System Settings, Notifications, Unraid Watcher** and allow alerts.
3. Make sure a Focus mode is not suppressing them.
4. Confirm **Notify about alerts** is on.

## Deluge

- **There is no Deluge tab:** the app shows it only when it sees a Docker container with "deluge" in its image or name, or when you enter a Deluge address in Settings, Servers. Check the container's name and image, or fill in the address.
- **"Deluge rejected the Web UI password":** enter the Web UI password under **Deluge Web UI password** in Settings, Servers. The default is `deluge`. This is the Web UI password, not the daemon password.
- **"Connection refused" or a timeout:** the Web UI is not reachable at the address shown in the panel. Check that the container is running and publishes the Web UI port (8112 by default), or set the right address in Settings.
- **"Doesn't look like the Deluge Web UI":** something else answered at that address. Check the port, and that any reverse proxy forwards the `/json` path.
- **"No Deluge daemon to connect to":** the Web UI is running but is not linked to a daemon. Open the Deluge Web UI once in a browser and use its Connection Manager to add the daemon.
- **Pause, resume, or remove fails:** the banner shows Deluge's own message. Copy it with the button on the banner.

## CPU core types, NPU, and GPU

- **The core bars say "CPU 0", "CPU 1" instead of core types:** the server's core layout could not be read, which usually means SSH was off or briefly unavailable the first time. Reopen the Performance tab after fixing SSH, or restart the app.
- **All the small cores are called "E-core" and none are "LP E-core":** the server did not report clock speeds for them, so the two kinds cannot be told apart. The app does not guess.
- **My CPU is not hybrid but shows groups:** it should show a single list. If it does not, tell me the CPU model so the detection can be improved.
- **There is no NPU card:** the card appears only when an NPU with a driver is found. If the NPU exists but is not usable, a card says that. Linux needs its `intel_vpu` driver for Intel NPUs, and the kernel in your Unraid version has to include it.
- **The NPU card says it does not report how busy the NPU is:** the driver is loaded but older than the one that provides a busy counter.
- **The NPU or GPU shows "measuring…":** the percentage needs two readings a few seconds apart. It appears after the next refresh.
- **There is no GPU card:** the server reported no graphics device, or it is a type this check does not know. Virtual machine graphics adapters are not listed.
- **The GPU card has no core count:** the count comes from the kernel's debug information, which is not always mounted or readable. The rest of the card still works.
- **The GPU activity looks too high on Intel:** it measures time spent awake rather than real work, so it can read a few points high. Compare it with the Intel GPU Top plugin if you need exact engine figures.
- **NVIDIA shows no load:** the load comes from `nvidia-smi`, which must be installed on the server. Without it the card shows only the device.

## Array operation progress

- **There is no progress card during a rebuild:** the app reads it over SSH, or from the Unraid API when SSH is off. Older API versions may not offer it, so turn on SSH.
- **"working out the time left":** the estimate needs about 20 seconds of readings. Until then the speed Unraid reports is used.
- **The time left changes a lot:** rebuilds slow down when the array is busy, and the estimate follows the real speed. A rebuild of a large disk takes days.
- **Pause or Cancel did nothing, or showed an error:** those buttons use the Unraid API's parity controls, which are made for parity checks. If your version does not apply them to a rebuild, use the Unraid web interface.

## Share spread and cache clean-up

- **Measuring a share is slow the first time and fast the second:** the server keeps recently read folder listings in memory, so a repeat measurement is nearly instant.
- **Measuring a share is slow:** it reads every file name on each disk that holds the share. Large shares on spinning disks can take minutes. Use **Stop** to cancel, and the disks measured so far stay on screen.
- **The disks woke up:** measuring has to read the disks. Do it when that does not matter.
- **The clean-up scan takes a long time:** it walks every folder on the pools. Keep your big folders (such as `appdata`) in the skip list so they are never entered. The scan runs at low priority and gives up after 25 minutes.
- **A folder I expected is not listed:** it is hidden by the age setting, the skip list, or the top-level switch, or it holds a file or a link somewhere inside. The summary says how many were hidden by your settings.
- **"No cache file has an identical copy on the array":** nothing on the cache, outside the skipped folders, is also on the array. That is the normal, healthy state after the mover has run.
- **Deleting files is switched off, and the sheet says the mover is running:** wait for the mover to finish, then scan again. Deleting while it runs could race with it.
- **Files appear under "differ from the array copy":** the same path exists on the cache and on the array with different contents. They are never offered for deletion. Compare them yourself and decide which to keep.
- **A file was kept when I deleted:** the sheet's message gives the reason: it changed since the scan, its array copy is missing or different, or it no longer exists. Scan again.
- **The comparison ran out of time:** the file check stops after 15 minutes and keeps what it found. Use the quick comparison, or add folders to the skip list.
- **This check needs the array to be started:** the array disks must be mounted to compare against them.
- **The pool I want is not offered:** pools come from the server's mounted filesystems. The pool must be mounted, which means the array is started.
- **"The scan didn't finish":** the server stopped answering part-way. Try again, with more folders in the skip list.

## Launch at login

- **The switch turns itself off or an error appears:** move the app to your **Applications** folder, open it from there, and try again.
- **Settings says macOS needs your approval:** open **System Settings, General, Login Items** and switch Unraid Watcher on. The **Open Login Items** button in Settings takes you there.
- **The window opens at login even though you wanted the menu bar only:** check that **Start in the menu bar only when launched at login** is on. If the window still appears, close it, and the app keeps running in the menu bar.
- **It did not start after a restart:** check that it is still listed and switched on in Login Items. Moving or replacing the app can drop the entry. Turn the option off and on again in Settings.

## Data that looks empty

| Symptom | Reason |
|---------|--------|
| Network rates empty | Rates need two samples. Wait for one more refresh. |
| CPU core bars and disk I/O empty | Same, they are computed from the difference between two samples. |
| SMART shows "Standby" | The disk is spun down and was deliberately not woken. Its last data is kept when available. |
| Temperatures missing | SSH is off, or the server exposes no sensors the app recognizes. |
| Share settings missing | SSH is off, or the share uses defaults and has no settings file. |
| Most shares show no usage bar | They report the same pool-wide figures. Use **Show spread across drives** on a share for its real size. |
| Torrents show "Size not known yet" | Deluge has not downloaded their metadata yet, so it does not know their size. |

## VM problems

### Creating a VM failed

The banner shows libvirt's own message. Common causes:

- **"A VM named ... already exists":** pick another name.
- **"A disk image already exists at ...":** a disk with data is already at that path. Choose another folder or name, or use the existing-image option.
- **A bridge or network error:** pick one of the bridges listed in the form. They come from your server.
- **Missing UEFI firmware files:** choose legacy BIOS, or check that your Unraid version includes OVMF.
- **Permission or path errors:** check the disk folder exists on a share that can hold VM disks.

Older builds of the app could fail with "per-device boot elements cannot be used together with os/boot elements". That was fixed. Update to the latest version.

If creation fails after the disk image was made, the app deletes the new image. An empty image left by an earlier failed attempt is replaced automatically.

### Clone failed

- The source VM must be shut off.
- VMs that use a physical disk device cannot be cloned automatically.
- Check there is enough free space for the copied disks.

### The browser console button opens a blank or broken page

Use **Open console (Screen Sharing)** instead. It connects straight to the VM's VNC port and does not depend on web interface paths.

### Edited XML was rejected

libvirt refuses invalid definitions and leaves the VM unchanged. The banner shows what it disliked. Common causes are a CPU topology that no longer matches the vCPU count, or references to CPUs that were removed.

## Shares

### "The server didn't accept the change"

Share changes are posted to Unraid's own web interface endpoint from the server. If that fails, check the change in the Unraid web interface to confirm what state the share is in, then try again. Share names can contain letters, numbers, spaces, underscores, hyphens, and periods.

### Delete is refused

The share still contains files on at least one disk. Empty it first. This protects your data.

## Building problems

- **Codesign cannot find an identity:** the script falls back to ad-hoc signing automatically. Install an Apple Development certificate (free with an Apple ID in Xcode) for stable signing.
- **The DMG window is not styled:** macOS asks to let your terminal control Finder the first time. Allow it, or accept the plain DMG, which still installs normally.
- **Gatekeeper blocks the app on another Mac:** right-click the app and choose Open the first time. Removing the warning for everyone needs a Developer ID certificate and notarization.

## Still stuck?

Click **Copy all errors** and, if relevant, copy the banner text of the failing action. Those two pieces of text usually identify the problem.

© 2026 Ray Munro. Licensed under the GNU General Public License v3.0 or later.
