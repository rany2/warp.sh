#!/bin/sh

# Safety options
set -e # Exit on error
set -u # Treat unset variables as an error
set -f # Disable globbing

# Constants
BASE_URL='https://api.cloudflareclient.com/v0a2483'
DEPENDENCIES="curl jq awk printf cat base64 hexdump wg"

# Validate dependencies are installed
exit_with_error=0
for dep in ${DEPENDENCIES}; do
	if ! command -v "${dep}" >/dev/null 2>&1; then
		echo "Error: ${dep} is not installed." >&2
		exit_with_error=1
	fi
done
[ "${exit_with_error}" -eq 1 ] && exit 1

# Initialize variables that are settable by the user
curlopts=
show_regonly=0
teams=
trace=0
wgproto=0

# Helper function to send traffic to Cloudflare API without
# tripping up their TLS fingerprinting mechanism and triggering
# a block.
cfcurl() {
	# shellcheck disable=SC2086
	curl \
		--header 'User-Agent: okhttp/3.12.1' \
		--header 'CF-Client-Version: a-6.16-2483' \
		--header 'Accept: application/json; charset=UTF-8' \
		--tls-max 1.2 \
		--ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-CCM:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-CCM:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:AES256-GCM-SHA384:AES256-CCM:AES128-GCM-SHA256:AES128-CCM:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES256-CCM:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES128-CCM:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA' \
		--disable \
		--silent \
		--show-error \
		--compressed \
		--fail \
		${curlopts} \
		"${@}"
}

# Strip port from IP:port string
strip_port() {
	IFS= read -r str
	printf '%s' "${str%:*}"
}

# Functions for options
show_trace() { cfcurl "https://www.cloudflare.com/cdn-cgi/trace"; exit "$1"; }
help_page() { cat >&2 <<-EOF

	Usage $0 [options]
	  -4  use ipv4 for curl
	  -6  use ipv6 for curl
	  -T  teams JWT token (default no JWT token is sent)
	  -t  show cloudflare trace and exit only
	  -h  show this help page and exit only

	Regarding Teams enrollment:
	  1. Visit https://<teams id>.cloudflareaccess.com/warp
	  2. Authenticate yourself as you would with the official client
	  3. Check the source code of the page for the JWT token or use the following code in the "Web Console" (Ctrl+Shift+K):
	  	  console.log(document.querySelector("meta[http-equiv='refresh']").content.split("=")[2])
	  4. Pass the output as the value for the parameter -T. The final command will look like:
	  	  ${0} -T eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.....

	EOF

	exit "${1}"
}

# Parse options
while getopts "h46acstT:" opt
do
	case "${opt}" in
		4) wgproto=4; ;;
		6) wgproto=6; ;;
		s) show_regonly=1 ;;
		t) trace=1 ;;
		T) teams="${OPTARG}" ;;
		h) help_page 0 ;;
		*) help_page 1 ;;
	esac
done

# If user is okay with forcing IP protocol on curl, we do so
case "${wgproto}" in
	4) curlopts="${curlopts} "'--ipv4'; ;;
	6) curlopts="${curlopts} "'--ipv6'; ;;
	*) ;;
esac

# If requested, we show trace after all options have been parsed
[ "${trace}" -eq 1 ] && show_trace 0

# Register a new account
priv="$(wg genkey)"
publ="$(printf %s "${priv}" | wg pubkey)"
reg="$(cfcurl --header 'Content-Type: application/json' --request "POST" --header 'CF-Access-Jwt-Assertion: '"${teams}" \
	--data '{"key":"'"${publ}"'","install_id":"","fcm_token":"","model":"","serial_number":"","locale":"en_US"}' \
	"${BASE_URL}/reg")"

# DEBUG: Show registration response and exit
[ "${show_regonly}" = 1 ] && { printf %s "${reg}" | jq; exit 0; }

# Load up variables for the Wireguard config template
cfg=$(printf %s "${reg}" | jq -r '.config|(
	.peers[0]|
	.public_key+"\n"+               # NR==1
	.endpoint.host+"\n"+            # NR==2
	.endpoint.v4+"\n"+              # NR==3
	.endpoint.v6)+"\n"+             # NR==4
	.interface.addresses.v4+"\n"    # NR==5
	+.interface.addresses.v6+"\n"+  # NR==6
	.client_id'                     # NR==7
)
cfcreds=$(printf %s "${reg}" | jq -r '
	.id+"\n"+                       # NR==1
	.account.id+"\n"+               # NR==2
	.account.license+"\n"+          # NR==3
	.token'                         # NR==4
)
endpointhostport=2408
pubkey=$(printf %s "${cfg}" | awk 'NR==1')
endpoint=$(printf %s "${cfg}" | awk 'NR==2' | strip_port)":${endpointhostport}"
endpoint4=$(printf %s "${cfg}" | awk 'NR==3' | strip_port)":${endpointhostport}"
endpoint6=$(printf %s "${cfg}" | awk 'NR==4' | strip_port)":${endpointhostport}"
addr4=$(printf %s "${cfg}" | awk 'NR==5')
addr6=$(printf %s "${cfg}" | awk 'NR==6')
cfclientidb64=$(printf %s "${cfg}" | awk 'NR==7')
cfclientidhex=$(printf %s "${cfclientidb64}" | base64 -d | hexdump -v -e '/1 "%02x\n"')
cfclientiddec=$(printf '%s\n' "${cfclientidhex}" | while read -r hex; do printf "%d, " "0x${hex}"; done)
cfclientiddec="[${cfclientiddec%, }]" # Remove trailing comma and space and add brackets
cfclientidhex=$(printf %s "${cfclientidhex}" | awk 'BEGIN { ORS=""; print "0x" } { print }') # Add 0x prefix and remove newline
cfdeviceid=$(printf %s "${cfcreds}" | awk 'NR==1')
cfaccountid=$(printf %s "${cfcreds}" | awk 'NR==2')
cflicense=$(printf %s "${cfcreds}" | awk 'NR==3')
[ -z "${cflicense}" ] && [ -n "${teams}" ] && cflicense="N/A"
cftoken=$(printf %s "${cfcreds}" | awk 'NR==4')

# Write WARP Wireguard config and quit
cat <<-EOF
	[Interface]
	PrivateKey = ${priv}
	#PublicKey = ${publ}
	Address = ${addr4}, ${addr6}
	DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001
	MTU = 1280

	# Cloudflare Warp specific variables
	#CFDeviceId = ${cfdeviceid}
	#CFAccountId = ${cfaccountid}
	#CFLicense = ${cflicense}
	#CFToken = ${cftoken}
	## Cloudflare Client ID in various formats.
	## NOTE: this is also referred to as "reserved key" as the client ID
	##       is put in the reserved key field in the WireGuard handshake.
	#CFClientIdB64 = ${cfclientidb64}
	#CFClientIdHex = ${cfclientidhex}
	#CFClientIdDec = ${cfclientiddec}

	[Peer]
	PublicKey = ${pubkey}
	AllowedIPs = 0.0.0.0/0, ::/0
	PersistentKeepalive = 25
	# If UDP 2408 is blocked, you could try UDP 500, UDP 1701, or UDP 4500.
	Endpoint = ${endpoint4}
	#Endpoint = ${endpoint6}
	#Endpoint = ${endpoint}
EOF
exit 0
