local M = { name = "chat", version = "0.1.0", ctx = nil }

function M.init(ctx) M.ctx = ctx end

function M.tick(dt) end

function M.onMessage(msg)
  if msg.t == "chat_send" then
    print("[chat] " .. tostring(msg.text or msg.message or ""))
    if M.ctx and M.ctx.net then
      M.ctx.net:send({ t = "chat_ack", id = M.ctx.config.deviceId })
    end
  end
end

return M
