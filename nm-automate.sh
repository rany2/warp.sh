#!/usr/bin/env bash

# Helper script to generate warp config and import
# it to NetworkManager (it will autoconnect by default)

./clean.sh
./warp.sh -4
nmcli connection delete warp
nmcli connection import file warp.conf type wireguard
nmcli connection modify warp ipv4.dns-priority -42
nmcli connection modify warp ipv6.dns-priority -42
nmcli connection modify warp connection.autoconnect yes
