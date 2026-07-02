#!/bin/sh
# Called as ExecStop in halium-mount-patch.service.
# Lazy-unmounts all bind mounts inside the LXC rootfs before container restart.

R=/usr/lib/aarch64-linux-gnu/lxc
[ -d "$R" ] || exit 0
awk -v r="$R/" '$2 ~ "^"r {print $2}' /proc/mounts 2>/dev/null \
    | sort -r \
    | while IFS= read -r mp; do
        umount -l "$mp" 2>/dev/null || true
    done
exit 0
