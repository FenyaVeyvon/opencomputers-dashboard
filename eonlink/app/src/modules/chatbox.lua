local component = require("component")

local M = { name = "chatbox", version = "0.1.0", ctx = nil, chat = nil }

function M.init(ctx)
  M.ctx = ctx
  if component.isAvailable("chat_box") then
    M.chat = component.chat_box
  elseif component.isAvailable("chatBox") then
    M.chat = component.chatBox
  end
end

function M.onMessage(msg)
  if msg.t == "chat_send" and M.chat then
    pcall(M.chat.say, tostring(msg.text or msg.message or ""))
  end
end

function M.onEvent(ev)
  if not ev or not M.ctx or not M.ctx.net then return end
  if ev[1] == "chat_message" then
    M.ctx.net:send({
      t = "chat_message",
      node = M.ctx.config.nodeId,
      player = tostring(ev[3] or ev[2] or ""),
      message = tostring(ev[4] or ev[3] or "")
    })
  end
end

return M
