#!/usr/bin/env bash

# Safety options and API paths
set -euf
warp_sourcefile="warp.source"
warp_configfile="warp.conf"
warp_apiurl='https://api.cloudflareclient.com/v0a977'

# Default variables that can be modified by user's options
wgoverride=0; wgproto=0; status=0; trace=0; wg='host'

# Setup headers, ciphers, and user agent to appear to be Android app
curlopts=( --header 'User-Agent: okhttp/3.12.1' --header 'Accept: application/json' --silent --compressed --tls-max 1.2 )
curlopts+=( --ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-CCM:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-CCM:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:AES256-GCM-SHA384:AES256-CCM:AES128-GCM-SHA256:AES128-CCM:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES256-CCM:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES128-CCM:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA' )

# Functions for options
show_trace() { curl "${curlopts[@]}" "https://cloudflare.com/cdn-cgi/trace"; exit "$1"; }
help_page() { cat <<-EOF

	Usage $0 [options]
	  -4  use ipv4 for wireguard endpoint and curl
	  -6  use ipv6 for wireguard endpoint and curl
	  -a  use DNS hostname for wireguard (overrides -4 or -6 for wireguard but keeps option for curl) (default)
	  -s  show status and exit only
	  -t  show cloudflare trace and exit only
	  -h  show this help page and exit only

	EOF

	exit "$1"
}

# Parse options
while getopts "h46ast" opt
do
	case "$opt" in
		4) curlopts+=( --ipv4 ); wgproto=4; ;;
		6) curlopts+=( --ipv6 ); wgproto=6; ;;
		a) wgoverride=1 ;;
		s) status=1 ;;
		t) trace=1 ;;
		h) help_page 0 ;;
		*) help_page 1 ;;
	esac
done

# If requested, we show trace after all options have been parsed
[ "$trace" = "1" ] && show_trace 0

# If source file present, we don't register another time
if [ -f "$warp_sourcefile" ]
then
	# shellcheck disable=SC1090
	source "$warp_sourcefile"
	reg="$(curl "${curlopts[@]}" --header "Authorization: Bearer ${auth[1]}" "${warp_apiurl}/reg/${auth[0]}")"
else
	priv="$(wg genkey)"
	publ="$(wg pubkey <<<"$priv")"
	reg="$(curl "${curlopts[@]}" --header 'Content-Type: application/json' --request "POST" --data '{"install_id":"","tos":"'"$(date -u +%FT%T.000Z)"'","key":"'"${publ}"'","fcm_token":"","type":"Android","locale":"en_US"}' \
		"${warp_apiurl}/reg")"
	# shellcheck disable=SC2207
	auth=( $(jq -r '.id+" "+.token' <<<"$reg") )
	cat > "$warp_sourcefile" <<-EOF
		priv=$priv
		publ=$publ
		auth[0]=${auth[0]}
		auth[1]=${auth[1]}
	EOF
fi

# Show current config's status if requested
[ "$status" = 1 ] && { jq <<<"$reg"; exit 0; }

# Send a request to enable WARP
curl "${curlopts[@]}" --header 'Content-Type: application/json' --header "Authorization: Bearer ${auth[1]}" \
	--request "PATCH" --data '{"warp_enabled":true}' "${prefix}/reg/${auth[0]}" >/dev/null 2>&1

# Change endpoint to v4 or v6 if the user requested it
if [ "$wgoverride" != 1 ]
then
	case "$wgproto" in
		4) wg="v4" ;;
		6) wg="v6" ;;
	esac
fi

# Load up variables for Wireguard templace with customized Endpoint based on user's choice
# shellcheck disable=SC2207
cfg=( $(jq -r '.config|(.peers[0]|.public_key+" "+.endpoint.'$wg')+" "+.interface.addresses.v4+" "+.interface.addresses.v6' <<<"$reg") )

# Write WARP Wireguard config and quit
cat > "$warp_configfile" <<-EOF
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
