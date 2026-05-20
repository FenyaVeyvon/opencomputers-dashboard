-- eon_oc_mvp.lua
-- OpenComputers 1.12.2 MVP console for:
-- 1) Flux Network telemetry via Adapter
-- 2) Reactors telemetry via Adapter
-- 3) AE2 / ME network telemetry via Adapter
-- 4) OpenSecurity Entity Detector players/entities
-- 5) Motion Sensor events
-- 6) ChatBox chat log/player seen list
--
-- Run:
--   lua /home/eon_oc_mvp.lua
--
-- Controls:
--   Q / Ctrl+C : exit
--   R          : reload config
--   M          : dump component methods to /tmp/eon_components.txt
--
-- Config file:
--   /etc/eon_oc_mvp.cfg
--
-- Example config:
--   node=main-base
--   scan_range=64
--   tick_seconds=1
--   player_ttl=180
--   entity_ttl=15
--   max_logs=200
--   me_item_limit=120
--   debug=false

local component = require("component")
local computer = require("computer")
local event = require("event")
local filesystem = require("filesystem")
local unicode = require("unicode")

local hasSerialization, serialization = pcall(require, "serialization")

local gpu = component.isAvailable("gpu") and component.gpu or nil

local CONFIG_PATH = "/etc/eon_oc_mvp.cfg"

local config = {
  node = "main-base",
  scan_range = 64,
  tick_seconds = 1,
  player_ttl = 180,
  entity_ttl = 15,
  motion_ttl = 15,
  max_logs = 200,
  me_item_limit = 120,
  debug = false
}

local state = {
  bootTime = computer.uptime(),
  logs = {},
  players = {},
  entities = {},
  motions = {},
  chat = {},
  systems = {
    flux = {},
    reactors = {},
    me = {}
  },
  components = {},
  stats = {
    lastScan = 0,
    lastRender = 0,
    scans = 0,
    errors = 0,
    componentCount = 0
  }
}

local COLORS = {
  bg = 0x0B0F14,
  panel = 0x111827,
  border = 0x334155,
  title = 0x60A5FA,
  text = 0xE5E7EB,
  muted = 0x94A3B8,
  good = 0x22C55E,
  warn = 0xF59E0B,
  bad = 0xEF4444,
  cyan = 0x06B6D4,
  purple = 0xA78BFA
}

local function toBool(value)
  value = tostring(value or ""):lower()
  return value == "1" or value == "true" or value == "yes" or value == "on"
end

local function loadConfig()
  if not filesystem.exists(CONFIG_PATH) then
    local f = io.open(CONFIG_PATH, "w")
    if f then
      f:write("node=main-base\n")
      f:write("scan_range=64\n")
      f:write("tick_seconds=1\n")
      f:write("player_ttl=180\n")
      f:write("entity_ttl=15\n")
      f:write("motion_ttl=15\n")
      f:write("max_logs=200\n")
      f:write("me_item_limit=120\n")
      f:write("debug=false\n")
      f:close()
    end
  end

  local f = io.open(CONFIG_PATH, "r")
  if not f then return end

  for line in f:lines() do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local k, v = line:match("^([%w_%-%.]+)%s*=%s*(.+)$")
      if k and v then
        if k == "node" then config.node = v
        elseif k == "scan_range" then config.scan_range = tonumber(v) or config.scan_range
        elseif k == "tick_seconds" then config.tick_seconds = tonumber(v) or config.tick_seconds
        elseif k == "player_ttl" then config.player_ttl = tonumber(v) or config.player_ttl
        elseif k == "entity_ttl" then config.entity_ttl = tonumber(v) or config.entity_ttl
        elseif k == "motion_ttl" then config.motion_ttl = tonumber(v) or config.motion_ttl
        elseif k == "max_logs" then config.max_logs = tonumber(v) or config.max_logs
        elseif k == "me_item_limit" then config.me_item_limit = tonumber(v) or config.me_item_limit
        elseif k == "debug" then config.debug = toBool(v)
        end
      end
    end
  end

  f:close()
end

local function uptime()
  return math.floor(computer.uptime())
end

local function timeTag()
  local t = uptime()
  local h = math.floor(t / 3600)
  local m = math.floor((t % 3600) / 60)
  local s = t % 60
  return string.format("%02d:%02d:%02d", h, m, s)
end

local function addLog(kind, message)
  local line = "[" .. timeTag() .. "][" .. tostring(kind) .. "] " .. tostring(message)
  table.insert(state.logs, line)

  while #state.logs > config.max_logs do
    table.remove(state.logs, 1)
  end
end

local function dbg(message)
  if config.debug then
    addLog("DBG", message)
  end
end

local function incError(message)
  state.stats.errors = state.stats.errors + 1
  addLog("ERR", message)
end

local function str(value)
  if value == nil then return "-" end
  return tostring(value)
end

local function lower(value)
  return tostring(value or ""):lower()
end

local function len(text)
  return unicode.len(tostring(text or ""))
end

local function cut(text, maxLen)
  text = tostring(text or "")
  if len(text) <= maxLen then return text end
  if maxLen <= 3 then return unicode.sub(text, 1, maxLen) end
  return unicode.sub(text, 1, maxLen - 3) .. "..."
end

local function pad(text, width)
  text = cut(text, width)
  local l = len(text)
  if l < width then
    return text .. string.rep(" ", width - l)
  end
  return text
end

local function fmtNumber(value)
  value = tonumber(value or 0) or 0
  if value >= 1000000000000 then return string.format("%.2fT", value / 1000000000000) end
  if value >= 1000000000 then return string.format("%.2fB", value / 1000000000) end
  if value >= 1000000 then return string.format("%.2fM", value / 1000000) end
  if value >= 1000 then return string.format("%.2fK", value / 1000) end
  return tostring(math.floor(value))
end

local function fmtRF(value)
  if value == nil then return "-" end
  return fmtNumber(value) .. " RF"
end

local function setFg(color)
  if gpu and gpu.setForeground then pcall(gpu.setForeground, color) end
end

local function setBg(color)
  if gpu and gpu.setBackground then pcall(gpu.setBackground, color) end
end

local function gpuSet(x, y, text, fg, bg)
  if not gpu then return end
  if bg then setBg(bg) end
  if fg then setFg(fg) end
  pcall(gpu.set, x, y, tostring(text or ""))
end

local function gpuFill(x, y, w, h, char, bg)
  if not gpu then return end
  if bg then setBg(bg) end
  pcall(gpu.fill, x, y, w, h, char or " ")
end

local function safeMethods(address)
  local ok, methods = pcall(component.methods, address)
  if ok and type(methods) == "table" then return methods end
  return {}
end

local function hasMethod(methods, name)
  return methods and methods[name] ~= nil
end

local function safeInvoke(address, method, ...)
  local ok, result = pcall(component.invoke, address, method, ...)
  if ok then return result end
  return nil
end

local function callFirst(address, methods, names, ...)
  for _, name in ipairs(names) do
    if hasMethod(methods, name) then
      local value = safeInvoke(address, name, ...)
      if value ~= nil then return value, name end
    end
  end
  return nil, nil
end

local function callFirstNumber(address, methods, names, ...)
  for _, name in ipairs(names) do
    if hasMethod(methods, name) then
      local value = safeInvoke(address, name, ...)
      if type(value) == "number" then return value, name end
      if tonumber(value) then return tonumber(value), name end
    end
  end
  return nil, nil
end

local function callFirstBool(address, methods, names)
  for _, name in ipairs(names) do
    if hasMethod(methods, name) then
      local value = safeInvoke(address, name)
      if type(value) == "boolean" then return value, name end
    end
  end
  return nil, nil
end

local function methodNames(methods)
  local out = {}
  for name in pairs(methods or {}) do out[#out + 1] = name end
  table.sort(out)
  return out
end

local function methodString(methods)
  return table.concat(methodNames(methods), ", ")
end

local function classifyComponent(address, ctype, methods)
  local name = lower(ctype)
  local ms = " " .. lower(methodString(methods)) .. " "

  local isME =
    name:find("me") ~= nil
    or name:find("applied") ~= nil
    or hasMethod(methods, "getItemsInNetwork")
    or hasMethod(methods, "getFluidsInNetwork")
    or hasMethod(methods, "getCraftables")
    or hasMethod(methods, "getStoredPower")

  local isReactor =
    name:find("reactor") ~= nil
    or name:find("bigreactor") ~= nil
    or name:find("br_") ~= nil
    or hasMethod(methods, "getFuelAmount")
    or hasMethod(methods, "getFuelTemperature")
    or hasMethod(methods, "getCasingTemperature")
    or hasMethod(methods, "getEnergyProducedLastTick")
    or hasMethod(methods, "getNumberOfControlRods")

  local isFlux =
    name:find("flux") ~= nil
    or ms:find("networkenergy") ~= nil
    or ms:find("flux") ~= nil

  local isEnergy =
    hasMethod(methods, "getEnergyStored")
    or hasMethod(methods, "getMaxEnergyStored")
    or hasMethod(methods, "getEnergy")
    or hasMethod(methods, "getMaxEnergy")
    or hasMethod(methods, "getEnergyCapacity")
    or hasMethod(methods, "getCapacity")

  -- If a block is clearly reactor or ME, do not call it Flux just because it has energy.
  if isReactor or isME then
    isFlux = isFlux and name:find("flux") ~= nil
  end

  -- Some Flux controllers through Adapter may only expose generic energy methods.
  -- Keep generic energy as a weak Flux candidate only if it is not reactor/ME.
  if isEnergy and not isReactor and not isME then
    isFlux = true
  end

  return {
    me = isME,
    reactor = isReactor,
    flux = isFlux,
    energy = isEnergy
  }
end

local function scanComponents()
  local list = {}
  local count = 0

  for address, ctype in component.list() do
    count = count + 1
    local methods = safeMethods(address)
    local classes = classifyComponent(address, ctype, methods)

    list[#list + 1] = {
      address = address,
      type = ctype,
      methods = methods,
      classes = classes
    }
  end

  table.sort(list, function(a, b)
    return tostring(a.type) < tostring(b.type)
  end)

  state.components = list
  state.stats.componentCount = count
end

local function collectFlux()
  local out = {}

  for _, c in ipairs(state.components) do
    if c.classes.flux then
      local stored, storedMethod = callFirstNumber(c.address, c.methods, {
        "getNetworkEnergy",
        "getEnergyStored",
        "getEnergy",
        "getStored",
        "getBuffer",
        "getEnergyAmount"
      })

      local max, maxMethod = callFirstNumber(c.address, c.methods, {
        "getMaxEnergyStored",
        "getMaxEnergy",
        "getCapacity",
        "getEnergyCapacity",
        "getMaxStorage",
        "getNetworkCapacity"
      })

      local input, inputMethod = callFirstNumber(c.address, c.methods, {
        "getInput",
        "getAverageInput",
        "getEnergyInput",
        "getTransferIn",
        "getNetworkInput",
        "getLastInput"
      })

      local output, outputMethod = callFirstNumber(c.address, c.methods, {
        "getOutput",
        "getAverageOutput",
        "getEnergyOutput",
        "getTransferOut",
        "getNetworkOutput",
        "getLastOutput"
      })

      local name, nameMethod = callFirst(c.address, c.methods, {
        "getNetworkName",
        "getName",
        "getCustomName"
      })

      out[#out + 1] = {
        address = c.address,
        type = c.type,
        name = name,
        stored = stored,
        max = max,
        input = input,
        output = output,
        methods = {
          stored = storedMethod,
          max = maxMethod,
          input = inputMethod,
          output = outputMethod,
          name = nameMethod
        }
      }
    end
  end

  state.systems.flux = out
end

local function collectReactors()
  local out = {}

  for _, c in ipairs(state.components) do
    if c.classes.reactor then
      local active, activeMethod = callFirstBool(c.address, c.methods, {
        "getActive",
        "isActive",
        "isActivelyCooled"
      })

      local stored, storedMethod = callFirstNumber(c.address, c.methods, {
        "getEnergyStored",
        "getEnergy",
        "getStored",
        "getEnergyAmount"
      })

      local max, maxMethod = callFirstNumber(c.address, c.methods, {
        "getMaxEnergyStored",
        "getMaxEnergy",
        "getCapacity",
        "getEnergyCapacity"
      })

      local produced, producedMethod = callFirstNumber(c.address, c.methods, {
        "getEnergyProducedLastTick",
        "getEnergyGeneratedLastTick",
        "getEnergyOutput",
        "getOutput",
        "getAverageOutput"
      })

      local fuel, fuelMethod = callFirstNumber(c.address, c.methods, {
        "getFuelAmount",
        "getFuelAmountMax",
        "getFuelConsumedLastTick"
      })

      local waste, wasteMethod = callFirstNumber(c.address, c.methods, {
        "getWasteAmount",
        "getWasteAmountMax"
      })

      local fuelTemp, fuelTempMethod = callFirstNumber(c.address, c.methods, {
        "getFuelTemperature",
        "getFuelTemp"
      })

      local casingTemp, casingTempMethod = callFirstNumber(c.address, c.methods, {
        "getCasingTemperature",
        "getCasingTemp"
      })

      local rods, rodsMethod = callFirstNumber(c.address, c.methods, {
        "getNumberOfControlRods",
        "getControlRodCount"
      })

      out[#out + 1] = {
        address = c.address,
        type = c.type,
        active = active,
        stored = stored,
        max = max,
        produced = produced,
        fuel = fuel,
        waste = waste,
        fuelTemp = fuelTemp,
        casingTemp = casingTemp,
        rods = rods,
        methods = {
          active = activeMethod,
          stored = storedMethod,
          max = maxMethod,
          produced = producedMethod,
          fuel = fuelMethod,
          waste = wasteMethod,
          fuelTemp = fuelTempMethod,
          casingTemp = casingTempMethod,
          rods = rodsMethod
        }
      }
    end
  end

  state.systems.reactors = out
end

local function itemCount(item)
  if type(item) ~= "table" then return 0 end
  return tonumber(item.size or item.amount or item.count or item.qty or item[2] or 0) or 0
end

local function itemName(item)
  if type(item) ~= "table" then return tostring(item) end
  return tostring(item.label or item.display_name or item.displayName or item.name or item.id or item[1] or "?")
end

local function isOreItem(name)
  name = lower(name)
  return name:find("ore") ~= nil
    or name:find("crushed") ~= nil
    or name:find("dust") ~= nil
    or name:find("ingot") ~= nil
    or name:find("nugget") ~= nil
    or name:find("plate") ~= nil
    or name:find("gem") ~= nil
end

local function collectME()
  local out = {}

  for _, c in ipairs(state.components) do
    if c.classes.me then
      local storedPower, storedPowerMethod = callFirstNumber(c.address, c.methods, {
        "getStoredPower",
        "getEnergyStored",
        "getEnergy",
        "getStored"
      })

      local maxPower, maxPowerMethod = callFirstNumber(c.address, c.methods, {
        "getMaxStoredPower",
        "getMaxEnergyStored",
        "getMaxEnergy",
        "getCapacity"
      })

      local avgUsage, avgUsageMethod = callFirstNumber(c.address, c.methods, {
        "getAvgPowerUsage",
        "getAveragePowerUsage",
        "getPowerUsage"
      })

      local idleUsage, idleUsageMethod = callFirstNumber(c.address, c.methods, {
        "getIdlePowerUsage",
        "getIdlePowerDrain"
      })

      local energyDemand, energyDemandMethod = callFirstNumber(c.address, c.methods, {
        "getEnergyDemand",
        "getPowerDemand"
      })

      local items = nil
      local itemMethod = nil

      if hasMethod(c.methods, "getItemsInNetwork") then
        items = safeInvoke(c.address, "getItemsInNetwork")
        itemMethod = "getItemsInNetwork"
      elseif hasMethod(c.methods, "getAvailableItems") then
        items = safeInvoke(c.address, "getAvailableItems")
        itemMethod = "getAvailableItems"
      elseif hasMethod(c.methods, "getItems") then
        items = safeInvoke(c.address, "getItems")
        itemMethod = "getItems"
      end

      local totalStacks = 0
      local totalItems = 0
      local oreItems = 0
      local ores = {}

      if type(items) == "table" then
        for _, item in pairs(items) do
          totalStacks = totalStacks + 1
          if totalStacks > config.me_item_limit then
            break
          end

          local n = itemName(item)
          local cnt = itemCount(item)

          totalItems = totalItems + cnt

          if isOreItem(n) then
            oreItems = oreItems + cnt
            ores[#ores + 1] = { name = n, count = cnt }
          end
        end
      end

      table.sort(ores, function(a, b) return a.count > b.count end)

      while #ores > 8 do
        table.remove(ores)
      end

      out[#out + 1] = {
        address = c.address,
        type = c.type,
        storedPower = storedPower,
        maxPower = maxPower,
        avgUsage = avgUsage,
        idleUsage = idleUsage,
        energyDemand = energyDemand,
        totalStacks = totalStacks,
        totalItems = totalItems,
        oreItems = oreItems,
        ores = ores,
        methods = {
          storedPower = storedPowerMethod,
          maxPower = maxPowerMethod,
          avgUsage = avgUsageMethod,
          idleUsage = idleUsageMethod,
          energyDemand = energyDemandMethod,
          items = itemMethod
        }
      }
    end
  end

  state.systems.me = out
end

local function addPlayer(name, source, extra)
  if not name or tostring(name) == "" then return end

  name = tostring(name)

  state.players[name] = {
    name = name,
    source = source or "unknown",
    seenAt = uptime(),
    extra = extra
  }
end

local function collectPlayers()
  -- Optional full-online detector if any addon exposes it.
  if component.isAvailable("online_detector") then
    local ok, detector = pcall(function() return component.getPrimary("online_detector") end)
    if ok and detector then
      local okList, list = pcall(function()
        if detector.getPlayerList then return detector.getPlayerList() end
        if detector.getPlayers then return detector.getPlayers() end
        if detector.players then return detector.players() end
        return nil
      end)

      if okList and type(list) == "table" then
        for _, name in pairs(list) do
          addPlayer(name, "online_detector")
        end
      end
    end
  end

  -- OpenSecurity Entity Detector.
  if component.isAvailable("os_entdetector") then
    local detector = component.getPrimary("os_entdetector")

    local okPlayers, players = pcall(detector.scanPlayers, math.max(1, math.min(64, config.scan_range)))
    if okPlayers and type(players) == "table" then
      for _, p in pairs(players) do
        if type(p) == "table" then
          addPlayer(p.name or p.username or p.label or p[1], "os_entdetector", p)
        elseif type(p) == "string" then
          addPlayer(p, "os_entdetector")
        end
      end
    end

    local okEntities, entities = pcall(detector.scanEntities, math.max(1, math.min(64, config.scan_range)))
    if okEntities and type(entities) == "table" then
      for _, e in pairs(entities) do
        local key = nil
        local name = nil

        if type(e) == "table" then
          name = tostring(e.name or e.label or e.type or e.id or e[1] or "entity")
          key = name .. ":" .. tostring(math.floor(tonumber(e.x or 0) or 0)) .. ":" .. tostring(math.floor(tonumber(e.y or 0) or 0)) .. ":" .. tostring(math.floor(tonumber(e.z or 0) or 0))
        elseif type(e) == "string" then
          name = e
          key = e
        end

        if key then
          state.entities[key] = {
            name = name,
            source = "os_entdetector",
            seenAt = uptime(),
            raw = e
          }
        end
      end
    end
  end

  -- Cleanup stale detected players/entities.
  local t = uptime()

  for name, p in pairs(state.players) do
    if p.source ~= "online_detector" and t - p.seenAt > config.player_ttl then
      state.players[name] = nil
    end
  end

  for key, e in pairs(state.entities) do
    if t - e.seenAt > config.entity_ttl then
      state.entities[key] = nil
    end
  end

  for i = #state.motions, 1, -1 do
    if t - state.motions[i].seenAt > config.motion_ttl then
      table.remove(state.motions, i)
    end
  end
end

local function handleChatEvent(eventName, ...)
  local args = {...}
  local username = nil
  local message = nil

  if eventName == "chat_message" then
    -- Computronics usually: chat_message, username, message
    username = args[1]
    message = args[2]
  elseif eventName == "chat" then
    -- Other chat boxes differ; try common layouts.
    if type(args[1]) == "string" and type(args[2]) == "string" then
      username = args[1]
      message = args[2]
    end
    if type(args[2]) == "string" and type(args[3]) == "string" then
      -- If first looks like UUID/address, username may be arg2 and message arg3.
      if len(args[1]) > 20 then
        username = args[2]
        message = args[3]
      end
    end
  end

  if username and message then
    addPlayer(username, "chatbox")
    local item = {
      time = uptime(),
      player = tostring(username),
      message = tostring(message)
    }
    table.insert(state.chat, item)
    while #state.chat > 50 do table.remove(state.chat, 1) end
    addLog("CHAT", "<" .. tostring(username) .. "> " .. tostring(message))
  end
end

local function handleMotionEvent(...)
  local args = {...}
  local entityName = nil

  for _, v in ipairs(args) do
    if type(v) == "string" and len(v) > 0 then
      -- Skip component address-looking strings.
      if not v:match("^[0-9a-f%-]+$") or len(v) < 20 then
        entityName = v
      end
    end
  end

  if not entityName then
    entityName = "motion"
  end

  local m = {
    seenAt = uptime(),
    name = tostring(entityName),
    raw = args
  }

  table.insert(state.motions, m)
  while #state.motions > 20 do table.remove(state.motions, 1) end

  addLog("MOTION", tostring(entityName))
end

local function collectAll()
  state.stats.scans = state.stats.scans + 1
  state.stats.lastScan = uptime()

  scanComponents()
  collectFlux()
  collectReactors()
  collectME()
  collectPlayers()
end

local function box(x, y, w, h, title, color)
  gpuFill(x, y, w, h, " ", COLORS.panel)

  setFg(color or COLORS.border)
  setBg(COLORS.panel)

  gpuSet(x, y, "+" .. string.rep("-", math.max(0, w - 2)) .. "+", color or COLORS.border, COLORS.panel)
  for row = 1, h - 2 do
    gpuSet(x, y + row, "|", color or COLORS.border, COLORS.panel)
    gpuSet(x + w - 1, y + row, "|", color or COLORS.border, COLORS.panel)
  end
  gpuSet(x, y + h - 1, "+" .. string.rep("-", math.max(0, w - 2)) .. "+", color or COLORS.border, COLORS.panel)

  if title then
    gpuSet(x + 2, y, " " .. title .. " ", COLORS.title, COLORS.panel)
  end
end

local function writeLine(x, y, w, text, fg)
  gpuSet(x, y, pad(text, w), fg or COLORS.text, COLORS.panel)
end

local function renderLogs(x, y, w, h)
  local line = y
  local maxLines = h
  local start = math.max(1, #state.logs - maxLines + 1)

  for i = start, #state.logs do
    local l = state.logs[i]
    local fg = COLORS.text
    if l:find("%[ERR%]") then fg = COLORS.bad
    elseif l:find("%[BOOT%]") then fg = COLORS.cyan
    elseif l:find("%[CHAT%]") then fg = COLORS.good
    elseif l:find("%[MOTION%]") then fg = COLORS.warn
    end

    writeLine(x, line, w, l, fg)
    line = line + 1
    if line >= y + h then break end
  end
end

local function sortedPlayers()
  local out = {}
  for _, p in pairs(state.players) do out[#out + 1] = p end
  table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return out
end

local function renderPlayers(x, y, w, h)
  local players = sortedPlayers()

  writeLine(x, y, w, "Players seen/online: " .. #players, COLORS.cyan)
  local line = y + 1

  for _, p in ipairs(players) do
    local age = uptime() - (p.seenAt or 0)
    local text = tostring(p.name) .. " [" .. tostring(p.source) .. " " .. tostring(age) .. "s]"
    writeLine(x, line, w, text, COLORS.text)
    line = line + 1
    if line >= y + h then break end
  end

  if #players == 0 then
    writeLine(x, y + 2, w, "No players detected yet.", COLORS.muted)
    writeLine(x, y + 3, w, "Need chatbox / online detector / OS entity detector.", COLORS.muted)
  end
end

local function renderFlux(x, y, w, h)
  local line = y
  writeLine(x, line, w, "Flux Networks: " .. #state.systems.flux, COLORS.purple)
  line = line + 1

  if #state.systems.flux == 0 then
    writeLine(x, line, w, "No Flux adapter detected.", COLORS.warn)
    line = line + 1
    writeLine(x, line, w, "Put Adapter on Flux Controller, not Plug/Storage.", COLORS.muted)
    return
  end

  for i, f in ipairs(state.systems.flux) do
    writeLine(x, line, w, "#" .. i .. " " .. tostring(f.name or f.type) .. " " .. f.address:sub(1, 8), COLORS.text)
    line = line + 1
    writeLine(x, line, w, "  Stored: " .. fmtRF(f.stored) .. " / " .. fmtRF(f.max), COLORS.good)
    line = line + 1
    writeLine(x, line, w, "  In: " .. fmtRF(f.input) .. " | Out: " .. fmtRF(f.output), COLORS.cyan)
    line = line + 1
    if line >= y + h then break end
  end
end

local function renderReactors(x, y, w, h)
  local line = y
  writeLine(x, line, w, "Reactors: " .. #state.systems.reactors, COLORS.warn)
  line = line + 1

  if #state.systems.reactors == 0 then
    writeLine(x, line, w, "No reactor adapter detected.", COLORS.muted)
    return
  end

  for i, r in ipairs(state.systems.reactors) do
    local activeText = r.active == nil and "?" or (r.active and "ON" or "OFF")
    writeLine(x, line, w, "#" .. i .. " " .. tostring(r.type) .. " " .. activeText .. " " .. r.address:sub(1, 8), r.active and COLORS.good or COLORS.bad)
    line = line + 1
    writeLine(x, line, w, "  RF: " .. fmtRF(r.stored) .. " / " .. fmtRF(r.max) .. " | Gen: " .. fmtRF(r.produced) .. "/t", COLORS.text)
    line = line + 1
    writeLine(x, line, w, "  Fuel: " .. str(r.fuel) .. " Waste: " .. str(r.waste), COLORS.text)
    line = line + 1
    writeLine(x, line, w, "  Temp fuel/case: " .. str(r.fuelTemp) .. " / " .. str(r.casingTemp), COLORS.text)
    line = line + 1
    if line >= y + h then break end
  end
end

local function renderME(x, y, w, h)
  local line = y
  writeLine(x, line, w, "ME Network: " .. #state.systems.me, COLORS.cyan)
  line = line + 1

  if #state.systems.me == 0 then
    writeLine(x, line, w, "No ME adapter detected.", COLORS.muted)
    line = line + 1
    writeLine(x, line, w, "Put Adapter on ME Controller or ME Interface.", COLORS.muted)
    return
  end

  local me = state.systems.me[1]
  writeLine(x, line, w, "Power: " .. fmtNumber(me.storedPower) .. " / " .. fmtNumber(me.maxPower) .. " AE", COLORS.text)
  line = line + 1
  writeLine(x, line, w, "Usage avg/idle/demand: " .. fmtNumber(me.avgUsage) .. " / " .. fmtNumber(me.idleUsage) .. " / " .. fmtNumber(me.energyDemand), COLORS.text)
  line = line + 1
  writeLine(x, line, w, "Items sampled: " .. me.totalStacks .. " stacks, " .. fmtNumber(me.totalItems) .. " items", COLORS.text)
  line = line + 1
  writeLine(x, line, w, "Ore/material total: " .. fmtNumber(me.oreItems), COLORS.good)
  line = line + 1

  for _, ore in ipairs(me.ores or {}) do
    writeLine(x, line, w, "  " .. fmtNumber(ore.count) .. "x " .. ore.name, COLORS.muted)
    line = line + 1
    if line >= y + h then break end
  end
end

local function renderDetectors(x, y, w, h)
  local line = y

  local entityCount = 0
  for _ in pairs(state.entities) do entityCount = entityCount + 1 end

  writeLine(x, line, w, "OpenSecurity / Sensors", COLORS.title)
  line = line + 1
  writeLine(x, line, w, "Range: " .. config.scan_range .. " | Entities: " .. entityCount .. " | Motion: " .. #state.motions, COLORS.text)
  line = line + 1

  if component.isAvailable("os_entdetector") then
    writeLine(x, line, w, "os_entdetector: OK", COLORS.good)
  else
    writeLine(x, line, w, "os_entdetector: missing", COLORS.warn)
  end
  line = line + 1

  if component.isAvailable("motion_sensor") then
    writeLine(x, line, w, "motion_sensor: OK", COLORS.good)
  else
    writeLine(x, line, w, "motion_sensor: event-only/missing", COLORS.muted)
  end
  line = line + 1

  if component.isAvailable("chat_box") or component.isAvailable("chatbox") then
    writeLine(x, line, w, "chatbox: OK", COLORS.good)
  else
    writeLine(x, line, w, "chatbox: wait chat events", COLORS.muted)
  end
  line = line + 1

  writeLine(x, line, w, "Components: " .. state.stats.componentCount .. " | Scans: " .. state.stats.scans .. " | Errors: " .. state.stats.errors, COLORS.muted)
  line = line + 1
  writeLine(x, line, w, "Keys: Q exit | R reload cfg | M dump methods", COLORS.muted)
  line = line + 1

  if #state.motions > 0 and line < y + h then
    writeLine(x, line, w, "Recent motion:", COLORS.warn)
    line = line + 1

    for i = #state.motions, math.max(1, #state.motions - 4), -1 do
      local m = state.motions[i]
      writeLine(x, line, w, "  " .. tostring(m.name) .. " " .. tostring(uptime() - m.seenAt) .. "s", COLORS.text)
      line = line + 1
      if line >= y + h then break end
    end
  end
end

local function render()
  if not gpu then
    print("No GPU component.")
    return
  end

  local w, h = gpu.getResolution()
  w = tonumber(w) or 80
  h = tonumber(h) or 25

  gpuFill(1, 1, w, h, " ", COLORS.bg)

  local rightW = math.max(28, math.floor(w * 0.32))
  local leftW = w - rightW
  local bottomH = math.max(10, math.floor(h * 0.38))
  local topH = h - bottomH

  if leftW < 45 then
    rightW = math.max(20, w - 45)
    leftW = w - rightW
  end

  -- Layout:
  -- left top: logs
  -- right top: online players
  -- left bottom: flux/reactor/me energy
  -- right bottom: detectors/status
  box(1, 1, leftW, topH, " LOGS / CHAT ", COLORS.border)
  box(leftW + 1, 1, rightW, topH, " ONLINE PLAYERS ", COLORS.border)
  box(1, topH + 1, leftW, bottomH, " ENERGY / SYSTEMS ", COLORS.border)
  box(leftW + 1, topH + 1, rightW, bottomH, " DETECTORS / STATUS ", COLORS.border)

  renderLogs(3, 2, leftW - 4, topH - 2)
  renderPlayers(leftW + 3, 2, rightW - 4, topH - 2)

  local energyX = 3
  local energyY = topH + 2
  local energyW = leftW - 4
  local colW = math.max(22, math.floor(energyW / 3) - 1)

  if energyW >= 78 then
    renderFlux(energyX, energyY, colW, bottomH - 2)
    renderReactors(energyX + colW + 1, energyY, colW, bottomH - 2)
    renderME(energyX + (colW + 1) * 2, energyY, energyW - (colW + 1) * 2, bottomH - 2)
  else
    -- Smaller screen: stack sections.
    local sectionH = math.floor((bottomH - 2) / 3)
    renderFlux(energyX, energyY, energyW, sectionH)
    renderReactors(energyX, energyY + sectionH, energyW, sectionH)
    renderME(energyX, energyY + sectionH * 2, energyW, bottomH - 2 - sectionH * 2)
  end

  renderDetectors(leftW + 3, topH + 2, rightW - 4, bottomH - 2)

  state.stats.lastRender = uptime()
end

local function dumpComponents()
  local path = "/tmp/eon_components.txt"
  local f = io.open(path, "w")

  if not f then
    incError("Cannot write " .. path)
    return
  end

  f:write("Eon OC MVP component dump\n")
  f:write("Node: " .. config.node .. "\n")
  f:write("Uptime: " .. tostring(computer.uptime()) .. "\n\n")

  for _, c in ipairs(state.components) do
    f:write("[" .. tostring(c.type) .. "] " .. tostring(c.address) .. "\n")
    f:write("classes: flux=" .. tostring(c.classes.flux) .. " reactor=" .. tostring(c.classes.reactor) .. " me=" .. tostring(c.classes.me) .. " energy=" .. tostring(c.classes.energy) .. "\n")
    local names = methodNames(c.methods)
    for _, name in ipairs(names) do
      f:write("  - " .. name .. "\n")
    end
    f:write("\n")
  end

  f:close()
  addLog("DUMP", "methods -> " .. path)
end

local function handleKey(address, char, code)
  -- q/Q
  if char == 113 or char == 81 then
    return "quit"
  end

  -- r/R
  if char == 114 or char == 82 then
    loadConfig()
    addLog("CFG", "reloaded " .. CONFIG_PATH)
    return nil
  end

  -- m/M
  if char == 109 or char == 77 then
    dumpComponents()
    return nil
  end

  return nil
end

local function boot()
  loadConfig()

  if not gpu then
    print("No GPU found. Install GPU + Screen.")
    return false
  end

  pcall(gpu.setResolution, gpu.maxResolution())
  setBg(COLORS.bg)
  setFg(COLORS.text)
  gpuFill(1, 1, select(1, gpu.getResolution()), select(2, gpu.getResolution()), " ", COLORS.bg)

  addLog("BOOT", "Eon OC MVP started")
  addLog("BOOT", "node=" .. config.node)
  addLog("BOOT", "cfg=" .. CONFIG_PATH)

  collectAll()
  dumpComponents()
  render()

  return true
end

local function shutdown()
  if gpu then
    setBg(0x000000)
    setFg(0xFFFFFF)
    local w, h = gpu.getResolution()
    gpu.fill(1, 1, w, h, " ")
    gpu.set(1, 1, "Eon OC MVP stopped.")
  end
end

if boot() then
  while true do
    local ev = {event.pull(config.tick_seconds)}
    local name = ev[1]

    if name == "interrupted" then
      break
    elseif name == "key_down" then
      local result = handleKey(ev[2], ev[3], ev[4])
      if result == "quit" then break end
    elseif name == "chat_message" or name == "chat" then
      handleChatEvent(name, select(2, table.unpack(ev)))
    elseif name == "motion" then
      handleMotionEvent(select(2, table.unpack(ev)))
    elseif name == "entityDetect" then
      local entityName = ev[2]
      if entityName then
        state.entities[tostring(entityName) .. ":" .. tostring(ev[3] or "")] = {
          name = tostring(entityName),
          source = "entityDetect",
          seenAt = uptime(),
          raw = ev
        }
        addLog("ENTITY", tostring(entityName))
      end
    end

    local ok, err = pcall(function()
      collectAll()
      render()
    end)

    if not ok then
      incError(err)
    end
  end

  shutdown()
end
