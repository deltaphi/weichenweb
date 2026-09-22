## Purpose

Build a Lua application that serves one web page for controlling turnouts. The
application has a web server and a TCP client connection to the railway control
system (the remote system).

## Web page

- The page contains a numeric turnout-address input at the bottom.
- The input has one red button and one green button beside it.
- The page also contains a list of the ten most recently controlled turnout
  addresses at the top. Each list entry has its own red and green button.
- The red and green controls represent the two turnout states. The exact
  protocol value for each state is defined in `Accessory-packet.md`; the
  application must use one consistent mapping for all controls.
- A control is submitted only when its button is pressed. A submission contains
  the turnout address and the selected state.
- After a successful submission, the address becomes the most recently used
  address. Existing entries are moved to the front rather than duplicated; the
  list is limited to ten entries. The order is most-recently-used first.
- Invalid or missing addresses must not result in a packet being sent. The page
  must report the validation error to the user. The valid numeric range is a
  configuration value and must be documented when the packet protocol is
  implemented.

## Server API

The web server must expose an endpoint for submitting a turnout action. The
endpoint accepts an address and a state, validates both values, and returns a
success or error response. The endpoint and response format may be chosen by
the implementation, but they must be documented and tested. Browser requests
must not be able to submit arbitrary data as a packet.

The recent-address list is server-side state so that all clients see the same
list. It is held in memory unless persistence is explicitly added later. The
list starts empty when the application starts.

## Remote connection

- The server reads `remote-host.txt` at startup. The file must contain exactly
  one non-empty line in `host:port` format, where `host` is the remote host
  name or address and `port` is a numeric TCP port.
- The server must reject missing, malformed, or ambiguous `remote-host.txt`
  files and report the configuration error at startup. Whitespace surrounding
  the host or port may be ignored, but additional non-empty lines are invalid.
- The server maintains a TCP connection to the host and port from
  `remote-host.txt`.
- Packets sent and received on this connection must follow `Accessory-packet.md`.
- `Accessory-packet.md` is a required project document and must define packet
  framing, the address and state encoding, acknowledgements, and error
  handling. No packet format may be inferred from this file alone.
- When a valid action is submitted, the server sends exactly one packet for
  that action.
- If the connection is unavailable or the packet cannot be sent, the action
  fails with an error response and must not be added to the recent-address
  list.
- The server must handle remote disconnects without crashing and must retry or
  report the failure according to the reconnect policy documented with the
  implementation.

## Configuration and operational requirements

- The web-server bind address, web-server port, and valid turnout-address range
  must be configurable.
- `remote-host.txt` must be supplied with the application and must not contain
  credentials or other settings.
- Configuration errors must be reported at startup.
- The application must log connection failures and failed submissions without
  logging sensitive configuration values.
- The application must run on Lua 5.4, as specified by the development
  container.
