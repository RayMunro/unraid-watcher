<p align="center"><img src="assets/icon.png" width="96" alt="Unraid Watcher icon"></p>

# Troubleshooting

Every page shows problems as orange messages at the top. Problems with optional extras (license, services, UPS, parity history, and per-disk or per-container details) are grouped into one grey, collapsed line so they do not clutter the page. Click **Copy all errors** to copy every message at once.

## Connection problems

### "A server with the specified hostname could not be found"

The **Server URL** in Settings is wrong, or your Mac cannot resolve the name. Use the same address you type in a browser to reach Unraid, for example `http://192.168.1.10`. Try the IP address instead of a name if `tower.local` does not resolve.

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
