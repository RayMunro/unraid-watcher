# Controls and safety

Unraid Watcher can change things on your server, not just read them. This guide explains what each action does, what it needs, and what protects you from mistakes.

## Permissions

| Method | Needed for |
|--------|------------|
| **Viewer API key** | All read-only dashboards |
| **Admin API key** | Container start, stop, pause, and resume; VM power actions; array start and stop; parity checks; archiving notifications |
| **SSH** | Disk spin up and down, mover, reboot and shutdown, container restart and logs, SMART tests, VM details, creation, editing, cloning, media, and console, share settings and management, the command console |

If you only want to monitor, use a Viewer key and leave SSH off. Nothing in the app can then change your server.

## Actions that ask for confirmation

| Action | What the confirmation warns about |
|--------|-----------------------------------|
| Stop a container | The container will stop |
| Stop the array | Shares, containers, and VMs become unavailable |
| Start a correcting parity check | Parity is rewritten to match the data disks |
| Spin down all disks | Disks in use spin up again on next access |
| Reboot the server | All services go down briefly |
| Shut down the server | The server powers off and cannot be turned on from the app |
| Reboot a VM | The VM restarts |
| Force stop a VM | Equivalent to pulling the plug |
| Extended SMART self-test | Can take hours and slows the disk |
| Delete a share | Removes the share definition |
| Remove a VM | Removes the definition only, disks are kept |

Actions that are easy to undo, such as starting a container, pausing a VM, or a short SMART test, run immediately.

## Built-in safeguards

- **Shares:** delete works only on empty shares. The app checks every disk and refuses if any file remains.
- **VMs:** removing a VM never deletes its disk images. Cloning requires the source VM to be shut off. Editing a VM definition is validated by libvirt, and a bad definition is rejected without changing the VM.
- **Failed VM creation:** if defining a VM fails, any new disk image the app created is removed. An existing disk image with data in it is never overwritten.
- **Spun-down disks:** SMART checks use a standby-aware mode so sleeping disks are not woken.
- **Input checks:** share names, VM names, disk device names, and file paths are validated, and everything passed to a shell command is quoted. Names with unusual characters are refused rather than risked.
- **Power commands** use Unraid's own powerdown, which stops the array cleanly before turning off or rebooting.

## The command console

The Console on the Controls tab runs exactly what you type, as the SSH user, with no filtering and no confirmation. It is as powerful as a terminal on the server. Treat it that way.

## Reversibility

| Action | Easy to undo? |
|--------|---------------|
| Start, stop, pause, or restart a container or VM | Yes |
| Spin disks up or down | Yes |
| Stop the array | Yes, start it again |
| Parity check (read-only) | Yes, cancel it |
| Parity check (correcting) | No, parity is rewritten |
| Force stop a VM | Risky, the guest may be left inconsistent |
| Delete an empty share | Re-create it |
| Remove a VM definition | Re-create it against the same disk |
| Shut down the server | Needs physical or out-of-band power on |
| Command console | Depends entirely on the command |

## Good habits

- Try new features on a test VM or an empty test share first.
- Use shut down rather than force stop for VMs whenever possible.
- Keep an up-to-date backup of your flash drive. VM and share definitions live there.
- After editing a VM's XML, check the VM in the Unraid web interface the first time.

© 2026 Ray Munro. All rights reserved.
