local M = { name = "inventory", version = "0.1.0", ctx = nil, elapsed = 0 }

function M.init(ctx) M.ctx = ctx end

function M.tick(dt)
  M.elapsed = M.elapsed + (dt or 0)
  if M.elapsed < 20 then return end
  M.elapsed = 0
  if M.ctx and M.ctx.net then
    M.ctx.net:send({ t = "inventory.status", slots = 16, used = 3 })
  end
end

function M.onMessage(msg) end

return M
