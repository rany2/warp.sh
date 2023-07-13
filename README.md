# warp.sh

By using this you agree to Cloudflare's ToS: https://www.cloudflare.com/application/terms/  

## Quick Guide

Make sure to have `jq`, `curl`, and `wireguard-tools` (for `wg genkey` and `wg pubkey`) installed
before using this shell script.  

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
  -T  teams JWT token (default no JWT token is sent)
  -t  show cloudflare trace and exit only
  -h  show this help page and exit only
```

### Regarding Teams enrollment:
  1. Visit https://\<teams id>.cloudflareaccess.com/warp
  2. Authenticate yourself as you would with the official client
  3. Check the source code of the page for the JWT token or use the following code in the "Web Console" (Ctrl+Shift+K):
```js
console.log(document.querySelector("meta[http-equiv='refresh']").content.split("=")[2])
```
  4. Pass the output as the value for the parameter -T. The final command will look like:
```shell
./warp.sh -T eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.....
```
