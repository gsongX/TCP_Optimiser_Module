#!/system/bin/sh

MODPATH="${0%/*}"
LOGFILE="$MODPATH/service.log"
FLAGFILE="/dev/.tcp_module_log_cleared"
MAX_LOG_LINES=200
DEBOUNCE_TIME=10

# Clear log on first run after boot
if [ ! -f "$FLAGFILE" ]; then
    rm -f "$LOGFILE" >/dev/null 2>&1
    touch "$FLAGFILE" >/dev/null 2>&1
fi

# On startup, reset description to default
if [ -f "$MODPATH/module.prop" ]; then
    default_desc="TCP Optimisations & update tcp_cong_algo based on interface"
    sed -i '/^description=/d' "$MODPATH/module.prop" && echo "description=$default_desc" >> "$MODPATH/module.prop"
fi

log_print() {
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $1" >> "$LOGFILE"

    line_count=$(wc -l < "$LOGFILE" 2>/dev/null | awk '{print $1}')
    if [ "$line_count" -gt "$MAX_LOG_LINES" ]; then
        tail -n "$((MAX_LOG_LINES / 2))" "$LOGFILE" > "${LOGFILE}.tmp"
        mv "${LOGFILE}.tmp" "$LOGFILE"
    fi
}

# Run commands as root using su -c
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        sh -c "$1"
    else
        su -c "$1"
    fi
}

update_description() {
    local iface="$1"
    local algo="$2"
    local icon="🌐"

    case "$iface" in
        wlan) icon="🛜" ;;
        mobile) icon="📶" ;;
    esac

    local desc="TCP Optimisations & update tcp_cong_algo based on interface | iface: $iface $icon | algo: $algo"
    run_as_root "sed -i '/^description=/d' \"$MODPATH/module.prop\" && echo \"description=$desc\" >> \"$MODPATH/module.prop\""
}

kill_tcp_connections() {
    if [ -f "$MODPATH/kill_connections" ]; then
        log_print "Killing all TCP connections (IPv4 and IPv6) due to congestion change"
        
        # Kill all IPv4 connections (destination 0.0.0.0/0)
        run_as_root "ss -K dst 0.0.0.0/0"  # Kill all IPv4 connections
        
        # Kill all IPv6 connections (destination ::/0)
        run_as_root "ss -K dst ::/0"  # Kill all IPv6 connections
    fi
}

set_congestion() {
    local algo="$1"
    local mode="$2"
    if grep -qw "$algo" /proc/sys/net/ipv4/tcp_available_congestion_control; then
        run_as_root "echo \"$algo\" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null"
        log_print "Applied congestion control: $algo ($mode)"
        kill_tcp_connections
        update_description "$mode" "$algo"
    else
        log_print "Unavailable algorithm: $algo"
    fi
}


get_active_iface() {
    iface=$(ip route get 192.0.2.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
    echo "$iface"
}

last_mode=""
change_time=0

while true; do
    iface=$(get_active_iface)

    new_mode="none"
    case "$iface" in
        wlan*) new_mode="wifi" ;;
        rmnet_data*) new_mode="mobile" ;;
        *) new_mode="none" ;;
    esac

    current_time=$(date +%s)

    if [ "$new_mode" != "$last_mode" ]; then
        if [ "$((current_time - change_time))" -ge "$DEBOUNCE_TIME" ]; then
            applied=0
            if [ "$new_mode" = "wifi" ]; then
                for algo in bbr reno cubic; do
                    if [ -f "$MODPATH/wlan_$algo" ]; then
                        set_congestion "$algo" "$new_mode"
                        applied=1
                        break
                    fi
                done
                [ "$applied" -eq 0 ] && set_congestion cubic "$new_mode"
            elif [ "$new_mode" = "mobile" ]; then
                for algo in bbr reno cubic; do
                    if [ -f "$MODPATH/rmnet_data_$algo" ]; then
                        set_congestion "$algo" "$new_mode"
                        applied=1
                        break
                    fi
                done
                [ "$applied" -eq 0 ] && set_congestion cubic "$new_mode"
            fi
            last_mode="$new_mode"
            change_time="$current_time"
        fi
    fi

    sleep 5
done
