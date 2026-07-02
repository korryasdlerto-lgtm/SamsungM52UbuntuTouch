#!/bin/sh
G=/sys/kernel/config/usb_gadget/g1
LOG=/userdata/usb-moded-bypass.log
IFACE=rndis0
IP=10.15.19.82
UDC_NAME=a600000.dwc3

log() { echo "$(date +%H:%M:%S) $*" >> $LOG; }
log "=== bypass v2 ==="

# configurator (ExecStartPre) already did:
#   mkdir -p g1 g1/strings/0x409 g1/configs/c.1 g1/configs/c.1/strings/0x409
# but with RNDIS_FUNCTION/RNDIS_IFNAME hardcoded it skipped creating the
# actual function - that was usb_moded's job. We do it ourselves now.

mkdir -p $G/functions/rndis.usb0
if [ ! -e $G/configs/c.1/rndis.usb0 ]; then
    ln -s $G/functions/rndis.usb0 $G/configs/c.1/rndis.usb0
fi
log "rndis.usb0 function created+linked"

echo "$IFACE" > $G/functions/rndis.usb0/ifname 2>>$LOG
log "ifname set to $IFACE ($(cat $G/functions/rndis.usb0/ifname 2>/dev/null))"

echo 0x1209 > $G/idVendor
echo 0x0004 > $G/idProduct
log "idVendor=1209 idProduct=0004"

echo "$UDC_NAME" > $G/UDC
if [ $? -ne 0 ]; then
    log "ERROR: UDC bind failed"
    ls -la $G/functions $G/configs/c.1 >> $LOG 2>&1
    sleep infinity
fi
log "UDC connected"

# ifname write pre-bind doesn't always take; ask the kernel what it
# actually named the netdev now that the gadget is bound.
sleep 0.2
ACTUAL_IFACE="$(cat $G/functions/rndis.usb0/ifname 2>/dev/null)"
if [ -z "$ACTUAL_IFACE" ]; then
    ACTUAL_IFACE="$IFACE"
fi
log "actual ifname: $ACTUAL_IFACE"

# Wait up to 6s for the interface
j=0
while [ $j -lt 60 ]; do
    ip link show "$ACTUAL_IFACE" > /dev/null 2>&1 && break
    sleep 0.1
    j=$((j+1))
done

if ! ip link show "$ACTUAL_IFACE" > /dev/null 2>&1; then
    log "ERROR: $ACTUAL_IFACE not found after 6s"
    ip link >> $LOG 2>&1
    sleep infinity
fi
IFACE="$ACTUAL_IFACE"
log "$IFACE appeared (after ${j}00ms)"

ip link set "$IFACE" up
ip addr flush dev "$IFACE" 2>/dev/null
ip addr add ${IP}/24 dev "$IFACE"
log "IP ${IP}/24 on $IFACE — ready"

sleep 0.3

mkdir -p /run/sshd
chmod 0755 /run/sshd
log "/run/sshd ensured"

log "Starting sshd on ${IP}:8022"
/usr/sbin/sshd -t -o PasswordAuthentication=yes -o PermitEmptyPasswords=yes \
    -o PermitRootLogin=no -o ListenAddress=${IP}:8022 >> $LOG 2>&1
log "sshd -t (config test) exit code: $?"

exec /usr/sbin/sshd -D -e \
    -o PasswordAuthentication=yes \
    -o PermitEmptyPasswords=yes \
    -o PermitRootLogin=no \
    -o ListenAddress=${IP}:8022 >> $LOG 2>&1
