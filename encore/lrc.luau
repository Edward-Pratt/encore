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

-- Moves every line and word earlier by an [offset:ms] tag (negative: later). A words
-- list is shared by the lines of one multi-stamp source line, so each moves once.
local function applyOffset(lines, offset)
  local moved = {}
  for _, line in ipairs(lines) do
    line.t = math.max(0, line.t - offset)
    if line.words and not moved[line.words] then
      moved[line.words] = true
      for _, w in ipairs(line.words) do w.t = math.max(0, w.t - offset) end
    end
  end
end

function M.parse(text)
  local lines = {}
  local offset = 0
  for line in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
    local raw = string.gsub(line, "\r$", "")
    local tag = string.match(raw, "^%s*%[offset:%s*([+-]?%d+)%s*%]")
    if tag then offset = tonumber(tag) end
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
  if offset ~= 0 then applyOffset(lines, offset) end
  table.sort(lines, function(a, b) return a.t < b.t end)
  return lines
end

local function isCredit(line)
  local text = line.text
  local colon = string.find(text, ":", 1, true) or string.find(text, "：", 1, true)
  local label = colon and string.sub(text, 1, colon - 1) or ""
  return label ~= "" and string.match(label, "^[\128-\255%s]+$") ~= nil
end

-- Drops credit lines such as "作词 : Name" (lyricist) or "编曲：Name" that some sources
-- (NetEase) put before and after the lyrics: a label of only non-ASCII characters before
-- a colon. Only the leading and trailing runs go: inside the song, "她说：..." ("she
-- said: ...") is a lyric. An empty line between two credits goes with them; empty
-- lines around the lyrics stay, since they time the gaps.
function M.stripCredits(lines)
  local first, last = 1, #lines
  for i = 1, #lines do
    if isCredit(lines[i]) then first = i + 1 elseif lines[i].text ~= "" then break end
  end
  for i = #lines, first, -1 do
    if isCredit(lines[i]) then last = i - 1 elseif lines[i].text ~= "" then break end
  end
  local out = {}
  for i = first, last do out[#out + 1] = lines[i] end
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
