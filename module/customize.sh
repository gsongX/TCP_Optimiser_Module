#!/system/bin/sh

ui_print "- Starting module customization..."

# Detect congestion algorithm
ui_print "- Checking TCP congestion algorithm..."
if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
    CONG="bbr"
    ui_print "- Found BBR!"
else
    CONG="cubic"
    ui_print "- BBR not found. Going with Cubic!"
fi

MODULE_NAME=$(basename "$MODPATH")
MODULE_PATH="/data/adb/modules/$MODULE_NAME"

# Check both live and update folders
check_exists_anywhere() {
    local prefix="$1"

    # Check in current path
    if ls "$MODPATH"/${prefix}_* >/dev/null 2>&1; then
        return 0
    fi
    
    # Check in Module main path
    if ls "$MODULE_PATH"/${prefix}_* >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

create_file_if_needed() {
    local prefix="$1"
    local suffix="$2"
    local target="$MODPATH/${prefix}_${suffix}"

    if check_exists_anywhere "$prefix"; then
        ui_print "- Skipping $target: another ${prefix}_* file exists."
        return
    fi

    if [ ! -f "$target" ]; then
        touch "$target"
        ui_print "- Created: $target"
    else
        ui_print "- Skipped: $target already exists"
    fi
}

# Create wlan_* based on BBR availability
if [ "$CONG" = "bbr" ]; then
    create_file_if_needed "wlan" "bbr"
else
    create_file_if_needed "wlan" "cubic"
fi

# Always create rmnet_data_cubic unless another exists
create_file_if_needed "rmnet_data" "cubic"
