# Unraid Watcher

A native macOS dashboard and control panel for your Unraid server, with a menu bar status item.

Unraid Watcher shows you what your server is doing (array health, disks, containers, VMs, shares, temperatures, network traffic, logs) and lets you act on it (start and stop containers and VMs, manage the array, run parity checks, create and clone VMs, manage shares) without opening the Unraid web interface.

© 2026 Ray Munro. All rights reserved.

## Highlights

- **Live overview** of CPU, memory, array state, Docker, VMs, and alerts
- **Disk health:** usage, temperatures, parity history, and SMART details per disk
- **Docker and VM control**, including VM creation, editing, cloning, and console access
- **Share management** with per-disk usage breakdowns
- **Performance and network** views: per-core load, disk I/O, fans, CPU temperatures, and traffic
- **macOS notifications** for hot disks, a hot CPU, SMART problems, and new Unraid alerts
- **Menu bar** summary that is always one click away
- **Secure by default:** the API key and SSH password live in the macOS Keychain

## Requirements

| Item | Requirement |
|------|-------------|
| Mac | macOS 14 (Sonoma) or later |
| Unraid | 7.2 or later (built-in API), or an older version with the Connect plugin |
| API key | Required. Viewer role to monitor, Admin role to use controls |
| SSH | Optional, but needed for temperatures, network traffic, SMART, logs, and the VM and share tools |

## Quick start

1. Build the app and open it (see [Building and releasing](docs/building-and-releasing.md)), or install it from the DMG.
2. Open **Settings** (Cmd+,).
3. Enter your server address, for example `http://192.168.1.10`, and your API key.
4. Optionally turn on SSH and enter your SSH user and password.
5. Click **Save & Connect**.

The full walkthrough is in [Getting started](docs/getting-started.md).

## Documentation

| Guide | What it covers |
|-------|----------------|
| [Getting started](docs/getting-started.md) | Creating an API key, enabling SSH, first connection |
| [User guide](docs/user-guide.md) | Every tab and what each control does |
| [Settings](docs/settings.md) | All preferences, defaults, and where data is stored |
| [Alerts and notifications](docs/alerts.md) | What triggers a notification and how to tune it |
| [Controls and safety](docs/controls-and-safety.md) | Destructive actions, confirmations, and permissions |
| [Troubleshooting](docs/troubleshooting.md) | Common errors and how to fix them |
| [Data sources](docs/data-sources.md) | Every API query, mutation, and SSH command the app uses |
| [Architecture](docs/architecture.md) | How the code is organized |
| [Building and releasing](docs/building-and-releasing.md) | Building the app, icon, and DMG installer |
| [Changelog](CHANGELOG.md) | Version history |

## Privacy and security

- Unraid Watcher talks only to the server address you enter. It has no analytics, no telemetry, and no third-party services.
- Your API key and SSH password are stored in the macOS Keychain, never in plain text on disk.
- Destructive actions (stopping the array, rebooting, deleting a share, force-stopping a VM) always ask for confirmation first.

## License

© 2026 Ray Munro. All rights reserved.
