local auth = require("core.auth")

local M = {}

function M.apply(config, log)
  auth.apply({ members = config.members or {} }, log)
end

return M
