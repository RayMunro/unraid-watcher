# Getting started

This guide takes you from a fresh install to a connected dashboard.

## 1. Prepare your Unraid server

### Create an API key

Unraid Watcher reads data through Unraid's GraphQL API, which needs an API key.

1. Open the Unraid web interface.
2. Go to **Settings, Management Access, API Keys**.
3. Create a new key.
4. Choose a role:
   - **Viewer** is enough to monitor everything on the dashboard.
   - **Admin** is needed for actions that change things through the API: starting and stopping containers, the array, parity checks, VM power actions, and archiving notifications.
5. Copy the key. You will paste it into Unraid Watcher.

Unraid 7.2 and later include the API. On older versions, install the Unraid Connect plugin to get it.

### Enable SSH (optional but recommended)

Some features read data or run commands directly on the server over SSH:

- CPU temperatures, fan speeds, network traffic, load, memory detail, disk I/O, and top processes
- SMART health details and self-tests
- The system log viewer and container logs
- Spinning disks up or down, the mover, reboot and shutdown
- VM details, creation, editing, cloning, media, and console access
- Share settings and share management
- The command console

To enable it, open **Settings, Management Access** in Unraid and turn on **Use SSH**. Make sure you know the root password, or set up key-based login.

### Find your server address

Use the same address you type in a browser to open the Unraid web interface, for example `http://192.168.1.10` or `http://tower.local`. If you use HTTPS with a self-signed certificate, see [Settings](settings.md).

## 2. Connect Unraid Watcher

1. Open Unraid Watcher.
2. Open **Settings** with Cmd+, (or the app menu).
3. Fill in:
   - **Server URL**: your server address
   - **API key**: the key you created
4. To use SSH features, turn on **Read temperatures & network over SSH** and fill in:
   - **SSH user**: usually `root`
   - **SSH password**: your server password, or leave it empty to use your Mac's SSH keys
5. Click **Save & Connect**.

macOS may ask for your login keychain password the first time the app reads or writes the saved API key or SSH password. Enter it and choose **Always Allow**. This is a normal macOS prompt, and the app never sees your keychain password.

## 3. Check that it works

- The **Overview** tab should show your hostname, CPU, memory, and array state within a few seconds.
- A small timestamp ("Updated ...") appears in the toolbar after each successful refresh.
- Any problems appear as orange messages at the top of the page. Click **Copy all errors** to copy them. See [Troubleshooting](troubleshooting.md) for what they mean.

## SSH with keys instead of a password

If you prefer keys, leave the SSH password empty and run this once in Terminal:

```sh
ssh-copy-id root@your-server-address
```

Unraid Watcher uses your Mac's SSH keys when no password is set. With a password set, it still tries keys first and then falls back to the password.

## Next steps

- Read the [User guide](user-guide.md) for a tour of each tab.
- Tune thresholds in [Alerts and notifications](alerts.md).
- Review [Controls and safety](controls-and-safety.md) before using the power and array controls.

© 2026 Ray Munro. All rights reserved.
