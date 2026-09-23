## Purpose

Build a Lua CGI application that serves one web page for controlling turnouts.
An existing web server invokes the CGI script; the application also has a TCP
client connection to the railway control system (the remote system).

## Web page

- The page has no visible headings. Its numeric turnout-address input and
  red/green controls remain pinned at the bottom of the viewport.
- The input has one red button and one green button beside it.
- The page also contains a list of up to 50 controlled turnout addresses above
  the address controls. The list scrolls independently without moving the
  address controls. Each list entry has its own red and green button.
- A `Clear history` button appears at the top of the page. It asks for
  confirmation before clearing the browser's recent-address cookie.
- A dropdown at the top left selects `FIFO` or `by Address`. `by Address` is
  the default. This setting controls display order only; the underlying history
  remains FIFO.
- When empty, the address input displays the grey placeholder `address`.
- The red and green controls represent the two turnout states. The exact
  protocol value for each state is defined in `Accessory-Packet.md`; the
  application must use one consistent mapping for all controls.
- A control is submitted only when its button is pressed. A submission contains
  the turnout address and the selected state.
- After a successful submission, a new address is appended to the FIFO list.
  Existing entries keep their current position and are not duplicated. The
  list is limited to 50 entries, dropping the oldest entry when full.
- Invalid or missing addresses must not result in a packet being sent. The page
  must report the validation error to the user. The valid numeric range is a
  configuration value and must be documented when the packet protocol is
  implemented.

## CGI and Server API

The application is invoked as a CGI script and must read the CGI environment and
request body from standard input. It must write a CGI `Status` header,
`Content-Type`, `Content-Length`, a blank line, and the response body. It must
not bind a listening web-server socket or emit an HTTP status line.

The reference deployment uses uhttpd with the script at
`/cgi-bin/weichenweb`. `GET /cgi-bin/weichenweb` returns the HTML page. The
browser submits actions to `POST /cgi-bin/weichenweb/api/turnout`; uhttpd must
pass `/api/turnout` as `PATH_INFO`.

The REST action endpoint is `POST /cgi-bin/weichenweb/api/turnout`, with
`/api/turnout` passed as `PATH_INFO`. It accepts an `application/json` object
with exactly these fields:

```json
{"address":3,"direction":"red","power":1}
```

`address` must be an integer in the configured inclusive range. `direction`
must be `red` or `green`, and `power` must be integer `0` or `1`; `0` switches
off and `1` switches on. The direction is mapped to the packet's `Stellung`
field and power is mapped to its `Strom` field as defined in
`Accessory-Packet.md`.

A successful request returns `200 OK` and `{"ok":true}`. Invalid input returns
`400 Bad Request`, a body-size violation returns `413 Payload Too Large`, and
an unavailable remote connection returns `503 Service Unavailable`. Browser
requests must not be able to submit arbitrary data as a packet.

`GET /cgi-bin/weichenweb/swagger` serves the Swagger UI page and
`GET /cgi-bin/weichenweb/swagger.json` serves the OpenAPI 3.0.3 document for
the REST endpoint. The UI references the Swagger UI distribution from
`unpkg.com`; the OpenAPI document is served by the application.

The website's controlled-address list is client-side state in the
`weichenweb_recent` cookie. The cookie contains at most 50 validated addresses
in FIFO order, oldest first, regardless of display order. After a successful
remote send, a previously unlisted address is appended; controlling an address
already in the list does not change its position. When full, adding a new
address removes the oldest. The response returns a `Set-Cookie` header with the
updated list. Failed remote actions do not update the cookie. Each browser has
its own list, and the cookie is only display state; it is not trusted for
authorization or packet construction.

The display selection is stored separately in the `weichenweb_order` cookie as
`fifo` or `address`. The default is `address`; in that mode the page sorts a
copy of the FIFO list for display and does not modify its stored order.

## Remote connection

- Each CGI invocation reads the remote endpoint before handling the request. The
  file, when present, must contain exactly one non-empty, trimmed line in
  `host:port` format, where `host` is the remote host name or address and
  `port` is a numeric TCP port from 1 through 65535. If the file is missing,
  the application uses `localhost:15731`.
- The application must reject unreadable, malformed, or ambiguous endpoint
  files and report the configuration error when the CGI process starts.
  Whitespace at the beginning or end of the single line is ignored;
  additional non-empty lines are invalid.
- For each accepted action, the CGI process opens a TCP connection to the host
  and port from the endpoint file, uses a two-second socket timeout, sends the
  packet with a full-write loop, and closes the connection when the invocation
  exits.
- Packets sent and received on this connection must follow `Accessory-Packet.md`.
- `Accessory-Packet.md` is a required project document and must define packet
  framing, the address and state encoding, acknowledgements, and error
  handling. No packet format may be inferred from this file alone.
- When a valid action is submitted, the server sends exactly one packet for
  that action.
- If the connection is unavailable or the packet cannot be sent, the action
  fails with an error response and must not be added to the recent-address
  list.
- A connection or send failure is logged and reported as `503`; the next CGI
  invocation creates a new connection. There is no persistent reconnect loop.

## Configuration and operational requirements

- The valid turnout-address range must be configurable. Web-server binding and
  CGI URL configuration belong to the existing web server, not the Lua script.
- The CAN UID used to construct the accessory packet must be configurable. The
  implementation uses the `CAN_UID` environment variable and documents its
  default as `0x00004711`.
- `remote-host.txt` is optional and must not contain credentials or other
  settings. If it is absent, the default endpoint is `localhost:15731`.
- In the uhttpd development container, `remote-host.txt` is copied to
  `/www/cgi-bin/remote-host.txt` because uhttpd does not pass arbitrary
  environment variables to CGI processes. `REMOTE_HOST_FILE` remains available
  when the hosting CGI server supplies it.
- Under uhttpd, the default paths and address range are used unless the server
  is wrapped with a configuration mechanism that supplies those environment
  variables. Configuration errors must be reported when the CGI process starts.
- The application must log connection failures and failed submissions without
  logging sensitive configuration values.
- The application must run on Lua 5.1 and nixio as supplied by the OpenWrt
  21.02.7 development container. The implementation must not use Lua 5.2+
  syntax or native bitwise operators.
- TCP connections use nixio: connect is nonblocking with a two-second poll
  timeout, and socket sends use a two-second send timeout and a full-write loop.
