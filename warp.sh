#!/bin/sh

# Safety options and API paths
set -euf
warp_apiurl='https://api.cloudflareclient.com/v0a2483'

# Default variables that can be modified by user's options
wgproto=0; status=0; trace=0; curlopts=

cfcurl() {
	# We need word splitting for $curlopts
	# shellcheck disable=SC2086
	curl \
		--header 'User-Agent: okhttp/3.12.1' \
		--header 'CF-Client-Version: a-6.16-2483' \
		--header 'Accept: application/json; charset=UTF-8' \
                --tls-max 1.2 \
                --ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-CCM:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-CCM:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:AES256-GCM-SHA384:AES256-CCM:AES128-GCM-SHA256:AES128-CCM:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES256-CCM:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES128-CCM:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA' \
		--silent \
		--compressed \
		--fail \
		$curlopts \
		"$@"
}

# Functions for options
show_trace() { cfcurl "https://www.cloudflare.com/cdn-cgi/trace"; exit "$1"; }
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
	4) curlopts="$curlopts "'--ipv4'; ;;
	6) curlopts="$curlopts "'--ipv6'; ;;
esac

# If requested, we show trace after all options have been parsed
[ "$trace" = "1" ] && show_trace 0

# Register a new account
priv="$(wg genkey)"
publ="$(printf %s "$priv" | wg pubkey)"
reg="$(cfcurl --header 'Content-Type: application/json' --request "POST" \
	--data '{"key":"'"${publ}"'","install_id":"","fcm_token":"","model":"","serial_number":"","locale":"en_US"}' \
	"${warp_apiurl}/reg")"

# Show current config's status if requested and exit
[ "$status" = 1 ] && { printf %s "$reg" | jq; exit 0; }

# Load up variables for the Wireguard config template
cfg=$(printf %s "$reg" | jq -r '.config|(.peers[0]|.public_key+"\n"+.endpoint.host)+"\n"+.interface.addresses.v4+"\n"+.interface.addresses.v6')
addr4=$(printf %s "$cfg" | head -n3 | tail -1)
addr6=$(printf %s "$cfg" | head -n4 | tail -1)
pubkey=$(printf %s "$cfg" | head -n1)
endpoint=$(printf %s "$cfg" | head -n2 | tail -1)

# Write WARP Wireguard config and quit
cat <<-EOF
	[Interface]
	PrivateKey = ${priv}
	Address = ${addr4}/32
	Address = ${addr6}/128
	DNS = 1.1.1.1
	DNS = 1.0.0.1
	DNS = 2606:4700:4700::1111
	DNS = 2606:4700:4700::1001
	MTU = 1280

	[Peer]
	PublicKey = ${pubkey}
	AllowedIPs = 0.0.0.0/0
	AllowedIPs = ::/0
	Endpoint = ${endpoint}
EOF
exit 0
