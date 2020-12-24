#!/usr/bin/env bash

./clean.sh
./warp.sh -4
nmcli connection delete warp
nmcli connection import file warp.conf type wireguard
