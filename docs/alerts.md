<p align="center"><img src="assets/icon.png" width="96" alt="Unraid Watcher icon"></p>

# Alerts and notifications

Unraid Watcher sends standard macOS notifications. Turn them on or off, and set temperature limits, in [Settings](settings.md).

## What triggers a notification

### Disk temperature

For every disk (parity, data, and cache) the app compares the temperature with your limits:

- At or above the **warning** limit (default 45 C): a "running hot" notification.
- At or above the **critical** limit (default 55 C): a "critical" notification.

To avoid repeated alerts, a disk must cool to **3 degrees below** the limit before it can alert at that level again. A disk hovering around the limit therefore notifies once, not every refresh.

The Overview tab also shows a Temperature alerts card for any disk at or above the warning limit, and disk temperatures are colored orange or red on the Array & Disks tab.

### CPU temperature (needs SSH)

When the hottest CPU sensor reaches the CPU limit (default 80 C), you get one notification. It re-arms after the temperature drops 3 degrees below the limit.

### SMART health (needs SSH)

When a disk's SMART health changes to **Warning** or **Failing**, you get a notification naming the disk and the first concern found. The same state does not notify twice. SMART is checked every 30 minutes, and whenever you click **Check now** on the SMART Health tab.

### Unraid notifications

New unread notifications with **alert** or **warning** importance are forwarded. Informational notifications are not. On the first refresh after launch, existing notifications are recorded silently so you are not flooded with old messages.

## Requirements and limits

- macOS asks for notification permission the first time the app launches. If you declined, enable it in **System Settings, Notifications, Unraid Watcher**.
- Notifications are sent only while the app is running. The app normally keeps running in the menu bar when its window is closed. Choose **Quit** from the menu bar panel to stop it.
- If the server is unreachable, the app cannot see problems on it. A disconnected server shows as a crossed-out icon in the menu bar.

## Testing

Open Settings and click **Send test notification**. If nothing appears, check System Settings, Notifications, and make sure Focus modes are not hiding them.

## Tuning tips

- Spinning hard drives are usually comfortable up to the mid 40s C. Many people use 45 C for warning and 55 C for critical, which are the defaults.
- SSDs and NVMe drives run hotter by design. If you get frequent warnings for a cache drive, raise the warning limit slightly or improve airflow.
- Your drives' own datasheets give their rated maximum temperature. Keep the critical limit safely below it.

© 2026 Ray Munro. Licensed under the GNU General Public License v3.0 or later.
