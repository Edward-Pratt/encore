--!nonstrict
-- NetEase Cloud Music (music.163.com), a backup lyrics source: a large catalogue with
-- synced lyrics for many tracks LRCLIB lacks, and word timing ("yrc") for many. Its
-- public web API needs no account. Same step shape as lyrics-lrclib.luau: one step
-- searches, picks a song and fetches its lyrics, word-timed when it has them.
local http = require("./lyrics-http.luau")
local lrc = require("./lrc.luau")
local yrc = require("./yrc.luau")

local M = {}

local SEARCH = "https://music.163.com/api/search/get?type=1&limit=10&s="
local LYRIC = "https://music.163.com/api/song/lyric/v1?lv=-1&yv=-1&id="
local MAX_DRIFT_S = 15
-- NetEase's text for "pure music, enjoy": an instrumental.
local INSTRUMENTAL = "纯音乐"

local function artistMatches(song, artist)
  if artist == "" then return true end
  artist = string.lower(artist)
  for _, a in ipairs(song.artists or {}) do
    local name = string.lower(a.name or "")
    if name ~= "" and (string.find(artist, name, 1, true) or string.find(name, artist, 1, true)) then return true end
  end
  return false
end

-- Songs by a matching artist, closest length first, at most TRIES: { song, drift }.
local TRIES = 3
local function candidates(songs, q)
  local out = {}
  for _, song in ipairs(type(songs) == "table" and songs or {}) do
    if artistMatches(song, q.artist) then
      local drift = q.durationS > 0 and math.abs((tonumber(song.duration) or 0) / 1000 - q.durationS) or 0
      out[#out + 1] = { song = song, drift = drift }
    end
  end
  table.sort(out, function(a, b) return a.drift < b.drift end)
  while #out > TRIES do table.remove(out) end
  return out
end

local function result(reply, drift)
  if type(reply) ~= "table" or reply.nolyric or reply.uncollected then return nil end
  local text = type(reply.lrc) == "table" and reply.lrc.lyric or ""
  if type(text) ~= "string" or text == "" then return nil end
  if string.find(text, INSTRUMENTAL, 1, true) then return { status = "instrumental", source = "NetEase" } end
  local words = type(reply.yrc) == "table" and type(reply.yrc.lyric) == "string" and yrc.parse(reply.yrc.lyric) or {}
  local lines = #words > 0 and lrc.stripCredits(words) or lrc.stripCredits(lrc.parse(text))
  if #lines > 0 then return { status = "synced", lines = lines, source = "NetEase", loose = drift > MAX_DRIFT_S } end
  return nil
end

-- Releases of one song differ: the closest length may have no lyrics, or no word
-- timing, while the next does. So up to TRIES are fetched, closest first; the first
-- word-timed one wins, else the first with lyrics.
function M.steps(q)
  return { { words = true, run = function(next)
    http.get(SEARCH .. http.enc(q.title .. " " .. q.artist), function(v, err)
      local list = candidates(v and v.result and v.result.songs, q)
      if err or #list == 0 then return next(nil, err) end
      local fallback, i = nil, 0
      local function try()
        i += 1
        local c = list[i]
        if not c then return next(fallback, false) end
        http.get(LYRIC .. tostring(c.song.id), function(reply, err2)
          local found = not err2 and result(reply, c.drift) or nil
          if found and (found.status == "instrumental" or found.lines and found.lines[1] and found.lines[1].words) then
            return next(found, false)
          end
          fallback = fallback or found
          try()
        end)
      end
      try()
    end)
  end } }
end

return M
