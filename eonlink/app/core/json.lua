local M = {}

local function skip(s, i)
  while true do
    local c = s:sub(i, i)
    if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then return i end
    i = i + 1
  end
end

local parseValue

local function parseString(s, i)
  i = i + 1
  local out = {}
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then return table.concat(out), i + 1 end
    if c == "\\" then
      local n = s:sub(i + 1, i + 1)
      if n == "n" then out[#out + 1] = "\n"
      elseif n == "r" then out[#out + 1] = "\r"
      elseif n == "t" then out[#out + 1] = "\t"
      else out[#out + 1] = n end
      i = i + 2
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  error("unterminated string")
end

local function parseNumber(s, i)
  local j = i
  while s:sub(j, j):match("[%d%+%-%e%E%.]") do j = j + 1 end
  return tonumber(s:sub(i, j - 1)), j
end

local function parseArray(s, i)
  local out = {}
  i = skip(s, i + 1)
  if s:sub(i, i) == "]" then return out, i + 1 end
  while true do
    local v
    v, i = parseValue(s, i)
    out[#out + 1] = v
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "]" then return out, i + 1 end
    if c ~= "," then error("expected comma") end
    i = skip(s, i + 1)
  end
end

local function parseObject(s, i)
  local out = {}
  i = skip(s, i + 1)
  if s:sub(i, i) == "}" then return out, i + 1 end
  while true do
    local key
    key, i = parseString(s, i)
    i = skip(s, i)
    if s:sub(i, i) ~= ":" then error("expected colon") end
    out[key], i = parseValue(s, skip(s, i + 1))
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "}" then return out, i + 1 end
    if c ~= "," then error("expected comma") end
    i = skip(s, i + 1)
  end
end

parseValue = function(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == '"' then return parseString(s, i) end
  if c == "{" then return parseObject(s, i) end
  if c == "[" then return parseArray(s, i) end
  if c == "t" and s:sub(i, i + 3) == "true" then return true, i + 4 end
  if c == "f" and s:sub(i, i + 4) == "false" then return false, i + 5 end
  if c == "n" and s:sub(i, i + 3) == "null" then return nil, i + 4 end
  return parseNumber(s, i)
end

function M.decode(s)
  local ok, value = pcall(function() return parseValue(s, 1) end)
  if ok then return value end
  return nil, value
end

local function encodeValue(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "string" then
    return '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t") .. '"'
  end
  if t == "table" then
    local isArray = true
    local max = 0
    for k in pairs(v) do
      if type(k) ~= "number" then isArray = false break end
      if k > max then max = k end
    end
    local out = {}
    if isArray then
      for i = 1, max do out[#out + 1] = encodeValue(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    for k, val in pairs(v) do
      out[#out + 1] = encodeValue(tostring(k)) .. ":" .. encodeValue(val)
    end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return "null"
end

function M.encode(v)
  return encodeValue(v)
end

return M
