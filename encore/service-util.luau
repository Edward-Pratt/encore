--!nonstrict
-- The service's common ground: its data dir, publishing to the surfaces, JSON and the
-- file-name hash the art and lyrics caches share. Required by every service-*.luau.

local M = {}

M.DATA = noctalia.pluginDataDir() or ""

function M.decode(text)
  local v = noctalia.json.decode(text or "")
  return type(v) == "table" and v or nil
end

-- Publishes only real changes: every state.set wakes the widget, panel and launcher.
local published = {}
function M.publish(key, value)
  local encoded = noctalia.json.encode(value) or ""
  if published[key] == encoded then return end
  published[key] = encoded
  noctalia.state.set(key, value)
end

-- A cache file name for any string: two 32-bit multiplicative hashes, as hex. Products
-- stay below 2^53, so plain number arithmetic is exact.
function M.hash(s)
  local a, b = 2166136261, 5381
  for i = 1, #s do
    local c = string.byte(s, i)
    a = (a * 131 + c) % 4294967296
    b = (b * 33 + c) % 4294967296
  end
  return string.format("%08x%08x", a, b)
end

function M.dir(name)
  local path = M.DATA .. "/" .. name
  noctalia.mkdirAll(path)
  return path
end

return M
