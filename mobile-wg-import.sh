#!/bin/sh

# Android Wireguard Helper script
# For use with the offical Wireguard app

./clean.sh
./warp.sh
qrencode -t ansiutf8 < warp.conf
