local component = require("component")
local protocol = require("core.protocol")
local M = {}

function M.new(config, log)
  local net = { config = config, log = log, socket = nil, buffer = "" }
  function net:connect()
    self:close()
    local host = tostring(self.config.host or "")
    host = host:gsub("^https?://", ""):gsub("/.*$", "")
    local ok, sock = pcall(component.internet.connect, host, self.config.port)
    if ok and sock then
      self.socket = sock
      return true
    end
    if self.log then self.log:warn("tcp connect failed: " .. tostring(sock)) end
    return nil, sock
  end
  function net:reconnect()
    self:close()
    return self:connect()
  end
  function net:close()
    if self.socket then
      local sock = self.socket
      pcall(function() sock.close() end)
    end
    self.socket = nil
    self.buffer = ""
  end
  function net:isConnected()
    return self.socket ~= nil
  end
  function net:send(msg)
    if not self.socket then return nil, "not connected" end
    local data = protocol.encode(msg)
    local ok, err = pcall(function() return self.socket.write(data) end)
    if not ok then
      ok, err = pcall(function() return self.socket.write(self.socket, data) end)
    end
    if not ok then self:close(); return nil, err end
    return true
  end
  function net:poll()
    if not self.socket then return nil end
    local ok, chunk = pcall(function() return self.socket.read(4096) end)
    if not ok then
      ok, chunk = pcall(function() return self.socket.read(self.socket, 4096) end)
    end
    if not ok then self:close(); return nil end
    if chunk and #chunk > 0 then self.buffer = self.buffer .. chunk end
    local line = self.buffer:match("^(.-)\n")
    if line then
      self.buffer = self.buffer:sub(#line + 2)
      return protocol.decode(line)
    end
    return nil
  end
  return net
end

return M
