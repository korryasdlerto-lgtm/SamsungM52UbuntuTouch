#!/bin/sh
G=/sys/kernel/config/usb_gadget/g1
LOG=/userdata/usb-moded-wrapper.log

log() {
    echo "$(date '+%H:%M:%S') $*" >> "$LOG" 2>/dev/null
    echo "<6>usb-moded-wrapper: $*" > /dev/kmsg 2>/dev/null
}

log "=== wrapper START ==="

# QCom msm-dwc3: force peripheral mode
if [ -d /sys/bus/platform/drivers/msm-dwc3 ]; then
    for dev in /sys/bus/platform/drivers/msm-dwc3/*/; do
        if [ -f "${dev}mode" ]; then
            log "dwc3 $(basename $dev): mode=$(cat ${dev}mode 2>/dev/null) -> peripheral"
            echo peripheral > "${dev}mode" 2>/dev/null
        fi
    done
    sleep 1
fi

if [ -d "$G" ]; then
    log "g1 exists, UDC=[$(cat $G/UDC 2>/dev/null)]"
    echo '' > "$G/UDC" 2>/dev/null || true
    i=0
    while [ "$(cat $G/UDC 2>/dev/null)" != "" ] && [ $i -lt 10 ]; do
        sleep 1; i=$((i+1))
    done
    log "UDC after unbind: [$(cat $G/UDC 2>/dev/null)] waited=${i}s"
    if [ -d "$G/configs/c.1" ]; then
        for lnk in "$G/configs/c.1/"*; do
            [ -L "$lnk" ] && rm -f "$lnk" 2>/dev/null && log "rm symlink: $lnk"
        done
    fi
    if [ -d "$G/functions" ]; then
        for f in "$G/functions/"*/; do
            [ -d "$f" ] && rmdir "$f" 2>/dev/null && log "rmdir func: $f"
        done
    fi
else
    log "g1 not found - fresh start"
fi

log "UDC list: $(ls /sys/class/udc 2>/dev/null)"
log "calling configurator"

exec /usr/libexec/ubports-usb-moded-configurator
