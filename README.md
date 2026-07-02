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
  `drivers/gpu/msm/adreno_a6xx_gmu.c`). This chain of investigation goes
  several layers deep - summary of what's confirmed so far, most recent first:

  1. **`vendor_init` SELinux domain transition fails, in a tight retry loop
     with no backoff.** `init: Could not set execcon for 'u:r:vendor_init:s0':
     Invalid argument`. Android's init forks a restricted-privilege
     subprocess for vendor-originated commands (see [AOSP vendor init
     docs](https://source.android.com/docs/security/features/selinux/vendor-init)),
     transitioning it into the `vendor_init` domain via `setexeccon()`. This
     requires the domain to actually be loaded into the kernel's SELinux
     policy state - if it isn't, the transition fails with EINVAL and
     (this is the dangerous part) **init retries instantly, with no
     backoff at all**, pegging a CPU core and generating real heat. This is
     **not killable by killing a process** - it's PID 1 (inside the
     container)'s own internal loop; the only way to stop it once started
     is `lxc-stop -n android -k` (whole-container force stop). It also
     appears capable of a hard system crash/watchdog-reset, not just a
     hang - captured in `/sys/fs/pstore/console-ramoops-0` after one
     occurrence. **Do not test this without a watchdog script running
     dmesg -w and force-stopping the container on a sustained burst.**

  2. **Root cause of the domain never loading:** the container's
     `/var/lib/lxc/android/config` has `lxc.cap.drop = mac_admin
     mac_override`. `CAP_MAC_ADMIN` is required for `load_policy()` -
     without it, Android's own init inside the container can never load
     its SELinux policy into the (non-namespaced, kernel-wide) SELinux
     subsystem in the first place, so *no* domain ever becomes valid, not
     just `vendor_init`. Removing `mac_admin` from that line **does**
     measurably help - `dmesg` shows `SELinux: Loaded file_contexts`
     appearing where it didn't before - but the loop **still occurs**, just
     with a different total count. Loading is at least partially
     succeeding but something about it remains incomplete or wrong.

  3. **`/sys/fs/selinux` does not exist on the host even after the
     `mac_admin` fix** (`mkdir /sys/fs/selinux` fails with EPERM - the
     kernel never created the stub, meaning SELinux's own early-boot LSM
     init never ran as an active module on this kernel, despite
     `CONFIG_SECURITY_SELINUX=y` *and* `CONFIG_DEFAULT_SECURITY_SELINUX=y`
     both being set in the kernel `.config`; `CONFIG_LSM=` lists both
     `selinux` and `apparmor`). Yet `load_policy()` from inside the
     container *does* partially work per point 2 above, apparently via a
     path that doesn't require the `selinuxfs` mount. This is the
     unresolved thread - why the stub directory is never created at boot,
     and whether that's fixable from a boot cmdline change or genuinely
     needs a kernel-side fix, is not yet determined. `/proc/cmdline` has
     `androidboot.selinux=permissive` but no explicit `lsm=` override.

  Given point 1's real crash/instability risk, **do not attempt to
  reproduce or continue this investigation without the watchdog pattern
  above**, and be aware it may require a kernel-level change (out of scope
  for a live phone without a full backup/recovery plan).

  Earlier, separate finding (already fixed, unrelated to the above):
  `vndservicemanager` also used to fail to *link* at all -
  `CANNOT LINK EXECUTABLE ".../vndservicemanager": cannot locate symbol
  "selinux_vendor_log_callback"` - because the installed
  `/system/lib64/libselinux.so` (actually bind-mounted from
  `/userdata/libselinux-stub.so`, an existing halium mechanism, not
  something this port added) predates that symbol existing in
  `external/selinux/libselinux`. Fixed live by adding the missing symbol
  and swapping the file in-place (atomically, via temp-file + `mv` in the
  same directory - a plain non-atomic overwrite while the file is mapped by
  running processes corrupts it and crashes unrelated things). This
  specific fix is stable and did not itself cause point 1-3 above; it just
  allowed execution to *reach* the vendor_init issue instead of dying
  earlier for an unrelated reason.
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

tools/                        ← diagnostic tools, not deployed automatically
  vendor-init-loop-watchdog.sh ← required before touching the vendor_init
                                 SELinux loop (see Known issues) - it's not
                                 killable by killing a process
```

## Installation

See [Installation.md](Installation.md).

## Build

See the [Halium porting guide](https://docs.halium.org/en/latest/porting/index.html).
Kernel source: `kernel/samsung/sm7325`

## Contributing

This is a personal porting effort. PRs and issues welcome.
