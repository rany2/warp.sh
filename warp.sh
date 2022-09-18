#!/usr/bin/env bash

# Safety options and API paths
set -euf
warp_apiurl='https://api.cloudflareclient.com/v0a2483'

# Default variables that can be modified by user's options
wgproto=0; status=0; trace=0

# Setup headers, user agent and compression to appear to be the Android app
curlopts=(
	--header 'User-Agent: okhttp/3.12.1'
	--header 'CF-Client-Version: a-6.16-2483'
	--header 'Accept: application/json; charset=UTF-8'
	--silent
	--compressed
	--fail
)

# Functions for options
show_trace() { curl "${curlopts[@]}" "https://www.cloudflare.com/cdn-cgi/trace"; exit "$1"; }
help_page() { cat >&2 <<-EOF

	Usage $0 [options]
	  -4  use ipv4 for curl
	  -6  use ipv6 for curl
	  -s  show status and exit only
	  -t  show cloudflare trace and exit only
	  -h  show this help page and exit only

	EOF

	exit "$1"
}

# Parse options
while getopts "h46acst" opt
do
	case "$opt" in
		4) wgproto=4; ;;
		6) wgproto=6; ;;
		s) status=1 ;;
		t) trace=1 ;;
		h) help_page 0 ;;
		*) help_page 1 ;;
	esac
done

# If user is okay with forcing IP protocol on curl, we do so
case "$wgproto" in
	4) curlopts+=( --ipv4 ); ;;
	6) curlopts+=( --ipv6 ); ;;
esac

# If requested, we show trace after all options have been parsed
[ "$trace" = "1" ] && show_trace 0

# Register a new account
priv="$(wg genkey)"
publ="$(wg pubkey <<<"$priv")"
reg="$(curl "${curlopts[@]}" --header 'Content-Type: application/json' --request "POST" \
	--data '{"key":"'"${publ}"'","install_id":"","fcm_token":"","model":"","serial_number":"","locale":"en_US"}' \
	"${warp_apiurl}/reg")"
# shellcheck disable=SC2207
auth=( $(jq -r '.id+" "+.token' <<<"$reg") )

# Show current config's status if requested and exit
[ "$status" = 1 ] && { jq <<<"$reg"; exit 0; }

# Load up variables for the Wireguard config template
# shellcheck disable=SC2207
cfg=( $(jq -r '.config|(.peers[0]|.public_key+" "+.endpoint.host)+" "+.interface.addresses.v4+" "+.interface.addresses.v6' <<<"$reg") )

# Write WARP Wireguard config and quit
cat <<-EOF
	[Interface]
	PrivateKey = ${priv}
	Address = ${cfg[2]}/32
	Address = ${cfg[3]}/128
	DNS = 1.1.1.1
	MTU = 1280

	[Peer]
	PublicKey = ${cfg[0]}
	AllowedIPs = 0.0.0.0/0
	AllowedIPs = ::/0
	Endpoint = ${cfg[1]}
EOF
exit 0
