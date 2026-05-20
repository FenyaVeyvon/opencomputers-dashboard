local event = require("event")
local computer = require("computer")
package.path = "/home/eonlink/?.lua;/home/eonlink/?/init.lua;" .. package.path
local logger = require("core.logger")
local net_tcp = require("core.net_tcp")
local auth = require("core.auth")
local gui = require("core.gui")

local configPath = "/home/eonlink/config.lua"
local configFn, configErr = loadfile(configPath)
if not configFn then error("config load failed: " .. tostring(configErr)) end
local config = configFn()
config.nodeId = config.nodeId or config.deviceId or "base_pc_1"
config.backend = config.backend or {}
config.backend.host = config.backend.host or "open.eonhorizon.net"
config.backend.port = config.backend.port or 4444
config.backend.token = config.backend.token or "change-me"
config.backend.nodeId = config.nodeId

local log = logger.new(config.debug)
local serverConfig = { members = {} }
local logs = {}
local function addLog(msg)
  logs[#logs + 1] = os.date("%H:%M:%S") .. " " .. tostring(msg)
  while #logs > 8 do table.remove(logs, 1) end
end

local net = net_tcp.new(config.backend, log)
local configVersion = 0
local lastReconnect = 0

local function hello()
  local ok, err = net:send({ t = "hello", node = config.nodeId, token = config.backend.token })
  if not ok then addLog("hello failed: " .. tostring(err)) end
end

local function ensureConnected()
  if net:isConnected() then return end
  local now = computer.uptime()
  if now - lastReconnect < 3 then return end
  lastReconnect = now
  local ok, err = net:connect()
  if ok then
    addLog("connected")
    hello()
  else
    addLog("connect failed: " .. tostring(err))
  end
end

local function applyNodeConfig(remote)
  if type(remote) ~= "table" then return end
  if remote.configVersion and remote.configVersion == configVersion then return end
  configVersion = remote.configVersion or configVersion
  if type(remote.members) == "table" then serverConfig.members = remote.members end
  auth.apply(serverConfig, log)
  addLog("config v" .. tostring(configVersion) .. " applied")
end

local function draw()
  gui.draw({
    node = config.nodeId,
    host = config.backend.host,
    port = config.backend.port,
    members = serverConfig.members,
    configVersion = configVersion,
    connected = net:isConnected(),
    status = net:isConnected() and "online" or "offline",
    logs = logs
  })
end

local last = os.clock()
local lastConfig = 0
local lastDraw = 0
while true do
  ensureConnected()
  local now = os.clock()
  local msg = net:poll()
  if msg and msg.t == "config" then applyNodeConfig(msg) end
  if net:isConnected() and now - lastConfig > 5 then
    local okConfig, errConfig = net:send({ t = "config_get", node = config.nodeId, token = config.backend.token })
    if not okConfig then addLog("config_get failed: " .. tostring(errConfig)) end
    local okLog, errLog = net:send({ t = "log", node = config.nodeId, level = "info", message = "heartbeat" })
    if not okLog then addLog("log failed: " .. tostring(errLog)) end
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
