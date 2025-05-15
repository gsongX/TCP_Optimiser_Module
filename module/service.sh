#!/system/bin/sh

MODPATH="${0%/*}"
DEBOUNCE_TIME=10

. $MODPATH/utils.sh # Load utils

# Get the list of available congestion control algorithms
congestion_algorithms=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control)

# On startup, reset description to default
if [ -f "$MODPATH/module.prop" ]; then
    default_desc="TCP Optimisations & update tcp_cong_algo based on interface"
    sed -i '/^description=/d' "$MODPATH/module.prop" && echo "description=$default_desc" >> "$MODPATH/module.prop"
fi

update_description() {
    local iface="$1"
    local algo="$2"
    local icon="⁉️"

    case "$iface" in
        Wi-Fi) icon="🛜" ;;
        Cellular) icon="📶" ;;
    esac

    local desc="TCP Optimisations & update tcp_cong_algo based on interface | iface: $iface $icon | algo: $algo"
    sed -i '/^description=/d' "$MODPATH/module.prop" && echo "description=$desc" >> "$MODPATH/module.prop"
}

kill_tcp_connections() {
    if [ -f "$MODPATH/kill_connections" ]; then
        log_print "Killing all TCP connections (IPv4 and IPv6) due to congestion change"
        
        # Kill all connections
        ss -K
    fi
}

set_max_initcwnd_initrwnd() {
    local active_iface="$1"
    if [ -f "$MODPATH/initcwnd_initrwnd" ]; then
        maxBufferSize=$(cat /proc/sys/net/ipv4/tcp_rmem | awk '{print $3}')
        mtu=$(ip link show "$active_iface" | awk '/mtu/ {print $NF}')
        mtu=$((mtu - 40))
        maxInitrwndValue=$((maxBufferSize / mtu))
        local applied
        applied=0

        while IFS= read -r line; do
            run_as_su "/system/bin/ip route change $line initcwnd 10 initrwnd $maxInitrwndValue"
            if [ $? -eq 0 ]; then
                 applied=1
            fi
        done <<EOF
$(run_as_su "/system/bin/ip route show | grep \"dev $active_iface\"")
EOF

        if [ "$applied" -eq 1 ]; then
            log_print "Setting initcwnd = 10; initrwnd = $maxInitrwndValue!"
        fi
    fi
}

set_congestion() {
    local algo="$1"
    local mode="$2"
    if echo "$congestion_algorithms" | grep -qw "$algo"; then
        echo "$algo" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
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
        wlan*) new_mode="Wi-Fi" ;;
        rmnet*) new_mode="Cellular" ;;
        *) new_mode="none" ;;
    esac

    current_time=$(date +%s)

    if [ "$new_mode" != "$last_mode" ] || [ -f "$MODPATH/force_apply" ]; then
        if [ "$((current_time - change_time))" -ge "$DEBOUNCE_TIME" ]; then
            applied=0
            if [ "$new_mode" = "Wi-Fi" ]; then
                for algo in $congestion_algorithms; do
                    if [ -f "$MODPATH/wlan_$algo" ]; then
                        set_congestion "$algo" "$new_mode"
                        set_max_initcwnd_initrwnd "$iface"
                        applied=1
                        break
                    fi
                done
                [ "$applied" -eq 0 ] && set_congestion cubic "$new_mode" && set_max_initcwnd_initrwnd "$iface"
            elif [ "$new_mode" = "Cellular" ]; then
                for algo in $congestion_algorithms; do
                    if [ -f "$MODPATH/rmnet_data_$algo" ]; then
                        set_congestion "$algo" "$new_mode"
                        set_max_initcwnd_initrwnd "$iface"
                        applied=1
                        break
                    fi
                done
                [ "$applied" -eq 0 ] && set_congestion cubic "$new_mode" && set_max_initcwnd_initrwnd "$iface"
            fi
            last_mode="$new_mode"
            change_time="$current_time"
			rm -f "$MODPATH/force_apply"
        fi
    fi

    sleep 5
done
