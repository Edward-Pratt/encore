--!nonstrict
-- What to ask a lyrics source for, from what a player reports. Web players report video
-- titles ("Artist - Song (Official Video)") and channel names ("ArtistVEVO",
-- "Artist - Topic"), so the fallback query cleans them up. Pure, and plain Lua 5 so
-- tests/pure.lua can run it without noctalia.

local M = {}

local NOISE = {
  "official music video", "official video", "official audio", "official lyric video",
  "lyric video", "lyrics", "music video", "audio", "visualizer", "visualiser", "hd", "4k",
  "remastered", "explicit",
}

local function trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end

-- Drops bracketed parts that only describe the upload: "(Official Video)", "[HD]".
local function stripNoise(title)
  local function drop(inner)
    local lower = string.lower(inner)
    for _, word in ipairs(NOISE) do
      if string.find(lower, word, 1, true) then return "" end
    end
    return nil
  end
  title = string.gsub(title, "%s*(%b())", function(part) return drop(string.sub(part, 2, -2)) end)
  title = string.gsub(title, "%s*(%b[])", function(part) return drop(string.sub(part, 2, -2)) end)
  return trim(title)
end

local function cleanArtist(artist)
  artist = string.gsub(artist, "%s*%-%s*Topic$", "")
  artist = string.gsub(artist, "VEVO$", "")
  return trim(artist)
end

-- The exact query: what the player says, for sources that match on all fields.
function M.exact(track)
  return { artist = trim(track.artists or ""), title = trim(track.title or ""), album = trim(track.album or ""),
    durationS = math.floor((track.lengthMs or 0) / 1000 + 0.5) }
end

-- The cleaned query for a search, or nil when it would equal the exact one.
function M.cleaned(track)
  local exact = M.exact(track)
  local artist, title = cleanArtist(exact.artist), stripNoise(exact.title)
  -- "Artist - Song" in the title wins over a channel name.
  local a, t = string.match(title, "^(.-)%s+[%-–—]%s+(.+)$")
  if a and t then artist, title = trim(a), stripNoise(t) end
  if title == "" then return nil end
  if artist == exact.artist and title == exact.title then return nil end
  return { artist = artist, title = title, album = "", durationS = exact.durationS }
end

return M
