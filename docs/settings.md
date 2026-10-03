<p align="center"><img src="assets/icon.png" width="96" alt="Unraid Watcher icon"></p>

# Settings

Open Settings with Cmd+, or from the menu bar panel. Changes to the connection take effect when you click **Save & Connect**.

## Connection

| Setting | Default | Notes |
|---------|---------|-------|
| **Server URL** | empty | The address you use for the Unraid web interface, for example `http://192.168.1.10`. If you leave off `http://`, the app adds it. |
| **API key** | empty | Stored in the macOS Keychain. Viewer role to monitor, Admin role to use actions. |
| **Allow self-signed certificate** | on | Lets the app connect to an HTTPS server whose certificate is not trusted by macOS. This only applies to the server address you entered. |
| **Refresh every N s** | 10 | How often data is refreshed. Range: 2 to 300 seconds. SSH features add a little work per refresh, so very short intervals may feel heavy on a small server. |

The app allows plain HTTP, so a normal home setup works without certificates. On HTTP, the API key travels unencrypted across your network. Use a trusted local network, or set up HTTPS on your server and enter an `https://` address.

## SSH

| Setting | Default | Notes |
|---------|---------|-------|
| **Read temperatures & network over SSH** | off | Master switch for every SSH-based feature. |
| **SSH user** | `root` | The account used to log in. |
| **SSH password** | empty | Optional. Stored in the Keychain. Leave it empty to use your Mac's SSH keys. |

How SSH login works:

- With no password set, the app runs `ssh` in batch mode and relies on your Mac's keys.
- With a password set, the app still offers your keys first, then falls back to the password. The password is passed to `ssh` through a small temporary helper script that reads it from the environment. It is never written to disk and never placed on a command line.
- The first connection to a server accepts and remembers its host key automatically.

## Alerts

| Setting | Default | Range | Notes |
|---------|---------|-------|-------|
| **Notify about alerts** | on | | Turns all macOS notifications on or off. |
| **Disk warning at** | 45 C | 30 to 70 | A disk at or above this temperature is shown as hot and triggers a warning notification. |
| **Disk critical at** | 55 C | 35 to 80 | A disk at or above this triggers a critical notification. |
| **CPU warning at** | 80 C | 50 to 100 | Needs SSH, because CPU temperature comes from the server's sensors. |
| **Send test notification** | | | Sends a sample notification and asks macOS for permission if needed. |

See [Alerts and notifications](alerts.md) for exactly when notifications fire.

## Where data is stored

| Data | Location |
|------|----------|
| API key | macOS Keychain, item name `apiKey` |
| SSH password | macOS Keychain, item name `sshPassword` |
| Server URL, SSH user, thresholds, refresh interval, toggles | App preferences (`com.raymondmunro.unraidwatcher`) |
| SSH password helper | A temporary script in the system temp folder, containing no secrets |

Nothing is sent anywhere except to your own server.

## Migrating from earlier names

The app was developed under earlier names. On first launch, it copies any preferences it finds from those earlier versions. Keychain items keep their names, so saved secrets carry over. macOS may ask once for your login keychain password to allow the renamed app to read them.

## Resetting everything

To clear all preferences:

```sh
defaults delete com.raymondmunro.unraidwatcher
```

To remove saved secrets, open **Keychain Access**, search for `apiKey` and `sshPassword`, and delete those items.

© 2026 Ray Munro. Licensed under the GNU General Public License v3.0 or later.
