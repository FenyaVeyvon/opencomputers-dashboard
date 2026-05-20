local fs = require("filesystem")
local M = {}

function M.dirname(path)
  return path:match("^(.*)/[^/]+$") or "/"
end

function M.exists(path)
  return fs.exists(path)
end

function M.mkdirp(path)
  if path and path ~= "" and not fs.exists(path) then
    return pcall(fs.makeDirectory, path)
  end
  return true
end

function M.readFile(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local data = f:read("*a")
  f:close()
  return data
end

function M.writeAtomic(path, data)
  local ok, err = M.mkdirp(M.dirname(path))
  if not ok then return nil, err end
  local tmp = path .. ".tmp"
  local f, openErr = io.open(tmp, "w")
  if not f then return nil, openErr end
  f:write(data or "")
  f:close()
  if fs.exists(path) then pcall(fs.remove, path) end
  local moved, moveErr = pcall(fs.rename, tmp, path)
  if not moved then return nil, moveErr end
  return true
end

return M
