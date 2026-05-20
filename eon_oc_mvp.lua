-- eon_oc_mvp.lua
-- Eon OpenComputers Dashboard v0.5.0
-- Clean telemetry: players/chat/ME/Flux only. No raw payload spam.
-- API:
--   POST https://open.eonhorizon.net/api/oc/telemetry
--   GET  https://open.eonhorizon.net/api/oc/config?node=<node>
--
-- ChatBox commands:
--   @status, @online, @api, @config, @help, @exit(owner)
--
-- Keys:
--   Q = exit
--   R = reload local config + pull backend config + force scan
--   M = dump component methods to /tmp/eon_methods.txt

local component = require("component")
local computer = require("computer")
local event = require("event")
local filesystem = require("filesystem")
local term = require("term")
local unicode = require("unicode")

local hasInternet, internet = pcall(require, "internet")
local unpack = table.unpack or _G.unpack

local VERSION = "0.5.0"
local CONFIG_PATH = "/etc/eon_dashboard.cfg"

local cfg = {
  apiBase = "https://open.eonhorizon.net/api/oc",
  node = "main-base",
  nodeLabel = "Main Base",
  nodeTags = { "base" },

  owner = "FenyaVeyvon",
  members = { "ElliEmerald" },

  token = "CHANGE_ME_SECRET",

  tick = 0.5,             -- 10 ticks
  telemetryEvery = 1.0,   -- POST every second
  configEvery = 10.0,     -- pull backend config every 10 sec
  onlineEvery = 1.0,
  meEvery = 2.0,
  fluxEvery = 1.0,

  scanRange = 64,
  playerTTL = 300,

  chatboxName = "§bEon§7Dash",

  maxChat = 40,
  maxLocalLog = 14,
  maxItems = 500,
  topItems = 12
}

local state = {
  exit = false,
  bootAt = computer.uptime(),

  lastTelemetry = -999,
  lastConfig = -999,
  lastOnline = -999,
  lastME = -999,
  lastFlux = -999,

  logs = {},
  chat = {},
  players = {},

  components = 0,
  exactOnline = false,

  api = {
    ok = false,
    status = "not sent",
    sent = 0,
    failed = 0,
    lastAt = 0
  },

  config = {
    ok = false,
    status = "not pulled",
    version = 0,
    pulled = 0,
    failed = 0,
    lastAt = 0
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
    materials = {}
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
local screenCache = {}
local layoutDrawn = false
local chatbox = nil

local colors = {
  bg = 0x070b10,
  panel = 0x111827,
  panel2 = 0x0f172a,
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

-- ------------------------------------------------------------
-- Config
-- ------------------------------------------------------------

local function splitCSV(s)
  local out = {}
  s = tostring(s or "")
  for part in s:gmatch("[^,]+") do
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    if part ~= "" then table.insert(out, part) end
  end
  return out
end

local function bool(v)
  v = tostring(v or ""):lower()
  return v == "1" or v == "true" or v == "yes" or v == "on"
end

local function writeDefaultConfig()
  if filesystem.exists(CONFIG_PATH) then return end
  local f = io.open(CONFIG_PATH, "w")
  if not f then return end

  f:write("# Eon Dashboard local bootstrap config\n")
  f:write("# Backend config is loaded from api_base + /config?node=<node>\n")
  f:write("api_base=https://open.eonhorizon.net/api/oc\n")
  f:write("token=CHANGE_ME_SECRET\n")
  f:write("node=main-base\n")
  f:write("node_label=Main Base\n")
  f:write("node_tags=base\n")
  f:write("owner=FenyaVeyvon\n")
  f:write("members=ElliEmerald\n")
  f:write("tick=0.5\n")
  f:write("telemetry_every=1\n")
  f:write("config_every=10\n")
  f:write("online_every=1\n")
  f:write("me_every=2\n")
  f:write("flux_every=1\n")
  f:write("scan_range=64\n")
  f:write("player_ttl=300\n")
  f:write("chatbox_name=§bEon§7Dash\n")
  f:write("max_chat=40\n")
  f:write("max_local_log=14\n")
  f:write("max_items=500\n")
  f:write("top_items=12\n")
  f:close()
end

local function applyKV(k, v, allowApiFields)
  if k == "api_base" and allowApiFields then cfg.apiBase = v
  elseif k == "token" and allowApiFields then cfg.token = v

  elseif k == "node" then cfg.node = v
  elseif k == "node_label" or k == "nodeLabel" then cfg.nodeLabel = v
  elseif k == "node_tags" or k == "nodeTags" then cfg.nodeTags = splitCSV(v)

  elseif k == "owner" then cfg.owner = v
  elseif k == "members" then cfg.members = splitCSV(v)

  elseif k == "tick" then cfg.tick = tonumber(v) or cfg.tick
  elseif k == "telemetry_every" or k == "telemetryEvery" then cfg.telemetryEvery = tonumber(v) or cfg.telemetryEvery
  elseif k == "config_every" or k == "configEvery" then cfg.configEvery = tonumber(v) or cfg.configEvery
  elseif k == "online_every" or k == "onlineEvery" then cfg.onlineEvery = tonumber(v) or cfg.onlineEvery
  elseif k == "me_every" or k == "meEvery" then cfg.meEvery = tonumber(v) or cfg.meEvery
  elseif k == "flux_every" or k == "fluxEvery" then cfg.fluxEvery = tonumber(v) or cfg.fluxEvery

  elseif k == "scan_range" or k == "scanRange" then cfg.scanRange = tonumber(v) or cfg.scanRange
  elseif k == "player_ttl" or k == "playerTTL" then cfg.playerTTL = tonumber(v) or cfg.playerTTL
  elseif k == "chatbox_name" or k == "chatboxName" then cfg.chatboxName = v
  elseif k == "max_chat" or k == "maxChat" then cfg.maxChat = tonumber(v) or cfg.maxChat
  elseif k == "max_local_log" or k == "maxLocalLog" then cfg.maxLocalLog = tonumber(v) or cfg.maxLocalLog
  elseif k == "max_items" or k == "maxItems" then cfg.maxItems = tonumber(v) or cfg.maxItems
  elseif k == "top_items" or k == "topItems" then cfg.topItems = tonumber(v) or cfg.topItems
  end
end

local function loadLocalConfig()
  writeDefaultConfig()
  local f = io.open(CONFIG_PATH, "r")
  if not f then return end

  for line in f:lines() do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local k, v = line:match("^([%w_%-%.]+)%s*=%s*(.+)$")
      if k and v then applyKV(k, v, true) end
    end
  end

  f:close()
end

local function syncUsers()
  pcall(computer.addUser, cfg.owner)
  for _, name in ipairs(cfg.members) do pcall(computer.addUser, name) end
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

-- ------------------------------------------------------------
-- Small utils
-- ------------------------------------------------------------

local function uptime()
  return math.floor(computer.uptime())
end

local function clock()
  local t = uptime()
  return string.format("%02d:%02d:%02d", math.floor(t / 3600), math.floor((t % 3600) / 60), t % 60)
end

local function log(kind, msg)
  table.insert(state.logs, "[" .. clock() .. "][" .. tostring(kind) .. "] " .. tostring(msg))
  while #state.logs > cfg.maxLocalLog do table.remove(state.logs, 1) end
end

local function addChat(player, message, uuid)
  local item = {
    time = uptime(),
    player = tostring(player or "?"),
    uuid = uuid and tostring(uuid) or nil,
    message = tostring(message or ""),
    text = "[" .. clock() .. "] <" .. tostring(player or "?") .. "> " .. tostring(message or "")
  }

  table.insert(state.chat, item)
  while #state.chat > cfg.maxChat do table.remove(state.chat, 1) end
end

local function cut(s, w)
  s = tostring(s or "")
  if unicode.len(s) <= w then return s end
  if w <= 3 then return unicode.sub(s, 1, w) end
  return unicode.sub(s, 1, w - 3) .. "..."
end

local function pad(s, w)
  s = cut(s, w)
  local l = unicode.len(s)
  if l < w then return s .. string.rep(" ", w - l) end
  return s
end

local function short(n)
  n = tonumber(n or 0) or 0
  if n >= 1000000000 then return string.format("%.1fккк", n / 1000000000):gsub("%.0", "") end
  if n >= 1000000 then return string.format("%.1fкк", n / 1000000):gsub("%.0", "") end
  if n >= 1000 then return string.format("%.1fк", n / 1000):gsub("%.0", "") end
  return tostring(math.floor(n))
end

local function isUuidLike(s)
  s = tostring(s or "")
  if s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then return true end
  if s:match("^[0-9a-fA-F%-]+$") and unicode.len(s) >= 20 then return true end
  return false
end

local function encodeUrl(s)
  s = tostring(s or "")
  return (s:gsub("([^%w%-%_%.%~])", function(c) return string.format("%%%02X", string.byte(c)) end))
end

-- ------------------------------------------------------------
-- JSON encode + tiny config parser
-- ------------------------------------------------------------

local function jsonEscape(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  return s
end

local function isArray(t)
  local count, max = 0, 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    count = count + 1
    if k > max then max = k end
  end
  return count == max
end

local function json(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then return tostring(v) end
  if t == "string" then return '"' .. jsonEscape(v) .. '"' end

  if t == "table" then
    local out = {}
    if isArray(v) then
      for i = 1, #v do out[#out + 1] = json(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end

    for k, val in pairs(v) do out[#out + 1] = json(tostring(k)) .. ":" .. json(val) end
    return "{" .. table.concat(out, ",") .. "}"
  end

  return json(tostring(v))
end

local function unescape(s)
  s = tostring(s or "")
  s = s:gsub('\\"', '"')
  s = s:gsub("\\\\", "\\")
  s = s:gsub("\\n", "\n")
  s = s:gsub("\\r", "\r")
  s = s:gsub("\\t", "\t")
  return s
end

local function getStr(src, key)
  local v = src:match('"' .. key .. '"%s*:%s*"([^"]*)"')
  if v ~= nil then return unescape(v) end
  return nil
end

local function getNum(src, key)
  local v = src:match('"' .. key .. '"%s*:%s*([%-%.%d]+)')
  if v ~= nil then return tonumber(v) end
  return nil
end

local function getArr(src, key)
  local raw = src:match('"' .. key .. '"%s*:%s*%[([^%]]*)%]')
  if not raw then return nil end
  local out = {}
  for item in raw:gmatch('"([^"]*)"') do table.insert(out, unescape(item)) end
  return out
end

-- ------------------------------------------------------------
-- GPU no-flicker render
-- ------------------------------------------------------------

local function initGPU()
  if not component.isAvailable("gpu") then
    print("No GPU.")
    return false
  end

  gpu = component.gpu
  local maxW, maxH = gpu.maxResolution()
  pcall(gpu.setResolution, maxW, maxH)
  gpu.setBackground(colors.bg)
  gpu.setForeground(colors.text)
  gpu.fill(1, 1, maxW, maxH, " ")
  screenCache = {}
  layoutDrawn = false
  return true
end

local function cell(x, y, text, fg, bg)
  if not gpu then return end
  fg = fg or colors.text
  bg = bg or colors.panel
  text = tostring(text or "")

  local key = x .. ":" .. y
  local sig = text .. "|" .. tostring(fg) .. "|" .. tostring(bg)
  if screenCache[key] == sig then return end
  screenCache[key] = sig

  gpu.setForeground(fg)
  gpu.setBackground(bg)
  gpu.set(x, y, text)
end

local function fill(x, y, w, h, ch, bg)
  gpu.setBackground(bg or colors.panel)
  gpu.fill(x, y, w, h, ch or " ")
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do screenCache[xx .. ":" .. yy] = nil end
  end
end

local function line(x, y, w, text, fg, bg)
  cell(x, y, pad(text, w), fg, bg or colors.panel)
end

local function box(x, y, w, h, title)
  fill(x, y, w, h, " ", colors.panel)
  cell(x, y, "+" .. string.rep("-", w - 2) .. "+", colors.border, colors.panel)
  for yy = y + 1, y + h - 2 do
    cell(x, yy, "|", colors.border, colors.panel)
    cell(x + w - 1, yy, "|", colors.border, colors.panel)
  end
  cell(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", colors.border, colors.panel)
  if title then cell(x + 2, y, " " .. title .. " ", colors.title, colors.panel) end
end

local function clearArea(x, y, w, h)
  for yy = y, y + h - 1 do line(x, yy, w, "", colors.text, colors.panel) end
end

-- ------------------------------------------------------------
-- Components
-- ------------------------------------------------------------

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
  if ok and result ~= nil then return result end
  return default
end

local function callNum(p, method, default, ...)
  local v = call(p, method, default, ...)
  if v == nil then return default end
  return tonumber(v) or default
end

local function firstNum(p, methods, names)
  for _, name in ipairs(names) do
    if has(methods, name) and p and p[name] then
      local v = callNum(p, name, nil)
      if v ~= nil then return v, name end
    end
  end
  return nil, nil
end

-- ------------------------------------------------------------
-- Chat / players
-- ------------------------------------------------------------

local function addPlayer(name, source, exact, uuid)
  name = tostring(name or "")
  if name == "" or name == "nil" or isUuidLike(name) then return end

  local old = state.players[name] or {}

  state.players[name] = {
    name = name,
    uuid = uuid or old.uuid,
    source = source or old.source or "seen",
    tags = cfg.nodeTags,
    node = cfg.node,
    nodeLabel = cfg.nodeLabel,
    online = true,
    exact = exact and true or false,
    seen = uptime()
  }

  if exact then state.exactOnline = true end
end

local function normalizePlayers(list, source, exact)
  if type(list) ~= "table" then return 0 end
  local count = 0

  for _, item in pairs(list) do
    local name, uuid = nil, nil
    if type(item) == "string" then
      name = item
    elseif type(item) == "table" then
      name = item.name or item.username or item.player or item.nick or item[1]
      uuid = item.uuid or item.id
    end

    if name then
      addPlayer(name, source, exact, uuid)
      count = count + 1
    end
  end

  return count
end

local function scanOnline()
  state.exactOnline = false

  local methodsToTry = {
    "getOnlinePlayers",
    "getPlayerList",
    "getPlayers",
    "getPlayerNames",
    "getOnlinePlayerNames",
    "players"
  }

  for addr, ctype in component.list() do
    local low = tostring(ctype):lower()

    if low:find("online") or low:find("player") or low:find("detector") then
      local methods = safeMethods(addr)
      local p = proxy(addr)

      for _, m in ipairs(methodsToTry) do
        if has(methods, m) then
          normalizePlayers(call(p, m, nil), ctype .. "." .. m, true)
        end
      end
    end
  end

  if component.isAvailable("os_entdetector") then
    local det = component.getPrimary("os_entdetector")
    local ok, players = pcall(det.scanPlayers, math.max(1, math.min(64, cfg.scanRange)))
    if ok then normalizePlayers(players, "os_entdetector", false) end
  end

  local t = uptime()
  for name, p in pairs(state.players) do
    if t - (p.seen or 0) > cfg.playerTTL then
      p.online = false
    else
      p.online = true
    end
  end
end

local function playersArray()
  local out = {}

  for _, p in pairs(state.players) do
    out[#out + 1] = {
      name = p.name,
      uuid = p.uuid,
      online = p.online and true or false,
      exact = p.exact and true or false,
      source = p.source,
      node = p.node,
      nodeLabel = p.nodeLabel,
      tags = p.tags,
      lastSeenUptime = p.seen,
      age = uptime() - (p.seen or uptime())
    }
  end

  table.sort(out, function(a, b)
    if a.online ~= b.online then return a.online end
    return tostring(a.name) < tostring(b.name)
  end)

  return out
end

local function parseChatEvent(eventName, args)
  local uuid, player, message = nil, nil, nil

  -- Robust layouts:
  -- chat_message, uuid, username, message
  -- chat_message, username, message, uuid
  -- chat_message, componentAddress, uuid, username, message
  -- chat_message, username, message
  if type(args[1]) == "string" and type(args[2]) == "string" and type(args[3]) == "string" and isUuidLike(args[1]) then
    uuid, player, message = args[1], args[2], args[3]
  elseif type(args[2]) == "string" and type(args[3]) == "string" and type(args[4]) == "string" and isUuidLike(args[2]) then
    uuid, player, message = args[2], args[3], args[4]
  elseif type(args[1]) == "string" and type(args[2]) == "string" and type(args[3]) == "string" and isUuidLike(args[3]) then
    player, message, uuid = args[1], args[2], args[3]
  elseif type(args[1]) == "string" and type(args[2]) == "string" then
    player, message = args[1], args[2]
  end

  if player and message and not isUuidLike(player) then
    addPlayer(player, "chatbox", false, uuid)
    addChat(player, message, uuid)

    if tostring(message):sub(1, 1) == "@" then
      local cmd = tostring(message):match("^(%S+)") or ""
      cmd = cmd:lower()

      if not isMember(player) then
        if chatbox then pcall(chatbox.say, "Нет доступа: " .. tostring(player)) end
        return
      end

      if cmd == "@status" then
        if chatbox then pcall(chatbox.say, "Online: " .. tostring(#playersArray()) .. " | ME: " .. short(state.me.totalItems) .. " | Flux: " .. short(state.flux.stored) .. "/" .. short(state.flux.max) .. " RF | API: " .. state.api.status) end
      elseif cmd == "@online" then
        local names = {}
        for _, p in ipairs(playersArray()) do
          if p.online then table.insert(names, p.name) end
        end
        if chatbox then pcall(chatbox.say, "Online: " .. (#names > 0 and table.concat(names, ", ") or "none")) end
      elseif cmd == "@api" then
        if chatbox then pcall(chatbox.say, "API: " .. state.api.status .. " sent=" .. state.api.sent .. " fail=" .. state.api.failed .. " cfg=" .. state.config.status) end
      elseif cmd == "@config" then
        if chatbox then pcall(chatbox.say, "Config v" .. tostring(state.config.version) .. " send=" .. cfg.telemetryEvery .. "s me=" .. cfg.meEvery .. "s flux=" .. cfg.fluxEvery .. "s") end
      elseif cmd == "@help" then
        if chatbox then pcall(chatbox.say, "@status @online @api @config @help" .. (isOwner(player) and " @exit" or "")) end
      elseif cmd == "@exit" and isOwner(player) then
        if chatbox then pcall(chatbox.say, "Stopping dashboard") end
        state.exit = true
      end
    end
  else
    log("CHAT?", tostring(args[1]) .. " | " .. tostring(args[2]) .. " | " .. tostring(args[3]) .. " | " .. tostring(args[4]))
  end
end

-- ------------------------------------------------------------
-- ME
-- ------------------------------------------------------------

local function itemId(item)
  if type(item) ~= "table" then return tostring(item) end
  local id = item.name or item.id or item.item or "unknown"
  local dmg = item.damage or item.dmg or item.metadata or item.meta
  if dmg ~= nil then return tostring(id) .. ":" .. tostring(dmg) end
  return tostring(id)
end

local function itemLabel(item)
  if type(item) ~= "table" then return tostring(item) end
  return tostring(item.label or item.displayName or item.display_name or item.name or item.id or "?")
end

local function itemCount(item)
  if type(item) ~= "table" then return 0 end
  return tonumber(item.size or item.amount or item.count or item.qty or 0) or 0
end

local function materialLike(id, label)
  local s = (tostring(id or "") .. " " .. tostring(label or "")):lower()
  return s:find("ore") or s:find("dust") or s:find("ingot") or s:find("plate") or s:find("gem") or s:find("crushed") or s:find("nugget") or s:find("raw")
end

local function findME()
  for _, ctype in ipairs({ "me_controller", "me_interface" }) do
    if component.isAvailable(ctype) then
      local addr = component.list(ctype)()
      if addr then return addr, ctype end
    end
  end

  for addr, ctype in component.list() do
    local m = safeMethods(addr)
    if has(m, "getItemsInNetwork") or has(m, "getAvailableItems") or has(m, "getStoredPower") then
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
    materials = {}
  }

  if not addr then return end

  local p = proxy(addr)
  local m = safeMethods(addr)

  local stored = firstNum(p, m, { "getStoredPower", "getEnergyStored", "getEnergy", "getStored" })
  local maxp = firstNum(p, m, { "getMaxStoredPower", "getMaxEnergyStored", "getMaxEnergy", "getCapacity" })
  local usage = firstNum(p, m, { "getAvgPowerUsage", "getAveragePowerUsage", "getPowerUsage", "getIdlePowerUsage" })

  local items, method = nil, nil
  if has(m, "getItemsInNetwork") then
    items, method = call(p, "getItemsInNetwork", nil), "getItemsInNetwork"
  elseif has(m, "getAvailableItems") then
    items, method = call(p, "getAvailableItems", nil), "getAvailableItems"
  elseif has(m, "getItems") then
    items, method = call(p, "getItems", nil), "getItems"
  end

  local map, mats = {}, {}
  local stacks, total = 0, 0

  if type(items) == "table" then
    for _, item in pairs(items) do
      stacks = stacks + 1
      if stacks > cfg.maxItems then break end

      local id = itemId(item)
      local label = itemLabel(item)
      local count = itemCount(item)
      total = total + count

      if not map[id] then map[id] = { id = id, label = label, count = 0 } end
      map[id].count = map[id].count + count

      if materialLike(id, label) then
        if not mats[id] then mats[id] = { id = id, label = label, count = 0 } end
        mats[id].count = mats[id].count + count
      end
    end
  end

  local top = {}
  for _, v in pairs(map) do table.insert(top, v) end
  table.sort(top, function(a, b) return a.count > b.count end)
  while #top > cfg.topItems do table.remove(top) end

  local materials = {}
  for _, v in pairs(mats) do table.insert(materials, v) end
  table.sort(materials, function(a, b) return a.count > b.count end)
  while #materials > cfg.topItems do table.remove(materials) end

  state.me.ok = true
  state.me.source = tostring(ctype) .. "." .. tostring(method or "?")
  state.me.address = tostring(addr)
  state.me.storedPower = stored
  state.me.maxPower = maxp
  state.me.usage = usage
  state.me.totalStacks = stacks
  state.me.totalItems = total
  state.me.top = top
  state.me.materials = materials
end

-- ------------------------------------------------------------
-- Flux
-- ------------------------------------------------------------

local function findFlux()
  if component.isAvailable("flux_controller") then
    local addr = component.list("flux_controller")()
    if addr then return addr, "flux_controller" end
  end

  for addr, ctype in component.list() do
    local low = tostring(ctype):lower()
    local m = safeMethods(addr)

    if low:find("flux") or has(m, "getNetworkEnergy") or has(m, "getEnergyStored") or has(m, "getMaxEnergyStored") then
      if not has(m, "getItemsInNetwork") and not has(m, "getStoredPower") then
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
  local m = safeMethods(addr)

  state.flux.ok = true
  state.flux.source = tostring(ctype)
  state.flux.address = tostring(addr)
  state.flux.stored = firstNum(p, m, { "getNetworkEnergy", "getEnergyStored", "getEnergy", "getStored", "getBuffer" })
  state.flux.max = firstNum(p, m, { "getNetworkCapacity", "getMaxEnergyStored", "getMaxEnergy", "getCapacity", "getEnergyCapacity" })
  state.flux.input = firstNum(p, m, { "getNetworkInput", "getInput", "getAverageInput", "getEnergyInput", "getTransferIn" })
  state.flux.output = firstNum(p, m, { "getNetworkOutput", "getOutput", "getAverageOutput", "getEnergyOutput", "getTransferOut" })
end

-- ------------------------------------------------------------
-- ChatBox
-- ------------------------------------------------------------

local function initChatBox()
  chatbox = nil

  if component.isAvailable("chat_box") then chatbox = component.chat_box
  elseif component.isAvailable("chatbox") then chatbox = component.chatbox end

  if chatbox and chatbox.setName then pcall(chatbox.setName, cfg.chatboxName) end
end

-- ------------------------------------------------------------
-- HTTP / config / telemetry
-- ------------------------------------------------------------

local function httpRead(handle, limit)
  local s = ""
  for chunk in handle do
    s = s .. tostring(chunk)
    if limit and #s > limit then return s:sub(1, limit) end
  end
  return s
end

local function applyRemoteConfig(src)
  if type(src) ~= "string" or src == "" then return false end

  local changed = false
  local function setS(key, cfgKey)
    local v = getStr(src, key)
    if v ~= nil and cfg[cfgKey] ~= v then cfg[cfgKey] = v; changed = true end
  end
  local function setN(key, cfgKey)
    local v = getNum(src, key)
    if v ~= nil and cfg[cfgKey] ~= v then cfg[cfgKey] = v; changed = true end
  end

  -- Backend config must not send apiBase/configUrl. URL is derived locally from apiBase.
  setS("node", "node")
  setS("nodeLabel", "nodeLabel")
  setS("owner", "owner")
  setS("chatboxName", "chatboxName")

  local tags = getArr(src, "nodeTags")
  if tags then cfg.nodeTags = tags; changed = true end

  local members = getArr(src, "members")
  if members then cfg.members = members; changed = true end

  setN("tick", "tick")
  setN("telemetryEvery", "telemetryEvery")
  setN("configEvery", "configEvery")
  setN("onlineEvery", "onlineEvery")
  setN("meEvery", "meEvery")
  setN("fluxEvery", "fluxEvery")
  setN("scanRange", "scanRange")
  setN("playerTTL", "playerTTL")
  setN("maxChat", "maxChat")
  setN("maxLocalLog", "maxLocalLog")
  setN("maxItems", "maxItems")
  setN("topItems", "topItems")

  local ver = getNum(src, "configVersion")
  if ver ~= nil then state.config.version = ver end

  if changed then
    syncUsers()
    initChatBox()
  end

  return changed
end

local function pullConfig()
  if not hasInternet or not internet then
    state.config.ok = false
    state.config.status = "no internet"
    state.config.failed = state.config.failed + 1
    return
  end

  local url = cfg.apiBase .. "/config?node=" .. encodeUrl(cfg.node)
  local headers = {
    ["Accept"] = "application/json",
    ["Authorization"] = "Bearer " .. tostring(cfg.token)
  }

  local ok, handle = pcall(internet.request, url, nil, headers, "GET")
  if not ok or not handle then
    state.config.ok = false
    state.config.status = "request failed"
    state.config.failed = state.config.failed + 1
    return
  end

  local okRead, response = pcall(httpRead, handle, 8192)
  if not okRead then
    state.config.ok = false
    state.config.status = "read failed"
    state.config.failed = state.config.failed + 1
    return
  end

  local changed = applyRemoteConfig(response)

  state.config.ok = true
  state.config.status = changed and "updated" or "OK"
  state.config.pulled = state.config.pulled + 1
  state.config.lastAt = uptime()
end

local function chatPayload()
  local out = {}
  for _, c in ipairs(state.chat) do
    out[#out + 1] = {
      time = c.time,
      player = c.player,
      uuid = c.uuid,
      message = c.message
    }
  end
  return out
end

local function payload()
  return {
    node = cfg.node,
    nodeLabel = cfg.nodeLabel,
    nodeTags = cfg.nodeTags,
    version = VERSION,
    uptime = computer.uptime(),

    computer = {
      energy = computer.energy(),
      maxEnergy = computer.maxEnergy()
    },

    players = {
      mode = state.exactOnline and "exact" or "seen",
      count = #playersArray(),
      list = playersArray()
    },

    chat = chatPayload(),

    me = state.me,
    flux = state.flux,

    api = {
      ok = state.api.ok,
      status = state.api.status,
      sent = state.api.sent,
      failed = state.api.failed
    },

    config = {
      ok = state.config.ok,
      status = state.config.status,
      version = state.config.version,
      pulled = state.config.pulled,
      failed = state.config.failed
    },

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
  if not hasInternet or not internet then
    state.api.ok = false
    state.api.status = "no internet"
    state.api.failed = state.api.failed + 1
    return
  end

  local url = cfg.apiBase .. "/telemetry"
  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. tostring(cfg.token)
  }

  local ok, handle = pcall(internet.request, url, json(payload()), headers, "POST")
  if not ok or not handle then
    state.api.ok = false
    state.api.status = "request failed"
    state.api.failed = state.api.failed + 1
    return
  end

  local okRead = pcall(httpRead, handle, 512)
  if okRead then
    state.api.ok = true
    state.api.status = "OK"
    state.api.sent = state.api.sent + 1
    state.api.lastAt = uptime()
  else
    state.api.ok = false
    state.api.status = "read failed"
    state.api.failed = state.api.failed + 1
  end
end

-- ------------------------------------------------------------
-- Render
-- ------------------------------------------------------------

local function drawLayout()
  if layoutDrawn then return end

  local w, h = gpu.getResolution()
  fill(1, 1, w, h, " ", colors.bg)

  local rightW = math.max(34, math.floor(w * 0.32))
  local leftW = w - rightW
  local bottomH = math.max(15, math.floor(h * 0.48))
  local topH = h - bottomH
  local statusH = 3

  box(1, 1, leftW, topH, " CHAT ")
  box(leftW + 1, 1, rightW, topH, " PLAYERS ")
  box(1, topH + 1, leftW, bottomH - statusH, " ME ITEMS ")
  box(leftW + 1, topH + 1, rightW, bottomH - statusH, " FLUX / API ")
  box(1, h - statusH + 1, w, statusH, " CONTROLS ")

  line(3, h - 1, 16, "[Refresh]", colors.good, colors.button)
  line(22, h - 1, 16, "[Status]", colors.cyan, colors.button)
  line(41, h - 1, 10, "[Exit]", colors.bad, colors.button)

  layoutDrawn = true
end

local function renderChat(x, y, w, h)
  clearArea(x, y, w, h)

  local start = math.max(1, #state.chat - h + 1)
  local yy = y

  for i = start, #state.chat do
    local c = state.chat[i]
    line(x, yy, w, c.player .. ": " .. c.message, colors.good)
    yy = yy + 1
    if yy >= y + h then return end
  end

  if #state.chat == 0 then
    line(x, y, w, "No chat yet. Try @status.", colors.muted)
  end
end

local function renderPlayers(x, y, w, h)
  clearArea(x, y, w, h)

  local players = playersArray()
  line(x, y, w, "Node: " .. cfg.nodeLabel .. " [" .. table.concat(cfg.nodeTags, ",") .. "]", colors.title)
  line(x, y + 1, w, "Players: " .. tostring(#players) .. " | " .. (state.exactOnline and "exact" or "seen"), state.exactOnline and colors.good or colors.warn)

  local yy = y + 3
  for _, p in ipairs(players) do
    local mark = p.online and "●" or "○"
    local fg = p.online and colors.good or colors.muted
    line(x, yy, w, mark .. " " .. p.name .. " | " .. p.nodeLabel, fg)
    yy = yy + 1
    if yy < y + h then
      line(x + 2, yy, w - 2, "uuid: " .. tostring(p.uuid or "-"), colors.muted)
      yy = yy + 1
    end
    if yy < y + h then
      line(x + 2, yy, w - 2, "seen " .. tostring(p.age) .. "s ago | " .. tostring(p.source), colors.muted)
      yy = yy + 1
    end
    if yy >= y + h then return end
  end
end

local function renderME(x, y, w, h)
  clearArea(x, y, w, h)

  if not state.me.ok then
    line(x, y, w, "ME not detected", colors.warn)
    line(x, y + 1, w, "Adapter -> ME Controller / Interface", colors.muted)
    return
  end

  line(x, y, w, "Total: " .. short(state.me.totalItems) .. " items | " .. short(state.me.totalStacks) .. " stacks", colors.good)
  line(x, y + 1, w, "Power: " .. short(state.me.storedPower) .. "/" .. short(state.me.maxPower) .. " AE | use " .. short(state.me.usage), colors.cyan)

  local yy = y + 3
  line(x, yy, w, "Top items:", colors.title)
  yy = yy + 1

  for _, item in ipairs(state.me.top) do
    line(x, yy, w, short(item.count) .. "x " .. item.label .. " [" .. item.id .. "]", colors.text)
    yy = yy + 1
    if yy >= y + h then return end
  end

  yy = yy + 1
  if yy < y + h then
    line(x, yy, w, "Materials:", colors.title)
    yy = yy + 1
  end

  for _, item in ipairs(state.me.materials) do
    line(x, yy, w, short(item.count) .. "x " .. item.label .. " [" .. item.id .. "]", colors.muted)
    yy = yy + 1
    if yy >= y + h then return end
  end
end

local function renderFluxApi(x, y, w, h)
  clearArea(x, y, w, h)

  if state.flux.ok then
    line(x, y, w, "Flux: " .. state.flux.source, colors.purple)
    line(x, y + 1, w, "Stored: " .. short(state.flux.stored) .. "/" .. short(state.flux.max) .. " RF", colors.good)
    line(x, y + 2, w, "In: " .. short(state.flux.input) .. " RF/t", colors.cyan)
    line(x, y + 3, w, "Out: " .. short(state.flux.output) .. " RF/t", colors.cyan)
  else
    line(x, y, w, "Flux not detected", colors.warn)
    line(x, y + 1, w, "Adapter -> Flux Controller", colors.muted)
  end

  line(x, y + 5, w, "API: " .. state.api.status .. " s=" .. state.api.sent .. " f=" .. state.api.failed, state.api.ok and colors.good or colors.warn)
  line(x, y + 6, w, "Config: " .. state.config.status .. " v=" .. tostring(state.config.version), state.config.ok and colors.good or colors.warn)
  line(x, y + 7, w, "Send: " .. tostring(cfg.telemetryEvery) .. "s | Pull: " .. tostring(cfg.configEvery) .. "s", colors.text)
  line(x, y + 8, w, "ChatBox: " .. (chatbox and "OK" or "missing"), chatbox and colors.good or colors.warn)
end

local function render()
  drawLayout()
  local w, h = gpu.getResolution()

  local rightW = math.max(34, math.floor(w * 0.32))
  local leftW = w - rightW
  local bottomH = math.max(15, math.floor(h * 0.48))
  local topH = h - bottomH
  local statusH = 3

  renderChat(3, 2, leftW - 4, topH - 2)
  renderPlayers(leftW + 3, 2, rightW - 4, topH - 2)
  renderME(3, topH + 2, leftW - 4, bottomH - statusH - 2)
  renderFluxApi(leftW + 3, topH + 2, rightW - 4, bottomH - statusH - 2)

  line(54, h - 1, w - 55, "v" .. VERSION .. " | " .. cfg.node .. " | " .. short(state.me.totalItems) .. " items | " .. state.api.status, colors.muted, colors.panel)
end

-- ------------------------------------------------------------
-- Main loop helpers
-- ------------------------------------------------------------

local function scanComponents()
  local n = 0
  for _ in component.list() do n = n + 1 end
  state.components = n
end

local function forceScan()
  scanComponents()
  scanOnline()
  scanME()
  scanFlux()
  local t = computer.uptime()
  state.lastOnline = t
  state.lastME = t
  state.lastFlux = t
end

local function periodic()
  local t = computer.uptime()

  if t - state.lastConfig >= cfg.configEvery then
    state.lastConfig = t
    pullConfig()
  end

  if t - state.lastOnline >= cfg.onlineEvery then
    state.lastOnline = t
    scanComponents()
    scanOnline()
  end

  if t - state.lastME >= cfg.meEvery then
    state.lastME = t
    scanME()
  end

  if t - state.lastFlux >= cfg.fluxEvery then
    state.lastFlux = t
    scanFlux()
  end

  if t - state.lastTelemetry >= cfg.telemetryEvery then
    state.lastTelemetry = t
    sendTelemetry()
  end
end

local function touch(_, x, y, button, player)
  local w, h = gpu.getResolution()
  if y ~= h - 1 then return end

  if x >= 3 and x <= 18 then
    pullConfig()
    forceScan()
    sendTelemetry()
    log("UI", "refresh")
  elseif x >= 22 and x <= 38 then
    if chatbox then pcall(chatbox.say, "ME: " .. short(state.me.totalItems) .. " | Flux: " .. short(state.flux.stored) .. "/" .. short(state.flux.max) .. " | API: " .. state.api.status) end
  elseif x >= 41 and x <= 50 then
    if player == nil or isOwner(player) then state.exit = true end
  end
end

local function dumpMethods()
  local f = io.open("/tmp/eon_methods.txt", "w")
  if not f then return end

  for addr, ctype in component.list() do
    f:write("[" .. tostring(ctype) .. "] " .. tostring(addr) .. "\n")
    local names = {}
    for name in pairs(safeMethods(addr)) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do f:write("  - " .. name .. "\n") end
    f:write("\n")
  end

  f:close()
  log("DUMP", "/tmp/eon_methods.txt")
end

-- ------------------------------------------------------------
-- Boot
-- ------------------------------------------------------------

local function boot()
  loadLocalConfig()
  syncUsers()

  if not initGPU() then return false end

  initChatBox()
  log("BOOT", "Eon Dashboard v" .. VERSION)
  log("BOOT", cfg.node .. " / " .. cfg.nodeLabel)

  pullConfig()
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
      if char == 113 or char == 81 then -- Q
        break
      elseif char == 114 or char == 82 then -- R
        loadLocalConfig()
        pullConfig()
        initChatBox()
        forceScan()
        sendTelemetry()
        log("CFG", "reloaded")
      elseif char == 109 or char == 77 then -- M
        dumpMethods()
      end
    elseif name == "touch" then
      touch(ev[2], ev[3], ev[4], ev[5], ev[6])
    elseif name == "chat_message" or name == "chat" then
      parseChatEvent(name, { select(2, unpack(ev)) })
    end

    local ok, err = pcall(function()
      periodic()
      render()
    end)

    if not ok then log("ERR", err) end
  end

  if chatbox then pcall(chatbox.say, "Eon dashboard stopped") end

  gpu.setBackground(0x000000)
  gpu.setForeground(0xffffff)
  local w, h = gpu.getResolution()
  gpu.fill(1, 1, w, h, " ")
  term.clear()
  print("Eon dashboard stopped.")
end
