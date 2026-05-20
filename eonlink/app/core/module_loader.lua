local M = {}

function M.load(config, ctx)
  local modules = {}
  for _, name in ipairs(config.modules or {}) do
    local ok, mod = pcall(require, "modules." .. name)
    if ok and type(mod) == "table" then
      local initOk, initErr = pcall(function() if mod.init then mod.init(ctx) end end)
      if initOk then
        modules[#modules + 1] = mod
        if ctx.log then ctx.log:info("module loaded: " .. tostring(mod.name or name)) end
      elseif ctx.log then
        ctx.log:error("module init failed " .. name .. ": " .. tostring(initErr))
      end
    elseif ctx.log then
      ctx.log:error("module load failed " .. name .. ": " .. tostring(mod))
    end
  end
  return modules
end

function M.tickAll(modules, dt)
  for _, mod in ipairs(modules or {}) do
    if mod.tick then pcall(mod.tick, dt) end
  end
end

function M.dispatchMessage(modules, msg)
  for _, mod in ipairs(modules or {}) do
    if mod.onMessage then pcall(mod.onMessage, msg) end
  end
end

return M
