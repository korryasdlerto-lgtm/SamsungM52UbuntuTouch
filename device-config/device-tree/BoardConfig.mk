DEVICE_PATH := device/samsung/m52xq

# Required for Halium: allows build to skip missing LineageOS extras
# (vim, nano, ssh, ntfs-3g, webview, etc.) not needed for Ubuntu Touch
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_MISSING_REQUIRED_MODULES := true

# Halium: use flat APEX (avoids APEX31/APEX33 LTO __get_tls link error)
OVERRIDE_TARGET_FLATTEN_APEX := true

include device/samsung/sm7325-common/BoardConfigCommon.mk

# Kernel
TARGET_KERNEL_SOURCE         := kernel/samsung/sm7325
TARGET_KERNEL_CONFIG        := vendor/lineage-m52xq_defconfig
BOARD_NAME                  := SRPUF17B001

# Kernel modules
BOARD_VENDOR_KERNEL_MODULES_LOAD := $(strip $(shell cat $(DEVICE_PATH)/modules.load))

# Recovery
TARGET_BOARD_INFO_FILE := $(DEVICE_PATH)/board-info.txt

# Display
TARGET_SCREEN_DENSITY := 420
TARGET_ADDITIONAL_GRALLOC_10_USAGE_BITS := 0x2000U

# Fingerprint
TARGET_SEC_FP_HAS_FINGERPRINT_GESTURES := true

# OTA assert
TARGET_OTA_ASSERT_DEVICE := m52xq

# Security patch
VENDOR_SECURITY_PATCH := 2023-05-01

# Properties
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop
TARGET_FORCE_PREBUILT_KERNEL := true
TARGET_PREBUILT_KERNEL   := $(DEVICE_PATH)/kernel-prebuilt
BOARD_KERNEL_IMAGE_NAME := Image
BOARD_KERNEL_CMDLINE := console=ttyMSM0,115200n8 earlycon=msm_geni_serial,0x04c8c000 androidboot.selinux=permissive androidboot.hardware=qcom loop.max_part=7 init=/init panic_on_warn=0 rootwait firmware_class.path=/sbin subsys_restart.enable_ramdump=0


# === HALIUM CONFIGURATION FROM FAIRPHONE 5 TEMPLATE ===
TARGET_HALIUM := true
BOARD_USES_HALIUM := true
BOARD_USES_HALIUM_RAMDISK := true
TARGET_RAMDISK_FSTYPE := lz4

BOARD_USES_RECOVERY_AS_BOOT := false
TARGET_NO_RECOVERY := true
BOARD_BOOT_HEADER_VERSION := 3
BOARD_MKBOOTIMG_ARGS += --header_version 3

BOARD_AVB_ENABLE := true
BOARD_AVB_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_BOOT_ADD_HASH_FOOTER_ARGS := --algorithm SHA256_RSA2048 --flags 3 --key external/avb/test/data/testkey_rsa2048.pem
# Переопределение системного init на Linux-линковщик Halium
# TARGET_INIT_VENDOR_LIB := libinit_halium

# Halium: disable custom sepolicy (incompatible with Android 12 checkpolicy)
BOARD_VENDOR_SEPOLICY_DIRS :=
BOARD_SEPOLICY_DIRS :=
BOARD_ODM_SEPOLICY_DIRS :=
SELINUX_IGNORE_NEVERALLOWS := true

# Halium: skip hiddenapi validation (no Java framework in Ubuntu Touch container)
UNSAFE_DISABLE_HIDDENAPI_FLAGS := true
SOONG_ALLOW_MISSING_DEPENDENCIES := true

# sm7325-common sets RESERVED_SIZE=3GB; clear it so we can set exact SIZE instead
BOARD_SYSTEMIMAGE_PARTITION_RESERVED_SIZE :=
# Exact size from LpMetadata: 8367856 sectors × 512 = 4284342272 bytes (1045982 4K-blocks)
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 4284342272
