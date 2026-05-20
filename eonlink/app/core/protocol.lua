local M = {}

local function esc(v)
  return tostring(v):gsub("%%", "%%25"):gsub(";", "%%3B"):gsub("=", "%%3D"):gsub("\n", "%%0A")
end

local function unesc(v)
  return tostring(v):gsub("%%0A", "\n"):gsub("%%3D", "="):gsub("%%3B", ";"):gsub("%%25", "%%")
end

function M.encode(tbl)
  local parts = {}
  for k, v in pairs(tbl or {}) do
    if type(v) ~= "table" then
      parts[#parts + 1] = esc(k) .. "=" .. esc(v)
    end
  end
  return table.concat(parts, ";") .. "\n"
end

function M.decode(line)
  local msg = {}
  for part in tostring(line or ""):gmatch("[^;]+") do
    local k, v = part:match("^([^=]+)=(.*)$")
    if k then msg[unesc(k)] = unesc(v) end
  end
  return msg
end

return M
