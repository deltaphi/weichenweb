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

local function accessory_packet(address, state, power)
  local loc_id = 0x3000 + address - 1
  local state_byte = state == "R" and 0x00 or 0x01
  local hash = accessory_hash(config.uid)
  local can_id = 4 * 2 ^ 25 + 0x16 * 2 ^ 16 + hash
  return int_bytes(can_id) .. string.char(0x06) .. int_bytes(loc_id)
    .. string.char(state_byte, power, 0x00, 0x00)
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

local function send_accessory(address, state, power)
  if not remote_socket then
    local connection, socket_error = socket.tcp()
    if not connection then return nil, socket_error end
    connection:settimeout(2)
    local connected, connect_error = connection:connect(config.remote_host, config.remote_port)
    if not connected then connection:close(); return nil, connect_error end
    remote_socket = connection
  end
  local sent, send_error = send_all(remote_socket, accessory_packet(address, state, power))
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
 <script>async function sendTurnout(address,direction){const response=await fetch(']] .. html_escape(api_url) .. [[',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({address:Number(address),direction:direction,power:1})});const result=await response.json();if(!response.ok){alert(result.error);return;}location.reload();}function submitAddress(direction){const input=document.getElementById('address');if(!input.value){alert('Enter a turnout address.');return;}sendTurnout(input.value,direction);}</script></body></html>]]
end

local function json_values(body)
  if not body:match("^%s*{.*}%s*$") then
    return nil, "request body must be a JSON object"
  end
  local values = {}
  local quoted = {}
  for key in body:gmatch('"([%w_]+)"%s*:') do
    if key ~= "address" and key ~= "direction" and key ~= "power" then
      return nil, "unknown JSON field: " .. key
    end
  end
  for key, value in body:gmatch('"([%w_]+)"%s*:%s*"([^"]*)"') do
    if values[key] then return nil, "duplicate JSON field: " .. key end
    values[key] = value
    quoted[key] = true
  end
  for key, value in body:gmatch('"([%w_]+)"%s*:%s*(-?%d+)') do
    if values[key] then return nil, "duplicate JSON field: " .. key end
    values[key] = value
  end
  if not values.address or not values.direction or not values.power then
    return nil, "request must contain address, direction, and power"
  end
  if quoted.address or quoted.power or not quoted.direction then
    return nil, "address and power must be integers; direction must be a string"
  end
  return values
end

local function json_string(value)
  return '"' .. tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"')
    :gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
end

local function swagger_spec()
  local script_name = os.getenv("SCRIPT_NAME") or "/cgi-bin/weichenweb"
  return [[{
  "openapi":"3.0.3",
  "info":{"title":"Weichenweb API","version":"1.0.0"},
  "servers":[{"url":]] .. json_string(script_name) .. [[}],
  "paths":{
    "/api/turnout":{
      "post":{
        "summary":"Switch a turnout",
        "operationId":"switchTurnout",
        "requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/TurnoutRequest"},"example":{"address":3,"direction":"red","power":1}}}},
        "responses":{"200":{"description":"Packet sent","content":{"application/json":{"schema":{"$ref":"#/components/schemas/Success"}}}},"400":{"description":"Invalid request"},"500":{"description":"Recent state unavailable"},"503":{"description":"Remote connection unavailable"}}
      }
    }
  },
  "components":{"schemas":{
    "TurnoutRequest":{"type":"object","required":["address","direction","power"],"additionalProperties":false,"properties":{"address":{"type":"integer","minimum":]] .. config.address_min .. [[,"maximum":]] .. config.address_max .. [[},"direction":{"type":"string","enum":["red","green"]},"power":{"type":"integer","enum":[0,1],"description":"0 = off, 1 = on"}}},
    "Success":{"type":"object","required":["ok"],"properties":{"ok":{"type":"boolean","example":true}}}
  }}
}]]
end

local function swagger_page()
  local script_name = os.getenv("SCRIPT_NAME") or "/cgi-bin/weichenweb"
  local spec_url = script_name .. "/swagger.json"
  return [[<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Weichenweb API</title>
<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
</head><body><div id="swagger-ui"></div>
<script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
<script>window.onload=function(){window.ui=SwaggerUIBundle({url:']] .. html_escape(spec_url) .. [[',dom_id:'#swagger-ui'});};</script>
</body></html>]]
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
  elseif method == "GET" and path == "/swagger" then
    response("200 OK", "text/html; charset=utf-8", swagger_page())
  elseif method == "GET" and path == "/swagger.json" then
    response("200 OK", "application/json", swagger_spec())
  elseif method == "POST" and path == "/api/turnout" then
    local values, parse_error = json_values(body or "")
    if not values then
      response("400 Bad Request", "application/json", json_error(parse_error))
      return
    end
    local address = tonumber(values.address or "")
    local direction = values.direction
    local power = tonumber(values.power or "")
    local state = direction == "red" and "R" or direction == "green" and "G"
    if not address or address ~= math.floor(address) or address < config.address_min or address > config.address_max then
      response("400 Bad Request", "application/json", json_error("address must be an integer in the configured range"))
    elseif not state then
      response("400 Bad Request", "application/json", json_error("direction must be red or green"))
    elseif not power or power ~= math.floor(power) or (power ~= 0 and power ~= 1) then
      response("400 Bad Request", "application/json", json_error("power must be integer 0 or 1"))
    else
      local sent, send_error = send_accessory(address, state, power)
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
