local event = require("event")
package.path = "/home/eonlink/?.lua;/home/eonlink/?/init.lua;" .. package.path
local logger = require("core.logger")
local net_tcp = require("core.net_tcp")
local event_bus = require("core.event_bus")
local state = require("core.state")
local module_loader = require("core.module_loader")

local configPath = "/home/eonlink/config.lua"
local configFn, configErr = loadfile(configPath)
if not configFn then error("config load failed: " .. tostring(configErr)) end
local config = configFn()

local log = logger.new(config.debug)
local ctx = {
  config = config,
  log = log,
  bus = event_bus.new(),
  state = state.new()
}

ctx.net = net_tcp.new(config.backend, log)
local modules = module_loader.load(config, ctx)

local function hello()
  ctx.net:send({ t = "hello", id = config.deviceId, token = config.backend.token })
end

local function ensureConnected()
  if ctx.net:isConnected() then return end
  if ctx.net:connect() then hello() end
end

local last = os.clock()
while true do
  ensureConnected()
  local msg = ctx.net:poll()
  if msg then module_loader.dispatchMessage(modules, msg) end
  local now = os.clock()
  local dt = now - last
  last = now
  module_loader.tickAll(modules, dt)
  event.pull(0.05)
end
