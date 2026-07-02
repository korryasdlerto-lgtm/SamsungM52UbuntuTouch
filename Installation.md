# Installation

> ⚠️ **This port is in development. No display yet — SSH-only access. Do not use as a daily driver.**

## Requirements

- Samsung Galaxy M52 5G (SM-M526B)
- TWRP recovery
- Ubuntu Touch rootfs (Halium 13 compatible), already flashed to userdata
- `adb` on PC (used from TWRP only — normal boot has no adb, SSH is used instead)

## Steps

All `adb push` commands below are run **from TWRP recovery**, where `/data`
on the device maps to the real userdata partition (same thing the running
system calls `/userdata`). This is different from an SSH shell on the
*booted* system, where `/data` is a symlink into the Android container
(`/data -> /android/data`) — don't confuse the two.

### 1. Flash Ubuntu Touch via TWRP

Flash the standard Halium 13 Ubuntu Touch installer zip, which writes
`boot.img`, `vendor_boot.img`, and the Ubuntu Touch rootfs to userdata.
This repo was last tested against `halium_boot_v31.img` + `vendor_boot_v16`.

### 2. Deploy overlay files (from TWRP)

```sh
adb push overlay/system/etc/systemd/system/  /data/system-data/etc/systemd/system/
adb push overlay/system/usr/                  /data/system-data/usr/
adb push overlay/system/var/lib/usb-moded/    /data/system-data/var/lib/usb-moded/
```

`/data/system-data/usr/...` won't take effect by itself — `/usr` on the
booted system is **not** overlaid from `system-data` the way `/etc` is (only
specific paths under `/etc` are live-bind-mounted from there). The
`mount-apexes.py` script needs to land on the real, writable root
filesystem instead:

```sh
adb shell "mount -o remount,rw /"
adb push overlay/system/usr/libexec/lxc-android-config/mount-apexes.py \
    /data/usr/libexec/lxc-android-config/mount-apexes.py
# (adjust the destination above to wherever your rootfs.img is mounted from
#  TWRP - typically also /data if it's a loop-mounted image on userdata)
adb shell "chmod +x /data/usr/libexec/lxc-android-config/mount-apexes.py"
```

### 3. Deploy scripts to /userdata (from TWRP)

```sh
for f in usb-moded-bypass.sh usb-moded-conf-wrapper.sh \
         fix-system-vendor-symlinks.sh fix-lxc-config-optional-usb-mount.sh \
         lxc-mount-cleanup.sh; do
    adb push "overlay/userdata/$f" "/data/$f"
    adb shell chmod +x "/data/$f"
done
```

### 4. Apply the selinux_stubs source patch and rebuild (optional, host-side)

Only needed if you're rebuilding the ROM from source. Doesn't need to be
done on-device.

```sh
cd vendor/halium/selinux_stubs
git apply /path/to/patches/0001-selinux_stubs-add-missing-selinux_vendor_log_callback.patch
cd ../../..
source build/envsetup.sh && lunch lineage_m52xq-userdebug && m libselinux_stubs
```

### 5. Boot Ubuntu Touch

Reboot from TWRP into the system (not recovery). USB will enumerate as
RNDIS (`1209:0004`) once `usb-moded-bypass.sh` runs.

```sh
sudo ip addr add 10.15.19.100/24 dev eth0   # first boot only, see note below
ssh -p 8022 phablet@10.15.19.82             # empty/any password
```

To avoid the manual `ip addr` step on every boot, create a persistent
NetworkManager profile once on your PC:

```sh
sudo nmcli connection add type ethernet con-name "phone-rndis" ifname eth0 \
    ipv4.method manual ipv4.addresses 10.15.19.100/24 ipv4.never-default yes \
    ipv6.method disabled connection.autoconnect yes connection.autoconnect-priority 100
```

Check logs after boot:
```sh
ssh -p 8022 phablet@10.15.19.82 "sudo cat /userdata/usb-moded-bypass.log"
ssh -p 8022 phablet@10.15.19.82 "sudo systemctl status lxc-android-config.service"
```
