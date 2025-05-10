#!/system/bin/sh

MODPATH="${0%/*}"

get_active_iface() {
    iface=$(ip route get 192.0.2.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
    echo "$iface"
}

iface=$(get_active_iface)

new_mode="none"
case "$iface" in
    wlan*) new_mode="Wi-Fi" ;;
    rmnet_data*) new_mode="Cellular" ;;
    *) new_mode="none" ;;
esac

if [ "$new_mode" != "none" ]; then
    echo "[+] Running Speed Test"
    echo "[+] Internet Type: $new_mode"
    echo "[+] Run 1: "
    ${MODPATH}/bin/speedtest
    echo ""
    echo "[+] Run 2: "
    ${MODPATH}/bin/speedtest
    echo ""
    echo "[+] Run 3: "
    ${MODPATH}/bin/speedtest
else
    echo "[-] No Active Internet Connection found!"
fi
