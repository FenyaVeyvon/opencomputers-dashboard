-- Mythic Chunky Turtle Telemetry v1.0 / CC:Tweaked + Advanced Peripherals
-- Install on the Chunky Turtle as startup.lua.
-- An Ender Modem (or Wireless Modem) must be installed on the turtle.
-- Radius MUST match the server's Advanced Peripherals chunkyTurtleRadius.
local PROTOCOL = "mythic.chunky.v1"
local RADIUS = 0
local LABEL = "BASE-TURTLE"

-- If you have no GPS hosts: enter the turtle's block coordinates from F3.
-- Leave nil to use GPS (if 4 GPS hosts are available).
local MANUAL_X, MANUAL_Y, MANUAL_Z = nil, nil, nil
-- Initial facing: 0 North (-Z), 1 East (+X), 2 South (+Z), 3 West (-X).
local START_FACING = 0

local state = {
  x = MANUAL_X, y = MANUAL_Y, z = MANUAL_Z,
  facing = START_FACING,
  source = MANUAL_X and MANUAL_Y and MANUAL_Z and "MANUAL" or "UNKNOWN",
  lastMove = "STANDBY",
}

local modemFound = false
peripheral.find("modem", function(name)
  rednet.open(name)
  modemFound = true
end)
if not modemFound then
  error("Attach a Wireless or Ender Modem to the turtle")
end

os.setComputerLabel(LABEL)
local dirNames = {"NORTH", "EAST", "SOUTH", "WEST"}
local startTime = os.clock()

local function syncGPS()
  local x, y, z = gps.locate(1, false)
  if x then
    state.x, state.y, state.z = math.floor(x + .5), math.floor(y + .5), math.floor(z + .5)
    state.source = "GPS"
  elseif state.source == "GPS" then
    state.source = "TRACKED"
  end
end

local function sendStatus()
  local hasPos = type(state.x) == "number" and type(state.y) == "number" and type(state.z) == "number"
  local cx, cz
  if hasPos then
    cx, cz = math.floor(state.x / 16), math.floor(state.z / 16)
  end
  rednet.broadcast({
    version = 1,
    id = os.getComputerID(),
    label = os.getComputerLabel(),
    x = state.x, y = state.y, z = state.z,
    cx = cx, cz = cz,
    facing = dirNames[state.facing + 1],
    source = state.source,
    fuel = turtle.getFuelLevel(),
    fuelLimit = turtle.getFuelLimit(),
    radius = RADIUS,
    action = state.lastMove,
    uptime = math.floor(os.clock() - startTime),
  }, PROTOCOL)
end

local function stepPosition(dx, dy, dz)
  if type(state.x) == "number" and type(state.y) == "number" and type(state.z) == "number" then
    state.x, state.y, state.z = state.x + dx, state.y + dy, state.z + dz
    if state.source == "GPS" then state.source = "TRACKED" end
  end
end

local vectors = {
  {0, -1}, -- North (dx, dz)
  {1, 0},  -- East
  {0, 1},  -- South
  {-1, 0}, -- West
}

local function doCommand(command, amount)
  local n = math.min(256, math.max(1, math.floor(tonumber(amount) or 1)))
  if command == "left" or command == "l" then
    turtle.turnLeft()
    state.facing = (state.facing + 3) % 4
    state.lastMove = "TURN LEFT"
    return true
  elseif command == "right" or command == "r" then
    turtle.turnRight()
    state.facing = (state.facing + 1) % 4
    state.lastMove = "TURN RIGHT"
    return true
  end
  local valid = {f = true, forward = true, b = true, back = true, u = true, up = true, d = true, down = true}
  if not valid[command] then return false, "Unknown command" end

  for i = 1, n do
    local ok, reason
    local dx, dz = table.unpack(vectors[state.facing + 1])
    if command == "f" or command == "forward" then
      ok, reason = turtle.forward()
      if ok then stepPosition(dx, 0, dz) end
    elseif command == "b" or command == "back" then
      ok, reason = turtle.back()
      if ok then stepPosition(-dx, 0, -dz) end
    elseif command == "u" or command == "up" then
      ok, reason = turtle.up()
      if ok then stepPosition(0, 1, 0) end
    else
      ok, reason = turtle.down()
      if ok then stepPosition(0, -1, 0) end
    end
    if not ok then return false, (reason or "Blocked") .. " at step " .. i end
  end
  state.lastMove = string.upper(command) .. " x" .. n
  return true
end

local function telemetryLoop()
  while true do
    syncGPS()
    sendStatus()
    sleep(3)
  end
end

local function commandLoop()
  print("MYTHIC CHUNKY TURTLE / #" .. os.getComputerID())
  print("Commands: f 10 | b 2 | u 4 | d 4 | l | r")
  print("Other: gps | pos | fuel | help")
  print("Telemetry is sent every 3 seconds.")
  while true do
    write("turtle> ")
    local input = read()
    if not input then return end
    local command, amount = input:lower():match("^%s*(%S+)%s*(%S*)")
    if command == "gps" then
      syncGPS()
      print("GPS mode: " .. state.source)
    elseif command == "pos" then
      print(("XYZ: %s, %s, %s [%s]"):format(tostring(state.x), tostring(state.y), tostring(state.z), state.source))
    elseif command == "fuel" then
      print("Fuel: " .. tostring(turtle.getFuelLevel()))
    elseif command == "help" then
      print("f/b/u/d [count] = movement; l/r = rotation")
      print("Start facing and manual coords are at top of file")
    elseif command then
      local ok, reason = doCommand(command, amount)
      if not ok then printError(reason) else print("OK: " .. state.lastMove) end
      sendStatus()
    end
  end
end

parallel.waitForAll(telemetryLoop, commandLoop)
