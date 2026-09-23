#!/usr/bin/lua

local socket = require("socket")

local function trim(value)
  return value:match("^%s*(.-)%s*$")
end

local function configuration_number(name, default, minimum, maximum)
  local raw = os.getenv(name) or default
  local value
  if type(raw) == "number" then
    value = raw
  elseif raw:match("^0[xX]%x+$") then
    value = tonumber(raw:sub(3), 16)
  else
    value = tonumber(raw)
  end
  if not value or value ~= math.floor(value) or value < minimum or value > maximum then
    error(name .. " must be an integer between " .. minimum .. " and " .. maximum)
  end
  return value
end

local function read_remote_host(path)
  local file, open_error = io.open(path, "r")
  if not file then error("cannot read " .. path .. ": " .. open_error) end
  local lines = {}
  for raw_line in file:lines() do
    local line = trim(raw_line)
    if line ~= "" then lines[#lines + 1] = line end
  end
  file:close()
  if #lines ~= 1 then error(path .. " must contain exactly one non-empty host:port line") end
  local host, port_text = lines[1]:match("^([^:]+):(%d+)$")
  local port = port_text and tonumber(port_text)
  if not host or not port or port < 1 or port > 65535 then
    error(path .. " must use host:port format with a TCP port from 1 to 65535")
  end
  return host, port
end

local config = {
  address_min = configuration_number("ADDRESS_MIN", 1, 1, 1024),
  address_max = configuration_number("ADDRESS_MAX", 1024, 1, 1024),
  uid = configuration_number("CAN_UID", "0x00004711", 0, 0xffffffff),
  remote_file = os.getenv("REMOTE_HOST_FILE") or "/www/cgi-bin/remote-host.txt",
  recent_file = os.getenv("RECENT_FILE") or "/tmp/weichenweb-recent.txt",
}
if config.address_min > config.address_max then error("ADDRESS_MIN must not be greater than ADDRESS_MAX") end
config.remote_host, config.remote_port = read_remote_host(config.remote_file)

local function read_recent()
  local file = io.open(config.recent_file, "r")
  if not file then return {} end
  local addresses = {}
  for line in file:lines() do
    local address = tonumber(trim(line))
    if address and address == math.floor(address)
        and address >= config.address_min and address <= config.address_max then
      addresses[#addresses + 1] = address
      if #addresses == 10 then break end
    end
  end
  file:close()
  return addresses
end

local recent = read_recent()
local function remember(address)
  for index, value in ipairs(recent) do
    if value == address then table.remove(recent, index); break end
  end
  table.insert(recent, 1, address)
  while #recent > 10 do table.remove(recent) end
  local temporary = config.recent_file .. ".tmp"
  local file, open_error = io.open(temporary, "w")
  if not file then return nil, open_error end
  for _, value in ipairs(recent) do file:write(value, "\n") end
  file:close()
  local renamed, rename_error = os.rename(temporary, config.recent_file)
  if not renamed then return nil, rename_error end
  return true
end

local function int_bytes(value)
  return string.char(
    math.floor(value / 0x1000000) % 0x100,
    math.floor(value / 0x10000) % 0x100,
    math.floor(value / 0x100) % 0x100,
    value % 0x100)
end

local function xor16(left, right)
  local result, bit = 0, 1
  while bit <= 0x8000 do
    if left % 2 ~= right % 2 then result = result + bit end
    left = math.floor(left / 2)
    right = math.floor(right / 2)
    bit = bit * 2
  end
  return result
end

local function accessory_hash(uid)
  local raw_hash = xor16(math.floor(uid / 0x10000), uid % 0x10000)
  -- CS1 uses bits 9..7 as 110; preserve the other hash bits.
  return math.floor(raw_hash / 0x400) * 0x400 + raw_hash % 0x80 + 0x300
end

local function accessory_packet(address, state)
  local loc_id = 0x3000 + address - 1
  local state_byte = state == "R" and 0x00 or 0x01
  local hash = accessory_hash(config.uid)
  local can_id = 4 * 2 ^ 25 + 0x16 * 2 ^ 16 + hash
  return int_bytes(can_id) .. string.char(0x06) .. int_bytes(loc_id)
    .. string.char(state_byte, 0x01, 0x00, 0x00)
end

local remote_socket
local function close_remote()
  if remote_socket then remote_socket:close(); remote_socket = nil end
end

local function send_all(connection, data)
  local position = 1
  while position <= #data do
    local sent, send_error, partial = connection:send(data, position)
    position = position + (sent or partial or 0)
    if not sent then return nil, send_error end
  end
  return true
end

local function send_accessory(address, state)
  if not remote_socket then
    local connection, socket_error = socket.tcp()
    if not connection then return nil, socket_error end
    connection:settimeout(2)
    local connected, connect_error = connection:connect(config.remote_host, config.remote_port)
    if not connected then connection:close(); return nil, connect_error end
    remote_socket = connection
  end
  local sent, send_error = send_all(remote_socket, accessory_packet(address, state))
  if not sent then close_remote(); return nil, send_error end
  return true
end

local function html_escape(value)
  return tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;")
    :gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;")
end

local function page()
  local entries = {}
  for _, address in ipairs(recent) do
    entries[#entries + 1] = string.format(
      '<li><span>Turnout %s</span><button class="red" onclick="sendTurnout(%d, \'R\')">Red</button><button class="green" onclick="sendTurnout(%d, \'G\')">Green</button></li>',
      html_escape(address), address, address)
  end
  local list = #entries > 0 and table.concat(entries, "\n") or "<li>No turnouts controlled yet.</li>"
  local script_name = os.getenv("SCRIPT_NAME") or ""
  local api_url = script_name .. "/api/turnout"
  return [[<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Turnout control</title>
<style>body{font:16px system-ui,sans-serif;max-width:42rem;margin:2rem auto;padding:0 1rem;color:#17202a}ul{padding:0;list-style:none}li{display:flex;gap:.5rem;align-items:center;margin:.6rem 0}li span{flex:1}button{border:0;border-radius:.35rem;color:#fff;padding:.65rem 1rem;font-weight:600;cursor:pointer}.red{background:#c0392b}.green{background:#16803c}input{font-size:1rem;padding:.6rem;width:8rem}.entry{border-top:1px solid #ddd;margin-top:2rem;padding-top:1rem}</style>
</head><body><h1>Turnout control</h1><h2>Recent turnouts</h2><ul>]] .. list .. [[</ul>
<div class="entry"><h2>Address</h2><input id="address" type="number" min="]] .. config.address_min .. [[" max="]] .. config.address_max .. [[" step="1">
<button class="red" onclick="submitAddress('R')">Red</button><button class="green" onclick="submitAddress('G')">Green</button></div>
 <script>async function sendTurnout(address,state){const response=await fetch(']] .. html_escape(api_url) .. [[',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'address='+encodeURIComponent(address)+'&state='+state});const result=await response.json();if(!response.ok){alert(result.error);return;}location.reload();}function submitAddress(state){const input=document.getElementById('address');if(!input.value){alert('Enter a turnout address.');return;}sendTurnout(input.value,state);}</script></body></html>]]
end

local function url_decode(value)
  return value:gsub("+", " "):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
end

local function form_values(body)
  local values = {}
  for pair in body:gmatch("[^&]+") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    if key then values[url_decode(key)] = url_decode(value) end
  end
  return values
end

local function json_error(message)
  return '{"error":"' .. message:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"}'
end

local function response(status, content_type, body)
  io.write("Status: " .. status .. "\r\nContent-Type: " .. content_type
    .. "\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body)
end

local function handle_request()
  local method = os.getenv("REQUEST_METHOD") or ""
  local path = os.getenv("PATH_INFO") or "/"
  local content_length = tonumber(os.getenv("CONTENT_LENGTH") or "0") or -1
  if content_length < 0 or content_length > 8192 then
    response("413 Payload Too Large", "application/json", json_error("invalid request body")); return
  end
  local body = content_length > 0 and io.read(content_length) or ""
  if content_length > 0 and (not body or #body ~= content_length) then
    response("400 Bad Request", "application/json", json_error("incomplete request body")); return
  end
  if method == "GET" and path == "/" then
    response("200 OK", "text/html; charset=utf-8", page())
  elseif method == "POST" and path == "/api/turnout" then
    local values = form_values(body or "")
    local address = tonumber(values.address or "")
    local state = values.state and values.state:upper()
    if not address or address ~= math.floor(address) or address < config.address_min or address > config.address_max then
      response("400 Bad Request", "application/json", json_error("address must be an integer in the configured range"))
    elseif state ~= "R" and state ~= "G" then
      response("400 Bad Request", "application/json", json_error("state must be R or G"))
    else
      local sent, send_error = send_accessory(address, state)
      if not sent then
        io.stderr:write("turnout send failed: " .. tostring(send_error) .. "\n")
        response("503 Service Unavailable", "application/json", json_error("remote connection unavailable"))
      else
        local remembered, remember_error = remember(address)
        if not remembered then
          io.stderr:write("recent-address state failed: " .. tostring(remember_error) .. "\n")
          response("500 Internal Server Error", "application/json", json_error("server state unavailable"))
        else
          response("200 OK", "application/json", '{"ok":true}')
        end
      end
    end
  else
    response("404 Not Found", "application/json", json_error("not found"))
  end
end

handle_request()
