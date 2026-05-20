local M = {}

function M.new()
  local bus = { listeners = {} }
  function bus:on(name, fn)
    self.listeners[name] = self.listeners[name] or {}
    table.insert(self.listeners[name], fn)
  end
  function bus:emit(name, data)
    for _, fn in ipairs(self.listeners[name] or {}) do
      pcall(fn, data)
    end
  end
  return bus
end

return M
