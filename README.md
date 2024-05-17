# warp.sh

By using this you agree to Cloudflare's ToS: <https://www.cloudflare.com/application/terms/>  

## Quick Guide #1

Make sure to have `jq`, `curl`, and `wireguard-tools` (for `wg genkey` and `wg pubkey`) installed
before using this shell script.  

```shell
git clone https://github.com/rany2/warp.sh.git
cd warp.sh
./warp.sh
```

The generated wireguard config will be printed to stdout.

## Quick Guide #2

To execute this script on GitHub Codespaces without the need to set up a local environment, follow these steps:

1. Open the repository and locate the green buttons. Click on "Code" then select "Codespaces" and finally choose "Create codespace on master".
2. Wait for the codespace to be created. Once it's ready, open the terminal and run the command `./warp.sh`.
3. After you've finished using the codespace, it's important to delete it to maintain cleanliness and save resources.

Please note that deleting the codespace will remove all the changes and configurations made within it, so make sure to save any important files or settings before closing.

## Usage options

```
Usage ./warp.sh [options]
  -4  use ipv4 for curl
  -6  use ipv6 for curl
  -T  teams JWT token (default no JWT token is sent)
  -R  refresh token (format is token,device_id,wg_private_key; specify this to get a refreshed config)
  -t  show cloudflare trace and exit only
  -h  show this help page and exit only
```

### Regarding Teams enrollment

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

### Regarding -T and -R options

`-T` and `-R` both could take a file as an argument. The file should be in the same
format as the command line argument. This is so that the token wouldn't be exposed
in the shell history or process list.
