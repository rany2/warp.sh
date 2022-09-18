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

The generated wireguard config will be printed to stdout.  

## Usage options

```
Usage ./warp.sh [options]
-4  use ipv4 for curl
-6  use ipv6 for curl
-s  show status and exit only
-t  show cloudflare trace and exit only
-h  show this help page and exit only
```
