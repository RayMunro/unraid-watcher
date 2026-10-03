# Unraid Watcher

A native macOS dashboard and control panel for an Unraid server, with a menu bar status item.

© 2026 Ray Munro. All rights reserved.

## Features

- **Overview:** system info, live CPU and memory graphs, array state, Docker, VM and alert counts
- **Array and disks:** usage, temperatures, parity history, mounted filesystems, SMART health per disk
- **Docker:** start, stop, restart, pause, and view logs
- **VMs:** start, stop, pause, reboot, create, edit (basics and full XML), clone, eject media, open the console
- **Shares:** settings, per-disk usage, create, edit, and delete empty shares
- **Performance and network:** per-core load, memory, disk I/O, fans, CPU temperatures, network traffic, system log
- **Controls:** array start and stop, parity checks, spin disks up or down, mover, reboot and shutdown, and an SSH console
- **Alerts:** macOS notifications for hot disks, a hot CPU, SMART problems, and new Unraid alerts

## Requirements

- macOS 14 or later
- Unraid 7.2 or later (built-in GraphQL API), or an older version with the Connect plugin
- An Unraid API key (Settings, Management Access, API Keys). Use a Viewer key to monitor only, or an Admin key to use the controls
- SSH access (optional) for temperatures, network traffic, SMART, logs, and the VM and share tools. Key login or a password both work

## Build

```sh
./build_app.sh     # builds "Unraid Watcher.app"
./make_dmg.sh      # builds dist/Unraid-Watcher-1.0.dmg
```

Open Settings (Cmd+,) and enter your server URL, API key, and optionally SSH details. The API key and SSH password are stored in your Keychain.

The build script signs with an Apple Development certificate when one is available, and falls back to ad-hoc signing otherwise. Distributing to other Macs without a Gatekeeper warning needs a Developer ID certificate and notarization.

## Notes

Many panels read optional API fields, and each is fetched separately, so a field your Unraid version does not support only affects its own panel. Use "Copy all errors" in the app to see exactly what failed.
