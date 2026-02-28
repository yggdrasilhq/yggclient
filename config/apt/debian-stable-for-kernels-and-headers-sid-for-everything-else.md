# Debian stable for kernels/headers, sid for everything else

## What happened
- An `apt full-upgrade` pulled in kernel `6.17.7+deb14+1` from unstable.
- ZFS DKMS 2.3.4 refused to build on that kernel (`Linux-Maximum: 6.16` in `/usr/src/zfs-2.3.4/META`), failing during `dkms` in `linux-image-6.17.7+deb14+1-amd64` post-install. The build error was `d_set_d_op` missing in `zpl_ctldir.c` for 6.17.
- Because the kernel postinst failed, `linux-image/headers 6.17.7` and their meta-packages stayed unconfigured and blocked further upgrades.

## Actions taken
- Removed the problematic 6.17.7 kernel, headers, and their meta-packages to unblock dpkg.
- Installed the Debian stable (trixie) kernel from the stable repo: `linux-image-amd64` and `linux-headers-amd64` (version `6.12.57+deb13`).
- Cleaned leftover older kernels/headers/kbuilds so only the trixie kernel stack remains installed.
- Added an apt pin to force all kernel/headers/kbuild packages to come from trixie and de-prioritize unstable for those packages:
  - `/etc/apt/preferences.d/kernel-trixie.pref`
    ```
    Package: linux-image-amd64 linux-image-* linux-headers-amd64 linux-headers-* linux-kbuild-*
    Pin: release n=trixie
    Pin-Priority: 1001

    Package: linux-image-amd64 linux-image-* linux-headers-amd64 linux-headers-* linux-kbuild-*
    Pin: release n=unstable
    Pin-Priority: 100
    ```

## Current state
- Installed/running kernel: `6.12.57+deb13` (trixie). Meta-packages now track trixie.
- ZFS DKMS builds succeed on the trixie kernel; no pending dpkg errors.
- `apt-cache policy linux-image-amd64` shows the trixie version (6.12.57-1) as candidate with priority 1001; sid kernel (6.17.7-2) is available but not selected.

## How to keep it stable
- Keep `/etc/apt/sources.list.d/debian-trixie.sources` enabled and leave the pin above in place.
- Do **not** install kernel packages with `-t unstable` or without the pin.
- Routine updates: `sudo apt update && sudo apt full-upgrade` will pull kernels/headers from trixie and other packages from unstable as before.
