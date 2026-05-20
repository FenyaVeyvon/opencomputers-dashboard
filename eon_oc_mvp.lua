-- eon.lua
-- Eon OpenComputers Dashboard MVP
-- Focus: online/player log + chatbox commands + ME network items + Flux Network.
-- No reactors. No full-screen flicker: static layout is drawn once, dynamic lines are updated only when changed.

local component = require("component")
local computer = require("computer")
local event = require("event")
local filesystem = require("filesystem")
local term = require("term")
local unicode = require("unicode")

local unpack = table.unpack or _G.unpack

local VERSION = "0.2.0"
local CONFIG_PATH = "/etc/eon_dashboard.cfg"

local cfg = {
  owner = "FenyaVeyvon",
  members = { "ElliEmerald" },
  scanRange = 64,
  tick = 0.35,
  fullScanEvery = 2.0,
  meScanEvery = 5.0,
  fluxScanEvery = 2.0,
  playerTTL = 300,
  chatboxName = "§bEon§7Dash",
  maxChat = 12,
  maxLogs = 12,
  maxItems = 250,
  topItems = 8
}

local state = {
  exit = false,
  startedAt = computer.uptime(),
  lastFullScan = 0,
  lastMEScan = 0,
  lastFluxScan = 0,
  logs = {},
  chat = {},
  players = {},
  onlineExact = false,
  components = 0,
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

local function splitCSV(s)
  local out = {}
  s = tostring(s or "")
  for part in s:gmatch("[^,]+") do
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    if part ~= "" then table.insert(out, part) end
  end
  return out
end

local function writeDefaultConfig()
  if filesystem.exists(CONFIG_PATH) then return end
  local f = io.open(CONFIG_PATH, "w")
  if not f then return end
  f:write("# Eon dashboard config\n")
  f:write("owner=FenyaVeyvon\n")
  f:write("members=ElliEmerald\n")
  f:write("scan_range=64\n")
  f:write("tick=0.35\n")
  f:write("full_scan_every=2\n")
  f:write("me_scan_every=5\n")
  f:write("flux_scan_every=2\n")
  f:write("player_ttl=300\n")
  f:write("chatbox_name=§bEon§7Dash\n")
  f:write("max_items=250\n")
  f:write("top_items=8\n")
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
        if k == "owner" then cfg.owner = v
        elseif k == "members" then cfg.members = splitCSV(v)
        elseif k == "scan_range" then cfg.scanRange = tonumber(v) or cfg.scanRange
        elseif k == "tick" then cfg.tick = tonumber(v) or cfg.tick
        elseif k == "full_scan_every" then cfg.fullScanEvery = tonumber(v) or cfg.fullScanEvery
        elseif k == "me_scan_every" then cfg.meScanEvery = tonumber(v) or cfg.meScanEvery
        elseif k == "flux_scan_every" then cfg.fluxScanEvery = tonumber(v) or cfg.fluxScanEvery
        elseif k == "player_ttl" then cfg.playerTTL = tonumber(v) or cfg.playerTTL
        elseif k == "chatbox_name" then cfg.chatboxName = v
        elseif k == "max_items" then cfg.maxItems = tonumber(v) or cfg.maxItems
        elseif k == "top_items" then cfg.topItems = tonumber(v) or cfg.topItems
        end
      end
    end
  end

  f:close()
end

local function isMember(name)
  name = tostring(name or "")
  if name == cfg.owner then return true end
  for _, n in ipairs(cfg.members) do
    if name == n then return true end
  end
  return false
end

local function isOwner(name)
  return tostring(name or "") == cfg.owner
end

local function syncUsers()
  pcall(computer.addUser, cfg.owner)
  for _, name in ipairs(cfg.members) do
    pcall(computer.addUser, name)
  end
end

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
  while #state.logs > cfg.maxLogs do table.remove(state.logs, 1) end
end

local function addChat(player, msg)
  table.insert(state.chat, "[" .. clock() .. "] <" .. tostring(player) .. "> " .. tostring(msg))
  while #state.chat > cfg.maxChat do table.remove(state.chat, 1) end
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
  if l < width then return text .. string.rep(" ", width - l) end
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
  -- Invalidate cache for this area.
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

local function callNumber(p, method, default, ...)
  local v = call(p, method, default, ...)
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

local function firstValue(p, methods, names)
  for _, name in ipairs(names) do
    if has(methods, name) and p and p[name] then
      local v = call(p, name, nil)
      if v ~= nil then return v, name end
    end
  end
  return nil, nil
end

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

  -- Generic exact online detectors.
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

  -- OpenSecurity: nearby players, not full server online.
  if component.isAvailable("os_entdetector") then
    local det = component.getPrimary("os_entdetector")
    local ok, players = pcall(det.scanPlayers, math.max(1, math.min(64, cfg.scanRange)))
    if ok then normalizePlayerList(players, "os_entdetector", false) end
  end

  local t = uptime()
  for name, p in pairs(state.players) do
    if not p.exact and t - p.seen > cfg.playerTTL then
      state.players[name] = nil
    end
  end
end

local function itemId(item)
  if type(item) ~= "table" then return tostring(item) end
  local name = item.name or item.id or item.item or "unknown"
  local dmg = item.damage or item.dmg or item.metadata or item.meta
  if dmg ~= nil then return tostring(name) .. ":" .. tostring(dmg) end
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
      -- Avoid ME controller being detected as generic energy.
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

local function countPlayers()
  local n = 0
  for _ in pairs(state.players) do n = n + 1 end
  return n
end

local function statusText()
  local mode = state.onlineExact and "exact" or "seen"
  return "Online(" .. mode .. "): " .. countPlayers()
    .. " | ME: " .. (state.me.ok and (fmt(state.me.totalItems) .. " items/" .. state.me.totalStacks .. " stacks") or "missing")
    .. " | Flux: " .. (state.flux.ok and (fmt(state.flux.stored) .. "/" .. fmt(state.flux.max) .. " RF") or "missing")
end

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
  elseif cmd == "@help" then
    say("Commands: @status, @online, @help" .. (isOwner(player) and ", @exit" or ""))
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
  local player, msg = nil, nil

  if name == "chat_message" then
    player = args[1]
    msg = args[2]
  elseif name == "chat" then
    if type(args[1]) == "string" and type(args[2]) == "string" then
      player = args[1]
      msg = args[2]
    end
    if type(args[1]) == "string" and type(args[2]) == "string" and type(args[3]) == "string" then
      if unicode.len(args[1]) > 20 then
        player = args[2]
        msg = args[3]
      end
    end
  end

  if player and msg then
    addPlayer(player, "chatbox", false)
    addChat(player, msg)
    handleCommand(player, msg)
  end
end

local function drawLayout()
  if layoutDrawn then return end

  local w, h = gpu.getResolution()
  fill(1, 1, w, h, " ", colors.bg)

  local rightW = math.max(30, math.floor(w * 0.32))
  local leftW = w - rightW
  local bottomH = math.max(12, math.floor(h * 0.42))
  local topH = h - bottomH
  local statusH = 3

  box(1, 1, leftW, topH, " CHAT / LOG ")
  box(leftW + 1, 1, rightW, topH, " ONLINE ")
  box(1, topH + 1, leftW, bottomH - statusH, " ME NETWORK ")
  box(leftW + 1, topH + 1, rightW, bottomH - statusH, " FLUX NETWORK ")
  box(1, h - statusH + 1, w, statusH, " CONTROLS ")

  line(3, h - 1, 18, "[Refresh]", colors.good, colors.button)
  line(23, h - 1, 18, "[Chat @status]", colors.cyan, colors.button)
  line(45, h - 1, 12, "[Exit]", colors.bad, colors.button)

  layoutDrawn = true
end

local function renderChat(x, y, w, h)
  clearInside(x, y, w, h)

  local lineNo = y
  local src = {}

  for _, l in ipairs(state.logs) do table.insert(src, l) end
  for _, l in ipairs(state.chat) do table.insert(src, l) end

  local start = math.max(1, #src - h + 1)
  for i = start, #src do
    local fg = colors.text
    if src[i]:find("%[ERR%]") then fg = colors.bad
    elseif src[i]:find("%[BOOT%]") then fg = colors.cyan
    elseif src[i]:find("<") then fg = colors.good
    end
    line(x, lineNo, w, src[i], fg)
    lineNo = lineNo + 1
    if lineNo >= y + h then break end
  end
end

local function renderOnline(x, y, w, h)
  clearInside(x, y, w, h)

  local players = {}
  for _, p in pairs(state.players) do table.insert(players, p) end
  table.sort(players, function(a, b) return a.name < b.name end)

  local mode = state.onlineExact and "exact online" or "seen/chat/range"
  line(x, y, w, "Mode: " .. mode, state.onlineExact and colors.good or colors.warn)
  line(x, y + 1, w, "Count: " .. #players, colors.cyan)

  local yy = y + 3
  for _, p in ipairs(players) do
    local age = uptime() - (p.seen or uptime())
    local exact = p.exact and "*" or "~"
    line(x, yy, w, exact .. " " .. p.name .. " [" .. p.source .. " " .. age .. "s]", p.exact and colors.good or colors.text)
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

local function renderFlux(x, y, w, h)
  clearInside(x, y, w, h)

  if not state.flux.ok then
    line(x, y, w, "Flux not detected", colors.warn)
    line(x, y + 1, w, "Adapter -> Flux Controller", colors.muted)
    return
  end

  line(x, y, w, "Source: " .. state.flux.source .. " " .. state.flux.address:sub(1, 8), colors.purple)
  line(x, y + 2, w, "Stored: " .. fmt(state.flux.stored) .. " / " .. fmt(state.flux.max) .. " RF", colors.good)
  line(x, y + 3, w, "Input:  " .. fmt(state.flux.input) .. " RF/t", colors.cyan)
  line(x, y + 4, w, "Output: " .. fmt(state.flux.output) .. " RF/t", colors.cyan)
  line(x, y + 6, w, "ChatBox: " .. (chatbox and "OK" or "missing"), chatbox and colors.good or colors.warn)
  line(x, y + 7, w, "Owner: " .. cfg.owner, colors.text)
  line(x, y + 8, w, "Member: " .. table.concat(cfg.members, ", "), colors.text)
end

local function render()
  if not gpu then return end

  drawLayout()

  local w, h = gpu.getResolution()
  local rightW = math.max(30, math.floor(w * 0.32))
  local leftW = w - rightW
  local bottomH = math.max(12, math.floor(h * 0.42))
  local topH = h - bottomH
  local statusH = 3

  renderChat(3, 2, leftW - 4, topH - 2)
  renderOnline(leftW + 3, 2, rightW - 4, topH - 2)
  renderME(3, topH + 2, leftW - 4, bottomH - statusH - 2)
  renderFlux(leftW + 3, topH + 2, rightW - 4, bottomH - statusH - 2)

  line(60, h - 1, w - 61, "v" .. VERSION .. " | " .. statusText(), colors.muted, colors.panel)
end

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
end

local function handleTouch(_, x, y, button, player)
  local w, h = gpu.getResolution()

  if y ~= h - 1 then return end

  if x >= 3 and x <= 20 then
    forceScan()
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

local function boot()
  loadConfig()
  syncUsers()

  if not initGPU() then return false end

  initChatbox()
  addLog("BOOT", "Eon dashboard v" .. VERSION)
  addLog("BOOT", "owner=" .. cfg.owner .. " member=" .. table.concat(cfg.members, ","))
  addLog("BOOT", "commands: @status @online @help @exit(owner)")

  forceScan()
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
        forceScan()
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

  if chatbox then say("Eon dashboard stopped") end

  gpu.setBackground(0x000000)
  gpu.setForeground(0xffffff)
  local w, h = gpu.getResolution()
  gpu.fill(1, 1, w, h, " ")
  term.clear()
  print("Eon dashboard stopped.")
end
