local MANIFEST_URL = "https://raw.githubusercontent.com/FenyaVeyvon/opencomputers-dashboard/main/eonlink/manifest.lua"

local component = require("component")
local fs = require("filesystem")

local function readAll(url)
  local internet = component.internet
  local ok, handle = pcall(internet.request, url)
  if not ok or not handle then return nil, "request failed: " .. tostring(handle) end
  local chunks = {}
  while true do
    local okChunk, chunk = pcall(function() return handle.read() end)
    if not okChunk then
      okChunk, chunk = pcall(function() return handle.read(math.huge) end)
    end
    if not okChunk then return nil, "read failed: " .. tostring(chunk) end
    if not chunk then break end
    chunks[#chunks + 1] = chunk
  end
  pcall(function() handle.close() end)
  return table.concat(chunks)
end

local function mkdirp(path)
  if path and path ~= "" and not fs.exists(path) then
    local ok, err = pcall(fs.makeDirectory, path)
    if not ok then return nil, err end
  end
  return true
end

local function dirname(path)
  return path:match("^(.*)/[^/]+$") or "/"
end

local function writeAtomic(path, data)
  local dir = dirname(path)
  local ok, err = mkdirp(dir)
  if not ok then return nil, err end
  local tmp = path .. ".tmp"
  local file, openErr = io.open(tmp, "w")
  if not file then return nil, openErr end
  file:write(data)
  file:close()
  if fs.exists(path) then pcall(fs.remove, path) end
  local moved, moveErr = pcall(fs.rename, tmp, path)
  if not moved then return nil, moveErr end
  return true
end

local function loadManifest()
  local data, err = readAll(MANIFEST_URL)
  if not data then return nil, err end
  local fn, loadErr = load(data, "=manifest", "t", {})
  if not fn then return nil, loadErr end
  local ok, manifest = pcall(fn)
  if not ok then return nil, manifest end
  return manifest
end

local function install()
  local manifest, err = loadManifest()
  if not manifest then error(err) end
  for _, f in ipairs(manifest.files or {}) do
    local target
    if f.target then
      target = f.target
    elseif f.path:match("^bin/") then
      target = "/bin/" .. f.path:match("bin/(.+)$")
    else
      target = manifest.installDir .. "/" .. f.path
    end
    if target ~= manifest.installDir .. "/config.lua" then
      local data, dlErr = readAll(f.url)
      if not data then error(dlErr) end
      local okWrite, writeErr = writeAtomic(target, data)
      if not okWrite then error(writeErr) end
    end
  end
  if not fs.exists(manifest.installDir .. "/config.lua") then
    local data = table.concat({
      "return {",
      "  nodeId = \"base_pc_1\",",
      "",
      "  backend = {",
      "    host = \"open.eonhorizon.net\",",
      "    port = 4444,",
      "    token = \"change-me\"",
      "  },",
      "",
      "  debug = true",
      "}",
      ""
    }, "\n")
    assert(writeAtomic(manifest.installDir .. "/config.lua", data))
  end
  print("EonLink installed: " .. tostring(manifest.version))
end

local ok, err = pcall(install)
if not ok then
  io.stderr:write("EonLink install failed: " .. tostring(err) .. "\n")
end
