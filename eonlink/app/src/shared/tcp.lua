local component = require("component")
local protocol = require("core.protocol")

local M = {}

local function readAll(handle)
  local chunks = {}
  while true do
    local ok, chunk = pcall(function() return handle.read() end)
    if not ok then ok, chunk = pcall(function() return handle.read(math.huge) end) end
    if not ok then return nil, chunk end
    if not chunk then break end
    chunks[#chunks + 1] = chunk
  end
  pcall(function() handle.close() end)
  return table.concat(chunks)
end

local function hostOnly(value)
  return tostring(value or ""):gsub("^https?://", ""):gsub("/.*$", "")
end

local function baseUrl(config)
  return "http://" .. hostOnly(config.host)
end

function M.new(config, log)
  local tcp = { config = config, log = log, connected = false, inbox = {} }

  function tcp:connect()
    local ok, handle = pcall(component.internet.request, baseUrl(self.config) .. "/api/health")
    if not ok or not handle then
      self.connected = false
      return nil, handle
    end
    local body, err = readAll(handle)
    if not body then
      self.connected = false
      return nil, err
    end
    local decoded = protocol.decode(body)
    if not decoded or decoded.ok ~= true then
      self.connected = false
      return nil, "backend unavailable"
    end
    self.connected = true
    return true
  end

  function tcp:reconnect()
    self:close()
    return self:connect()
  end

  function tcp:close()
    self.connected = false
  end

  function tcp:isConnected()
    return self.connected
  end

  function tcp:send(msg)
    local node = tostring(self.config.nodeId or self.config.node or msg.node or "base_pc_1")
    local url = baseUrl(self.config) .. "/api/nodes/" .. node .. "/rpc"
    local headers = { ["Content-Type"] = "application/json" }
    local ok, handle = pcall(component.internet.request, url, protocol.encode(msg):gsub("\n$", ""), headers, "POST")
    if not ok or not handle then
      self.connected = false
      return nil, handle
    end
    local body, err = readAll(handle)
    if not body then
      self.connected = false
      return nil, err
    end
    local decoded = protocol.decode(body)
    if decoded then self.inbox[#self.inbox + 1] = decoded end
    self.connected = true
    return true
  end

  function tcp:poll()
    if #self.inbox == 0 then return nil end
    return table.remove(self.inbox, 1)
  end

  return tcp
end

return M
