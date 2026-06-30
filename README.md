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

## Status

| Feature | Status |
|---|---|
| Boot (Ubuntu Touch) | ✅ Boots |
| USB gadget (NCM) | 🔧 In progress |
| SSH / ADB over USB | 🔧 In progress |
| LXC Android container | ✅ Starts |
| Display (Lomiri) | ❌ Not yet |
| Wi-Fi | ❌ Not yet |
| Calls / SMS | ❌ Not yet |
| Camera | ❌ Not yet |

## Key kernel notes

- `CONFIG_USB_CONFIGFS_RNDIS` is **not set** in Samsung's kernel — RNDIS is unavailable
- `CONFIG_USB_F_NCM=y` and `CONFIG_USB_CONFIGFS_NCM=y` — **NCM is available** (used instead of RNDIS)
- USB controller: `a600000.dwc3`

## Repo structure

```
overlay/system/              ← copied to /data/system-data/ on device
  etc/
    systemd/system/          ← custom systemd units and drop-ins
    default/usb-moded.d/     ← usb-moded device config
  var/lib/usb-moded/         ← usb-moded persistent state

scripts/                     ← scripts deployed to /userdata/ on device
  mount-patched-v3.sh        ← Android LXC mount hook (main patch)
  usb-gadget-preconfigure.sh ← USB gadget cleanup before usb-moded
  usb-gadget-reset.sh        ← early-boot USB gadget reset
  lxc-mount-cleanup.sh       ← LXC bind-mount cleanup on stop
```

## Installation

See [Installation.md](Installation.md).

## Build

See the [Halium porting guide](https://docs.halium.org/en/latest/porting/index.html).
Kernel source: `kernel/samsung/sm7325`

## Contributing

This is a personal porting effort. PRs and issues welcome.
