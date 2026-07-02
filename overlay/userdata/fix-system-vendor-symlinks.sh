#!/bin/sh
# This device's system.img/vendor.img use a "double-nested" layout: the real
# content lives at system/system/*, not system/* directly. Stock compat
# symlinks like system/bin -> /system/bin only resolve correctly from
# *inside* the LXC container's own root; from the Ubuntu Touch host
# namespace they loop back on themselves (self-referential /system).
#
# This breaks anything that resolves /system or /vendor from the host side:
# getprop (libhybris fallback reads /system/build.prop), and the EGL/GLES
# loader used by the Mir "android2" graphics platform (looks for
# /vendor/lib64/egl/libEGL_<hw>.so).
#
# Fix: point host /system directly at the real nested content, and give
# /vendor a real (non-symlink) directory backed by a physical copy of the
# container's live /vendor view, since /vendor is mounted *inside* the
# container's own private mount namespace and isn't visible via a static
# host-side path at all.

set -e

mount -o remount,rw /

# /system: retarget the self-referential symlink to the real nested dir.
rm -f /system
ln -s /android/system/system /system

# /vendor: the real content only exists inside the running container's own
# mount namespace (mounted fresh at container start, not inherited from any
# host-visible static path). Copy it out once to /userdata (writable, not
# space-constrained like /), then bind-mount that copy over /vendor.
CPID="$(lxc-info -n android -p -H 2>/dev/null)"
if [ -n "$CPID" ] && [ -d "/proc/$CPID/root/vendor" ]; then
    if [ ! -d /userdata/vendor-real ]; then
        mkdir -p /userdata/vendor-real
        rsync -a "/proc/$CPID/root/vendor/" /userdata/vendor-real/
    fi
    rm -f /vendor
    mkdir -p /vendor
    mountpoint -q /vendor || mount --bind /userdata/vendor-real /vendor

    # bionic's default library search path checks /vendor/lib64 directly,
    # not /vendor/lib64/egl - the adreno EGL sub-driver dlopen()s by bare
    # name and needs to be reachable there too.
    ln -sf egl/eglSubDriverAndroid.so /vendor/lib64/eglSubDriverAndroid.so 2>/dev/null || true
fi

mount -o remount,ro /
