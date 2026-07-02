#!/bin/sh
# Watches dmesg for the "Restarting subcontext" tight-loop pattern (Android
# init spinning on setexeccon failure - not killable via a normal process
# kill, since it's PID 1's own internal retry, not a separate process).
# On detection, force-stops the whole LXC container immediately.
LOG=/userdata/gmu-watchdog.log
COUNT=0
LAST_RESET=$(date +%s)

echo "$(date '+%H:%M:%S') watchdog started" >> "$LOG"

dmesg -w 2>/dev/null | while read -r line; do
    case "$line" in
        *"Restarting subcontext"*)
            NOW=$(date +%s)
            if [ $((NOW - LAST_RESET)) -gt 3 ]; then
                COUNT=0
                LAST_RESET=$NOW
            fi
            COUNT=$((COUNT + 1))
            if [ "$COUNT" -ge 60 ]; then
                echo "$(date '+%H:%M:%S') LOOP DETECTED ($COUNT in <2s) - force-stopping container" >> "$LOG"
                lxc-stop -n android -k >> "$LOG" 2>&1
                echo "$(date '+%H:%M:%S') container stopped" >> "$LOG"
                COUNT=0
            fi
            ;;
    esac
done
