local downloader = require("core.downloader")
local fsutil = require("core.fsutil")
local M = {}

M.url = "https://raw.githubusercontent.com/FenyaVeyvon/opencomputers-dashboard/main/eonlink/manifest.lua"

function M.loadRemote()
  local data, err = downloader.fetch(M.url)
  if not data then return nil, err end
  local fn, loadErr = load(data, "=eonlink-manifest", "t", {})
  if not fn then return nil, loadErr end
  local ok, manifest = pcall(fn)
  if not ok then return nil, manifest end
  return manifest
end

function M.targetFor(manifest, file)
  if file.target then return file.target end
  if file.path:match("^bin/") then return "/bin/" .. file.path:match("bin/(.+)$") end
  return manifest.installDir .. "/" .. file.path
end

function M.installFiles(manifest, mode)
  for _, file in ipairs(manifest.files or {}) do
    local target = M.targetFor(manifest, file)
    if target ~= manifest.installDir .. "/config.lua" then
      if mode ~= "repair" or not fsutil.exists(target) then
        local ok, err = downloader.download(file.url, target)
        if not ok then return nil, err end
      end
    end
  end
  return true
end

return M
