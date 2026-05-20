local json = require("core.json")
local M = {}

function M.encode(tbl)
  return json.encode(tbl or {}) .. "\n"
end

function M.decode(line)
  return json.decode(line)
end

return M
