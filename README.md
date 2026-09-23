# Weichenweb

## Run In The Dev Container

The devcontainer uses `openwrt/rootfs:x86_64-21.02.7` and installs uhttpd, Lua
5.1, nixio, Bash, Git, and sudo. Its startup command copies the CGI script
and remote endpoint into uhttpd's document root and starts uhttpd on port 8080.

To use a remote endpoint other than the default `localhost:15731`, copy and
edit the example before creating or restarting the container:

```sh
cp remote-host.txt.example remote-host.txt
```

After the container starts, open
`http://localhost:8080/cgi-bin/weichenweb` in a browser. If the Dockerfile or
devcontainer configuration changes, rebuild/reopen the devcontainer so the
OpenWrt image and packages are recreated. The Lua script is not a standalone
HTTP server and must not be started directly.

## Run With Docker

The application defaults to `localhost:15731`. To configure another endpoint,
copy and edit `remote-host.txt.example`, then build the image from the project
directory:

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

If present, `remote-host.txt` must contain exactly one trimmed `host:port` line,
with a TCP port from 1 through 65535. If the file is absent, the default remote
endpoint is `localhost:15731`. The server sends the 13-byte TCP packet described
in `Accessory-Packet.md`.

## Configuration

The following environment variables are supported when supplied by the CGI
server: `REMOTE_HOST_FILE` (default `/www/cgi-bin/remote-host.txt`),
`ADDRESS_MIN` (default `1`), `ADDRESS_MAX` (default `1024`), and `CAN_UID` (default `0x00004711`,
decimal or hexadecimal). The reference uhttpd setup uses the default file paths
because uhttpd does not pass arbitrary environment variables to CGI processes.
It provides the standard CGI variables and routes `/api/turnout` as
`PATH_INFO`.

## REST API And Swagger UI

Open the interactive API documentation at
`http://localhost:8080/cgi-bin/weichenweb/swagger`. Swagger UI loads its
OpenAPI document from `/cgi-bin/weichenweb/swagger.json` and provides the
`POST /api/turnout` operation.

The REST endpoint accepts JSON with an integer `address`, `direction` set to
`red` or `green`, and integer `power` set to `0` (off) or `1` (on):

```sh
curl -X POST http://localhost:8080/cgi-bin/weichenweb/api/turnout \
  -H 'Content-Type: application/json' \
  -d '{"address":3,"direction":"red","power":1}'
```

`address` must be from `ADDRESS_MIN` through `ADDRESS_MAX`. A successful
request returns `{"ok":true}`. The Swagger UI page loads the Swagger UI
JavaScript and CSS from `unpkg.com`, so the browser needs internet access for
the interactive styling and controls; the OpenAPI document itself is served
locally.

The website stores up to 50 controlled addresses in FIFO order in the
`weichenweb_recent` browser cookie. Controlling a listed turnout does not move
it; new addresses are appended and the oldest address is dropped when full.
The list remains FIFO internally. The dropdown at the top left selects `FIFO`
or `by Address` for display; `by Address` is the default and is saved in the
`weichenweb_order` cookie. The `Clear history` button at the top of the page
asks for confirmation, then clears the history cookie for that browser. The
history cookie is updated after successful turnout actions, so the website
does not require a writable server filesystem. The list is per browser and is
not used to authorize or construct packets.

The page has no visible headings. The recent-turnout list scrolls independently
above the address input and buttons, which stay pinned at the bottom of the
viewport. An empty address input shows the placeholder `address`.

The TCP connection is established for each CGI request that submits an action
using nixio. Connection setup has a two-second timeout; sends use a two-second
socket timeout and a full-write loop. The connection is closed when the request
exits. A connection or send failure returns CGI status `503`; the next request
tries to connect again.
