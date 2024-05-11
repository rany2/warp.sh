#!/bin/sh

# Android Wireguard Helper script
# For use with the official Wireguard app

./warp.sh "$@" | grep -Ev '^(#|$)' | tr -d ' ' | qrencode -t ansiutf8
