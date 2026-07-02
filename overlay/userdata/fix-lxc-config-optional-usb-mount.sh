#!/bin/sh
# /var/lib/lxc/android/config masks the Android USB HAL by bind-mounting
# /dev/null over its binary - a common halium technique so Android's own USB
# HAL doesn't fight usb-moded for the gadget. This device's vendor image
# doesn't actually ship that binary at all, so the mount.entry fails
# (non-optional), and LXC aborts the whole container start instead of
# just skipping that one entry - the container never got past
# lxc_setup(), and usb-moded's rescue-mode issue was never even the real
# blocker on first boot.
#
# Fix: add the "optional" mount.entry flag (matching the vendor/data/odm
# entries already in this file) so a missing target is skipped instead of
# fatal.

set -e
CFG=/var/lib/lxc/android/config
LINE='lxc.mount.entry = /dev/null vendor/bin/hw/android.hardware.usb@1.3-service-qti bind bind,ro'

if grep -qF "$LINE 0 0" "$CFG" 2>/dev/null; then
    mount -o remount,rw /
    sed -i "s|${LINE} 0 0|${LINE},optional 0 0|" "$CFG"
    mount -o remount,ro /
fi
