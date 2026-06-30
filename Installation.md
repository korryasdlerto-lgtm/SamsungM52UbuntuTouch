# Installation

> ⚠️ **This port is in development. SSH/USB is not stable yet. Do not use as a daily driver.**

## Requirements

- Samsung Galaxy M52 5G (SM-M526B)
- TWRP recovery
- Ubuntu Touch rootfs (Halium 13 compatible)
- `adb` on PC

## Steps

### 1. Flash Ubuntu Touch via TWRP

Flash the standard Halium 13 Ubuntu Touch installer zip, which writes:
- `boot.img` (with Halium kernel)
- `vendor_boot.img`
- Ubuntu Touch rootfs to userdata

### 2. Deploy overlay files

Boot into TWRP, then from PC:

```sh
# Copy systemd units and config
adb push overlay/system/etc/systemd/system/ /data/system-data/etc/systemd/system/
adb push overlay/system/etc/default/        /data/system-data/etc/default/
adb push overlay/system/var/lib/usb-moded/  /data/system-data/var/lib/usb-moded/
```

### 3. Deploy scripts to /userdata

```sh
adb push scripts/mount-patched-v3.sh        /data/mount-patched-v3.sh
adb push scripts/usb-gadget-preconfigure.sh /data/usb-gadget-preconfigure.sh
adb push scripts/usb-gadget-reset.sh        /data/usb-gadget-reset.sh
adb push scripts/lxc-mount-cleanup.sh       /data/lxc-mount-cleanup.sh

adb shell chmod +x /data/mount-patched-v3.sh
adb shell chmod +x /data/usb-gadget-preconfigure.sh
adb shell chmod +x /data/usb-gadget-reset.sh
adb shell chmod +x /data/lxc-mount-cleanup.sh
```

### 4. Enable systemd units

```sh
adb shell "mkdir -p /data/system-data/etc/systemd/system/basic.target.wants"
adb shell "ln -sf /etc/systemd/system/usb-gadget-reset.service \
    /data/system-data/etc/systemd/system/basic.target.wants/usb-gadget-reset.service"
adb shell "ln -sf /etc/systemd/system/halium-mount-patch.service \
    /data/system-data/etc/systemd/system/lxc-android-config.service.wants/halium-mount-patch.service"
```

### 5. Boot Ubuntu Touch

Reboot from TWRP. Ubuntu Touch should start.

Check logs after ~3 min:
```sh
adb shell cat /userdata/usb-gadget-preconfigure.log
adb shell cat /userdata/usb-moded.log
```
