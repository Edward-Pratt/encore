--!nonstrict
-- LRCLIB (lrclib.net), the first lyrics source. steps(q, exact) returns the lookups for
-- one query, each { run = function(next), words } where run calls next(result, failed)
-- and words says whether the source can give word timing; result is
-- { status = "synced" | "plain" | "instrumental", lines | plain, source, loose } or nil.
-- loose: the closest version found is more than MAX_DRIFT_S off the player's length (a
-- different edit, or a wrong length from the player), so its timing may not match.
local http = require("./lyrics-http.luau")
local lrc = require("./lrc.luau")

local M = {}

local API = "https://lrclib.net/api/"
-- A search hit this far from the player's length is a different recording.
local MAX_DRIFT_S = 15

local function result(entry, drift)
  if type(entry) ~= "table" then return nil end
  if entry.instrumental then return { status = "instrumental", source = "LRCLIB" } end
  local synced = type(entry.syncedLyrics) == "string" and lrc.parse(entry.syncedLyrics) or {}
  if #synced > 0 then return { status = "synced", lines = synced, source = "LRCLIB", loose = (drift or 0) > MAX_DRIFT_S } end
  if type(entry.plainLyrics) == "string" and entry.plainLyrics ~= "" then
    return { status = "plain", plain = entry.plainLyrics, source = "LRCLIB" }
  end
  return nil
end

-- The best search hit and its drift: a synced one within MAX_DRIFT_S, else any within
-- it, else the closest synced one, else the closest.
local function best(list, durationS)
  local pick, pickScore, pickDrift = nil, nil, 0
  for _, entry in ipairs(type(list) == "table" and list or {}) do
    local drift = durationS > 0 and math.abs((tonumber(entry.duration) or 0) - durationS) or 0
    local synced = type(entry.syncedLyrics) == "string" and entry.syncedLyrics ~= ""
    local score = (drift > MAX_DRIFT_S and 2000 or 0) + (synced and 0 or 1000) + drift
    if not pickScore or score < pickScore then pick, pickScore, pickDrift = entry, score, drift end
  end
  return pick, pickDrift
end

local function url(path, q, withAlbum)
  local parts = { "track_name=" .. http.enc(q.title), "artist_name=" .. http.enc(q.artist) }
  if withAlbum then
    if q.album ~= "" then parts[#parts + 1] = "album_name=" .. http.enc(q.album) end
    if q.durationS > 0 then parts[#parts + 1] = "duration=" .. q.durationS end
  end
  return API .. path .. "?" .. table.concat(parts, "&")
end

-- exact: the player's own fields, so the exact-match endpoint is worth asking; a
-- cleaned query only searches.
function M.steps(q, exact)
  local steps = {}
  if exact then
    steps[#steps + 1] = { words = false, run = function(next)
      http.get(url("get", q, true), function(v, err) next(result(v), err) end)
    end }
  end
  steps[#steps + 1] = { words = false, run = function(next)
    http.get(url("search", q, false), function(v, err) next(result(best(v, q.durationS)), err) end)
  end }
  return steps
end

return M
