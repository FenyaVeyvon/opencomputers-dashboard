local component = require("component")
local protocol = require("core.protocol")
local M = {}

function M.new(config, log)
  local net = { config = config, log = log, connected = false, inbox = {} }

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

  local function endpoint(self)
    local host = tostring(self.config.host or "")
    host = host:gsub("^https?://", ""):gsub("/.*$", "")
    local node = tostring(self.config.nodeId or self.config.node or "base_pc_1")
    return "http://" .. host .. "/api/nodes/" .. node .. "/rpc"
  end

  function net:connect()
    self.connected = true
    return true
  end

  function net:reconnect()
    self:close()
    return self:connect()
  end

  function net:close()
    self.connected = false
  end

  function net:isConnected()
    return self.connected
  end

  function net:send(msg)
    local data = protocol.encode(msg):gsub("\n$", "")
    local headers = { ["Content-Type"] = "application/json" }
    local ok, handle = pcall(component.internet.request, endpoint(self), data, headers, "POST")
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
    return true
  end

  function net:poll()
    if #self.inbox == 0 then return nil end
    return table.remove(self.inbox, 1)
  end

  return net
end

return M
