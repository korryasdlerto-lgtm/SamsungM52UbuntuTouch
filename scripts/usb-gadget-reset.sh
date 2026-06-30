#!/bin/sh
# Runs early in basic.target (usb-gadget-reset.service).
# At this point g1 usually does not exist yet - that is expected.
# The real cleanup happens in usb-gadget-preconfigure.sh (ExecStartPre of usb-moded).
# Logs: /userdata/usb-gadget-reset.log

G=/sys/kernel/config/usb_gadget/g1
LOG=/userdata/usb-gadget-reset.log
echo "$(date): starting usb-gadget-reset" >> "$LOG" 2>/dev/null

[ -d "$G" ] || { echo "$(date): g1 not found, exit" >> "$LOG" 2>/dev/null; exit 0; }

echo "$(date): g1 found, UDC=$(cat $G/UDC 2>/dev/null)" >> "$LOG" 2>/dev/null

echo '' > "$G/UDC" 2>/dev/null && \
    echo "$(date): UDC unbound" >> "$LOG" 2>/dev/null || \
    echo "$(date): UDC unbind failed" >> "$LOG" 2>/dev/null

echo "$(date): configs: $(ls $G/configs/ 2>/dev/null)" >> "$LOG" 2>/dev/null
echo "$(date): functions: $(ls $G/functions/ 2>/dev/null)" >> "$LOG" 2>/dev/null
echo "$(date): done" >> "$LOG" 2>/dev/null
exit 0
