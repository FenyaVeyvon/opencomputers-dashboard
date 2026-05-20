local M = { name = "machines", version = "0.1.0", ctx = nil, elapsed = 0 }

function M.init(ctx) M.ctx = ctx end

function M.tick(dt)
  M.elapsed = M.elapsed + (dt or 0)
  if M.elapsed < 15 then return end
  M.elapsed = 0
  if M.ctx and M.ctx.net then
    M.ctx.net:send({ t = "machine.status", online = true, active = 0 })
  end
end

function M.onMessage(msg) end

return M
