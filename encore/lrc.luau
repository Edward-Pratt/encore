--!nonstrict
-- LRC lyrics: parse "[mm:ss.xx] text" lines into { t = ms, text } sorted by time, and
-- find the line playing at a position. Enhanced LRC ("[00:12.00]<00:12.00>Some
-- <00:12.40>words") also gives words = [{ t, text, space }], as yrc.luau does. Pure, and plain Lua 5 so tests/pure.lua can run
-- it without noctalia.

local M = {}

local function ms(mm, ss, frac)
  local v = (tonumber(mm) * 60 + tonumber(ss)) * 1000
  if frac ~= "" then v = v + math.floor(tonumber(frac) * 10 ^ (3 - #frac) + 0.5) end
  return v
end

-- Words from "<mm:ss.xx>word <mm:ss.xx>word", or nil without word stamps; and the text
-- with the stamps removed.
local function words(rest)
  if not string.find(rest, "<%d+:%d+[%.:]?%d*>") then return nil, rest end
  local list, plain = {}, string.gsub(rest, "<%d+:%d+[%.:]?%d*>", "")
  for mm, ss, frac, raw in string.gmatch(rest, "<(%d+):(%d+)[%.:]?(%d*)>([^<]*)") do
    local word = string.match(raw, "^%s*(.-)%s*$")
    if word ~= "" then list[#list + 1] = { t = ms(mm, ss, frac), text = word, space = string.match(raw, "%s$") ~= nil } end
  end
  return #list > 0 and list or nil, plain
end

function M.parse(text)
  local lines = {}
  for line in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
    local raw = string.gsub(line, "\r$", "")
    -- One line may carry several stamps: "[00:12.00][01:30.50] chorus".
    local stamps = {}
    local rest = raw
    while true do
      local mm, ss, frac, after = string.match(rest, "^%s*%[(%d+):(%d+)[%.:]?(%d*)%](.*)$")
      if not mm then break end
      stamps[#stamps + 1] = ms(mm, ss, frac)
      rest = after
    end
    local list, plain = words(rest)
    local lineText = string.match(plain, "^%s*(.-)%s*$")
    for _, t in ipairs(stamps) do lines[#lines + 1] = { t = t, text = lineText, words = list } end
  end
  table.sort(lines, function(a, b) return a.t < b.t end)
  return lines
end

-- Drops credit lines such as "作词 : Name" (lyricist) or "编曲：Name" that some sources
-- (NetEase) put among the lyrics: a label of only non-ASCII characters before a colon.
function M.stripCredits(lines)
  local out = {}
  for _, line in ipairs(lines) do
    local text = line.text
    local colon = string.find(text, ":", 1, true) or string.find(text, "：", 1, true)
    local label = colon and string.sub(text, 1, colon - 1) or ""
    if not (label ~= "" and string.match(label, "^[\128-\255%s]+$")) then out[#out + 1] = line end
  end
  return out
end

-- Index of the last line that has started by `ms`, or 0 before the first.
function M.lineAt(lines, ms)
  local lo, hi = 1, #lines
  local found = 0
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if lines[mid].t <= ms then
      found = mid
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return found
end

return M
