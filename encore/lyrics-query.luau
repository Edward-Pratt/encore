--!nonstrict
-- What to ask a lyrics source for, from what a player reports. Web players report video
-- titles ("Artist - Song (Official Video)") and channel names ("ArtistVEVO",
-- "Artist - Topic"); streaming apps add version tails ("Song - 2006 Remaster") and
-- alternative titles in brackets ("Song (Why Don't You Use It!)"). The fallback query
-- drops all of that. Pure, and plain Lua 5 so tests/pure.lua can run it without noctalia.

local M = {}

local NOISE = {
  "official music video", "official video", "official audio", "official lyric video",
  "lyric video", "lyrics", "music video", "audio", "visualizer", "visualiser", "hd", "4k",
  "remastered", "explicit",
}

-- Words that mark a " - ..." tail as a version of the song rather than part of its name.
local VERSION = {
  "remaster", "live", "version", "mix", "edit", "mono", "stereo", "single", "acoustic", "demo",
  "bonus", "instrumental", "deluxe", "anniversary", "recorded", "radio", "session",
}

-- " - ", " – " or " — " between two parts. The en and em dash are three bytes each in
-- UTF-8, so they cannot sit in a Lua character class: each dash is its own pattern.
local DASHES = { "^(.-)%s+%-%s+(.+)$", "^(.-)%s+–%s+(.+)$", "^(.-)%s+—%s+(.+)$" }

-- The parts before and after the first dash, or nil.
local function splitDash(s)
  local base, tail
  for _, pattern in ipairs(DASHES) do
    local b, t = string.match(s, pattern)
    if b and (not base or #b < #base) then base, tail = b, t end
  end
  return base, tail
end

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

local function isVersion(tail)
  local lower = string.lower(tail)
  if string.match(lower, "^%d%d%d%d$") then return true end
  for _, word in ipairs(VERSION) do
    if string.find(lower, word, 1, true) then return true end
  end
  return false
end

-- "Song - 2006 Remaster" -> "Song".
local function stripVersion(title)
  local base, tail = splitDash(title)
  if base and isVersion(tail) then return trim(base) end
  return title
end

-- Every bracketed part: "Song (Why Don't You Use It!) [Live]" -> "Song".
local function stripBrackets(title)
  local s = string.gsub(title, "%s*%b()", "")
  s = string.gsub(s, "%s*%b[]", "")
  return trim(s)
end

local function cleanArtist(artist)
  artist = string.gsub(artist, "%s*%-%s*Topic$", "")
  artist = string.gsub(artist, "VEVO$", "")
  return trim(artist)
end

-- Whether a source's artist name is the queried one: either contains the other, ignoring
-- case ("Queen" matches "Queen & David Bowie"). Any name matches an empty query artist.
function M.sameArtist(queried, name)
  queried, name = string.lower(queried or ""), string.lower(name or "")
  if queried == "" then return true end
  if name == "" then return false end
  return string.find(queried, name, 1, true) ~= nil or string.find(name, queried, 1, true) ~= nil
end

-- The exact query: what the player says, for sources that match on all fields.
function M.exact(track)
  return { artist = trim(track.artists or ""), title = trim(track.title or ""), album = trim(track.album or ""),
    durationS = math.floor((track.lengthMs or 0) / 1000 + 0.5) }
end

-- The cleaned query for a search, or nil when it would equal the exact one.
function M.cleaned(track)
  local exact = M.exact(track)
  local artist, title = cleanArtist(exact.artist), stripVersion(stripNoise(exact.title))
  -- "Artist - Song" in a video title: split only when the player's artist is a channel
  -- (VEVO, "- Topic", none) or the left part names the artist, so a music app's
  -- "Song - Something" keeps its title.
  local a, t = splitDash(title)
  if a and t then
    local channel = exact.artist == "" or artist ~= exact.artist
    local names = artist ~= "" and string.find(string.lower(a), string.lower(artist), 1, true)
    if channel or names then artist, title = trim(a), stripVersion(stripNoise(t)) end
  end
  local bare = stripBrackets(title)
  if bare ~= "" then title = bare end
  if title == "" then return nil end
  if artist == exact.artist and title == exact.title then return nil end
  return { artist = artist, title = title, album = "", durationS = exact.durationS }
end

return M
