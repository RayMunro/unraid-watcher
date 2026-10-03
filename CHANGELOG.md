<p align="center"><img src="docs/assets/icon.png" width="96" alt="Unraid Watcher icon"></p>

# Changelog

All notable changes to Unraid Watcher are listed here.

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
