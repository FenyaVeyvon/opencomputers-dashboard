local component = require("component")
local term = require("term")
local M = {}

local gpu = component.isAvailable("gpu") and component.gpu or nil

local function color(bg, fg)
  if not gpu then return end
  gpu.setBackground(bg)
  gpu.setForeground(fg)
end

local function text(x, y, value, bg, fg)
  if not gpu then return end
  color(bg or 0x111111, fg or 0xffffff)
  gpu.set(x, y, tostring(value))
end

function M.draw(state)
  if not gpu then
    print("EonLink " .. tostring(state.status))
    return
  end
  local w, h = gpu.getResolution()
  color(0x0b0f14, 0xd7e1ea)
  term.clear()
  color(0x111827, 0x70e1ff)
  gpu.fill(1, 1, w, 3, " ")
  text(3, 2, "EonLink Node", 0x111827, 0x70e1ff)
  text(w - 18, 2, tostring(state.status or "offline"), 0x111827, state.connected and 0x6ee778 or 0xff6b6b)

  text(3, 5, "Node", 0x0b0f14, 0x8fa3b7)
  text(16, 5, state.node or "-", 0x0b0f14, 0xffffff)
  text(3, 6, "Backend", 0x0b0f14, 0x8fa3b7)
  text(16, 6, tostring(state.host) .. ":" .. tostring(state.port), 0x0b0f14, 0xffffff)
  text(3, 7, "Config", 0x0b0f14, 0x8fa3b7)
  text(16, 7, "v" .. tostring(state.configVersion or 0), 0x0b0f14, 0xffffff)

  color(0x16202b, 0xffffff)
  gpu.fill(3, 9, w - 4, 1, " ")
  text(5, 9, "Members", 0x16202b, 0x70e1ff)
  local y = 11
  for _, member in ipairs(state.members or {}) do
    if y < h - 6 then
      text(5, y, "+ " .. tostring(member), 0x0b0f14, 0xd7e1ea)
      y = y + 1
    end
  end

  color(0x16202b, 0xffffff)
  gpu.fill(3, h - 5, w - 4, 1, " ")
  text(5, h - 5, "Log", 0x16202b, 0x70e1ff)
  y = h - 3
  for i = math.max(1, #(state.logs or {}) - 2), #(state.logs or {}) do
    text(5, y, tostring(state.logs[i] or ""), 0x0b0f14, 0x8fa3b7)
    y = y + 1
  end
end

return M
