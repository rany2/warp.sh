# warp.sh

By using this you agree to Cloudflare's ToS: https://www.cloudflare.com/application/terms/  

## Quick Guide

Make sure to have `jq`, `curl`, and `wireguard-tools` (for `wg genkey` and `wg pubkey`) installed
before using this bash script.  

```shell
git clone https://github.com/rany2/warp.sh.git
cd warp.sh
./warp.sh
```

The generated wireguard config will have the filename `warp.conf` and will be
located in the same location you ran the script in.  

You could use the profile with `NetworkManager` by doing 
`nmcli connection import file warp.conf type wireguard` or with `wg-quick` by doing
`wg-quick up ./warp.conf`.  

If you want the generated wireguard config to use an IPv4 address instead of a hostname,
use `./warp.sh -4` instead of `./warp.sh`.

## Usage options

```
Usage	./warp.sh [options]

-4	use ipv4 for wireguard endpoint and curl
-6	use ipv6 for wireguard endpoint and curl
-a	use DNS hostname for wireguard (overrides -4 or -6 for wireguard but keeps option for curl) (default)
-s	show status and exit only
-t	show cloudflare trace and exit only
-h	show this help page and exit only
```
