--!nonstrict
-- NetEase "yrc" word-timed lyrics: lines like
--   [28000,9300](28000,1550,0)Beween (29550,1550,0)the (31100,1550,0)father
-- parsed to { t, text, words = [{ t, text, space }] } sorted by time, the same shape
-- lrc.parse gives (lines without word timing have no `words`). A word may be a syllable;
-- space says whether a space follows it. Credit lines arrive as JSON
-- objects ({"t":0,"c":[...]}) and are skipped. Pure, and plain Lua 5 so tests/pure.lua
-- can run it without noctalia.

local M = {}

local function trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end

function M.parse(text)
  local lines = {}
  for raw in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
    local start, rest = string.match(raw, "^%[(%d+),%d+%](.*)$")
    if start then
      -- Split on the timing markers themselves, so a word may hold "(" as in "(oh)".
      local words, parts = {}, {}
      local MARK = "%((%d+),%d+,%-?%d+%)"
      local s, e, wt = string.find(rest, MARK)
      while s do
        local ns, ne, nwt = string.find(rest, MARK, e + 1)
        local raw = string.sub(rest, e + 1, (ns or #rest + 1) - 1)
        local word = trim(raw)
        if word ~= "" then
          words[#words + 1] = { t = tonumber(wt), text = word, space = string.match(raw, "%s$") ~= nil }
          parts[#parts + 1] = raw
        end
        s, e, wt = ns, ne, nwt
      end
      if #words > 0 then
        lines[#lines + 1] = { t = tonumber(start), text = trim(table.concat(parts)), words = words }
      end
    end
  end
  table.sort(lines, function(a, b) return a.t < b.t end)
  return lines
end

return M
