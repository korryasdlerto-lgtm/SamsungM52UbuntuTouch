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

| Image | Version | File |
|---|---|---|
| `halium_boot` | v40 | [`images/halium_boot_v40.img`](images/halium_boot_v40.img) |
| `vendor_boot` | v16 (signed) | [`images/vendor_boot_v16_signed.img`](images/vendor_boot_v16_signed.img) |

v40 has `CONFIG_SECURITY_SELINUX=y` (see "Kernel config fix" below — this is
the confirmed-working setting; a same-day follow-up attempt to fully compile
SELinux *out* of the kernel entirely, v39, caused a total boot failure — see
"Do not retry" note below) plus the same ramdisk/cmdline as the v33-era
working build. `vendor_boot` (DTB + vendor ramdisk) has not needed to change
since v16 and is not rebuilt alongside every `halium_boot` bump.

## Status

| Feature | Status |
|---|---|
| Boot (Ubuntu Touch) | ✅ Boots |
| USB gadget (RNDIS) | ✅ Working |
| SSH over USB | ✅ Stable |
| LXC Android container | ✅ Boots and stays up (SELinux loop fixed, see below) |
| Android property access (getprop, host-side) | ✅ Working |
| `vendor.qti.hardware.display.composer` / `vndservicemanager` | ✅ Fixed — see "vndservicemanager crash-loop fix" below |
| Display (Lomiri/Mir) | 🔧 Blocked on `HidlComposer::createClient()` returning no client (`failed to create composer client`, `LOG_ALWAYS_FATAL` abort) — see Known issues. A prior session reported reaching a later-stage `/dev/kgsl-3d0` GPU timeout instead; not yet reconciled whether that was a different live state or this composer-client issue is itself new/regressed. |
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
- The Adreno EGL/GLES vendor libraries (`libEGL_adreno.so`,
  `libGLESv2_adreno.so`, `libGLESv1_CM_adreno.so`) live in
  `/vendor/lib64/egl/` on this device, but Mir's `graphics-android2`
  platform (via libhybris) does a bare `dlopen()` that only searches
  `/vendor/lib64/` directly, not the `egl/` subdirectory — same issue as
  `eglSubDriverAndroid.so` (see above). Fixed by symlinking all three
  directly into `/vendor/lib64/`.
- Observed `/android/apex` mounted **twice** (two stacked `tmpfs`, confirmed
  via `findmnt -A /android/apex`) after unmasking and restarting
  `lxc-android-config.service` mid-session for testing. The second, empty
  `tmpfs` shadows the working APEX bind-mounts underneath — `ls /android/apex`
  shows empty even though the mounts are still there one layer down. Symptom:
  `getprop`/anything needing host-side bionic fails again with `library
  "libc.so" not found`, even though it worked right after boot. `mount-apexes.py`
  *does* already guard against this with `os.path.ismount("/android/apex")`
  (line 160) — so this needs more investigation (likely a mount-namespace/
  propagation quirk when the mount-apexes service re-triggers via
  `lxc-android-config.service`'s dependency chain, not a missing check).
  Workaround: `sudo umount /android/apex` once to pop the shadowing layer.

## Kernel config fix: SELinux was never compiled in (root cause of the vendor_init loop)

The `vendor_init` SELinux loop described below (and the GPU chain that was
blocked behind it) turned out to have a one-line root cause, found by
grepping the actual kernel defconfig instead of trusting what earlier
`.config` inspection suggested:

```
kernel/samsung/sm7325/arch/arm64/configs/vendor/lineage-m52xq_defconfig:6722
# CONFIG_SECURITY_SELINUX is not set
```

**SELinux was not compiled into the kernel at all**, despite
`CONFIG_DEFAULT_SECURITY_SELINUX=y` and a full set of `CONFIG_SECURITY_SELINUX_*`
sub-options already present in the defconfig (dead weight without the parent
option). This is why `/sys/fs/selinux` never got created no matter what
userspace/LXC capability fixes were applied — the kernel had no SELinux LSM
to register it. `androidboot.selinux=permissive` in the cmdline is a
userspace/vendor_init hint only; it does nothing if the kernel can't back it.

Fix: flip that one line to `CONFIG_SECURITY_SELINUX=y`, rebuild the kernel
(`Image`), repack `boot.img` (kernel + same ramdisk/cmdline, header v3) →
`halium_boot_v33.img`. AppArmor stays on (`CONFIG_SECURITY_APPARMOR=y`) since
Ubuntu Touch itself needs it — this kernel supports full LSM stacking
(confirmed via the string `LSM: security= is ignored because it is superseded
by lsm=` present in the built kernel binary), and `CONFIG_LSM=` already lists
both `selinux` and `apparmor`, so no cmdline change was actually required
once the module itself was compiled in.

**Result, confirmed after flashing v33 and testing under the watchdog:**
`/sys/fs/selinux` now exists with a fully populated selinuxfs (`enforce`,
`policy`, `booleans`, etc.), the `vendor_init` execcon retry loop is gone
(0 occurrences vs. a 60+/2s runaway loop before), and
`lxc-android-config.service` starts and stays running normally. An earlier
attempt at a lighter fix — just adding `lsm=lockdown,yama,loadpin,safesetid,
integrity,selinux,smack,tomoyo,apparmor` to `BOARD_KERNEL_CMDLINE` without
rebuilding the kernel (`halium_boot_v32.img`) — was tested first and **did
not help at all**; the loop reproduced identically. This makes sense in
hindsight: `lsm=` only selects *which already-compiled* LSMs get initialized
and in what order — it can't add a module that was never compiled in.

**Do not retry fully compiling SELinux back out of the kernel.** A same-day
follow-up experiment (v39) went the other direction — `CONFIG_SECURITY_SELINUX`
set to `is not set` again, hoping to sidestep SELinux instead of fixing it —
under the theory that our `libselinux-stub.so` bind-mount (see below) makes a
real kernel policy unnecessary. This **caused a total boot failure**: no USB
gadget, no SSH, confirmed via TWRP pstore capture (`/sys/fs/pstore/console-ramoops-0`,
works even when the flashed boot is fully hung) to be a ~800/sec tight
fork-loop — `init: Could not set execcon for 'u:r:vendor_init:s0': Invalid
argument` / `init: Restarting subcontext 'u:r:vendor_init:s0'` — pegging the
CPU so hard nothing else (including USB enumeration) could proceed. Root
cause: Android init's `SubcontextProcess` mechanism does a **direct `write()`
to `/proc/thread-self/attr/exec`**, not a dynamic `libselinux.so` call, so no
userspace stub can intercept it — the kernel LSM has to actually be present
(even policy-less) for that write to be tolerated instead of hard-EINVALing
every single time with no backoff. Reverted same-day back to
`CONFIG_SECURITY_SELINUX=y`, re-flashed v38, confirmed working again.

## vndservicemanager crash-loop fix (composer `service_manager` class)

Even with the kernel SELinux fix above and `/sys/fs/selinux` present, no
*policy* is ever loaded into it (Halium's boot flow execs straight into
`/init second_stage`, skipping Android init's dedicated `/init selinux_setup`
stage — confirmed via `/usr/libexec/lxc-android-config/start-android-container`).
`/sys/fs/selinux/class/` has 0 entries. This broke `vndservicemanager`'s
per-call authorization: `frameworks/native/cmds/servicemanager/Access.cpp`'s
`canAdd()`/`canFind()` resolve a security class by string
(`string_to_security_class("service_manager")`), which can't succeed with no
policy loaded, and the real (stock Samsung) binary at `/vendor/bin/vndservicemanager`
fails closed on that — every `addService()`/`getService()` call gets denied.
This specifically broke `vendor.qti.hardware.display.composer`'s self-registration
(`HWCSession::Init()` → `qService::init()` registers `"display.qservice"` then
immediately self-looks-it-up via `getService()` on `/dev/vndbinder` — the
lookup returns NULL, `HWCSession::Init()` returns `-EINVAL`, which the shell
reports as exit status 234 = `256 - 22`) in a tight ~5.2s restart loop, taking
`surfaceflinger`/`zygote`/`netd`/`gpu`/`mediametrics`/`wificond` down with it
via `onrestart class_restart hal`.

Our own AOSP tree already has the intended Halium fix for this
(`Access.cpp`'s `actionAllowed()`/`actionAllowedFromLookup()` both start with
`// Disabled for Halium` + `return true;`, unconditionally allowing every
call) — it was just never compiled into a binary actually running on the
device, since `/vendor` is stock Samsung's untouched image. The *official*
Halium mechanism for getting a fixed `libselinux` into `vndservicemanager` is
`LD_PRELOAD` of `libselinux_stubs.so` (see `hybris-patches/system/linkerconfig/`
in this repo — needs a linkerconfig namespace patch to permit the cross-namespace
load into the VNDK vendor namespace at all, which is also why our older
`libselinux-stub.so` bind-mount-over-the-real-`.so`-path trick never actually
took effect for `vndservicemanager`/vendor-namespace processes in the first
place — Treble VNDK linker namespacing does its own separate resolution).

**Fix applied**: built `vndservicemanager` directly from our own
already-patched source (`make vndservicemanager` after `lunch
lineage_m52xq-userdebug`) and bind-mounted the resulting binary over the
stock one — see `overlay/userdata/vndservicemanager-halium` in this repo, and
add this line to `mount-patched-v3.sh` right after the `/dev/mapper/vendor`
mount (needs `/vendor` mounted first):
```sh
mount --bind /userdata/vndservicemanager-halium "${R}/vendor/bin/vndservicemanager" 2>/dev/null || true
```
Since this binary has `return true;` hardcoded in its own authorization
logic, it doesn't need `libselinux`/the stub/`LD_PRELOAD` at all — more
robust than the official mechanism, and confirms independently the same
approach used by the closest comparable device with a genuinely working
Ubuntu Touch port, the Nothing Phone 1 ("spacewar", also Snapdragon
778G/SM7325) — its `github.com/Nonta72/nothing-spacewar` overlay ships the
exact same `vendor/bin/vndservicemanager` binary-replacement pattern.

**Confirmed working**: `vendor.qti.hardware.display.composer-service` and
`surfaceflinger` both stayed up 35+ seconds with zero restarts (was crashing
every ~5.2s before). `logcat` confirms the old failure signature
(`qdqservice: Adding display.qservice failed` → `Service display.qservice
didn't start. Returning NULL` → `HWCSession::Init: Failed to acquire
display.qservice`) is gone.

**New, later-stage blocker** (not yet fixed): `lomiri-system-compositor` now
fails fast (~0.2s, SIGABRT) with `failed to create composer client` instead —
real progress (past the old failure point), but a new wall. Traced to
`HidlComposerHal.cpp:230`, `HidlComposer::HidlComposer()`:
`IComposer::getService()` now succeeds, but the follow-up `createClient()`
HIDL call never sets a client (`Error != NONE`, silently — the AOSP code
doesn't log which error), so `LOG_ALWAYS_FATAL("failed to create composer
client")` aborts. Ruled out: `surfaceflinger` holding the client first
(tested with `kill -STOP` on its PID for the duration of a manual
`lomiri-system-compositor --debug-without-dm ...` test — same failure with it
fully paused); kernel-level binder/SELinux denial (`dmesg` has zero `avc:`
messages the whole session, consistent with no policy meaning nothing to
check against; `strace -f -p <composer-service-pid>` during a live attempt
showed all `BINDER_WRITE_READ` ioctls returning `0` — the transport-level
IPC completes fine, the rejection is purely inside the closed-source Qualcomm
SDM composer implementation). Not yet confirmed: whether the calling
identity matters — our test (and the real `lightdm.service`, which also has
no `User=`/`Group=` set) calls the compositor as host-side root (uid 0),
which lacks the `android_graphics`/`android_input` supplementary groups the
`phablet` user has; testing as `phablet` gets blocked even earlier by a
*different* problem (`must have at least EGL 1.4`, DRM master claim fails
without root) before it can even reach the composer-client stage, so this
remains an open, untested lead rather than a confirmed cause.

## Android-side zygote64 / system_server boot chain (telephony/RIL track)

This is a **separate, parallel track** from the Lomiri/Mir display work
above: telephony (SIM/RIL, `phone`/`isub` services) needs the actual Android
`zygote64` → `system_server` Java stack to come up inside the LXC container,
independent of whether a real display/SurfaceFlinger exists. Screen
rendering stays on the hybris/Mir path either way, unaffected by any of
this.

Starting point this round was zygote64 dying instantly with
`NoClassDefFoundError` on `SystemServiceRegistry`'s static init. Fixed, in
order (each confirmed via reboot + logcat, most via dexlib2 bytecode
patching of `framework.jar`/`services.jar` since a full AOSP rebuild wasn't
always practical mid-chain — patched jars are shipped in `builds/userdata/`,
see below):

1. `SystemServiceRegistry.<clinit>` aborted the whole class on the first
   APEX-only service class it couldn't resolve (`TetheringManager`, etc.) —
   wrapped the registration calls in try/catch instead of letting one
   missing service kill every other service's registration.
2. `ActivityThread.initializeMainlineModules()` had the same problem for
   `BluetoothFrameworkInitializer` — same try/catch treatment, plus a
   standalone `framework-bluetooth-stub.jar` added to `BOOTCLASSPATH` so the
   class at least resolves (doesn't need to fully function yet).
3. `AppRestrictionController`'s `RoleManager`-dependent lambda field
   initializer crashed `ActivityManagerService`'s construction — NOP'd out
   via raw binary dex patching (dexlib2's `DexPool.writeTo()` reliably
   *corrupts* `services.jar`'s large classes.dex on any round-trip, even
   completely unchanged — raw byte patching with checksum/SHA1 recompute is
   the only thing that worked for this specific file).
4. Native `SurfaceComposerClient.cpp`: ~20+ call sites that dereference
   `ComposerService::getComposerService()`/`ComposerServiceAIDL::getComposerService()`
   without a null check (crash after crash, one function at a time) — this
   device's Halium fork stubs out the real SurfaceFlinger connection
   entirely (by design — see the top of this README), so every caller needs
   to handle a null composer service gracefully. Also fabricated a complete
   **fake default display** (real M52 5G panel specs: 1080×2400, density
   420) so `DisplayManagerService`'s `WaitForDisplay` boot phase succeeds in
   ~20ms instead of timing out at 10s or segfaulting — this alone was
   previously unsolved upstream for this class of device.
   - Regression caught and fixed *this* session: stubbing
     `ComposerServiceAIDL::connectLocked()` by fully deleting its
     `waitForService<gui::ISurfaceComposer>()` call (to avoid a real
     indefinite hang, since that AIDL path was never stubbed by upstream)
     silently dropped `libgui.so`'s only reference to
     `gui::ISurfaceComposer::asInterface`/`BnScreenCaptureListener::onTransact`
     — Soong's `static_libs` (unlike `whole_static_libs`) only pulls in
     archive members that are actually referenced, so those symbols vanished
     from the exported `.so` even though `libandroid_runtime.so`/
     `libstagefright.so` still need them (`CANNOT LINK EXECUTABLE`,
     `app_process64`/`camera_service`/`mediaextractor` crash-looping). Fixed
     by using `checkService()` (non-blocking, returns null immediately)
     instead of deleting the call outright — keeps the symbol reference
     alive for the linker while still avoiding any hang. **Lesson: never
     just delete/comment-out a call to a real AIDL/HIDL interface type in
     this codebase to "stub" it — always route through some real call
     (checkService, a stub returning null, etc.) that keeps the compiler
     referencing the interface, or the shared library's exported ABI
     silently breaks for every *other* library that links against it.**
5. `LocalDisplayAdapter`/`Choreographer`/`WindowAnimator`:
   `DisplayEventReceiver.nativeInit()` always fails (`status=-19`/ENODEV, no
   real vsync source) and threw uncaught from every caller. Fixed at the
   root in `DisplayEventReceiver.java`'s constructor (catch + leave
   `mReceiverPtr = 0`, matching the null-ptr handling `scheduleVsync()`
   already had) instead of patching every individual caller one at a time.
6. zygote's native FD allowlist (`frameworks/base/core/jni/fd_utils.cpp`)
   only accepted APEX jar paths under `/apex/...`, not `/system/apex/...`
   (where our APEX content actually lives, since `apexd` never truly
   activates most APEXes here — see point 8) — zygote aborted with `Not
   allowlisted` trying to keep those FDs open across fork. Extended the
   allowlist check to also accept the `/system/apex/**/javalib/*.jar` form.
7. `RuntimePermissionsPersistence`/`RuntimePermissionsPersistenceImpl`
   (`NoClassDefFoundError` in `PackageManagerService`'s constructor) turned
   out to be a classpath **misclassification**, not a missing file:
   `service-permission.jar` was wired into `STANDALONE_SYSTEMSERVER_JARS`
   (its own child classloader, invisible to `services.jar`'s direct
   constructor call), but AOSP's own
   `build/make/target/product/default_art_config.mk` lists
   `com.android.permission:service-permission` under
   `PRODUCT_APEX_SYSTEM_SERVER_JARS` — the *main*, non-standalone list.
   Moved it to `SYSTEMSERVERCLASSPATH` in `mount.sh` to match stock AOSP's
   actual classloader wiring.
8. `PackageManagerService` threw `Required services extension package is
   missing, check config_servicesExtensionPackage` because `apexd` here only
   ever "activates" `com.android.apex.cts.shim.apex` (the one real `.apex`
   file on `/system/apex/`; everything else — wifi, permission, extservices,
   tethering, etc. — is a pre-extracted *directory* we bind-mount by hand,
   invisible to apexd's own internal Binder-queried active-package state).
   `getApexScanPartitions()`/`ApexManager.getActiveApexInfos()` normally
   calls the real `apexd` over Binder for this — but AOSP ships a second
   implementation, `ApexManagerFlattenedApex`, specifically for devices
   without updatable APEX support: it just globs `/apex/*` directories
   directly, no `apexd` involved at all. Forced this path by setting
   `ro.apex.updatable=false` (`ro.*` is write-once/first-writer-wins, and
   `/vendor/build.prop` — the only place this device sets it to `true` — is
   patched at that exact line in `mount.sh` rather than raced against via
   load order). `com.android.extservices` also needed adding to the
   already-existing simple whole-APEX-directory bind-mount loop (unlike
   `com.android.tethering`, we *do* want `extservices`'s `priv-app/` scanned
   — that's the actual `android.ext.services` package
   `config_servicesExtensionPackage` needs).

**Status at last checkpoint: very close.** `PackageManagerService` now
constructs fully (was previously the hard stop), `ActivityManagerService`
starts, boot reaches `WindowManager`/`Choreographer` init. Point 5 above
(the `DisplayEventReceiver` fix) was written and rebuilt as a source-level
`frameworks/base` fix but **not yet freshly deployed/reboot-tested** at the
moment of this commit — see `patches/0003-frameworks_base-zygote64-system_server-boot-fixes.patch`.
Next reboot should tell us if this clears the last known crash or surfaces
another one further down the `SystemServer.startBootstrapServices()`/
`startCoreServices()`/`startOtherServices()` chain. `builds/userdata/`
contains the exact deployed artifacts (patched `framework.jar`/`services.jar`,
`libgui.so` v7, `libandroid_runtime.so` v1, etc.) and
`overlay/userdata/mount.sh` is the full, currently-live LXC container-start
hook with every fix above wired in — treat it as the
single source of truth for the current live device state, since a lot of
this was iterated live via `ssh`+bind-mounts faster than full rebuild
cycles allowed.

## Known issues

- **GPU init (`/dev/kgsl-3d0`) fails with `ETIMEDOUT`** on open — confirmed via
  `strace` on a manually-launched `lomiri-system-compositor` (with the SELinux
  fix above in place, container running, and all vendor library path issues
  fixed): `openat(AT_FDCWD, "/dev/kgsl-3d0", O_RDWR|O_SYNC) = -1 ETIMEDOUT`.
  This is the same `adreno_first_open` → GMU `PwrLimitsExitIdl` OOB timeout
  symptom seen at the very start of graphics bring-up, but now cleanly
  isolated — it is the **only** remaining blocker in the Mir → EGL → GPU
  chain (Mir now correctly selects the `ubports:android2` driver, finds and
  loads all vendor EGL/GLES libraries, hwservicemanager/vndbinder/the AIDL
  composer3 service are all up). Mir's own error at this point is
  `must have at least EGL 1.4` (from `mir-android2-platform`'s
  `gl_context.cpp`, `create_and_initialize_display()`) — `eglInitialize()`
  succeeds but returns a version too low, consistent with EGL falling back
  to a stub/null implementation once the real device open times out.
  - GMU firmware blobs (`a660_gmu.bin`, `a660_sqe.fw`) **are** present at
    `/vendor/firmware/`. Tried live-setting
    `/sys/module/firmware_class/parameters/path` to `/vendor/firmware`
    (cmdline has no `firmware_class.path=` at all, unlike the device's
    stock/default `BOARD_KERNEL_CMDLINE`) — **no effect**, so either the
    ZAP/GMU firmware load path doesn't go through the generic
    `firmware_class` search at all (Qualcomm's PIL/`subsys-pil-tz`
    mechanism may use a fixed/device-tree-driven path instead), or it's
    only read once very early at boot before this could be changed live.
  - No further forum/upstream precedent found for this exact combination
    (Android 13, AIDL-only Composer3, `mir-android2-platform`, SM7325) as
    of this writing — this looks like it needs kernel/device-tree-level
    GMU power-sequencing work, not a userspace fix. Confirmed the kernel
    itself has no local patches (`HEAD` matches upstream
    `LineageOS/android_kernel_samsung_sm7325`'s `lineage-20` branch exactly).

- ~~**`vendor_init` SELinux domain transition loop**~~ — **fixed**, see
  "Kernel config fix" above. Keeping the original investigation notes below
  since they document the (wrong) userspace-only diagnosis path and the
  capability/mount fixes that were still worth keeping even though they
  weren't the actual root cause:

  1. `vendor_init` SELinux domain transition failed, in a tight retry loop
     with no backoff: `init: Could not set execcon for 'u:r:vendor_init:s0':
     Invalid argument`. Android's init forks a restricted-privilege
     subprocess for vendor-originated commands (see [AOSP vendor init
     docs](https://source.android.com/docs/security/features/selinux/vendor-init)),
     transitioning it into the `vendor_init` domain via `setexeccon()`. Not
     killable by killing a process - it's PID 1 (inside the container)'s own
     internal loop; only `lxc-stop -n android -k` (whole-container force
     stop) stops it. Capable of a hard system crash/watchdog-reset, captured
     in `/sys/fs/pstore/console-ramoops-0` on one occurrence. **Still test
     any container start/restart under the watchdog pattern below until
     this has been re-verified stable over many boots.**

  2. The container's `/var/lib/lxc/android/config` had `lxc.cap.drop =
     mac_admin mac_override`. `CAP_MAC_ADMIN` is required for
     `load_policy()`. Removing `mac_admin` **is still a required fix** (kept
     in the shipped config) even though it turned out not to be sufficient
     by itself — without the kernel fix above, this alone still left the
     loop running, just with a different count.

  3. `/sys/fs/selinux` not existing was the symptom that led to finding the
     real root cause (kernel config, above) — kept here for the debugging
     trail, since this is what a from-scratch investigation on a similar
     device would hit first too.

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
  mount.sh                     ← THE LXC container-start hook (/var/lib/lxc/
                                 android/mount.sh) — every zygote64/
                                 system_server boot fix from this session is
                                 wired in here as a bind-mount over the real
                                 /system|/vendor file, plus BOOTCLASSPATH/
                                 SYSTEMSERVERCLASSPATH construction and prop
                                 overrides. Single most load-bearing file in
                                 this repo for the telephony/RIL track.

patches/                      ← patches against AOSP source trees in this
                                 manifest (NOT part of the overlay - apply
                                 and rebuild the relevant module)
  0001-selinux_stubs-...patch  ← vendor/halium/selinux_stubs missing stub fix
  0002-frameworks_native-...patch ← fake default display + composer
                                 null-checks (frameworks/native/libs/gui)
  0003-frameworks_base-...patch ← zygote64/system_server boot fixes
                                 (fd_utils.cpp allowlist, DisplayEventReceiver,
                                 LocalDisplayAdapter, SurfaceControl)

builds/userdata/               ← exact deployed build artifacts (patched
                                 framework.jar/services.jar, libgui.so,
                                 libandroid_runtime.so, vndservicemanager,
                                 boot-framework.{oat,art,vdex}) — reproducing
                                 these from source means re-applying dexlib2
                                 bytecode patches on top of a fresh AOSP
                                 build (see zygote64/system_server section
                                 above); these binaries are the actual
                                 last-known-good/in-progress state, kept here
                                 since the source-only patches don't capture
                                 the bytecode-level fixes

device-config/                 ← reference copies of the exact kernel defconfig
                                 and core device tree makefiles used for the
                                 current build (halium_boot v40 / vendor_boot v16)
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
