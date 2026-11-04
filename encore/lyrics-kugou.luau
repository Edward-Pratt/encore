--!nonstrict
-- Kugou (lyrics.kugou.com), a backup lyrics source with synced LRC for a large
-- catalogue. Its public lyrics search needs no account: one request finds candidates
-- by "artist - title" and length, a second downloads the chosen one as base64 LRC.
-- Same step shape as lyrics-lrclib.luau.
local http = require("./lyrics-http.luau")
local lrc = require("./lrc.luau")
local base64 = require("./base64.luau")
local query = require("./lyrics-query.luau")

local M = {}

local SEARCH = "https://lyrics.kugou.com/search?ver=1&man=yes&client=pc"
local DOWNLOAD = "https://lyrics.kugou.com/download?ver=1&client=pc&fmt=lrc&charset=utf8"
local MAX_DRIFT_S = 15

-- The candidate by the queried artist with the closest length, and its drift in seconds.
-- Kugou's search is fuzzy: without the artist check it hands back other songs' lyrics.
local function pick(candidates, q)
  local best, bestDrift = nil, nil
  for _, c in ipairs(type(candidates) == "table" and candidates or {}) do
    local drift = q.durationS > 0 and math.abs((tonumber(c.duration) or 0) / 1000 - q.durationS) or 0
    if c.id and c.accesskey and query.sameArtist(q.artist, c.singer) and (not bestDrift or drift < bestDrift) then
      best, bestDrift = c, drift
    end
  end
  return best, bestDrift or 0
end

-- Kugou opens with a "Title - Artist" line at 0:00; it is not a lyric.
local function dropTitleLine(lines, q)
  local first = lines[1]
  if first and first.t < 1000 and string.lower(first.text) == string.lower(q.title .. " - " .. q.artist) then
    table.remove(lines, 1)
  end
  return lines
end

local function result(reply, q, drift)
  if type(reply) ~= "table" or type(reply.content) ~= "string" then return nil end
  local text = base64.decode(reply.content)
  if not text then return nil end
  local lines = dropTitleLine(lrc.stripCredits(lrc.parse(text)), q)
  if #lines == 0 then return nil end
  return { status = "synced", lines = lines, source = "Kugou", loose = drift > MAX_DRIFT_S }
end

function M.steps(q)
  return { { run = function(next)
    local url = SEARCH .. "&keyword=" .. http.enc(q.artist .. " - " .. q.title)
    if q.durationS > 0 then url ..= "&duration=" .. (q.durationS * 1000) end
    http.get(url, function(v, err)
      local c, drift = pick(v and v.candidates, q)
      if err or not c then return next(nil, err) end
      http.get(`{DOWNLOAD}&id={c.id}&accesskey={c.accesskey}`, function(reply, err2) next(result(reply, q, drift), err2) end)
    end)
  end } }
end

return M
