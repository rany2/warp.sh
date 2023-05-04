#!/bin/sh

# Android Wireguard Helper script
# For use with the official Wireguard app

./warp.sh "$@" | qrencode -t ansiutf8
