<p align="center"><img src="docs/assets/icon.png" width="96" alt="Unraid Watcher icon"></p>

# Changelog

All notable changes to Unraid Watcher are listed here.

## 1.2.0

- **Multiple servers:** add as many Unraid servers as you like in Settings, each with its own address, API key, and SSH login. All of them are monitored and alert in the background.
- **Server picker and overview:** switch servers from the sidebar or with Cmd+1 to Cmd+9, and see every server at a glance in the all-servers overview.
- **Menu bar:** the panel lists every server, and the icon shows when any server is down.
- **Notifications** name the server when you have more than one.
- **Safer controls:** the array, reboot, and shutdown confirmations now say which server they apply to.
- **Upgrading:** an existing single server and its saved passwords are migrated automatically.
- **Deluge panel:** a Deluge tab appears when a server runs Deluge. It shows live download and upload speeds, torrent counts, free space, and every torrent with progress, speeds, ETA, ratio, and peers, with filtering, sorting, and search. You can pause and resume torrents or everything at once, force a recheck, remove torrents with or without their files, and add magnet links. The Deluge address and Web UI password are set per server in Settings.
- **Documentation:** the guides and the PDF now cover multiple servers and the Deluge panel.

## 1.1.0

- **Launch at login:** a new Settings option to start Unraid Watcher with your Mac. A second option starts it in the menu bar only, so alerts keep working without opening a window. It uses macOS's own login item system, so it also appears in System Settings, General, Login Items.
- **Documentation:** the guides, the troubleshooting page, and the PDF now cover launch at login.

## 1.0.0

First release.

- **Dashboard:** overview, system and hardware details, UPS, license and services
- **Storage:** array and disk status and temperatures, parity history, mounted filesystems, SMART health per disk with self-tests
- **Performance:** per-core CPU, memory breakdown, disk I/O, fans, CPU temperatures, network traffic, top processes, system log
- **Docker:** start, stop, restart, pause, resume, and container logs
- **VMs:** power actions, details, creation wizard, editing (basics, media, full XML), cloning, install media eject, and console access
- **Shares:** settings, per-disk usage, create, edit, and delete empty shares
- **Controls:** array start and stop, parity checks, disk spin up and down, mover, reboot and shutdown, SSH command console
- **Alerts:** macOS notifications for hot disks, hot CPU, SMART problems, and new Unraid alerts, with adjustable thresholds
- **Menu bar** status item with a quick summary
- **Security:** API key and SSH password stored in the Keychain, SSH by key or password, confirmation for destructive actions
- **Packaging:** app icon, About window, build scripts, and a DMG installer
- **License:** GNU General Public License v3.0 or later

© 2026 Ray Munro. Licensed under the GNU General Public License v3.0 or later.
