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
cf_trace=0
curl_ip_protocol=0
curl_opts=
show_regonly=0
teams_ephemeral_token=

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
		${curl_opts} \
		"${@}"
}

# Strip port from IP:port string
strip_port() {
	IFS= read -r str
	printf '%s' "${str%:*}"
}

# Print separator for better readability
print_separator() {
	printf '%s\n' '----------------------------------------' >&2
}

# Functions for options
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
while getopts "46stT:h" opt; do
	case "${opt}" in
		4) curl_ip_protocol=4 ;;
		6) curl_ip_protocol=6 ;;
		s) show_regonly=1 ;;
		t) cf_trace=1 ;;
		T) teams_ephemeral_token="${OPTARG}" ;;
		h) help_page 0 ;;
		*) help_page 1 ;;
	esac
done

# If user is okay with forcing IP protocol on curl, we do so
case "${curl_ip_protocol}" in
	4) curl_opts="${curl_opts} "'--ipv4'; ;;
	6) curl_opts="${curl_opts} "'--ipv6'; ;;
	*) ;;
esac

# If requested, we show trace after all options have been parsed
if [ "${cf_trace}" -eq 1 ]; then
	cfcurl "https://www.cloudflare.com/cdn-cgi/trace"
	exit 0
fi

# Register a new account
wg_private_key="$(wg genkey)"
wg_public_key="$(printf %s "${wg_private_key}" | wg pubkey)"
reg="$(cfcurl --header 'Content-Type: application/json' --request "POST" --header 'CF-Access-Jwt-Assertion: '"${teams_ephemeral_token}" \
	--data '{"key":"'"${wg_public_key}"'","install_id":"","fcm_token":"","model":"","serial_number":"","locale":"en_US"}' \
	"${BASE_URL}/reg")"

# DEBUG: Show registration response
if [ "${show_regonly}" -eq 1 ]; then
	printf '%s\n' "${reg}" | jq
	print_separator
fi

# Extract Wireguard details from registration response
wg_config=$(printf %s "${reg}" | jq -r '.config|(
	.peers[0]|
	.public_key+"\n"+               # NR==1
	.endpoint.host+"\n"+            # NR==2
	.endpoint.v4+"\n"+              # NR==3
	.endpoint.v6)+"\n"+             # NR==4
	.interface.addresses.v4+"\n"    # NR==5
	+.interface.addresses.v6+"\n"+  # NR==6
	.client_id                      # NR==7
	'
)
endpoint_port=2408
peer_public_key=$(printf %s "${wg_config}" | awk 'NR==1')
endpoint_host=$(printf %s "${wg_config}" | awk 'NR==2' | strip_port)":${endpoint_port}"
endpoint_ipv4=$(printf %s "${wg_config}" | awk 'NR==3' | strip_port)":${endpoint_port}"
endpoint_ipv6=$(printf %s "${wg_config}" | awk 'NR==4' | strip_port)":${endpoint_port}"
address_ipv4=$(printf %s "${wg_config}" | awk 'NR==5')
address_ipv6=$(printf %s "${wg_config}" | awk 'NR==6')
client_id_b64=$(printf %s "${wg_config}" | awk 'NR==7')
client_id_hex=$(printf %s "${client_id_b64}" | base64 -d | hexdump -v -e '/1 "%02x\n"')
client_id_dec=$(printf '%s\n' "${client_id_hex}" | while read -r hex; do printf "%d, " "0x${hex}"; done)
## Add brackets and remove trailing comma and space
client_id_dec="[${client_id_dec%, }]"
## Add 0x prefix and remove newline
client_id_hex=$(printf %s "${client_id_hex}" | awk 'BEGIN { ORS=""; print "0x" } { print }')

# Extract Cloudflare credentials from registration response
cf_creds=$(printf %s "${reg}" | jq -r '
	.id+"\n"+                       # NR==1
	.account.id+"\n"+               # NR==2
	.account.license+"\n"+          # NR==3
	.token                          # NR==4
	'
)
device_id=$(printf %s "${cf_creds}" | awk 'NR==1')
account_id=$(printf %s "${cf_creds}" | awk 'NR==2')
account_license=$(printf %s "${cf_creds}" | awk 'NR==3')
if [ -z "${account_license}" ] && [ -n "${teams_ephemeral_token}" ]; then
	account_license="N/A"
elif [ -z "${account_license}" ]; then
	account_license="Unknown"
fi
token=$(printf %s "${cf_creds}" | awk 'NR==4')

# Write WARP Wireguard config and quit
cat <<-EOF
	[Interface]
	PrivateKey = ${wg_private_key}
	#PublicKey = ${wg_public_key}
	Address = ${address_ipv4}, ${address_ipv6}
	DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001
	MTU = 1280

	# Cloudflare Warp specific variables
	#CFDeviceId = ${device_id}
	#CFAccountId = ${account_id}
	#CFAccountLicense = ${account_license}
	#CFToken = ${token}
	## Cloudflare Client ID in various formats.
	## NOTE: this is also referred to as "reserved key" as the client ID
	##       is put in the reserved key field in the WireGuard handshake.
	#CFClientIdB64 = ${client_id_b64}
	#CFClientIdHex = ${client_id_hex}
	#CFClientIdDec = ${client_id_dec}

	[Peer]
	PublicKey = ${peer_public_key}
	AllowedIPs = 0.0.0.0/0, ::/0
	PersistentKeepalive = 25
	# If UDP 2408 is blocked, you could try UDP 500, UDP 1701, or UDP 4500.
	Endpoint = ${endpoint_ipv4}
	#Endpoint = ${endpoint_ipv6}
	#Endpoint = ${endpoint_host}
EOF
exit 0
