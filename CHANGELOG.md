<p align="center"><img src="docs/assets/icon.png" width="96" alt="Unraid Watcher icon"></p>

# Changelog

All notable changes to Unraid Watcher are listed here.

## Unreleased

New:

- **Array operation progress:** while the array is rebuilding a disk, building parity, running a parity check, or clearing a disk, the Overview shows a progress bar with the percentage, how much is done, the speed, and about how long is left, with a note on what it means for your data. The percentage also shows beside Overview in the sidebar, in the menu bar, and on each server's card. You get a notification when it ends. The Controls tab shows the same progress with Pause and Cancel.

- **Share spread:** open any share and see how it is spread across your drives, measured one disk at a time with a stacked bar, a table of sizes and percentages, and the disks it is not on. You can stop it part-way.
- **Cache clean-up for files the mover left behind:** the same scan now also finds files on your cache pools that already exist, at the same path, on an array disk. They are listed with the disk that holds the copy. A file is only ever offered, and only ever deleted, when the array copy matches, and the delete step compares the two byte for byte again just before removing each file. Files that differ, changed recently, sit in skipped folders, or are links are never touched, and deleting is refused while the mover is running.
- **Cache clean-up:** scan your cache pools for empty folders and remove the ones you choose. The scan only reads, skips `appdata`, `system` and `domains` by default, ignores recently changed folders, and deletes only folders that are still empty at the moment of deletion.

Fixes found by running the app against a real server.

- **Stop buttons:** stopping a long scan or measurement returns at once. Before, with a shared SSH connection, a cancelled command kept the app waiting until the command ended on its own.
- **Controls:** the confirmations for stop array, a correcting parity check, spin down all disks, reboot, and shut down never appeared, so those buttons did nothing. They now ask first, and the question names the server. Nothing ran in the meantime, so no action was taken by accident.

- **SSH:** one connection is now shared and reused, instead of a new login on every refresh. This stops the server's log filling with login lines and makes refreshes faster.
- **Logs:** shows the last 250 lines and hides the app's own SSH login lines by default, with a switch to show them.
- **Array problems:** a disk Unraid reports as disabled or invalid now shows in red, in an Array problems card on the Overview, and triggers a notification. It was grey before.
- **Array:** the parity disk's size was shown in the wrong unit (GB instead of TB).
- **Shares:** when many shares report the same pool-wide figures, the misleading per-share bars are hidden and a note explains why.
- **Deluge:** the sidebar icon was missing. Unknown tracker totals (-1), an undefined ratio, and torrents with no size yet are now shown sensibly.
- **Wording:** "Zero KB/s" now reads "0 bytes/s" throughout.
- **Sensors:** temperatures are sorted naturally (Package, then Core 0, 1, 2 and so on), and two chips with the same name, such as two NVMe drives, are numbered.
- **Network graph:** the axis shows speeds such as "20 MB/s" instead of "3.0E7".
- **Overview:** the memory card's "used" figure now matches the percentage.
- **Start-up:** the window is brought forward at launch, and starting quietly at login finds the window by its identifier, since its title is now the server's name.

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
