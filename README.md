# Ubuntu Touch / Halium 13 — Samsung Galaxy M52 5G (SM-M526B / m52xq)

> **Work in progress.** Port is being actively developed.

## Device info

| Field | Value |
|---|---|
| Model | Samsung Galaxy M52 5G |
| Codename | m52xq |
| SoC | Qualcomm Snapdragon 778G (SM7325) |
| RAM | 6 / 8 GB |
| Android base | Android 13 (One UI 5) |
| Halium version | 13 |
| Kernel | Samsung downstream (4.19) |

## Boot images in use

| Image | Version |
|---|---|
| `halium_boot` | v31 |
| `vendor_boot` | v16 (signed) |

## Status

| Feature | Status |
|---|---|
| Boot (Ubuntu Touch) | ✅ Boots |
| USB gadget (RNDIS) | ✅ Working |
| SSH over USB | ✅ Stable |
| LXC Android container | ✅ Boots and stays up |
| Android property access (getprop, host-side) | ✅ Working |
| Display (Lomiri/Mir) | 🔧 Graphics driver selected, GPU init blocked (see Known issues) |
| Wi-Fi | ❌ Not yet |
| Calls / SMS | ❌ Not yet |
| Camera | ❌ Not yet |

## Key kernel notes

- `CONFIG_USB_CONFIGFS_RNDIS` is **not set**, but RNDIS still works: `CONFIG_USB_F_GSI=y`
  bundles `rndis.o` directly into `usb_f_gsi.o` when `CONFIG_USB_F_RNDIS` is unset
  (see `drivers/usb/gadget/function/Makefile`). The configfs function name is
  `rndis.usb0`, real interface name that appears is `usb0` (not `rndis0`).
- USB controller: `a600000.dwc3`
- `usb-moded` (stock, from rootfs) always enters rescue mode (`0x0afe`) a few
  seconds after start regardless of flags, killing any RNDIS session before
  `usb-moded-ssh.service` can start. We fully replace `usb-moded`'s `ExecStart`
  with our own script instead of fighting the rescue timer.
- `usb-moded.service`'s `CapabilityBoundingSet` was scoped to the *original*
  `usb_moded` binary's needs only. Since we now run `sshd` under this same
  unit, it needs the full capability set (chroot for privsep, chown for pty,
  audit_write for session accounting, sys_ptrace/setpcap for debugging) —
  see `overlay/system/etc/systemd/system/usb-moded.service.d/zz-usb-gadget-reset.conf`.
- `/var/lib/lxc/android/config` bind-mounts `/dev/null` over the Android USB
  HAL binary (`android.hardware.usb@1.3-service-qti`) to keep it from
  fighting `usb-moded` for the gadget. This device's vendor image doesn't
  ship that binary at all, so the `lxc.mount.entry` failed (non-optional)
  and **aborted the entire container start** — this was the very first
  blocker, before usb-moded's rescue-mode timer ever became relevant. Fixed
  by adding `,optional` to that one mount entry, matching the other entries
  in the same file — see `overlay/userdata/fix-lxc-config-optional-usb-mount.sh`.
- `system.img`/`vendor.img` use a **double-nested layout**: real content is at
  `system/system/*` and `vendor/lib64/*` reached only through the *running
  container's own* mount namespace, not `vendor/*`/`system/*`. Compat symlinks
  like `system/bin -> /system/bin` only resolve correctly from *inside* the
  LXC container; from the Ubuntu Touch host they self-loop. This breaks
  anything resolving `/system` or `/vendor` from the host (getprop, EGL
  loader) unless fixed — see `overlay/userdata/fix-system-vendor-symlinks.sh`.
- `lxc-android-config` on this build is missing the upstream
  `lxc-android-config-mount-apexes.service` / `mount-apexes.py` pair (mounts
  `com.android.runtime`/`art`/`i18n`/`vndk.*` APEXes for host-side libhybris
  use). Without it, host-side bionic can't load `libc.so`/`libcutils.so`
  (needed for `getprop`, and for Mir's `graphics-android2` platform). We
  ship the missing files ourselves, patched for this device's nested
  `system/system/apex` layout — see
  `overlay/system/usr/libexec/lxc-android-config/mount-apexes.py`.
- `mir-platform-graphics-android2-15` (from UBports' `mir-android2-platform`,
  a modern libhybris/AIDL-Composer3-aware Mir platform) is required — the
  older `mir-platform-graphics-android15`/`-caf15` only support the legacy
  `hwcomposer.<board>.so` HAL module, which this device's vendor image does
  not ship (it only has the AIDL `android.hardware.graphics.composer3`
  service). Install via `.deb` from `repo2.ubports.com`, matching the
  installed `libmirserver`/`libmirplatform` version exactly.

## Known issues

- **GPU init (`/dev/kgsl-3d0`) fails with `ETIMEDOUT`** on first open
  (`adreno_first_open` → GMU `PwrLimitsExitIdl` OOB timeout in
  `drivers/gpu/msm/adreno_a6xx_gmu.c`). Root cause found: `vndservicemanager`
  (inside the LXC container) fails to start — `CANNOT LINK EXECUTABLE
  ".../vndservicemanager": cannot locate symbol "selinux_vendor_log_callback"`
  — because the currently-installed `/system/lib64/libselinux.so` predates
  this symbol being added to `external/selinux/libselinux`. This crash-loops
  `vndservicemanager` (and by extension the whole `hal` service class,
  including the display composer) every ~5s via
  `onrestart class_restart hal`, which is very likely why the GPU/GMU power
  state never stabilizes.
  - The missing symbol **does** exist in this tree's
    `external/selinux/libselinux` source (`src/android/android.c`) — a
    straight rebuild+swap of `libselinux.so` fixes `vndservicemanager`, but
    introduced a **new, tighter** crash loop elsewhere (`init: Could not set
    execcon for 'u:r:vendor_init:s0'`), i.e. the freshly-built `libselinux.so`
    is not fully ABI-compatible with whatever this device's other prebuilt
    binaries (at least `init`) expect. **Do not swap the whole library** —
    reverted, not shipped. The correct fix is a surgical binary patch that
    adds *only* the missing symbol to the existing installed `.so` (e.g. via
    an `objcopy`/linker script based symbol injection) rather than a full
    rebuild from current source. Not yet done — see `patches/` for the
    (safe, tested, but insufficient on its own) `selinux_stubs` fix, and the
    notes above for what's actually needed next.
  - `vendor/halium/selinux_stubs/stubs.c` *also* has an analogous bug
    (declares `selinux_vendor_log_callback` in `libselinux_stubs.map.txt`
    without implementing it) — fixed safely in
    `patches/0001-selinux_stubs-add-missing-selinux_vendor_log_callback.patch`.
    This didn't affect `vndservicemanager` (it links the real `libselinux`,
    not the stub), but is a real bug worth fixing regardless.

## Repo structure

```
overlay/system/              ← copied to the on-device systemd/etc tree
                                (NOTE: /data/system-data/... only overlays
                                specific dirs, NOT /usr — see Installation.md)
  etc/
    systemd/system/          ← custom systemd units and drop-ins
    default/usb-moded.d/     ← usb-moded device config
  usr/libexec/lxc-android-config/
    mount-apexes.py           ← missing upstream apex-mounting script (patched
                                 for this device's nested system/system/apex)
  var/lib/usb-moded/          ← usb-moded persistent state

overlay/userdata/             ← deployed to /userdata/ on device
  usb-moded-bypass.sh          ← replaces usb_moded entirely: RNDIS setup + sshd
  usb-moded-conf-wrapper.sh    ← gadget cleanup, called before the bypass script
  fix-system-vendor-symlinks.sh ← fixes host /system, /vendor (see notes above)
  fix-lxc-config-optional-usb-mount.sh ← the very first LXC-container-won't-
                                 start fix (see notes above)
  lxc-mount-cleanup.sh         ← lazy-unmounts LXC bind mounts before restart

patches/                      ← patches against AOSP source trees in this
                                 manifest (NOT part of the overlay - apply
                                 and rebuild the relevant module)
  0001-selinux_stubs-...patch  ← vendor/halium/selinux_stubs missing stub fix

device-config/                ← reference copies of the exact kernel defconfig
                                 and core device tree makefiles used for the
                                 current build (halium_boot v31 / vendor_boot v16)
  kernel/lineage-m52xq_defconfig
  device-tree/BoardConfig.mk, device.mk, lineage_m52xq.mk, ...
```

## Installation

See [Installation.md](Installation.md).

## Build

See the [Halium porting guide](https://docs.halium.org/en/latest/porting/index.html).
Kernel source: `kernel/samsung/sm7325`

## Contributing

This is a personal porting effort. PRs and issues welcome.
