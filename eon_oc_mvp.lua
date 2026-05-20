-- eon_oc_mvp.lua
-- Eon OpenComputers Dashboard + API telemetry + remote config
-- Target telemetry: https://open.eonhorizon.net/api/oc/telemetry
-- Target config:    https://open.eonhorizon.net/api/oc/config?node=<node>
--
-- Main:
-- - chat log with correct username/message parsing
-- - @status / @online / @api / @config / @help / @exit
-- - online/seen players
-- - ME items by id
-- - Flux Network stats
-- - POST telemetry every 1 second by default
-- - pulls config from backend every 10 seconds by default
-- - no full-screen flicker: static UI once, dynamic cells only when changed

local component = require("component")
local computer = require("computer")
local event = require("event")
local filesystem = require("filesystem")
local term = require("term")
local unicode = require("unicode")

local hasInternet, internet = pcall(require, "internet")
local unpack = table.unpack or _G.unpack

local VERSION = "0.4.0"
local CONFIG_PATH = "/etc/eon_dashboard.cfg"

local cfg = {
  node = "main-base",

  owner = "FenyaVeyvon",
  members = { "ElliEmerald" },

  scanRange = 64,
  tick = 0.5,                 -- 10 MC ticks ~= 0.5s
  fullScanEvery = 1.0,
  meScanEvery = 2.0,
  fluxScanEvery = 1.0,

  telemetryEnabled = true,
  telemetryUrl = "https://open.eonhorizon.net/api/oc/telemetry",
  telemetryToken = "CHANGE_ME_SECRET",
  telemetryEvery = 1.0,

  remoteConfigEnabled = true,
  configUrl = "https://open.eonhorizon.net/api/oc/config",
  configEvery = 10.0,
  configVersion = 0,

  playerTTL = 300,
  chatboxName = "§bEon§7Dash",
  maxChat = 30,
  maxLogs = 20,
  maxItems = 500,
  topItems = 12
}

local state = {
  exit = false,
  startedAt = computer.uptime(),

  lastFullScan = 0,
  lastMEScan = 0,
  lastFluxScan = 0,
  lastTelemetry = 0,
  lastConfigPull = -999,

  logs = {},
  chat = {},
  players = {},

  onlineExact = false,
  components = 0,

  api = {
    enabled = false,
    ok = false,
    lastStatus = "not sent",
    lastResponse = "",
    lastError = nil,
    lastSentAt = 0,
    sent = 0,
    failed = 0
  },

  configApi = {
    enabled = false,
    ok = false,
    lastStatus = "not pulled",
    lastError = nil,
    lastPulledAt = 0,
    pulled = 0,
    failed = 0
  },

  me = {
    ok = false,
    source = "-",
    address = "-",
    storedPower = nil,
    maxPower = nil,
    usage = nil,
    totalStacks = 0,
    totalItems = 0,
    top = {},
    ores = {}
  },

  flux = {
    ok = false,
    source = "-",
    address = "-",
    stored = nil,
    max = nil,
    input = nil,
    output = nil
  }
}

local gpu = nil
local screen = {}
local layoutDrawn = false
local chatbox = nil

local colors = {
  bg = 0x0b0f14,
  panel = 0x111827,
  border = 0x334155,
  title = 0x60a5fa,
  text = 0xe5e7eb,
  muted = 0x94a3b8,
  good = 0x22c55e,
  warn = 0xf59e0b,
  bad = 0xef4444,
  cyan = 0x06b6d4,
  purple = 0xa78bfa,
  button = 0x1f2937
}

-- -------------------------
-- Config
-- -------------------------

local function splitCSV(s)
  local out = {}
  s = tostring(s or "")

  for part in s:gmatch("[^,]+") do
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    if part ~= "" then table.insert(out, part) end
  end

  return out
end

local function boolValue(v)
  v = tostring(v or ""):lower()
  return v == "1" or v == "true" or v == "yes" or v == "on"
end

local function writeDefaultConfig()
  if filesystem.exists(CONFIG_PATH) then return end

  local f = io.open(CONFIG_PATH, "w")
  if not f then return end

  f:write("# Eon OpenComputers Dashboard local fallback config\n")
  f:write("# Backend config overrides these values from /api/oc/config\n")
  f:write("node=main-base\n")
  f:write("owner=FenyaVeyvon\n")
  f:write("members=ElliEmerald\n")
  f:write("scan_range=64\n")
  f:write("tick=0.5\n")
  f:write("full_scan_every=1\n")
  f:write("me_scan_every=2\n")
  f:write("flux_scan_every=1\n")
  f:write("player_ttl=300\n")
  f:write("chatbox_name=§bEon§7Dash\n")
  f:write("max_chat=30\n")
  f:write("max_logs=20\n")
  f:write("max_items=500\n")
  f:write("top_items=12\n")
  f:write("telemetry_enabled=true\n")
  f:write("telemetry_url=https://open.eonhorizon.net/api/oc/telemetry\n")
  f:write("telemetry_token=CHANGE_ME_SECRET\n")
  f:write("telemetry_every=1\n")
  f:write("remote_config_enabled=true\n")
  f:write("config_url=https://open.eonhorizon.net/api/oc/config\n")
  f:write("config_every=10\n")
  f:close()
end

local function loadConfig()
  writeDefaultConfig()

  local f = io.open(CONFIG_PATH, "r")
  if not f then return end

  for line in f:lines() do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")

    if line ~= "" and line:sub(1, 1) ~= "#" then
      local k, v = line:match("^([%w_%-%.]+)%s*=%s*(.+)$")

      if k and v then
        if k == "node" then cfg.node = v
        elseif k == "owner" then cfg.owner = v
        elseif k == "members" then cfg.members = splitCSV(v)

        elseif k == "scan_range" then cfg.scanRange = tonumber(v) or cfg.scanRange
        elseif k == "tick" then cfg.tick = tonumber(v) or cfg.tick
        elseif k == "full_scan_every" then cfg.fullScanEvery = tonumber(v) or cfg.fullScanEvery
        elseif k == "me_scan_every" then cfg.meScanEvery = tonumber(v) or cfg.meScanEvery
        elseif k == "flux_scan_every" then cfg.fluxScanEvery = tonumber(v) or cfg.fluxScanEvery
        elseif k == "player_ttl" then cfg.playerTTL = tonumber(v) or cfg.playerTTL

        elseif k == "chatbox_name" then cfg.chatboxName = v
        elseif k == "max_chat" then cfg.maxChat = tonumber(v) or cfg.maxChat
        elseif k == "max_logs" then cfg.maxLogs = tonumber(v) or cfg.maxLogs
        elseif k == "max_items" then cfg.maxItems = tonumber(v) or cfg.maxItems
        elseif k == "top_items" then cfg.topItems = tonumber(v) or cfg.topItems

        elseif k == "telemetry_enabled" then cfg.telemetryEnabled = boolValue(v)
        elseif k == "telemetry_url" then cfg.telemetryUrl = v
        elseif k == "telemetry_token" then cfg.telemetryToken = v
        elseif k == "telemetry_every" then cfg.telemetryEvery = tonumber(v) or cfg.telemetryEvery

        elseif k == "remote_config_enabled" then cfg.remoteConfigEnabled = boolValue(v)
        elseif k == "config_url" then cfg.configUrl = v
        elseif k == "config_every" then cfg.configEvery = tonumber(v) or cfg.configEvery
        end
      end
    end
  end

  f:close()
end

local function isOwner(name)
  return tostring(name or "") == cfg.owner
end

local function isMember(name)
  name = tostring(name or "")
  if name == cfg.owner then return true end

  for _, n in ipairs(cfg.members) do
    if name == n then return true end
  end

  return false
end

local function syncUsers()
  pcall(computer.addUser, cfg.owner)

  for _, name in ipairs(cfg.members) do
    pcall(computer.addUser, name)
  end
end

-- -------------------------
-- Utils
-- -------------------------

local function uptime()
  return math.floor(computer.uptime())
end

local function clock()
  local t = uptime()
  local h = math.floor(t / 3600)
  local m = math.floor((t % 3600) / 60)
  local s = t % 60
  return string.format("%02d:%02d:%02d", h, m, s)
end

local function addLog(kind, msg)
  table.insert(state.logs, "[" .. clock() .. "][" .. tostring(kind) .. "] " .. tostring(msg))

  while #state.logs > cfg.maxLogs do
    table.remove(state.logs, 1)
  end
end

local function addChat(player, msg, uuid)
  table.insert(state.chat, {
    time = uptime(),
    text = "[" .. clock() .. "] <" .. tostring(player) .. "> " .. tostring(msg),
    player = tostring(player),
    message = tostring(msg),
    uuid = uuid and tostring(uuid) or nil
  })

  while #state.chat > cfg.maxChat do
    table.remove(state.chat, 1)
  end
end

local function cut(text, width)
  text = tostring(text or "")

  if unicode.len(text) <= width then return text end
  if width <= 3 then return unicode.sub(text, 1, width) end

  return unicode.sub(text, 1, width - 3) .. "..."
end

local function pad(text, width)
  text = cut(text, width)
  local l = unicode.len(text)

  if l < width then
    return text .. string.rep(" ", width - l)
  end

  return text
end

local function fmt(n)
  n = tonumber(n or 0) or 0

  if n >= 1000000000000 then return string.format("%.2fT", n / 1000000000000) end
  if n >= 1000000000 then return string.format("%.2fB", n / 1000000000) end
  if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
  if n >= 1000 then return string.format("%.2fK", n / 1000) end

  return tostring(math.floor(n))
end

local function isUuidLike(s)
  s = tostring(s or "")
  if s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
    return true
  end

  if s:match("^[0-9a-fA-F%-]+$") and unicode.len(s) >= 20 then
    return true
  end

  return false
end

local function encodeUrl(s)
  s = tostring(s or "")
  s = s:gsub("([^%w%-%_%.%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return s
end

-- -------------------------
-- JSON encode + tiny config JSON reader
-- -------------------------

local function jsonEscape(str)
  str = tostring(str or "")
  str = str:gsub("\\", "\\\\")
  str = str:gsub('"', '\\"')
  str = str:gsub("\n", "\\n")
  str = str:gsub("\r", "\\r")
  str = str:gsub("\t", "\\t")
  return str
end

local function isArray(t)
  local count = 0
  local max = 0

  for k, _ in pairs(t) do
    if type(k) ~= "number" then return false end
    count = count + 1
    if k > max then max = k end
  end

  return max == count
end

local function json(value)
  local t = type(value)

  if t == "nil" then return "null" end
  if t == "boolean" then return value and "true" or "false" end
  if t == "number" then return tostring(value) end
  if t == "string" then return '"' .. jsonEscape(value) .. '"' end

  if t == "table" then
    local out = {}

    if isArray(value) then
      for i = 1, #value do out[#out + 1] = json(value[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end

    for k, v in pairs(value) do
      out[#out + 1] = json(tostring(k)) .. ":" .. json(v)
    end

    return "{" .. table.concat(out, ",") .. "}"
  end

  return json(tostring(value))
end

local function unescapeJsonString(s)
  s = tostring(s or "")
  s = s:gsub('\\"', '"')
  s = s:gsub("\\\\", "\\")
  s = s:gsub("\\n", "\n")
  s = s:gsub("\\r", "\r")
  s = s:gsub("\\t", "\t")
  return s
end

local function jsonString(src, key)
  local patterns = {
    '"' .. key .. '"%s*:%s*"([^"]*)"',
    '"' .. key:gsub("_", "") .. '"%s*:%s*"([^"]*)"'
  }

  for _, p in ipairs(patterns) do
    local v = src:match(p)
    if v ~= nil then return unescapeJsonString(v) end
  end

  return nil
end

local function jsonNumber(src, key)
  local v = src:match('"' .. key .. '"%s*:%s*([%-%.%d]+)')
  if v ~= nil then return tonumber(v) end
  return nil
end

local function jsonBool(src, key)
  local v = src:match('"' .. key .. '"%s*:%s*(true)')
  if v ~= nil then return true end

  v = src:match('"' .. key .. '"%s*:%s*(false)')
  if v ~= nil then return false end

  return nil
end

local function jsonStringArray(src, key)
  local raw = src:match('"' .. key .. '"%s*:%s*%[([^%]]*)%]')
  if not raw then return nil end

  local out = {}
  for item in raw:gmatch('"([^"]*)"') do
    table.insert(out, unescapeJsonString(item))
  end

  return out
end

-- -------------------------
-- GPU render without flicker
-- -------------------------

local function initGPU()
  if not component.isAvailable("gpu") then
    print("No GPU found.")
    return false
  end

  gpu = component.gpu

  local maxW, maxH = gpu.maxResolution()
  pcall(gpu.setResolution, maxW, maxH)

  gpu.setBackground(colors.bg)
  gpu.setForeground(colors.text)
  gpu.fill(1, 1, maxW, maxH, " ")

  screen = {}
  return true
end

local function setCell(x, y, text, fg, bg)
  if not gpu then return end

  fg = fg or colors.text
  bg = bg or colors.panel
  text = tostring(text or "")

  local key = x .. ":" .. y
  local sig = text .. "|" .. tostring(fg) .. "|" .. tostring(bg)

  if screen[key] == sig then return end

  screen[key] = sig

  gpu.setForeground(fg)
  gpu.setBackground(bg)
  gpu.set(x, y, text)
end

local function fill(x, y, w, h, ch, bg)
  if not gpu then return end

  gpu.setBackground(bg or colors.panel)
  gpu.fill(x, y, w, h, ch or " ")

  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do
      screen[xx .. ":" .. yy] = nil
    end
  end
end

local function line(x, y, w, text, fg, bg)
  setCell(x, y, pad(text, w), fg or colors.text, bg or colors.panel)
end

local function box(x, y, w, h, title)
  fill(x, y, w, h, " ", colors.panel)

  setCell(x, y, "+" .. string.rep("-", w - 2) .. "+", colors.border, colors.panel)

  for yy = y + 1, y + h - 2 do
    setCell(x, yy, "|", colors.border, colors.panel)
    setCell(x + w - 1, yy, "|", colors.border, colors.panel)
  end

  setCell(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", colors.border, colors.panel)

  if title then
    setCell(x + 2, y, " " .. title .. " ", colors.title, colors.panel)
  end
end

local function clearInside(x, y, w, h)
  for yy = y, y + h - 1 do
    line(x, yy, w, "", colors.text, colors.panel)
  end
end

-- -------------------------
-- Component helpers
-- -------------------------

local function safeMethods(addr)
  local ok, methods = pcall(component.methods, addr)
  if ok and type(methods) == "table" then return methods end
  return {}
end

local function has(methods, name)
  return methods and methods[name] ~= nil
end

local function proxy(addr)
  local ok, p = pcall(component.proxy, addr)
  if ok then return p end
  return nil
end

local function call(p, method, default, ...)
  if not p or not p[method] then return default end

  local ok, result = pcall(p[method], ...)

  if ok and result ~= nil then
    return result
  end

  return default
end

local function callNumber(p, method, default, ...)
  local v = call(p, method, default, ...)
  if v == nil then return default end
  return tonumber(v) or default
end

local function firstNumber(p, methods, names)
  for _, name in ipairs(names) do
    if has(methods, name) and p and p[name] then
      local v = callNumber(p, name, nil)
      if v ~= nil then return v, name end
    end
  end

  return nil, nil
end

-- -------------------------
-- Online / players
-- -------------------------

local function addPlayer(name, source, exact)
  name = tostring(name or "")

  if name == "" or name == "nil" then return end

  state.players[name] = {
    name = name,
    source = source or "seen",
    seen = uptime(),
    exact = exact and true or false
  }

  if exact then state.onlineExact = true end
end

local function normalizePlayerList(list, source, exact)
  if type(list) ~= "table" then return 0 end

  local count = 0

  for _, item in pairs(list) do
    local name = nil

    if type(item) == "string" then
      name = item
    elseif type(item) == "table" then
      name = item.name or item.username or item.player or item.nick or item[1]
    end

    if name then
      addPlayer(name, source, exact)
      count = count + 1
    end
  end

  return count
end

local function scanOnline()
  state.onlineExact = false

  local onlineMethods = {
    "getOnlinePlayers",
    "getPlayerList",
    "getPlayers",
    "getPlayerNames",
    "getOnlinePlayerNames",
    "players"
  }

  for addr, ctype in component.list() do
    local t = tostring(ctype):lower()

    if t:find("online") or t:find("player") or t:find("detector") then
      local methods = safeMethods(addr)
      local p = proxy(addr)

      for _, m in ipairs(onlineMethods) do
        if has(methods, m) then
          local list = call(p, m, nil)
          normalizePlayerList(list, ctype .. "." .. m, true)
        end
      end
    end
  end

  -- OpenSecurity only detects nearby players.
  if component.isAvailable("os_entdetector") then
    local det = component.getPrimary("os_entdetector")
    local ok, players = pcall(det.scanPlayers, math.max(1, math.min(64, cfg.scanRange)))

    if ok then
      normalizePlayerList(players, "os_entdetector", false)
    end
  end

  local t = uptime()

  for name, p in pairs(state.players) do
    if not p.exact and t - p.seen > cfg.playerTTL then
      state.players[name] = nil
    end
  end
end

local function playerArray()
  local out = {}

  for _, p in pairs(state.players) do
    out[#out + 1] = {
      name = p.name,
      source = p.source,
      seen = p.seen,
      age = uptime() - (p.seen or uptime()),
      exact = p.exact and true or false
    }
  end

  table.sort(out, function(a, b)
    return tostring(a.name) < tostring(b.name)
  end)

  return out
end

local function countPlayers()
  local n = 0
  for _ in pairs(state.players) do n = n + 1 end
  return n
end

-- -------------------------
-- ME Network
-- -------------------------

local function itemId(item)
  if type(item) ~= "table" then return tostring(item) end

  local name = item.name or item.id or item.item or "unknown"
  local dmg = item.damage or item.dmg or item.metadata or item.meta

  if dmg ~= nil then
    return tostring(name) .. ":" .. tostring(dmg)
  end

  return tostring(name)
end

local function itemLabel(item)
  if type(item) ~= "table" then return tostring(item) end

  return tostring(item.label or item.displayName or item.display_name or item.name or item.id or "?")
end

local function itemCount(item)
  if type(item) ~= "table" then return 0 end

  return tonumber(item.size or item.amount or item.count or item.qty or 0) or 0
end

local function isOreLike(id, label)
  local s = (tostring(id or "") .. " " .. tostring(label or "")):lower()

  return s:find("ore")
    or s:find("dust")
    or s:find("ingot")
    or s:find("plate")
    or s:find("gem")
    or s:find("crushed")
    or s:find("nugget")
    or s:find("raw")
end

local function findME()
  local preferred = { "me_controller", "me_interface" }

  for _, ctype in ipairs(preferred) do
    if component.isAvailable(ctype) then
      local addr = component.list(ctype)()
      if addr then return addr, ctype end
    end
  end

  for addr, ctype in component.list() do
    local methods = safeMethods(addr)

    if has(methods, "getItemsInNetwork") or has(methods, "getAvailableItems") or has(methods, "getStoredPower") then
      return addr, ctype
    end
  end

  return nil, nil
end

local function scanME()
  local addr, ctype = findME()

  state.me = {
    ok = false,
    source = "-",
    address = "-",
    storedPower = nil,
    maxPower = nil,
    usage = nil,
    totalStacks = 0,
    totalItems = 0,
    top = {},
    ores = {}
  }

  if not addr then return end

  local p = proxy(addr)
  local methods = safeMethods(addr)

  local stored = firstNumber(p, methods, { "getStoredPower", "getEnergyStored", "getEnergy", "getStored" })
  local maxp = firstNumber(p, methods, { "getMaxStoredPower", "getMaxEnergyStored", "getMaxEnergy", "getCapacity" })
  local usage = firstNumber(p, methods, { "getAvgPowerUsage", "getAveragePowerUsage", "getPowerUsage", "getIdlePowerUsage" })

  local items = nil
  local itemMethod = nil

  if has(methods, "getItemsInNetwork") then
    items = call(p, "getItemsInNetwork", nil)
    itemMethod = "getItemsInNetwork"
  elseif has(methods, "getAvailableItems") then
    items = call(p, "getAvailableItems", nil)
    itemMethod = "getAvailableItems"
  elseif has(methods, "getItems") then
    items = call(p, "getItems", nil)
    itemMethod = "getItems"
  end

  local map = {}
  local oreMap = {}
  local stacks = 0
  local total = 0

  if type(items) == "table" then
    for _, item in pairs(items) do
      stacks = stacks + 1
      if stacks > cfg.maxItems then break end

      local id = itemId(item)
      local label = itemLabel(item)
      local count = itemCount(item)

      total = total + count

      if not map[id] then
        map[id] = { id = id, label = label, count = 0 }
      end
      map[id].count = map[id].count + count

      if isOreLike(id, label) then
        if not oreMap[id] then
          oreMap[id] = { id = id, label = label, count = 0 }
        end
        oreMap[id].count = oreMap[id].count + count
      end
    end
  end

  local top = {}
  for _, v in pairs(map) do table.insert(top, v) end
  table.sort(top, function(a, b) return a.count > b.count end)
  while #top > cfg.topItems do table.remove(top) end

  local ores = {}
  for _, v in pairs(oreMap) do table.insert(ores, v) end
  table.sort(ores, function(a, b) return a.count > b.count end)
  while #ores > cfg.topItems do table.remove(ores) end

  state.me.ok = true
  state.me.source = tostring(ctype) .. "." .. tostring(itemMethod or "?")
  state.me.address = tostring(addr)
  state.me.storedPower = stored
  state.me.maxPower = maxp
  state.me.usage = usage
  state.me.totalStacks = stacks
  state.me.totalItems = total
  state.me.top = top
  state.me.ores = ores
end

-- -------------------------
-- Flux Network
-- -------------------------

local function findFlux()
  if component.isAvailable("flux_controller") then
    local addr = component.list("flux_controller")()
    if addr then return addr, "flux_controller" end
  end

  for addr, ctype in component.list() do
    local low = tostring(ctype):lower()
    local methods = safeMethods(addr)

    if low:find("flux")
      or has(methods, "getNetworkEnergy")
      or has(methods, "getEnergyStored")
      or has(methods, "getMaxEnergyStored") then

      -- Avoid ME as generic energy.
      if not has(methods, "getItemsInNetwork") and not has(methods, "getStoredPower") then
        return addr, ctype
      end
    end
  end

  return nil, nil
end

local function scanFlux()
  local addr, ctype = findFlux()

  state.flux = {
    ok = false,
    source = "-",
    address = "-",
    stored = nil,
    max = nil,
    input = nil,
    output = nil
  }

  if not addr then return end

  local p = proxy(addr)
  local methods = safeMethods(addr)

  local stored = firstNumber(p, methods, { "getNetworkEnergy", "getEnergyStored", "getEnergy", "getStored", "getBuffer" })
  local maxv = firstNumber(p, methods, { "getNetworkCapacity", "getMaxEnergyStored", "getMaxEnergy", "getCapacity", "getEnergyCapacity" })
  local input = firstNumber(p, methods, { "getNetworkInput", "getInput", "getAverageInput", "getEnergyInput", "getTransferIn" })
  local output = firstNumber(p, methods, { "getNetworkOutput", "getOutput", "getAverageOutput", "getEnergyOutput", "getTransferOut" })

  state.flux.ok = true
  state.flux.source = tostring(ctype)
  state.flux.address = tostring(addr)
  state.flux.stored = stored
  state.flux.max = maxv
  state.flux.input = input
  state.flux.output = output
end

-- -------------------------
-- ChatBox
-- -------------------------

local function initChatbox()
  chatbox = nil

  if component.isAvailable("chat_box") then
    chatbox = component.chat_box
  elseif component.isAvailable("chatbox") then
    chatbox = component.chatbox
  end

  if chatbox and chatbox.setName then
    pcall(chatbox.setName, cfg.chatboxName)
  end
end

local function say(msg)
  if chatbox and chatbox.say then
    pcall(chatbox.say, tostring(msg))
  end
end

local function statusText()
  local mode = state.onlineExact and "exact" or "seen"

  return "Online(" .. mode .. "): " .. countPlayers()
    .. " | ME: " .. (state.me.ok and (fmt(state.me.totalItems) .. " items/" .. state.me.totalStacks .. " stacks") or "missing")
    .. " | Flux: " .. (state.flux.ok and (fmt(state.flux.stored) .. "/" .. fmt(state.flux.max) .. " RF") or "missing")
    .. " | API: " .. (state.api.ok and "OK" or state.api.lastStatus)
end

local function handleCommand(player, msg)
  msg = tostring(msg or "")

  if msg:sub(1, 1) ~= "@" then return end

  local cmd = msg:match("^(%S+)")
  cmd = tostring(cmd or ""):lower()

  if not isMember(player) then
    say("Нет доступа: " .. tostring(player))
    return
  end

  if cmd == "@status" then
    say(statusText())
  elseif cmd == "@online" then
    local names = {}
    for name in pairs(state.players) do table.insert(names, name) end
    table.sort(names)
    say("Players: " .. (#names > 0 and table.concat(names, ", ") or "none"))
  elseif cmd == "@api" then
    say("API: " .. tostring(state.api.lastStatus) .. " sent=" .. tostring(state.api.sent) .. " failed=" .. tostring(state.api.failed) .. " cfg=" .. tostring(state.configApi.lastStatus))
  elseif cmd == "@config" then
    say("Config: v" .. tostring(cfg.configVersion) .. " scan=" .. tostring(cfg.scanRange) .. " send=" .. tostring(cfg.telemetryEvery) .. "s me=" .. tostring(cfg.meScanEvery) .. "s")
  elseif cmd == "@help" then
    say("Commands: @status, @online, @api, @config, @help" .. (isOwner(player) and ", @exit" or ""))
  elseif cmd == "@exit" then
    if isOwner(player) then
      say("Exit requested by owner " .. player)
      state.exit = true
    else
      say("@exit доступен только owner")
    end
  end
end

local function parseChatEvent(name, args)
  local player = nil
  local msg = nil
  local uuid = nil

  -- Known bad old parse:
  -- chat_message, uuid/componentAddress, username, message
  -- User saw: uuid: FenyaVeyvon
  -- It means args[1] was uuid/address, args[2] username, args[3] real message.
  if name == "chat_message" then
    if type(args[1]) == "string" and type(args[2]) == "string" and type(args[3]) == "string" and isUuidLike(args[1]) then
      uuid = args[1]
      player = args[2]
      msg = args[3]
    elseif type(args[1]) == "string" and type(args[2]) == "string" then
      player = args[1]
      msg = args[2]
    end
  elseif name == "chat" then
    if type(args[1]) == "string" and type(args[2]) == "string" and type(args[3]) == "string" and isUuidLike(args[1]) then
      uuid = args[1]
      player = args[2]
      msg = args[3]
    elseif type(args[1]) == "string" and type(args[2]) == "string" then
      player = args[1]
      msg = args[2]
    end
  end

  if player and msg then
    addPlayer(player, "chatbox", false)
    addChat(player, msg, uuid)
    handleCommand(player, msg)
  else
    addLog("CHAT?", "unknown event args: " .. tostring(args[1]) .. " | " .. tostring(args[2]) .. " | " .. tostring(args[3]))
  end
end

-- -------------------------
-- Remote config / HTTP
-- -------------------------

local function httpRead(handle, limit)
  local response = ""

  for chunk in handle do
    response = response .. tostring(chunk)
    if limit and #response > limit then
      response = response:sub(1, limit)
      break
    end
  end

  return response
end

local function applyRemoteConfig(src)
  if type(src) ~= "string" or src == "" then return false end

  local changed = false

  local s

  s = jsonString(src, "node")
  if s and s ~= "" and s ~= cfg.node then cfg.node = s; changed = true end

  s = jsonString(src, "owner")
  if s and s ~= "" and s ~= cfg.owner then cfg.owner = s; changed = true end

  local arr = jsonStringArray(src, "members")
  if arr then cfg.members = arr; changed = true end

  s = jsonString(src, "chatboxName") or jsonString(src, "chatbox_name")
  if s and s ~= "" and s ~= cfg.chatboxName then
    cfg.chatboxName = s
    initChatbox()
    changed = true
  end

  s = jsonString(src, "telemetryUrl") or jsonString(src, "telemetry_url")
  if s and s ~= "" and s ~= cfg.telemetryUrl then cfg.telemetryUrl = s; changed = true end

  s = jsonString(src, "telemetryToken") or jsonString(src, "telemetry_token")
  if s and s ~= "" and s ~= cfg.telemetryToken then cfg.telemetryToken = s; changed = true end

  s = jsonString(src, "configUrl") or jsonString(src, "config_url")
  if s and s ~= "" and s ~= cfg.configUrl then cfg.configUrl = s; changed = true end

  local n

  n = jsonNumber(src, "scanRange") or jsonNumber(src, "scan_range")
  if n then cfg.scanRange = n; changed = true end

  n = jsonNumber(src, "tick")
  if n then cfg.tick = n; changed = true end

  n = jsonNumber(src, "fullScanEvery") or jsonNumber(src, "full_scan_every")
  if n then cfg.fullScanEvery = n; changed = true end

  n = jsonNumber(src, "meScanEvery") or jsonNumber(src, "me_scan_every")
  if n then cfg.meScanEvery = n; changed = true end

  n = jsonNumber(src, "fluxScanEvery") or jsonNumber(src, "flux_scan_every")
  if n then cfg.fluxScanEvery = n; changed = true end

  n = jsonNumber(src, "telemetryEvery") or jsonNumber(src, "telemetry_every")
  if n then cfg.telemetryEvery = n; changed = true end

  n = jsonNumber(src, "configEvery") or jsonNumber(src, "config_every")
  if n then cfg.configEvery = n; changed = true end

  n = jsonNumber(src, "playerTTL") or jsonNumber(src, "player_ttl")
  if n then cfg.playerTTL = n; changed = true end

  n = jsonNumber(src, "maxChat") or jsonNumber(src, "max_chat")
  if n then cfg.maxChat = n; changed = true end

  n = jsonNumber(src, "maxLogs") or jsonNumber(src, "max_logs")
  if n then cfg.maxLogs = n; changed = true end

  n = jsonNumber(src, "maxItems") or jsonNumber(src, "max_items")
  if n then cfg.maxItems = n; changed = true end

  n = jsonNumber(src, "topItems") or jsonNumber(src, "top_items")
  if n then cfg.topItems = n; changed = true end

  n = jsonNumber(src, "configVersion") or jsonNumber(src, "version")
  if n then cfg.configVersion = n end

  local b

  b = jsonBool(src, "telemetryEnabled")
  if b == nil then b = jsonBool(src, "telemetry_enabled") end
  if b ~= nil then cfg.telemetryEnabled = b; changed = true end

  b = jsonBool(src, "remoteConfigEnabled")
  if b == nil then b = jsonBool(src, "remote_config_enabled") end
  if b ~= nil then cfg.remoteConfigEnabled = b; changed = true end

  if changed then
    syncUsers()
  end

  return changed
end

local function pullRemoteConfig()
  if not cfg.remoteConfigEnabled then
    state.configApi.enabled = false
    state.configApi.lastStatus = "disabled"
    return
  end

  state.configApi.enabled = true

  if not hasInternet or not internet then
    state.configApi.ok = false
    state.configApi.lastStatus = "no internet"
    state.configApi.failed = state.configApi.failed + 1
    return
  end

  local url = cfg.configUrl .. "?node=" .. encodeUrl(cfg.node)

  local headers = {
    ["Accept"] = "application/json",
    ["Authorization"] = "Bearer " .. tostring(cfg.telemetryToken)
  }

  local ok, handleOrErr = pcall(internet.request, url, nil, headers, "GET")

  if not ok or not handleOrErr then
    state.configApi.ok = false
    state.configApi.lastStatus = "request failed"
    state.configApi.lastError = tostring(handleOrErr)
    state.configApi.failed = state.configApi.failed + 1
    addLog("CFG", "pull failed: " .. tostring(handleOrErr))
    return
  end

  local readOk, responseOrErr = pcall(httpRead, handleOrErr, 4096)

  if not readOk then
    state.configApi.ok = false
    state.configApi.lastStatus = "read failed"
    state.configApi.lastError = tostring(responseOrErr)
    state.configApi.failed = state.configApi.failed + 1
    addLog("CFG", "read failed: " .. tostring(responseOrErr))
    return
  end

  local changed = applyRemoteConfig(responseOrErr)

  state.configApi.ok = true
  state.configApi.lastStatus = changed and "updated" or "OK"
  state.configApi.lastError = nil
  state.configApi.lastPulledAt = uptime()
  state.configApi.pulled = state.configApi.pulled + 1
end

-- -------------------------
-- Payload + telemetry POST
-- -------------------------

local function logsArray()
  local out = {}
  for _, l in ipairs(state.logs) do out[#out + 1] = l end
  return out
end

local function chatArray()
  local out = {}

  for _, c in ipairs(state.chat) do
    out[#out + 1] = {
      time = c.time,
      text = c.text,
      player = c.player,
      message = c.message,
      uuid = c.uuid
    }
  end

  return out
end

local function payload()
  local players = playerArray()

  return {
    node = cfg.node,
    version = VERSION,
    uptime = computer.uptime(),

    computer = {
      energy = computer.energy(),
      maxEnergy = computer.maxEnergy()
    },

    api = {
      url = cfg.telemetryUrl,
      enabled = cfg.telemetryEnabled,
      ok = state.api.ok,
      lastStatus = state.api.lastStatus,
      sent = state.api.sent,
      failed = state.api.failed
    },

    config = {
      url = cfg.configUrl,
      enabled = cfg.remoteConfigEnabled,
      ok = state.configApi.ok,
      lastStatus = state.configApi.lastStatus,
      pulled = state.configApi.pulled,
      failed = state.configApi.failed,
      version = cfg.configVersion,

      active = {
        scanRange = cfg.scanRange,
        tick = cfg.tick,
        telemetryEvery = cfg.telemetryEvery,
        fullScanEvery = cfg.fullScanEvery,
        meScanEvery = cfg.meScanEvery,
        fluxScanEvery = cfg.fluxScanEvery,
        maxItems = cfg.maxItems,
        topItems = cfg.topItems,
        maxChat = cfg.maxChat,
        maxLogs = cfg.maxLogs
      }
    },

    players = {
      mode = state.onlineExact and "exact" or "seen",
      count = #players,
      list = players
    },

    chat = chatArray(),
    logs = logsArray(),

    me = state.me,
    flux = state.flux,

    meta = {
      owner = cfg.owner,
      members = cfg.members,
      components = state.components,
      chatbox = chatbox ~= nil,
      internet = hasInternet and true or false
    }
  }
end

local function sendTelemetry()
  if not cfg.telemetryEnabled then
    state.api.enabled = false
    state.api.lastStatus = "disabled"
    return
  end

  state.api.enabled = true

  if not hasInternet or not internet then
    state.api.ok = false
    state.api.lastStatus = "no internet"
    state.api.failed = state.api.failed + 1
    return
  end

  local body = json(payload())

  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. tostring(cfg.telemetryToken)
  }

  local ok, handleOrErr = pcall(internet.request, cfg.telemetryUrl, body, headers, "POST")

  if not ok or not handleOrErr then
    state.api.ok = false
    state.api.lastStatus = "request failed"
    state.api.lastError = tostring(handleOrErr)
    state.api.failed = state.api.failed + 1
    addLog("API", "POST failed: " .. tostring(handleOrErr))
    return
  end

  local readOk, responseOrErr = pcall(httpRead, handleOrErr, 512)

  if readOk then
    state.api.ok = true
    state.api.lastStatus = "OK"
    state.api.lastResponse = responseOrErr
    state.api.lastError = nil
    state.api.lastSentAt = uptime()
    state.api.sent = state.api.sent + 1
  else
    state.api.ok = false
    state.api.lastStatus = "read error"
    state.api.lastError = tostring(responseOrErr)
    state.api.failed = state.api.failed + 1
    addLog("API", "read error: " .. tostring(responseOrErr))
  end
end

-- -------------------------
-- Render
-- -------------------------

local function drawLayout()
  if layoutDrawn then return end

  local w, h = gpu.getResolution()

  fill(1, 1, w, h, " ", colors.bg)

  local rightW = math.max(36, math.floor(w * 0.34))
  local leftW = w - rightW
  local bottomH = math.max(15, math.floor(h * 0.48))
  local topH = h - bottomH
  local statusH = 3

  box(1, 1, leftW, topH, " CHAT / LOG ")
  box(leftW + 1, 1, rightW, topH, " ONLINE ")
  box(1, topH + 1, leftW, bottomH - statusH, " ME NETWORK ")
  box(leftW + 1, topH + 1, rightW, bottomH - statusH, " FLUX / API / CONFIG ")
  box(1, h - statusH + 1, w, statusH, " CONTROLS ")

  line(3, h - 1, 18, "[Refresh]", colors.good, colors.button)
  line(23, h - 1, 18, "[Chat @status]", colors.cyan, colors.button)
  line(45, h - 1, 12, "[Exit]", colors.bad, colors.button)

  layoutDrawn = true
end

local function renderChat(x, y, w, h)
  clearInside(x, y, w, h)

  local src = {}

  for _, l in ipairs(state.logs) do
    src[#src + 1] = { text = l, kind = "log" }
  end

  for _, c in ipairs(state.chat) do
    src[#src + 1] = { text = c.text, kind = "chat" }
  end

  local start = math.max(1, #src - h + 1)
  local yy = y

  for i = start, #src do
    local fg = colors.text
    local text = src[i].text

    if src[i].kind == "chat" then
      fg = colors.good
    elseif text:find("%[ERR%]") then
      fg = colors.bad
    elseif text:find("%[BOOT%]") then
      fg = colors.cyan
    elseif text:find("%[API%]") then
      fg = colors.purple
    elseif text:find("%[CFG%]") then
      fg = colors.warn
    end

    line(x, yy, w, text, fg)
    yy = yy + 1

    if yy >= y + h then break end
  end
end

local function renderOnline(x, y, w, h)
  clearInside(x, y, w, h)

  local players = playerArray()
  local mode = state.onlineExact and "exact online" or "seen/chat/range"

  line(x, y, w, "Mode: " .. mode, state.onlineExact and colors.good or colors.warn)
  line(x, y + 1, w, "Count: " .. #players, colors.cyan)

  local yy = y + 3

  for _, p in ipairs(players) do
    local exact = p.exact and "*" or "~"
    line(x, yy, w, exact .. " " .. p.name .. " [" .. p.source .. " " .. p.age .. "s]", p.exact and colors.good or colors.text)
    yy = yy + 1
    if yy >= y + h then break end
  end
end

local function renderME(x, y, w, h)
  clearInside(x, y, w, h)

  if not state.me.ok then
    line(x, y, w, "ME not detected", colors.warn)
    line(x, y + 1, w, "Adapter -> ME Controller or ME Interface", colors.muted)
    return
  end

  line(x, y, w, "Source: " .. state.me.source .. " " .. state.me.address:sub(1, 8), colors.cyan)
  line(x, y + 1, w, "Power: " .. fmt(state.me.storedPower) .. " / " .. fmt(state.me.maxPower) .. " AE | use " .. fmt(state.me.usage), colors.text)
  line(x, y + 2, w, "Items: " .. fmt(state.me.totalItems) .. " total | " .. state.me.totalStacks .. " stacks sampled", colors.good)

  local yy = y + 4

  line(x, yy, w, "Top items by id:", colors.title)
  yy = yy + 1

  for _, item in ipairs(state.me.top) do
    line(x, yy, w, fmt(item.count) .. "x " .. item.id .. " | " .. item.label, colors.text)
    yy = yy + 1
    if yy >= y + h then return end
  end

  yy = yy + 1

  if yy < y + h then
    line(x, yy, w, "Ore/material:", colors.title)
    yy = yy + 1
  end

  for _, item in ipairs(state.me.ores) do
    line(x, yy, w, fmt(item.count) .. "x " .. item.id .. " | " .. item.label, colors.muted)
    yy = yy + 1
    if yy >= y + h then return end
  end
end

local function renderFluxApi(x, y, w, h)
  clearInside(x, y, w, h)

  if not state.flux.ok then
    line(x, y, w, "Flux not detected", colors.warn)
    line(x, y + 1, w, "Adapter -> Flux Controller", colors.muted)
  else
    line(x, y, w, "Flux: " .. state.flux.source .. " " .. state.flux.address:sub(1, 8), colors.purple)
    line(x, y + 1, w, "Stored: " .. fmt(state.flux.stored) .. " / " .. fmt(state.flux.max) .. " RF", colors.good)
    line(x, y + 2, w, "Input:  " .. fmt(state.flux.input) .. " RF/t", colors.cyan)
    line(x, y + 3, w, "Output: " .. fmt(state.flux.output) .. " RF/t", colors.cyan)
  end

  local ay = y + 5

  line(x, ay, w, "API: " .. tostring(cfg.telemetryUrl), colors.title)
  line(x, ay + 1, w, "POST: " .. tostring(state.api.lastStatus) .. " s=" .. tostring(state.api.sent) .. " f=" .. tostring(state.api.failed), state.api.ok and colors.good or colors.warn)
  line(x, ay + 2, w, "CFG: " .. tostring(state.configApi.lastStatus) .. " p=" .. tostring(state.configApi.pulled) .. " f=" .. tostring(state.configApi.failed), state.configApi.ok and colors.good or colors.warn)
  line(x, ay + 3, w, "Every: post=" .. tostring(cfg.telemetryEvery) .. "s cfg=" .. tostring(cfg.configEvery) .. "s", colors.text)
  line(x, ay + 4, w, "Internet: " .. tostring(hasInternet), hasInternet and colors.good or colors.bad)
  line(x, ay + 5, w, "ChatBox: " .. (chatbox and "OK" or "missing"), chatbox and colors.good or colors.warn)
  line(x, ay + 6, w, "Owner: " .. cfg.owner, colors.text)
  line(x, ay + 7, w, "Member: " .. table.concat(cfg.members, ", "), colors.text)
end

local function render()
  if not gpu then return end

  drawLayout()

  local w, h = gpu.getResolution()
  local rightW = math.max(36, math.floor(w * 0.34))
  local leftW = w - rightW
  local bottomH = math.max(15, math.floor(h * 0.48))
  local topH = h - bottomH
  local statusH = 3

  renderChat(3, 2, leftW - 4, topH - 2)
  renderOnline(leftW + 3, 2, rightW - 4, topH - 2)
  renderME(3, topH + 2, leftW - 4, bottomH - statusH - 2)
  renderFluxApi(leftW + 3, topH + 2, rightW - 4, bottomH - statusH - 2)

  line(60, h - 1, w - 61, "v" .. VERSION .. " | " .. statusText(), colors.muted, colors.panel)
end

-- -------------------------
-- Scans / events
-- -------------------------

local function scanComponentsCount()
  local n = 0
  for _ in component.list() do n = n + 1 end
  state.components = n
end

local function forceScan()
  scanComponentsCount()
  scanOnline()
  scanME()
  scanFlux()

  state.lastFullScan = computer.uptime()
  state.lastMEScan = computer.uptime()
  state.lastFluxScan = computer.uptime()
end

local function periodicScan()
  local t = computer.uptime()

  if t - state.lastConfigPull >= cfg.configEvery then
    state.lastConfigPull = t
    pullRemoteConfig()
  end

  if t - state.lastFullScan >= cfg.fullScanEvery then
    scanComponentsCount()
    scanOnline()
    state.lastFullScan = t
  end

  if t - state.lastMEScan >= cfg.meScanEvery then
    scanME()
    state.lastMEScan = t
  end

  if t - state.lastFluxScan >= cfg.fluxScanEvery then
    scanFlux()
    state.lastFluxScan = t
  end

  if t - state.lastTelemetry >= cfg.telemetryEvery then
    state.lastTelemetry = t
    sendTelemetry()
  end
end

local function handleTouch(_, x, y, button, player)
  local w, h = gpu.getResolution()

  if y ~= h - 1 then return end

  if x >= 3 and x <= 20 then
    pullRemoteConfig()
    forceScan()
    sendTelemetry()
    addLog("UI", "refresh by " .. tostring(player or "?"))
  elseif x >= 23 and x <= 40 then
    say(statusText())
    addLog("UI", "chat status")
  elseif x >= 45 and x <= 56 then
    if player == nil or isOwner(player) then
      state.exit = true
    else
      say("Exit только owner: " .. cfg.owner)
    end
  end
end

local function dumpMethods()
  local f = io.open("/tmp/eon_methods.txt", "w")
  if not f then return end

  for addr, ctype in component.list() do
    f:write("[" .. tostring(ctype) .. "] " .. tostring(addr) .. "\n")

    local methods = safeMethods(addr)
    local names = {}

    for name in pairs(methods) do table.insert(names, name) end
    table.sort(names)

    for _, name in ipairs(names) do f:write("  - " .. name .. "\n") end
    f:write("\n")
  end

  f:close()
  addLog("DUMP", "/tmp/eon_methods.txt")
end

-- -------------------------
-- Boot / main
-- -------------------------

local function boot()
  loadConfig()
  syncUsers()

  state.api.enabled = cfg.telemetryEnabled
  state.configApi.enabled = cfg.remoteConfigEnabled

  if not initGPU() then return false end

  initChatbox()

  addLog("BOOT", "Eon dashboard v" .. VERSION)
  addLog("BOOT", "node=" .. cfg.node)
  addLog("BOOT", "api=" .. cfg.telemetryUrl)
  addLog("BOOT", "config=" .. cfg.configUrl)
  addLog("BOOT", "commands: @status @online @api @config @help @exit(owner)")

  pullRemoteConfig()
  forceScan()
  sendTelemetry()
  render()

  return true
end

if boot() then
  while not state.exit do
    local ev = { event.pull(cfg.tick) }
    local name = ev[1]

    if name == "interrupted" then
      break
    elseif name == "key_down" then
      local char = ev[3]

      if char == 113 or char == 81 then -- q/Q
        break
      elseif char == 109 or char == 77 then -- m/M
        dumpMethods()
      elseif char == 114 or char == 82 then -- r/R
        loadConfig()
        initChatbox()
        pullRemoteConfig()
        forceScan()
        sendTelemetry()
        addLog("CFG", "reloaded")
      end
    elseif name == "touch" then
      handleTouch(ev[2], ev[3], ev[4], ev[5], ev[6])
    elseif name == "chat_message" or name == "chat" then
      parseChatEvent(name, { select(2, unpack(ev)) })
    end

    local ok, err = pcall(function()
      periodicScan()
      render()
    end)

    if not ok then
      addLog("ERR", err)
    end
  end

  if chatbox then
    say("Eon dashboard stopped")
  end

  gpu.setBackground(0x000000)
  gpu.setForeground(0xffffff)

  local w, h = gpu.getResolution()
  gpu.fill(1, 1, w, h, " ")

  term.clear()
  print("Eon dashboard stopped.")
end
