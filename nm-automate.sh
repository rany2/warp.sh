#!/bin/sh

# Helper script to generate warp config and import
# it to NetworkManager (it will autoconnect by default)

echo "* Generating Cloudflare WARP config to warp.conf"
./warp.sh "$@" > warp.conf
echo "* Removing old WARP config from NetworkManager"
nmcli connection delete warp
echo "* Importing new WARP config to NetworkManager"
sleep 1  # to give NetworkManager time to down old WARP if
nmcli connection import file warp.conf type wireguard
echo "* Modifying DNS priority settings for WARP to prevent DNS leaks"
nmcli connection modify warp ipv4.dns-priority -42
nmcli connection modify warp ipv6.dns-priority -42
echo "* Starting WARP at startup, \`nmcli connection modify warp connection.autoconnect no\" to undo"
nmcli connection modify warp connection.autoconnect yes
echo "* WARP is enabled"
nmcli connection up warp
