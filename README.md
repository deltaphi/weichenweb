# Weichenweb

## Run In The Dev Container

The devcontainer uses `openwrt/rootfs:x86_64-21.02.7` and installs uhttpd, Lua
5.1, LuaSocket, Bash, Git, and sudo. Its startup command copies the CGI script
and remote endpoint into uhttpd's document root and starts uhttpd on port 8080.

Copy the example remote endpoint before creating or restarting the container:

```sh
cp remote-host.txt.example remote-host.txt
```

After the container starts, open
`http://localhost:8080/cgi-bin/weichenweb` in a browser. If the Dockerfile or
devcontainer configuration changes, rebuild/reopen the devcontainer so the
OpenWrt image and packages are recreated. The Lua script is not a standalone
HTTP server and must not be started directly.

## Run With Docker

Prepare the remote endpoint and build the image from the project directory:

```sh
cp remote-host.txt.example remote-host.txt
docker build -t weichenweb:21.02 .
```

Start the container interactively. The container startup command copies the CGI
files into uhttpd's document root, starts uhttpd, and leaves the shell running:

```sh
docker run --rm -it \
  --name weichenweb \
  --publish 8080:8080 \
  --volume "$PWD:/workspace" \
  weichenweb:21.02
```

Open `http://localhost:8080/cgi-bin/weichenweb` while the container is running.
Press `Ctrl-D` or type `exit` to stop it.

`remote-host.txt` must contain exactly one trimmed `host:port` line, with a TCP
port from 1 through 65535. The server sends the 13-byte TCP packet described in
`Accessory-Packet.md`.

## Configuration

The following environment variables are supported when supplied by the CGI
server: `REMOTE_HOST_FILE` (default `/www/cgi-bin/remote-host.txt`),
`RECENT_FILE` (default `/tmp/weichenweb-recent.txt`), `ADDRESS_MIN` (default
`1`), `ADDRESS_MAX` (default `1024`), and `CAN_UID` (default `0x00000001`,
decimal or hexadecimal). The reference uhttpd setup uses the default file paths
because uhttpd does not pass arbitrary environment variables to CGI processes.
It provides the standard CGI variables and routes `/api/turnout` as
`PATH_INFO`.

The web API is `POST /cgi-bin/weichenweb/api/turnout` with an
`application/x-www-form-urlencoded` body containing `address` and `state`.
`address` must be an integer from `ADDRESS_MIN` through `ADDRESS_MAX`; `state`
must be `R` or `G`. A successful request returns `{"ok":true}`.

The TCP connection is established for each CGI request that submits an action,
uses a two-second timeout, and is closed when the request exits. A connection or
send failure returns CGI status `503`; the next request tries to connect again.
