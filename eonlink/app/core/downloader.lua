local component = require("component")
local fsutil = require("core.fsutil")
local M = {}

function M.fetch(url)
  local ok, handle = pcall(component.internet.request, url)
  if not ok or not handle then return nil, tostring(handle) end
  local chunks = {}
  while true do
    local okRead, chunk = pcall(function() return handle.read() end)
    if not okRead then
      okRead, chunk = pcall(function() return handle.read(math.huge) end)
    end
    if not okRead then return nil, tostring(chunk) end
    if not chunk then break end
    chunks[#chunks + 1] = chunk
  end
  pcall(function() handle.close() end)
  return table.concat(chunks)
end

function M.download(url, target)
  local data, err = M.fetch(url)
  if not data then return nil, err end
  return fsutil.writeAtomic(target, data)
end

return M
