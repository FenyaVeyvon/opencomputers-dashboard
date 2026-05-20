local M = {}

function M.new(debug)
  local log = { debugEnabled = debug and true or false }
  local function line(level, msg)
    print(os.date("%H:%M:%S") .. " [" .. level .. "] " .. tostring(msg))
  end
  function log:debug(msg) if self.debugEnabled then line("DEBUG", msg) end end
  function log:info(msg) line("INFO", msg) end
  function log:warn(msg) line("WARN", msg) end
  function log:error(msg) line("ERROR", msg) end
  return log
end

return M
