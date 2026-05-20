local M = {}

function M.new()
  local state = { values = {} }
  function state:get(key, default)
    local v = self.values[key]
    if v == nil then return default end
    return v
  end
  function state:set(key, value)
    self.values[key] = value
  end
  return state
end

return M
