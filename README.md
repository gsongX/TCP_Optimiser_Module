# TCP_Optimiser_Module
A Magisk/KernelSU module to change tcp congestion algorithm based on current active internet type and some network enhancements.

# Why?
In certain kernel, TCP Congestion Algorithm BBR might be enabled. Or you want to enable certain algorithm or settings based on what interface you are using. I observed that in my kernel, when i use BBR with WiFi I get 50-60 Mbps more upload speed compared to cubic, but BBR gives bad upload speed in cellular. So I designed this module to switch based on active internet facing interface.

# How to use
1. Install the module.
2. It creates 2 files `wlan_{algo}` and `rmnet_data_{algo}` in module folder.
3. Reboot device.

## Note:
1. Default algorithm is **cubic** for **cellular**.
2. Default algorithm is **brr** if exists for **WiFi**. Else **cubic**.
3. You can change algorithm by just renaming the file in same format. Eg: If you want to change WiFi TCP congestion algorithm to **reno**, rename `wlan_{algo}` file to `wlan_reno`.
4. There is an option to kill current tcp connections during algorithm change. This might stop downloads, uploads or other ongoing connections. So apps affected might need to be restarted. To enable create a file named `kill_connections` in module folder. This is disabled by default.
5. Algorithm is applied only if present in kernel.
