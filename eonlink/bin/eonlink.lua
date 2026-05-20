local fs = require("filesystem")
local shell = require("shell")
local args = {...}

package.path = "/home/eonlink/?.lua;/home/eonlink/?/init.lua;" .. package.path

local manifestCore = "/home/eonlink/core/manifest.lua"
local manifestUrl = "https://raw.githubusercontent.com/FenyaVeyvon/opencomputers-dashboard/main/eonlink/manifest.lua"

local function loadCoreManifest()
  if not fs.exists(manifestCore) then return nil end
  package.loaded["core.manifest"] = nil
  return require("core.manifest")
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function fetchManifest()
  local core = loadCoreManifest()
  if core then return core.loadRemote() end
  local component = require("component")
  local ok, handle = pcall(component.internet.request, manifestUrl)
  if not ok or not handle then return nil, handle end
  local chunks = {}
  while true do
    local okRead, chunk = pcall(function() return handle.read() end)
    if not okRead then
      okRead, chunk = pcall(function() return handle.read(math.huge) end)
    end
    if not okRead then return nil, chunk end
    if not chunk then break end
    chunks[#chunks + 1] = chunk
  end
  pcall(function() handle.close() end)
  local fn = assert(load(table.concat(chunks), "=manifest", "t", {}))
  return fn()
end

local function install(mode)
  local manifest, err = fetchManifest()
  if not manifest then error(err) end
  local core = loadCoreManifest()
  if not core then
    shell.execute("wget -fq https://raw.githubusercontent.com/FenyaVeyvon/opencomputers-dashboard/main/installer/installer.lua /tmp/eonlink-installer.lua")
    shell.execute("/tmp/eonlink-installer.lua")
    return
  end
  assert(core.installFiles(manifest, mode))
  print("EonLink " .. mode .. " complete: " .. tostring(manifest.version))
end

local function run()
  shell.execute("/home/eonlink/main.lua")
end

local function listModules()
  print("Members are managed by backend config per node.")
end

local function writeConfig(cfg)
  local lines = {
    "return {",
    "  nodeId = " .. string.format("%q", cfg.nodeId or cfg.deviceId or "base_pc_1") .. ",",
    "",
    "  backend = {",
    "    host = " .. string.format("%q", cfg.backend.host or "open.eonhorizon.net") .. ",",
    "    port = " .. tostring(cfg.backend.port or 4445) .. ",",
    "    token = " .. string.format("%q", cfg.backend.token or "change-me"),
    "  },"
  }
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  debug = " .. tostring(cfg.debug and true or false)
  lines[#lines + 1] = "}"
  local fsutil = require("core.fsutil")
  assert(fsutil.writeAtomic("/home/eonlink/config.lua", table.concat(lines, "\n") .. "\n"))
end

local function setModule(name, enabled)
  error("members are managed by backend config")
end

local function version()
  local localVersion = read("/home/eonlink/VERSION") or "unknown"
  local manifest = fetchManifest()
  print("local: " .. localVersion:gsub("%s+$", ""))
  print("manifest: " .. tostring(manifest and manifest.version or "unknown"))
end

local cmd = args[1]
local ok, err = pcall(function()
  if cmd == "install" then install("install")
  elseif cmd == "update" then install("update")
  elseif cmd == "repair" then install("repair")
  elseif cmd == "run" then run()
  elseif cmd == "modules" then listModules()
  elseif cmd == "enable" then setModule(args[2], true)
  elseif cmd == "disable" then setModule(args[2], false)
  elseif cmd == "version" then version()
  else
    print("Usage: EonLink install|update|repair|run|modules|enable <module>|disable <module>|version")
  end
end)

if not ok then io.stderr:write("EonLink error: " .. tostring(err) .. "\n") end
