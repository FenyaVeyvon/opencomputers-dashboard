-- Mythic Chunk Loader Dashboard v1.0
-- Install as startup.lua on an Advanced Computer with an Ender Modem.
-- Connect a 4-wide x 3-tall Advanced Monitor (wired directly or via wired modem).
local PROTOCOL = "mythic.chunky.v1"
local FILTER_TURTLE_ID = nil -- Set to a turtle computer ID if you have several turtles.
local STALE_AFTER = 9
local monitor = peripheral.find("monitor")
if not monitor then error("Attach an Advanced Monitor to this computer") end
monitor.setTextScale(0.5)
local mw, mh = monitor.getSize()
local modemCount = 0
peripheral.find("modem", function(name)
  rednet.open(name)
  modemCount = modemCount + 1
end)
if modemCount == 0 then error("Attach a modem to the main computer") end

local last, lastAt = nil, 0
local C = colors
local function fill(x, y, n, bg, char)
  if y < 1 or y > mh or x > mw or n < 1 then return end
  n = math.min(n, mw - x + 1)
  if n < 1 then return end
  monitor.setBackgroundColor(bg)
  monitor.setTextColor(C.white)
  monitor.setCursorPos(x, y)
  monitor.write(string.rep(char or " ", n))
end
local function put(x, y, str, fg, bg)
  if y < 1 or y > mh or x > mw then return end
  local s = tostring(str):sub(1, mw - x + 1)
  monitor.setBackgroundColor(bg or C.black)
  monitor.setTextColor(fg or C.white)
  monitor.setCursorPos(x, y)
  monitor.write(s)
end
local function field(x, y, title, value, col)
  put(x, y, title, C.lightGray)
  put(x, y + 1, tostring(value), col or C.white)
end
local function draw()
  mw, mh = monitor.getSize()
  monitor.setBackgroundColor(C.black)
  monitor.clear()
  local alive = last and (os.clock() - lastAt) <= STALE_AFTER
  fill(1, 1, mw, C.blue)
  put(2, 1, "MYTHIC // CHUNK NETWORK", C.white, C.blue)
  put(math.max(1, mw - 9), 1, alive and "[ONLINE]" or "[OFFLINE]", alive and C.lime or C.red, C.blue)
  put(2, 3, "LIVE LOADED AREA (ESTIMATE)", C.cyan)
  fill(2, 4, mw - 2, C.gray, "-")
  local hasCoords = last and type(last.cx) == "number" and type(last.cz) == "number"
  local size = 11
  local left, top = 3, 6
  local radius = last and math.max(0, math.floor(tonumber(last.radius) or 0)) or 0
  local hMap = math.min(size, mh - top - 3)
  if hMap > 0 then
    for row = 0, hMap - 1 do
      for col = 0, size - 1 do
        local dx, dz = col - 5, row - 5
        local bg = C.gray
        local marker = "  "
        if hasCoords then
          if math.abs(dx) <= radius and math.abs(dz) <= radius then bg = alive and C.green or C.brown end
          if dx == 0 and dz == 0 then bg = alive and C.cyan or C.red; marker = "@@" end
        end
        fill(left + col * 2, top + row, 2, bg, " ")
        if marker ~= "  " then put(left + col * 2, top + row, marker, C.black, bg) end
      end
    end
  end
  local side = 28
  if mw < 48 then
    put(2, mh - 3, "Monitor too small; use 4x3, scale 0.5", C.orange)
  else
    field(side, 6, "TURTLE", last and ("#" .. tostring(last.id) .. " " .. tostring(last.label)) or "WAITING FOR SIGNAL", C.cyan)
    field(side, 9, "BLOCK XYZ", hasCoords and (last.x .. ", " .. last.y .. ", " .. last.z) or "UNKNOWN / NO GPS", hasCoords and C.white or C.orange)
    field(side, 12, "CHUNK X / Z", hasCoords and (last.cx .. " / " .. last.cz) or "UNKNOWN", C.white)
    field(side, 15, "LOADED ZONE*", last and ((radius * 2 + 1) .. " x " .. (radius * 2 + 1) .. " chunks") or "UNKNOWN", C.lime)
    field(side, 18, "FUEL", last and (tostring(last.fuel) .. " / " .. tostring(last.fuelLimit)) or "---", C.orange)
    if mh >= 25 then
      field(side, 21, "POSITION SOURCE", last and last.source or "---", C.cyan)
      field(side, 24, "HEADING", last and last.facing or "---", C.white)
    end
  end
  if mh >= 21 then
    put(3, 19, "N", C.lightGray)
    put(13, 19, "+X >", C.lightGray)
  end
  fill(1, mh - 1, mw, C.gray)
  put(2, mh - 1, alive and "LINK: CONNECTED" or "LINK: NO HEARTBEAT", alive and C.lime or C.red, C.gray)
  put(2, mh, "*Estimated from configured radius; no server-side verification", C.lightGray)
end

monitor.setBackgroundColor(C.black)
monitor.clear()
draw()
while true do
  local id, message = rednet.receive(PROTOCOL, 1.5)
  if id and type(message) == "table" and message.version == 1 then
    if (FILTER_TURTLE_ID == nil or id == FILTER_TURTLE_ID) then
      message.id = id
      last, lastAt = message, os.clock()
    end
  end
  draw()
end
