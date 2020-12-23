#!/usr/bin/env bash

set -eu

prefix="https://api.cloudflareclient.com/v0a977"

show_help() {
	echo ""
	echo -e "Usage\t$0 [options]"
	echo -e "\t-4\tuse ipv4 for wireguard endpoint and curl"
	echo -e "\t-6\tuse ipv6 for wireguard endpoint and curl"
	echo -e "\t-a\tuse DNS hostname for wireguard (overrides -4 or -6 for wireguard but keeps option for curl)"
	echo -e ""
}

curlopts=""
wgoverride=0
wgproto=0
while getopts "h?46a" opt; do
	case "$opt" in
		h|\?)
			show_help
			exit 0
		;;
		4)
			curlopts+=" -4"
			wgproto=4
		;;
		6)
			curlopts+=" -6"
			wgproto=6
		;;
		a)
			wgoverride=1
		;;
	esac
done

if [ -f "warp.source" ];then
	source "warp.source"
	reg="$(curl $curlopts --compressed -s \
		-H 'User-Agent: okhttp/3.12.1' \
		-H "Authorization: Bearer ${auth[1]}" \
		-H 'Content-Type: application/json' \
		"${prefix}/reg/${auth[0]}")"
else
	priv="$(wg genkey)"
	publ="$(printf '%s' "$priv"|wg pubkey)"
	reg="$(curl $curlopts --compressed -s \
		-H 'User-Agent: okhttp/3.12.1' \
		-H 'Content-Type: application/json' \
		-X "POST" -d '{"install_id":"","tos":"'"$(date -u +%FT%T.000Z)"'","key":"'"${publ}"'","fcm_token":"","type":"ios","locale":"en_US"}' \
		"${prefix}/reg")"
	auth=( $(printf '%s' "$reg" | jq -r '.id+" "+.token') )
	{
	printf 'priv="%s"\n' "$priv"
	printf 'publ="%s"\n' "$publ"
	printf 'auth[0]="%s"\n' "${auth[0]}"
	printf 'auth[1]="%s"\n' "${auth[1]}"
	} > warp.source
fi

curl $curlopts --compressed -s \
	-H 'User-Agent: okhttp/3.12.1' \
	-H "Authorization: Bearer ${auth[1]}" \
	-H 'Content-Type: application/json' \
	-X "PATCH" -d '{"warp_enabled":true}' \
	"${prefix}/reg/${auth[0]}" >/dev/null 2>&1

wg="host"
if [ "$wgoverride" != 1 ];then
	case $wgproto in
		4) wg="v4" ;;
		6) wg="v6" ;;
	esac
fi

cfg=( $(printf '%s' "$reg" | jq -r '.config|(.peers[0]|.public_key+" "+.endpoint.'$wg')+" "+.interface.addresses.v4+" "+.interface.addresses.v6') )

{
	echo "[Interface]"
	echo "Address = ${cfg[2]},${cfg[3]}"
	echo "PrivateKey = ${priv}"
	echo "DNS = 1.1.1.1"
	echo "MTU = 1280"
	echo ""
	echo "[Peer]"
	echo "PublicKey = ${cfg[0]}"
	echo "AllowedIPs = 0.0.0.0/0,::/0"
	echo "Endpoint = ${cfg[1]}"

} > warp.conf
