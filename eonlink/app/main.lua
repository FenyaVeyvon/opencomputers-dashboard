local event = require("event")
package.path = "/home/eonlink/?.lua;/home/eonlink/?/init.lua;" .. package.path
local logger = require("core.logger")
local net_tcp = require("core.net_tcp")
local auth = require("core.auth")
local gui = require("core.gui")
local fsutil = require("core.fsutil")

local configPath = "/home/eonlink/config.lua"
local configFn, configErr = loadfile(configPath)
if not configFn then error("config load failed: " .. tostring(configErr)) end
local config = configFn()
config.nodeId = config.nodeId or config.deviceId or "base_pc_1"
config.members = config.members or {}
config.backend.nodeId = config.nodeId

local log = logger.new(config.debug)
local logs = {}
local function addLog(msg)
  logs[#logs + 1] = os.date("%H:%M:%S") .. " " .. tostring(msg)
  while #logs > 8 do table.remove(logs, 1) end
end

local net = net_tcp.new(config.backend, log)
local configVersion = 0

local function hello()
  net:send({ t = "hello", node = config.nodeId, token = config.backend.token })
end

local function ensureConnected()
  if net:isConnected() then return end
  if net:connect() then
    addLog("connected")
    hello()
  end
end

local function saveRuntimeConfig()
  local out = {
    "return {",
    "  nodeId = " .. string.format("%q", config.nodeId) .. ",",
    "",
    "  backend = {",
    "    host = " .. string.format("%q", config.backend.host) .. ",",
    "    port = " .. tostring(config.backend.port) .. ",",
    "    token = " .. string.format("%q", config.backend.token),
    "  },",
    "",
    "  members = {"
  }
  for _, name in ipairs(config.members or {}) do
    out[#out + 1] = "    " .. string.format("%q", name) .. ","
  end
  out[#out + 1] = "  },"
  out[#out + 1] = ""
  out[#out + 1] = "  debug = " .. tostring(config.debug and true or false)
  out[#out + 1] = "}"
  fsutil.writeAtomic(configPath, table.concat(out, "\n") .. "\n")
end

local function applyNodeConfig(remote)
  if type(remote) ~= "table" then return end
  if remote.configVersion and remote.configVersion == configVersion then return end
  configVersion = remote.configVersion or configVersion
  if type(remote.members) == "table" then config.members = remote.members end
  auth.apply(config, log)
  saveRuntimeConfig()
  addLog("config v" .. tostring(configVersion) .. " applied")
end

local function draw()
  gui.draw({
    node = config.nodeId,
    host = config.backend.host,
    port = config.backend.port,
    members = config.members,
    configVersion = configVersion,
    connected = net:isConnected(),
    status = net:isConnected() and "online" or "offline",
    logs = logs
  })
end

local last = os.clock()
local lastConfig = 0
local lastDraw = 0
auth.apply(config, log)
while true do
  ensureConnected()
  local now = os.clock()
  local msg = net:poll()
  if msg and msg.t == "config" then applyNodeConfig(msg) end
  if net:isConnected() and now - lastConfig > 5 then
    net:send({ t = "config_get", node = config.nodeId, token = config.backend.token })
    net:send({ t = "log", node = config.nodeId, level = "info", message = "heartbeat" })
    lastConfig = now
  end
  if now - lastDraw > 1 then
    draw()
    lastDraw = now
  end
  local dt = now - last
  last = now
  event.pull(0.05)
end
