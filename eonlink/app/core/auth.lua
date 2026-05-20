local computer = require("computer")
local M = {}

local previous = {}

local function contains(list, name)
  for _, item in ipairs(list or {}) do
    if item == name then return true end
  end
  return false
end

function M.apply(config, log)
  local members = config.members or {}
  local desired = {}
  for _, name in ipairs(members) do
    desired[name] = true
    if not contains(previous, name) then
      local ok, err = pcall(computer.addUser, name)
      if log then log[ok and "info" or "warn"](log, (ok and "member added: " or "member add failed: ") .. tostring(name) .. (ok and "" or " " .. tostring(err))) end
    end
  end
  for _, name in ipairs(previous) do
    if not desired[name] then
      local ok, err = pcall(computer.removeUser, name)
      if log then log[ok and "info" or "warn"](log, (ok and "member removed: " or "member remove failed: ") .. tostring(name) .. (ok and "" or " " .. tostring(err))) end
    end
  end
  previous = {}
  for _, name in ipairs(members) do previous[#previous + 1] = name end
end

return M
