# warp.sh

By using this you agree to Cloudflare's ToS: https://www.cloudflare.com/application/terms/  

## How to use?

Make sure to have `jq`, `curl`, and `wireguard-tools` installed before using this bash script.  

```shell
git clone https://github.com/rany2/warp.sh.git
cd warp.sh
./warp.sh
```

The generated wireguard config will have the filename `warp.conf` and will be located in the same location you ran the script in.  

If you want the generated wireguard config to use an IPv4 address instead of a hostname,
use `./warp.sh -4` instead of `./warp.sh`. For other options check `./warp.sh -h`.
