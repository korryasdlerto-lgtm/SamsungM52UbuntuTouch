#!/bin/sh
# Runs as ExecStartPre in usb-moded.service BEFORE ubports-usb-moded-configurator.
# Android init (in LXC) creates and binds the USB gadget (g1) with mtp/adb config.
# This script unbinds the UDC and removes configs/c.1 so the configurator gets a
# clean slate and can create its own c.1 without EBUSY.
#
# Drop-in: /etc/systemd/system/usb-moded.service.d/gadget-reset.conf
# Logs: /userdata/usb-gadget-preconfigure.log

G=/sys/kernel/config/usb_gadget/g1
LOG=/userdata/usb-gadget-preconfigure.log
echo "$(date): starting gadget preconfigure" >> "$LOG" 2>/dev/null

[ -d "$G" ] || { echo "$(date): g1 not found, nothing to do" >> "$LOG" 2>/dev/null; exit 0; }

echo "$(date): g1 found, UDC=$(cat $G/UDC 2>/dev/null)" >> "$LOG" 2>/dev/null

# 1. Unbind UDC
echo '' > "$G/UDC" 2>/dev/null && \
    echo "$(date): UDC unbound" >> "$LOG" 2>/dev/null || \
    echo "$(date): UDC unbind failed" >> "$LOG" 2>/dev/null

# 2. Remove symlinks from c.1 (mtp.usb0, ffs.adb etc from Android init)
for lnk in "$G/configs/c.1/"*; do
    [ -L "$lnk" ] || continue
    rm -f "$lnk" 2>/dev/null && \
        echo "$(date): removed symlink $lnk" >> "$LOG" 2>/dev/null || true
done

# 3. Remove c.1/strings subdirs
for s in "$G/configs/c.1/strings/"*/; do
    [ -d "$s" ] && rmdir "$s" 2>/dev/null || true
done

# 4. Remove c.1 itself so ubports-usb-moded-configurator gets a clean mkdir
rmdir "$G/configs/c.1" 2>/dev/null && \
    echo "$(date): removed c.1" >> "$LOG" 2>/dev/null || \
    echo "$(date): rmdir c.1 failed, remaining: $(ls $G/configs/c.1/ 2>/dev/null)" >> "$LOG" 2>/dev/null

echo "$(date): done, configs=$(ls $G/configs/ 2>/dev/null) functions=$(ls $G/functions/ 2>/dev/null)" >> "$LOG" 2>/dev/null
exit 0
