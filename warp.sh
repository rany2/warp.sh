#!/bin/sh

# Safety options
set -e # Exit on error
set -u # Treat unset variables as an error
set -f # Disable globbing

# Constants
BASE_URL='https://api.cloudflareclient.com/v0a2483'
DEPENDENCIES="curl jq awk printf cat base64 wg"
AT_LEAST_ONE_OF_THESE="xxd,hexdump,od"

# Validate dependencies are installed
exit_with_error=0
for dep in ${DEPENDENCIES}; do
	if ! command -v "${dep}" >/dev/null 2>&1; then
		echo "Error: ${dep} is not installed." >&2
		exit_with_error=1
	fi
done
for dep in ${AT_LEAST_ONE_OF_THESE}; do
	while IFS=, read -r dep1 dep2 dep3; do
		if command -v "${dep1}" >/dev/null 2>&1 || \
			command -v "${dep2}" >/dev/null 2>&1 || \
			command -v "${dep3}" >/dev/null 2>&1; then
			break
		fi
		echo "Error: At least one of ${dep1}, ${dep2}, or ${dep3} is required." >&2
		exit_with_error=1
	done <<-EOF
		${dep}
	EOF
done
[ "${exit_with_error}" -eq 1 ] && exit 1

# Initialize variables that are settable by the user
cf_trace=0
curl_ip_protocol=0
curl_opts=
refresh_token=
show_regonly=0
teams_ephemeral_token=
token=
model_name="rany2/warp.sh"
device_name=

# Helper function to send traffic to Cloudflare API without
# tripping up their TLS fingerprinting mechanism and triggering
# a block.
cfcurl() {
	# shellcheck disable=SC2086
	curl \
		--header 'User-Agent: 1.1.1.1/6.81' \
		--header 'CF-Client-Version: a-6.81-2410012252.0' \
		--header 'Accept: application/json; charset=UTF-8' \
		--tls-max 1.2 \
		--ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-CCM:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-CCM:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:AES256-GCM-SHA384:AES256-CCM:AES128-GCM-SHA256:AES128-CCM:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES256-CCM:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES128-CCM:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA' \
		--disable \
		--silent \
		--show-error \
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
	  -R  refresh token (format is token,device_id,wg_private_key; specify this to get a refreshed config)
	  -m  model name (default is rany2/warp.sh)
	  -d  device name (default is blank)
	  -t  show cloudflare trace and exit only
	  -h  show this help page and exit only

	Regarding Teams enrollment:
	  1. Visit https://<teams id>.cloudflareaccess.com/warp
	  2. Authenticate yourself as you would with the official client
	  3. Check the source code of the page for the JWT token or use the following code in the "Web Console" (Ctrl+Shift+K):
	  	  console.log(document.querySelector("meta[http-equiv='refresh']").content.split("=")[2])
	  4. Pass the output as the value for the parameter -T. The final command will look like:
	  	  ${0} -T eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.....

	Regarding -T and -R options:
	  -T and -R both could take a file as an argument. The file should be in the same format as the command line argument.
	  This is so that the token wouldn't be exposed in the shell history or process list.

	EOF

	exit "${1}"
}

clientid_to_hex() {
	if command -v xxd >/dev/null 2>&1; then
		xxd -p -c 1
	elif command -v hexdump >/dev/null 2>&1; then
		hexdump -v -e '/1 "%02x\n"'
	elif command -v od >/dev/null 2>&1; then
		od -An -v -t x1 -w1 | awk '{$1=$1; print}'
	else
		echo "Error: No suitable command found to convert client ID to hex." >&2
		exit 1
	fi
}

# Parse options
while getopts "46stT:R:m:d:h" opt; do
	case "${opt}" in
		4) curl_ip_protocol=4 ;;
		6) curl_ip_protocol=6 ;;
		s) show_regonly=1 ;;
		t) cf_trace=1 ;;
		T) teams_ephemeral_token="${OPTARG}" ;;
		R) refresh_token="${OPTARG}" ;;
		m) model_name="${OPTARG}" ;;
		d) device_name="${OPTARG}" ;;
		h) help_page 0 ;;
		*) help_page 1 ;;
	esac
done

# If a file is provided as an argument to -T, we read the token from the file
if [ -n "${teams_ephemeral_token}" ] && [ -e "${teams_ephemeral_token}" ]; then
	teams_ephemeral_token=$(cat "${teams_ephemeral_token}")
fi

# If a file is provided as an argument to -R, we read the token from the file
if [ -n "${refresh_token}" ] && [ -e "${refresh_token}" ]; then
	refresh_token=$(cat "${refresh_token}")
fi

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

if [ -n "${refresh_token}" ]; then
	# If a refresh token is provided, we use it to get a new config
	token=$(printf %s "${refresh_token}" | awk -F, '{print $1}')
	device_id=$(printf %s "${refresh_token}" | awk -F, '{print $2}')
	wg_private_key=$(printf %s "${refresh_token}" | awk -F, '{print $3}')
	wg_public_key=$(printf %s "${wg_private_key}" | wg pubkey)
	reg="$(cfcurl --header 'Content-Type: application/json' -H "Authorization: Bearer ${token}" "${BASE_URL}/reg/${device_id}")"
else
	# Register a new account if no refresh token is provided
	wg_private_key="$(wg genkey)"
	wg_public_key="$(printf %s "${wg_private_key}" | wg pubkey)"
	reg="$(cfcurl --header 'Content-Type: application/json' --request "POST" --header 'CF-Access-Jwt-Assertion: '"${teams_ephemeral_token}" \
		--data '{"key":"'"${wg_public_key}"'","install_id":"","fcm_token":"","model":"'"${model_name}"'","serial_number":"","name":"'"${device_name}"'","locale":"en_US"}' \
		"${BASE_URL}/reg")"
fi

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
	.interface.addresses.v4+"\n"+   # NR==5
	.interface.addresses.v6+"\n"+   # NR==6
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
client_id_hex=$(printf %s "${client_id_b64}" | base64 -d | clientid_to_hex)
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
if [ -z "${token}" ]; then
	token=$(printf %s "${cf_creds}" | awk 'NR==4')
fi

# Write WARP Wireguard config and quit
cat <<-EOF
	[Interface]
	PrivateKey = ${wg_private_key}
	#PublicKey = ${wg_public_key}
	Address = ${address_ipv4}, ${address_ipv6}
	DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001
	MTU = 1280

	# To refresh the config, run the following command:
	# ${0} -R '${token},${device_id},${wg_private_key}'
	# or
	# ${0} -R /path/to/refresh_token.txt
	# where refresh_token.txt contains the above string.

	# Cloudflare Warp specific variables
	#CFDeviceId = ${device_id}
	#CFAccountId = ${account_id}
	#CFAccountLicense = ${account_license}
	#CFToken = ${token}
	## Cloudflare Client ID in various formats.
	## NOTE: this is also referred to as "reserved key" as the client ID
	##       is put in the reserved field in the WireGuard header.
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
