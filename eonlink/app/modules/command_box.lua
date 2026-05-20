local M = { name = "command_box", version = "0.1.0", ctx = nil }

function M.init(ctx) M.ctx = ctx end

function M.tick(dt) end

local function send(result, value)
  if M.ctx and M.ctx.net then
    M.ctx.net:send({ t = "cmd_result", result = result, value = value or "" })
  end
end

function M.onMessage(msg)
  if msg.t ~= "cmd" then return end
  local cmd = tostring(msg.cmd or msg.command or "")
  if cmd == "ping" then
    send("pong")
  elseif cmd == "echo" then
    send("echo", msg.text or msg.value or "")
  elseif cmd == "scan_slots" then
    send("scan_slots", "slots=16;used=3")
  else
    send("unknown", cmd)
  end
end

return M
