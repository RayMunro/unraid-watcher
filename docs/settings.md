<p align="center"><img src="assets/icon.png" width="96" alt="Unraid Watcher icon"></p>

# Settings

Open Settings with Cmd+, or from the menu bar panel. It has two tabs: **Servers** for each server you monitor, and **General** for preferences that apply to all of them.

## Servers tab

The list on the left holds your servers. Use **+** to add one and **-** to remove the selected one. Click a server to edit it, then click **Save & Connect** to apply the changes and reconnect. A small status next to the button shows whether the server is connected.

Each server has its own settings and its own saved secrets:

| Setting | Default | Notes |
|---------|---------|-------|
| **Name** | `Server N` | Shown in the sidebar picker, the menu bar, and in notifications. |
| **Server URL** | empty | The address you use for the Unraid web interface, for example `http://192.168.1.10`. If you leave off `http://`, the app adds it. |
| **API key** | empty | Stored in the macOS Keychain. Viewer role to monitor, Admin role to use actions. |
| **Allow self-signed certificate** | on | Lets the app connect to an HTTPS server whose certificate is not trusted by macOS. This only applies to this server's address. |
| **Read temperatures & network over SSH** | off | Master switch for every SSH-based feature on this server. |
| **SSH user** | `root` | The account used to log in. |
| **SSH password** | empty | Optional. Stored in the Keychain. Leave it empty to use your Mac's SSH keys. |
| **Deluge address** | empty | Optional. Leave it empty and the app finds Deluge itself: it looks for a Deluge container and uses the Web UI port Docker publishes for it (8112 if none). Fill it in if Deluge runs elsewhere, uses HTTPS, or sits behind a reverse proxy, for example `https://deluge.home.lan`. |
| **Deluge Web UI password** | empty | Stored in the Keychain. When empty, Deluge's default password `deluge` is used. |

Removing a server deletes its saved API key, SSH password, and Deluge password from your Keychain. Nothing changes on the server itself.

The app allows plain HTTP, so a normal home setup works without certificates. On HTTP, the API key travels unencrypted across your network. Use a trusted local network, or set up HTTPS on your server and enter an `https://` address.

How SSH login works:

- With no password set, the app runs `ssh` in batch mode and relies on your Mac's keys.
- With a password set, the app still offers your keys first, then falls back to the password. The password is passed to `ssh` through a small temporary helper script that reads it from the environment. It is never written to disk and never placed on a command line.
- The first connection to a server accepts and remembers its host key automatically.

## General tab

These apply to every server.

| Setting | Default | Range | Notes |
|---------|---------|-------|-------|
| **Refresh every N s** | 10 | 2 to 300 | How often each server is refreshed. SSH features add a little work per refresh, so very short intervals may feel heavy on a small server. |
| **Launch at login** | off | | Starts Unraid Watcher when you log in to your Mac. See below. |
| **Start in the menu bar only when launched at login** | on | | Appears once launch at login is on. |
| **Notify about alerts** | on | | Turns all macOS notifications on or off. |
| **Disk warning at** | 45 C | 30 to 70 | A disk at or above this is shown as hot and triggers a warning notification. |
| **Disk critical at** | 55 C | 35 to 80 | A disk at or above this triggers a critical notification. |
| **CPU warning at** | 80 C | 50 to 100 | Needs SSH, because CPU temperature comes from the server's sensors. |
| **Send test notification** | | | Sends a sample notification and asks macOS for permission if needed. |

See [Alerts and notifications](alerts.md) for exactly when notifications fire.

### Launch at login

- The app registers itself with macOS as a login item. You can also see and change this in **System Settings, General, Login Items**, and the two always agree.
- At login the app starts quietly in the menu bar instead of opening its window. Choose **Open Dashboard** from the menu bar icon whenever you want the window. Turn off **Start in the menu bar only when launched at login** if you would rather see the window.
- If macOS asks for approval, Settings shows a notice with an **Open Login Items** button. Switch Unraid Watcher on there.
- Login items work best when the app is in your **Applications** folder. Settings shows a tip if it is somewhere else, such as a mounted installer or the Downloads folder.
- Opening the app yourself, at any time, always shows the window as normal. Only a launch by macOS at login starts hidden.

## Where data is stored

| Data | Location |
|------|----------|
| API key | macOS Keychain, one item per server, named `apiKey.<server id>` |
| SSH password | macOS Keychain, one item per server, named `sshPassword.<server id>` |
| Deluge Web UI password | macOS Keychain, one item per server, named `delugePassword.<server id>` |
| Server list (name, URL, SSH user, certificate and SSH switches) | App preferences (`com.raymondmunro.unraidwatcher`), under `servers` |
| Which server is selected, thresholds, refresh interval, toggles | App preferences (`com.raymondmunro.unraidwatcher`) |
| SSH password helper | A temporary script in the system temp folder, containing no secrets |

Nothing is sent anywhere except to your own server.

## Upgrading from a single-server version

Earlier versions kept one server in plain settings. On first launch of a multi-server version, the app turns it into your first server. The name is taken from the server address, so rename it if you like. The API key and SSH password are copied into that server's own Keychain items, and the old items are removed once the copy is confirmed. macOS may ask once for your login keychain password so the app can read the old items. Choose **Always Allow**.

If you later go back to an older version, it will not find the old settings, because they were moved. Re-enter them there.

The app was also developed under earlier names. On first launch it copies any preferences it finds from those versions too.

## Resetting everything

To clear all preferences:

```sh
defaults delete com.raymondmunro.unraidwatcher
```

To remove saved secrets, open **Keychain Access**, search for `apiKey` and `sshPassword`, and delete those items. Removing a server in Settings deletes its items for you.

© 2026 Ray Munro. Licensed under the GNU General Public License v3.0 or later.
