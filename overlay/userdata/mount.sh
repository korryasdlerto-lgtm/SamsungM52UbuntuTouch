#!/bin/sh
exec >> /userdata/mount-hook.log 2>&1
set -x

R="${LXC_ROOTFS_MOUNT}"

mknod -m 666 "${R}/dev/null"         c 1 3  2>/dev/null || true
mknod -m 600 "${R}/dev/kmsg"         c 1 11 2>/dev/null || true
mknod -m 666 "${R}/dev/random"       c 1 8  2>/dev/null || true
mknod -m 666 "${R}/dev/urandom"      c 1 9  2>/dev/null || true
mknod -m 660 "${R}/dev/loop-control" c 10 237 2>/dev/null || true
[ -f "${R}/proc/cmdline" ] && chmod 440 "${R}/proc/cmdline" || true

for SELINUX_PATH in \
    "${R}/system/lib64/libselinux.so" \
    "${R}/lib64/libselinux.so"; do
    [ -f "$SELINUX_PATH" ] && mount --bind /userdata/libselinux-stub.so "$SELINUX_PATH" 2>/dev/null || true
done

mount -t ext4 -o ro /dev/mapper/vendor  "${R}/vendor"  2>/dev/null || true

# /system/etc/prop.default does not actually exist on this ROM (checked live --
# only /system/build.prop and /vendor/build.prop exist), so the earlier prop.default
# bind-mount block below is silently skipped (its own "[ -f "$PROP_ORIG" ]" check is
# false) and never actually applied anything through it. ro.apex.updatable=true is
# set in /vendor/build.prop specifically; since it's the ONLY definition (confirmed
# via grep, not present in system/build.prop) it wins outright regardless of ro.*
# write-once semantics -- so we patch this file's line directly rather than relying
# on load-order tricks. See PROP_ORIG block below and the SYSTEMSERVERCLASSPATH/
# ApexManagerFlattenedApex comment there for why this property matters.
VENDOR_BUILD_PROP="${R}/vendor/build.prop"
if [ -f "$VENDOR_BUILD_PROP" ]; then
    VENDOR_BUILD_PROP_TMP="/run/halium-vendor-build.prop"
    sed 's/^ro\.apex\.updatable=true$/ro.apex.updatable=false/' "$VENDOR_BUILD_PROP" > "$VENDOR_BUILD_PROP_TMP" 2>/dev/null
    chmod 644 "$VENDOR_BUILD_PROP_TMP" 2>/dev/null
    mount --bind "$VENDOR_BUILD_PROP_TMP" "$VENDOR_BUILD_PROP" 2>/dev/null || true
    mount -o remount,ro,bind "$VENDOR_BUILD_PROP" 2>/dev/null || true
fi

# Halium vndservicemanager (built from patched Access.cpp - SELinux checks disabled)
mount --bind /userdata/vndservicemanager-halium "${R}/vendor/bin/vndservicemanager" 2>/dev/null || true
mount --bind /userdata/init-halium-nolimits "${R}/system/bin/init" 2>/dev/null || true
# SystemServiceRegistry.<clinit> (framework.jar/classes.dex) без try/catch падает
# NoClassDefFoundError на ПЕРВОМ APEX-only классе в статическом блоке
# (registerService(TETHERING_SERVICE, TetheringManager.class, ...), строка 403
# AOSP android-13.0.0_r1) -- верификация ВСЕГО класса рвётся, zygote крашится в
# цикле. Пропатчен байткодом (dexlib2, try/catch Ljava/lang/Throwable; вокруг
# этого блока) -- при недоступности TetheringManager просто продолжает
# регистрацию остальных сервисов вместо падения всего zygote.
mount --bind /userdata/framework-patched-tethering-fix.jar "${R}/system/framework/framework.jar" 2>/dev/null || true

# android.bluetooth.BluetoothActivityEnergyInfo/UidTraffic (small Parcelable data
# classes, no real Bluetooth stack behavior needed) -- BatteryStatsService in
# services.jar declares noteBluetoothControllerActivity(BluetoothActivityEnergyInfo)
# overriding IBatteryStats; ART hard-fails BatteryStatsService verification if
# that param type cannot resolve at all, crashing ActivityManagerService construction
# and thus all of system_server. Hand-compiled from packages/modules/Bluetooth source
# against our own framework.jar (no full Bluetooth mainline APEX needed).
: > "${R}/system/framework/framework-bluetooth-stub.jar" 2>/dev/null
mount --bind /userdata/framework-bluetooth-stub.jar "${R}/system/framework/framework-bluetooth-stub.jar" 2>/dev/null || true

# com.android.server.am.AppRestrictionController field-initializer for
# mRoleHolderChangedListener (android.app.role.OnRoleHoldersChangedListener, part of the
# same missing RoleManager mainline module) constructs an ExternalSyntheticLambda whose
# declared interface cannot resolve, hard-failing that lambda class link and crashing
# ActivityManagerService construction -- and thus all of system_server. Removed the 3
# dead instructions (NEW_INSTANCE/INVOKE_DIRECT/IPUT_OBJECT) via dexlib2.
mount --bind /userdata/services-patched.jar "${R}/system/framework/services.jar" 2>/dev/null || true

# libgui.so: SurfaceComposerClient::getCompositionPreference() called
# ComposerService::getComposerService()->getCompositionPreference(...) without a null
# check. Halium already stubs out the real SurfaceFlinger connection (connectLocked()
# never assigns mComposerService, see commented-out waitForService call in this same
# file) since Ubuntu Touch uses its own display server, not SurfaceFlinger -- so this
# call dereferences a null sp<> and segfaults. Hit via
# DisplayManagerService.<init> -> SurfaceControl.getCompositionColorSpaces(), crashing
# system_server with SIGSEGV right after ActivityManagerService successfully started.
# Added a null check (returns NO_INIT) plus a matching Java-side null check in
# SurfaceControl.getCompositionColorSpaces() for the null int[] this produces.
mount --bind /userdata/libgui-v7.so "${R}/system/lib64/libgui.so" 2>/dev/null || true

# fd_utils.cpp's FileDescriptorAllowlist::IsAllowed() only accepts APEX jar paths under
# /apex/, not /system/apex/ (where our APEX jars actually live since apexd doesn't activate
# them here) -- zygote aborts with "Not allowlisted" on fork trying to keep these FDs open.
# Patched IsAllowed() to also accept /system/apex/**/javalib/*.jar.
mount --bind /userdata/libandroid_runtime-v1.so "${R}/system/lib64/libandroid_runtime.so" 2>/dev/null || true






# firmware_mnt (sda23, vfat) содержит a660_zap.mdt/.b00-.b02 (реальный zap shader
# от Samsung!), но это ОТДЕЛЬНАЯ партиция от /dev/mapper/vendor и не монтируется
# автоматически внутрь contейнерного /vendor (наш Halium mount_all — фейковый).
mkdir -p "${R}/vendor/firmware_mnt" 2>/dev/null || true
mount -t vfat -o ro /dev/sda23 "${R}/vendor/firmware_mnt" 2>/dev/null || true
# wpss rev7 firmware (m526br, bootloader rev7) from TheMuppets vendor blob repo
for wf in wpss.b00 wpss.b01 wpss.b02 wpss.b03 wpss.b04 wpss.b05 wpss.b06 wpss.b07 wpss.mdt; do
    mount --bind "/userdata/wpss-rev7/${wf}" "${R}/vendor/firmware/${wf}" 2>/dev/null || true
done
mount -t ext4 -o ro /dev/mapper/product "${R}/product" 2>/dev/null || true

APEX_MOUNT="${R}/apex"
APEX_SRC="${R}/system/apex"
mount -t tmpfs android_apex "${APEX_MOUNT}" 2>/dev/null || true
for apex_name in com.android.runtime com.android.art com.android.i18n com.android.media com.android.wifi com.android.os.statsd com.android.sdkext com.android.adbd com.android.conscrypt com.android.extservices; do
    if [ -d "${APEX_SRC}/${apex_name}" ]; then
        mkdir -p "${APEX_MOUNT}/${apex_name}"
        mount -o bind "${APEX_SRC}/${apex_name}" "${APEX_MOUNT}/${apex_name}" 2>/dev/null || true
    fi
done

# SystemServiceRegistry.java:403 (Android 13) без try/catch делает
# registerService(TETHERING_SERVICE, TetheringManager.class, ...) -- если
# TetheringManager (framework-tethering.jar, APEX com.android.tethering) не
# резолвится через boot classloader, верификация ВСЕГО класса
# SystemServiceRegistry падает с NoClassDefFoundError на первом же
# APEX-классе (раньше wifi по порядку) -> zygote крашится в цикле.
# Подтверждено live-тестом: java.lang.ClassNotFoundException: android.net.TetheringManager.
# Монтируем javalib/ (framework-tethering.jar и т.д.) + apex_manifest.pb +
# lib/lib64 (нужны linkerconfig'у для генерации namespace "com_android_tethering" --
# без них linkerconfig падает с Aborted и namespace не создаётся вообще, что
# ломает JNI-инициализацию TetheringManager с "no namespace called
# com_android_tethering"). НЕ монтируем bin/ (нативные сервисы/демоны) и
# priv-app/ (TetheringNext.apk -- подозреваемая причина прошлой поломки ssh/netd
# на 68с, вероятно через авто-установку PackageManager'ом при старте
# system_server). service-connectivity.jar (в javalib/) сознательно НЕ
# добавляется в *CLASSPATH ниже, чтобы не запускать сам
# ConnectivityService/TetheringService -- нужна только резолвируемость класса.
if [ -d "${APEX_SRC}/com.android.tethering" ]; then
    mkdir -p "${APEX_MOUNT}/com.android.tethering/javalib" "${APEX_MOUNT}/com.android.tethering/lib" "${APEX_MOUNT}/com.android.tethering/lib64"
    mount -o bind "${APEX_SRC}/com.android.tethering/javalib" "${APEX_MOUNT}/com.android.tethering/javalib" 2>/dev/null || true
    [ -d "${APEX_SRC}/com.android.tethering/lib" ] && mount -o bind "${APEX_SRC}/com.android.tethering/lib" "${APEX_MOUNT}/com.android.tethering/lib" 2>/dev/null || true
    [ -d "${APEX_SRC}/com.android.tethering/lib64" ] && mount -o bind "${APEX_SRC}/com.android.tethering/lib64" "${APEX_MOUNT}/com.android.tethering/lib64" 2>/dev/null || true
    [ -f "${APEX_SRC}/com.android.tethering/apex_manifest.pb" ] && { : > "${APEX_MOUNT}/com.android.tethering/apex_manifest.pb"; mount -o bind "${APEX_SRC}/com.android.tethering/apex_manifest.pb" "${APEX_MOUNT}/com.android.tethering/apex_manifest.pb" 2>/dev/null || true; }
fi

# apexd никогда по-настоящему не запускается в этом проекте (вместо него —
# ручные bind mount'ы APEX выше), а именно apexd в реальном Android после
# ИСПРАВЛЕНО 2026-07-07: раньше VNDK бинд делался ПОСЛЕ linkerconfig, из
# предположения что VNDK крашит linkerconfig -- оказалось ложным (реальная
# причина краша в тесте была banальным отсутствием mkdir целевой директории,
# не связана с VNDK вообще). Без VNDK на момент вызова linkerconfig генерирует
# УПРОЩЁННЫЙ конфиг без под-неймспейсов на каждый APEX (только [system]/
# [vendor]/... без "com_android_art" и т.д.) -- это и было причиной
# "nativeloader: Error finding namespace of apex: no namespace called
# com_android_art" -> zygote падает при JNI_CreateJavaVM -> InitNativeMethods.
# Переносим VNDK bind ДО генерации apex-info-list.xml/вызова linkerconfig.
if [ -d "${APEX_SRC}/com.android.vndk.current" ]; then
    mkdir -p "${APEX_MOUNT}/com.android.vndk.current" "${APEX_MOUNT}/com.android.vndk.v33"
    mount -o bind "${APEX_SRC}/com.android.vndk.current" "${APEX_MOUNT}/com.android.vndk.current" 2>/dev/null || true
    mount -o bind "${APEX_SRC}/com.android.vndk.current" "${APEX_MOUNT}/com.android.vndk.v33" 2>/dev/null || true
fi
cat > "${APEX_MOUNT}/apex-info-list.xml" <<XMLEOF
<?xml version="1.0" encoding="utf-8"?>
<apex-info-list>
  <apex-info moduleName="com.android.runtime" modulePath="/system/apex/com.android.runtime" preinstalledModulePath="/system/apex/com.android.runtime" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="false"/>
  <apex-info moduleName="com.android.art" modulePath="/system/apex/com.android.art" preinstalledModulePath="/system/apex/com.android.art" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="true"/>
  <apex-info moduleName="com.android.i18n" modulePath="/system/apex/com.android.i18n" preinstalledModulePath="/system/apex/com.android.i18n" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="false"/>
  <apex-info moduleName="com.android.media" modulePath="/system/apex/com.android.media" preinstalledModulePath="/system/apex/com.android.media" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="false"/>
  <apex-info moduleName="com.android.wifi" modulePath="/system/apex/com.android.wifi" preinstalledModulePath="/system/apex/com.android.wifi" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="false"/>
  <apex-info moduleName="com.android.os.statsd" modulePath="/system/apex/com.android.os.statsd" preinstalledModulePath="/system/apex/com.android.os.statsd" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="false"/>
  <apex-info moduleName="com.android.sdkext" modulePath="/system/apex/com.android.sdkext" preinstalledModulePath="/system/apex/com.android.sdkext" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="false"/>
  <apex-info moduleName="com.android.adbd" modulePath="/system/apex/com.android.adbd" preinstalledModulePath="/system/apex/com.android.adbd" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="false"/>
  <apex-info moduleName="com.android.conscrypt" modulePath="/system/apex/com.android.conscrypt" preinstalledModulePath="/system/apex/com.android.conscrypt" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="false"/>
  <apex-info moduleName="com.android.extservices" modulePath="/system/apex/com.android.extservices" preinstalledModulePath="/system/apex/com.android.extservices" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="false"/>
  <apex-info moduleName="com.android.vndk.v33" modulePath="/system/apex/com.android.vndk.current" preinstalledModulePath="/system/apex/com.android.vndk.current" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="false"/>
  <apex-info moduleName="com.android.tethering" modulePath="/system/apex/com.android.tethering" preinstalledModulePath="/system/apex/com.android.tethering" versionCode="1" versionName="1" isFactory="true" isActive="true" provideSharedApexLibs="false"/>
</apex-info-list>
XMLEOF
ls -la "${APEX_MOUNT}/com.android.runtime/bin/linkerconfig" 2>&1
chroot "${R}" /apex/com.android.runtime/bin/linkerconfig --target /linkerconfig 2>&1
chmod 644 "${R}/linkerconfig/ld.config.txt" 2>/dev/null || true
rm -f "${APEX_MOUNT}/apex-info-list.xml"

mount -t tmpfs android_mnt          "${R}/mnt"          2>/dev/null || true
# mount.sh только что перекрыл /mnt пустым tmpfs, но хост УЖЕ монтировал сюда
# реальный persist (/dev/sda5) в /mnt/vendor/persist ДО этого — ADSP не видит
# реестр калибровки сенсоров (/mnt/vendor/persist/sensors/registry/registry)
# и падает с SNS_REG_TASK assert. Возвращаем persist поверх свежего tmpfs.
mkdir -p "${R}/mnt/vendor/persist" 2>/dev/null || true
mount --bind /var/lib/lxc/android/rootfs/mnt/vendor/persist "${R}/mnt/vendor/persist" 2>/dev/null || true
mount -t tmpfs android_linkerconfig "${R}/linkerconfig"  2>/dev/null || true

mkdir -p "${R}/metadata/apex/sessions" 2>/dev/null || true
mount -t tmpfs android_metadata "${R}/metadata" 2>/dev/null || true
mkdir -p "${R}/metadata/apex/sessions" 2>/dev/null || true

PROP_ORIG="${R}/system/etc/prop.default"
if [ -f "$PROP_ORIG" ]; then
    PROP_TMP="/run/halium-prop.default"
    cat "$PROP_ORIG" > "$PROP_TMP"
    # zygote64 exits(0) with zero Java-visible logging right after its background
    # mainline-module verification task finishes; strace shows no clone/fork ever
    # happened, just hundreds of mprotect(READ)/(READ|WRITE) toggles on an anon
    # page immediately before exit_group(0) -- the classic pattern of ART writing
    # out a JIT profile file (guarded by mprotect during the write) as part of
    # Runtime shutdown. -Xjitsaveprofilinginfo is already in the zygote command
    # line; try disabling profile saving/use via properties to see if that's what's
    # aborting/exiting the runtime silently (still unconfirmed root cause).
    # ro.apex.updatable=true (set in /vendor/build.prop) makes PackageManagerService
    # use ApexManagerImpl, which asks the real apexd (via Binder getActivePackages())
    # which APEX dirs to scan for priv-app/etc content. apexd only activates actual
    # .apex FILES (only com.android.apex.cts.shim.apex qualifies) -- everything else
    # here is a pre-extracted directory we bind-mount by hand, invisible to apexd's own
    # state, so PackageManagerService never sees framework-permission/extservices/etc
    # ("Missing required system package: android.ext.services"). ro.apex.updatable is
    # ro.* (write-once, first writer wins) and prop.default loads before vendor/build.prop,
    # so setting it false here forces ApexManagerFlattenedApex instead, which just globs
    # /apex/* directories directly -- no apexd/Binder involved, matches our architecture.
    printf "\nro.crypto.state=unsupported\nro.crypto.type=none\ndalvik.vm.usejitprofiles=false\nro.apex.updatable=false\n" >> "$PROP_TMP"
    chmod 644 "$PROP_TMP"
    mount -o bind "$PROP_TMP" "$PROP_ORIG" 2>/dev/null || true
fi

patch_rc() {
    SRC="$1"; shift
    TMP="/run/halium-rc-$(echo "$SRC" | tr "/" "-")"
    sed "$@" "$SRC" > "$TMP" 2>/dev/null && \
        chmod 644 "$TMP" && \
        mount --bind "$TMP" "$SRC" 2>/dev/null || true
}

# boringssl self-test: нестабильный (иногда падает, иногда нет), reboot_on_failure
# вызывает НАСТОЯЩИЙ trigger_shutdown() -> init внутри контейнера зацикленно
# перезапускается каждые ~2-3с. Убираем reboot_on_failure, чтобы при провале
# init просто логировал ошибку и шёл дальше (как и остальные патчи ниже).
BSSL_RC="${R}/vendor/etc/init/boringssl_self_test.rc"
[ -f "$BSSL_RC" ] && patch_rc "$BSSL_RC" "/reboot_on_failure/d"
BSSL_SYS_RC="${R}/system/etc/init/hw/init.rc"
# Также вырезаем "mount none /linkerconfig/bootstrap /linkerconfig bind rec" —
# иначе контейнерный init позже перемонтирует /linkerconfig обратно на
# минимальный bootstrap-конфиг, затирая тот полный ld.config.txt, который мы
# только что сгенерировали выше (см. комментарий про apexd/apex-info-list.xml).
# ДОБАВЛЕНО: apexd никогда не запускается, поэтому APEX-предоставленный rc-файл
# (com.android.sdkext/etc/derive_classpath.rc), который ОПРЕДЕЛЯЕТ сервис
# "derive_classpath", никогда не парсится init'ом -- реальный apexd обычно сам
# указывает init'у дополнительно сканировать etc/ каждого активного APEX.
# Из-за этого "exec_start derive_classpath" (уже есть в init.rc, on post-fs-
# data) молча падает: сервис с таким именем не зарегистрирован. Без этого
# BOOTCLASSPATH никогда не получает jar'ы APEX-модулей (framework-wifi.jar и
# т.д.) -> zygote падает с NoClassDefFoundError на WifiInfo/
# SystemServiceRegistry в бесконечном цикле. Вписываем определение сервиса
# прямо в начало init.rc, чтобы exec_start нашёл его.
if [ -f "$BSSL_SYS_RC" ]; then
    TMP_INIT_RC="/run/halium-rc-init-full"
    TMP_INIT_FILTERED="/run/halium-rc-init-filtered"
    EXPORT_BLOCK="/run/halium-rc-init-export-block"
    printf '    export BOOTCLASSPATH /apex/com.android.art/javalib/core-oj.jar:/apex/com.android.art/javalib/core-libart.jar:/apex/com.android.art/javalib/okhttp.jar:/apex/com.android.art/javalib/bouncycastle.jar:/apex/com.android.art/javalib/apache-xml.jar:/system/framework/framework.jar:/system/framework/framework-graphics.jar:/system/framework/ext.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/ims-common.jar:/apex/com.android.i18n/javalib/core-icu4j.jar:/apex/com.android.conscrypt/javalib/conscrypt.jar:/apex/com.android.media/javalib/updatable-media.jar:/apex/com.android.os.statsd/javalib/framework-statsd.jar:/apex/com.android.sdkext/javalib/framework-sdkextensions.jar:/apex/com.android.wifi/javalib/framework-wifi.jar:/apex/com.android.tethering/javalib/framework-connectivity.jar:/apex/com.android.tethering/javalib/framework-connectivity-t.jar:/apex/com.android.tethering/javalib/framework-tethering.jar:/system/framework/framework-bluetooth-stub.jar:/system/apex/com.android.permission/javalib/framework-permission.jar:/system/apex/com.android.permission/javalib/framework-permission-s.jar\n    export DEX2OATBOOTCLASSPATH /apex/com.android.art/javalib/core-oj.jar:/apex/com.android.art/javalib/core-libart.jar:/apex/com.android.art/javalib/okhttp.jar:/apex/com.android.art/javalib/bouncycastle.jar:/apex/com.android.art/javalib/apache-xml.jar:/system/framework/framework.jar:/system/framework/framework-graphics.jar:/system/framework/ext.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/ims-common.jar:/apex/com.android.i18n/javalib/core-icu4j.jar\n    export SYSTEMSERVERCLASSPATH /system/framework/com.android.location.provider.jar:/system/framework/services.jar:/system/framework/org.lineageos.platform.jar:/apex/com.android.art/javalib/service-art.jar:/apex/com.android.media/javalib/service-media-s.jar:/system/apex/com.android.permission/javalib/service-permission.jar\n    export STANDALONE_SYSTEMSERVER_JARS /apex/com.android.os.statsd/javalib/service-statsd.jar:/apex/com.android.wifi/javalib/service-wifi.jar\n' > "$EXPORT_BLOCK" 2>/dev/null
    sed -e "/reboot_on_failure/d" -e "\#mount none /linkerconfig/bootstrap /linkerconfig bind rec#d" "$BSSL_SYS_RC" > "$TMP_INIT_FILTERED" 2>/dev/null
    # Реальный apexd/derive_classpath ТОЖЕ работает (подтверждено live: apexd.status=ready,
    # init.svc.derive_classpath=stopped) и в самом init.rc уже штатно есть
    # "exec_start derive_classpath" + "load_exports /data/system/environ/classpath"
    # (секция on init). Раньше наш export стоял В НАЧАЛЕ файла (on early-init) и
    # выполнялся ПЕРВЫМ -- а этот штатный load_exports идёт ПОЗЖЕ и молча
    # ПЕРЕЗАПИСЫВАЕТ его старым/неполным содержимым классpath-файла (он не видит
    # частично смонтированный com.android.tethering без apex_manifest.pb).
    # Подтверждено live-тестом (/proc/PID/environ реального zygote): наш export с
    # tethering/connectivity добавлялся в init.rc, но у живого zygote всё равно
    # был СТАРЫЙ BOOTCLASSPATH без них. Поэтому вставляем наш export СРАЗУ ПОСЛЕ
    # реальной строки load_exports -- чтобы наше значение выполнялось последним и
    # побеждало.
    LOAD_EXPORTS_LINE=$(grep -n "load_exports /data/system/environ/classpath" "$TMP_INIT_FILTERED" 2>/dev/null | head -1 | cut -d: -f1)
    {
        if [ -n "$LOAD_EXPORTS_LINE" ]; then
            sed -n "1,${LOAD_EXPORTS_LINE}p" "$TMP_INIT_FILTERED"
            cat "$EXPORT_BLOCK"
            NEXT_LINE=$((LOAD_EXPORTS_LINE + 1))
            sed -n "${NEXT_LINE},\$p" "$TMP_INIT_FILTERED"
        else
            printf 'on early-init\n'
            cat "$EXPORT_BLOCK"
            printf '\n'
            cat "$TMP_INIT_FILTERED"
        fi
    } > "$TMP_INIT_RC" 2>/dev/null
    chmod 644 "$TMP_INIT_RC" 2>/dev/null
    mount --bind "$TMP_INIT_RC" "$BSSL_SYS_RC" 2>/dev/null || true
fi

# /data/system/environ/classpath is ALSO read directly by some components
# (confirmed live: PackageManagerService/Settings still resolved an old/incomplete
# classpath from this file even after the init.rc-level "export BOOTCLASSPATH ..."
# above was fixed to win over the real derive_classpath's load_exports). The real
# derive_classpath service (apexd) regenerates this file at "on init" time on every
# boot, so a plain write gets clobbered -- bind-mount our version read-only instead,
# same technique as boot-framework.oat, so derive_classpath's write just no-ops.
if [ -f "$EXPORT_BLOCK" ]; then
    CLASSPATH_FILE="${R}/data/system/environ/classpath"
    CLASSPATH_TMP="/run/halium-rc-classpath-file"
    sed 's/^    //' "$EXPORT_BLOCK" > "$CLASSPATH_TMP" 2>/dev/null
    chmod 644 "$CLASSPATH_TMP" 2>/dev/null
    if [ -f "$CLASSPATH_FILE" ]; then
        mount --bind "$CLASSPATH_TMP" "$CLASSPATH_FILE" 2>/dev/null || true
        mount -o remount,ro,bind "$CLASSPATH_FILE" 2>/dev/null || true
    fi
fi

VOLD_RC="${R}/system/etc/init/vold.rc"
[ -f "$VOLD_RC" ] && patch_rc "$VOLD_RC" "/reboot_on_failure/d"

# init.zygote64_32.rc is patched ONCE here with everything it needs.
# IMPORTANT: patch_rc derives its temp filename purely from $SRC's path, so
# calling it twice for the SAME file uses the SAME /run/halium-rc-... temp
# file both times. The second call's "sed ... "$SRC" > "$TMP"" then reads
# from a path that's already bind-mounted onto that very $TMP file -- the
# shell's ">" truncates $TMP (== the bind-mount source) before sed even
# opens $SRC for reading, so sed reads an empty file and the service
# definition is silently wiped out entirely (confirmed live: zygote never
# started at all, /system/etc/init/hw/init.zygote64_32.rc was 0 bytes).
# Never call patch_rc twice on the same target -- always merge into one call.
#
# 1) framework.jar checksum changed (our TetheringManager/field-fix patch),
# so the prebuilt /system/framework/arm64/boot-framework.oat no longer
# matches it. zygote detects this, backgrounds a dex2oat recompile of the
# whole boot image, and (per AOSP's standard "regenerate boot image" flow)
# exits(0) itself so init can relaunch it once a fresh image is ready.
# init's OWN built-in health check (system/core/init/service.cpp, hardcoded
# ">4", never reset since sys.boot_completed never reaches 1) treats every
# one of those exits as a "crash" and after the 5th one nukes the whole
# zygote/netd/thermal process group -- long before dex2oat (compiling a
# 34MB framework.jar on this CPU) can finish. -Xnoimage-dex2oat tells ART to
# just skip the boot image entirely (interpreter/JIT only, slower cold
# start, no regenerate-and-restart cycle).
#
# 2) "onrestart restart netd" / "onrestart restart wificond" explicitly
# restart netd/wificond every time zygote restarts, IGNORING their "class
# disabled" (an explicit "restart X" bypasses class gating in Android
# init). netd crashes on its own (we never got it fully working), and after
# 4 crashes init's own updatable-component health check nukes the whole
# zygote process group with SIGKILL, restarting zygote, which re-triggers
# "onrestart restart netd" -- a self-sustaining kill loop. Confirmed live
# via dmesg: "process with updatable components 'netd' exited 4 times
# before boot completed" immediately followed by "Sending signal 9 to
# service 'zygote'". Drop those two onrestart lines too.
ZYGOTE64_32_RC="${R}/system/etc/init/hw/init.zygote64_32.rc"
[ -f "$ZYGOTE64_32_RC" ] && patch_rc "$ZYGOTE64_32_RC" \
    -e "s/-Xzygote /-Xzygote -Xnoimage-dex2oat /" \
    -e "/onrestart restart netd/d" \
    -e "/onrestart restart wificond/d"

# Prebuilt boot-framework.oat/.art/.vdex (and every boot image extension
# compiled AFTER framework.jar in BOOTCLASSPATH order: ext, framework-graphics,
# telephony-common, voip-common, ims-common, core-icu4j) embed the ORIGINAL
# framework.jar's dex checksum. Our patched framework.jar (TetheringManager/
# SystemServiceRegistry <clinit> try/catch fix) has a different checksum, so
# at boot ART logs "dex file checksum ... does not match ... external dex
# file framework.jar" and tries to recompile the extension -- which fails
# immediately because -Xnoimage-dex2oat (above) disables dex2oat entirely.
# The extension is then left in a broken "present but invalid" state, and
# ART's ClassLinker treats SystemServiceRegistry (and anything else that
# would have lived in that extension) as permanently unresolvable --
# "NoClassDefFoundError: Class not found using the boot class loader" on the
# FIRST preloadClasses() attempt, which preloadClasses() rethrows as a fatal
# Error, killing zygote before any fork ever happens. Confirmed live via
# -verbose:class logcat capture. Deleting the stale files outright (not just
# leaving a mismatch) makes ART see "no extension" instead of "invalid
# extension", which falls back to reading the dex directly -- no recompile
# attempted, no crash.
for f in boot-ext boot-framework-graphics boot-telephony-common \
         boot-voip-common boot-ims-common boot-core-icu4j; do
    rm -f "${R}/system/framework/arm64/${f}.oat" \
          "${R}/system/framework/arm64/${f}.art" \
          "${R}/system/framework/arm64/${f}.vdex"
done

# boot-framework.{art,vdex,oat} is different: instead of deleting it (which
# just made zygote hit the SAME "extension missing, dex2oat disabled" dead
# end as every other stale extension), we manually ran dex2oat64 offline
# (bypassing zygote's watchdog-limited background compile entirely, via
# nsenter from the host with real fd redirection -- Android's /system/bin/sh
# can't exec N<>file for fd>4, host bash can) against the CURRENT patched
# framework.jar, with --compiler-filter=verify (fast -- verification only,
# no AOT codegen) and --single-image covering the whole framework.jar+
# framework-graphics+ext+telephony-common+voip-common+ims-common+core-icu4j
# chain, matching the exact command zygote itself uses (captured live via
# ps/cmdline during a brief manual app_process64 probe). Confirmed live:
# with this file in place, zygote survived 45s (preloadClasses succeeded,
# SystemServiceRegistry resolved) instead of dying instantly -- but zygote
# ITSELF deleted the file again around the 45s mark (still trying to
# "regenerate" it, per the same background-recompile-then-restart flow
# -Xnoimage-dex2oat is supposed to head off) and reverted to instant-death.
# Bind-mounting our precompiled copy read-only prevents that: unlink() on a
# mountpoint fails with EBUSY and open() for write fails with EROFS, so
# zygote's regen attempt just no-ops instead of destroying the file.
mkdir -p "${R}/system/framework/arm64" 2>/dev/null
for f in boot-framework.art boot-framework.vdex boot-framework.oat; do
    SRC="/userdata/bootext/${f}"
    DST="${R}/system/framework/arm64/${f}"
    if [ -f "$SRC" ]; then
        : > "$DST" 2>/dev/null
        mount --bind "$SRC" "$DST" 2>/dev/null || true
        mount -o remount,ro,bind "$DST" 2>/dev/null || true
    fi
done

# apexd.rc/bpfloader.rc -- ранее никогда не патчились, потому что загрузка
# никогда не доходила так далеко (zygote крашился раньше). bpfloader.rc сам
# документирует: "failure will cause netd crashloop and thus system server
# crashloop... the only recovery is a full kernel reboot" -- ровно то, что мы
# наблюдаем сейчас (массовое sig9 всех сервисов, каскадящее в modem SSR).
APEXD_RC="${R}/system/etc/init/apexd.rc"
[ -f "$APEXD_RC" ] && patch_rc "$APEXD_RC" "/reboot_on_failure/d"
BPFLOADER_RC="${R}/system/etc/init/bpfloader.rc"
[ -f "$BPFLOADER_RC" ] && patch_rc "$BPFLOADER_RC" "/reboot_on_failure/d"

NETD_RC="${R}/system/etc/init/netd.rc"
# netd.rc САМ содержит "onrestart restart zygote" / "onrestart restart
# zygote_secondary" -- симметричная (обратная) связь тому, что мы уже убрали
# из init.zygote64_32.rc. netd падает сам (вероятно из-за dlopen() резолвера
# из отсутствующего com.android.resolv APEX -- см. комментарий в файле) и
# тянет zygote за собой через этот onrestart. Подтверждено live через dmesg:
# "Service 'netd' (pid N) exited with status 1" сразу перед "Sending signal 9
# to service 'zygote'".
[ -f "$NETD_RC" ] && patch_rc "$NETD_RC" \
    -e "/reboot_on_failure/d" \
    -e "/onrestart restart zygote/d" \
    -e "s/^\(\s*\)class main/\1class disabled/" \
    -e "s/^\(\s*\)critical$/\1# critical (disabled for Ubuntu Touch)/"

for RC in \
    "${R}/vendor/etc/init/android.hardware.health@2.1.rc" \
    "${R}/vendor/etc/init/android.hardware.health@2.0.rc" \
    "${R}/system/etc/init/healthd.rc"; do
    [ -f "$RC" ] && patch_rc "$RC" \
        -e "/reboot_on_failure/d" \
        -e "s/^\(\s*\)critical$/\1# critical (disabled)/" \
        -e "s/^\(\s*\)class main/\1class disabled/"
done

for RC in \
    "${R}/system/etc/init/zygote.rc" \
    "${R}/system/etc/init/zygote64.rc" \
    "${R}/system/etc/init/zygote_secondary.rc"; do
    [ -f "$RC" ] && patch_rc "$RC" \
        -e "/reboot_on_failure/d" \
        -e "s/^\(\s*\)critical$/\1# critical (disabled)/"
done

for RC in \
    "${R}/vendor/etc/init/android.hardware.wifi.supplicant-service.rc" \
    "${R}/vendor/etc/init/wpa_supplicant*.rc"; do
    [ -f "$RC" ] && patch_rc "$RC" \
        -e "/reboot_on_failure/d" \
        -e "s/^\(\s*\)class main/\1class disabled/"
done

for RC in \
    "${R}/system/etc/init/rild.rc" \
    "${R}/vendor/etc/init/rild*.rc"; do
    [ -f "$RC" ] && patch_rc "$RC" \
        -e "/reboot_on_failure/d" \
        -e "s/^\(\s*\)class main/\1class disabled/" \
        -e "s/^\(\s*\)critical$/\1# critical (disabled)/"
done

USB_STUB="/run/halium-stub-usb.rc"
printf "# USB gadget managed by Ubuntu Touch (usb-moded). Android disabled.\n" > "$USB_STUB"
chmod 644 "$USB_STUB"
for USB_RC in \
    "${R}/system/etc/init/hw/init.usb.rc" \
    "${R}/system/etc/init/hw/init.usb.configfs.rc" \
    "${R}/vendor/etc/init/hw/init.qcom.usb.rc" \
    "${R}/vendor/etc/init/android.hardware.usb@1.3-service-qti.rc"; do
    [ -f "$USB_RC" ] && mount --bind "$USB_STUB" "$USB_RC" 2>/dev/null || true
done


# Modem PIL boot fails with "Failed to locate modem.mdt(rc:-2)" -- the real
# modem.mdt/.b00-.bNN firmware files exist on their own dedicated
# /dev/block/by-name/modem partition (vfat, image/+verinfo/ dirs), but the
# container never mounts it anywhere the kernel's firmware search looks.
mkdir -p "${R}/vendor/firmware-modem" 2>/dev/null || true
mount -t vfat -o ro /dev/block/by-name/modem "${R}/vendor/firmware-modem" 2>/dev/null || true

# EFS/fsg fix: modem rmts_get_buffer needs /dev/block/sdf1 reachable as
# bootdevice/by-name/fsg inside the container.
mkdir -p "${R}/dev/block/platform/soc/1d84000.ufshc/by-name" 2>/dev/null || true
mkdir -p "${R}/dev/block/bootdevice" 2>/dev/null || true
if [ ! -e "${R}/dev/block/sdf1" ]; then
    for i in 1 2 3 4 5; do
        SDF1_MAJMIN="$(stat -c '%t:%T' /dev/block/sdf1 2>/dev/null)"
        [ -n "$SDF1_MAJMIN" ] && [ "$SDF1_MAJMIN" != "0:0" ] && break
        sleep 0.2
    done
    if [ -n "$SDF1_MAJMIN" ] && [ "$SDF1_MAJMIN" != "0:0" ]; then
        mknod -m 660 "${R}/dev/block/sdf1" b "0x${SDF1_MAJMIN%%:*}" "0x${SDF1_MAJMIN##*:}" 2>/dev/null || true
    fi
fi
ln -sf ../../sdf1 "${R}/dev/block/platform/soc/1d84000.ufshc/by-name/fsg" 2>/dev/null || true
ln -sfn platform/soc/1d84000.ufshc "${R}/dev/block/bootdevice" 2>/dev/null || true
exit 0
