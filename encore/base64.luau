--!nonstrict
-- Base64 decoding (standard alphabet, padding optional, whitespace ignored), for lyrics
-- sources that send LRC encoded. Pure, and plain Lua 5 so tests/pure.lua can run it.

local M = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, #ALPHABET do VALUE[string.byte(ALPHABET, i)] = i - 1 end

-- The decoded bytes, or nil when the input holds a character outside the alphabet.
function M.decode(s)
  s = string.gsub(s or "", "[%s=]", "")
  local out, bits, count = {}, 0, 0
  for i = 1, #s do
    local v = VALUE[string.byte(s, i)]
    if not v then return nil end
    bits = bits * 64 + v
    count = count + 1
    if count == 4 then
      local a = math.floor(bits / 65536)
      local b = math.floor(bits / 256) % 256
      out[#out + 1] = string.char(a, b, bits % 256)
      bits, count = 0, 0
    end
  end
  if count == 3 then
    bits = bits * 64
    out[#out + 1] = string.char(math.floor(bits / 65536), math.floor(bits / 256) % 256)
  elseif count == 2 then
    bits = bits * 4096
    out[#out + 1] = string.char(math.floor(bits / 65536))
  end
  return table.concat(out)
end

return M
