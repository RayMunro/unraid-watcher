<p align="center"><img src="assets/icon.png" width="96" alt="Unraid Watcher icon"></p>

# Controls and safety

Unraid Watcher can change things on your server, not just read them. This guide explains what each action does, what it needs, and what protects you from mistakes.

## Several servers

Actions always apply to the server you are viewing, which is named in the sidebar picker and at the top of the window. The confirmations for stopping the array, a correcting parity check, spinning down all disks, rebooting, and shutting down repeat the server's name. Read it before you confirm, especially if your servers have similar roles.

## Permissions

| Method | Needed for |
|--------|------------|
| **Viewer API key** | All read-only dashboards |
| **Admin API key** | Container start, stop, pause, and resume; VM power actions; array start and stop; parity checks; archiving notifications |
| **SSH** | Disk spin up and down, mover, reboot and shutdown, container restart and logs, SMART tests, VM details, creation, editing, cloning, media, and console, share settings and management, the command console |

Each server has its own key and its own SSH setting, so you can give a server you only watch a Viewer key and no SSH, and keep Admin access for the ones you manage. If you only want to monitor, use a Viewer key and leave SSH off. Nothing in the app can then change your server.

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
| Delete cache files that are copies of array files | Shows the list first, then confirms. Each file is re-checked byte for byte against its array copy just before it is deleted |
| Delete empty cache folders | Shows the list first, then confirms. Only folders with nothing inside are removed |
| Remove a torrent in Deluge | Choose to keep the files, or delete them too (cannot be undone) |

Actions that are easy to undo, such as starting a container, pausing a VM, or a short SMART test, run immediately.

## Built-in safeguards

**Cache clean-up: files**

- A cache file is only ever deleted when an identical copy exists on an array disk. "On the array" means a real array disk (`/mnt/disk1`, `/mnt/disk2`, and so on), never another pool.
- The scan can decide by size and date, or by comparing every byte. Whichever you choose, the delete step compares the two files byte for byte again, right before deleting each one. A file is kept, and reported, if it no longer exists, has changed since the scan, has no copy on an array disk, or differs from that copy.
- Files whose array copy differs are listed for your information and are never offered for deletion.
- Files changed in the last hour (adjustable), symbolic links, files in the skipped top-level folders, and files directly in the pool root are never examined.
- Only regular files are removed, never folders, and the array copy is never touched.
- Deleting is refused while the mover is running, and the scan says so.
- Files in shares that use the mover are ticked by default. Files in shares that prefer the cache, use it exclusively, or do not use it are listed but not ticked, because for those shares the cache copy is meant to be there.

**Cache clean-up: folders**

- The scan only reads. Nothing is deleted until you tick folders and confirm.
- Only folders with no files and no links anywhere inside are ever listed, and each is checked again at the moment it is deleted: the delete step removes a folder only if it is empty right then, deepest first. A folder that gained a file since the scan is left alone, along with its parents.
- The pool itself, and anything outside it, can never be named: paths must sit inside the pool and may not contain `..`.
- `appdata`, `system` and `domains` are skipped by default and never entered. Recently changed folders are skipped by default.
- Empty top-level folders (the folder for a share) are left alone unless you switch that on.

**Everything else**

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
| Delete a cache file that is identical on the array | Yes, in the sense that nothing is lost: the identical copy stays on the array |
| Delete an empty cache folder | Yes, it is empty, so the system recreates it when something needs it |
| Remove a torrent (keep files) | Re-add the torrent or magnet link |
| Remove a torrent and delete files | No, the files are gone |
| Shut down the server | Needs physical or out-of-band power on |
| Command console | Depends entirely on the command |

## Good habits

- Try new features on a test VM or an empty test share first.
- Use shut down rather than force stop for VMs whenever possible.
- Keep an up-to-date backup of your flash drive. VM and share definitions live there.
- After editing a VM's XML, check the VM in the Unraid web interface the first time.

© 2026 Ray Munro. Licensed under the GNU General Public License v3.0 or later.
