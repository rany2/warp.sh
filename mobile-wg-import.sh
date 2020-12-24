#!/usr/bin/env bash

# Android Wireguard Helper script
# For use with the offical Wireguard app

./clean.sh
./warp.sh -4
qrencode -t ansiutf8 < warp.conf
