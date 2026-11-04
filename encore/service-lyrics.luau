--!nonstrict
-- Lyrics for the shown track, published as `lyrics`:
--   { key, status = "off" | "idle" | "loading" | "synced" | "plain" | "instrumental" | "none" | "error",
--     lines = [{ t, text }] (synced), plain = string (plain),
--     source = "LRCLIB" | "NetEase" | "Kugou", loose = true when the version's length differs }
-- One lookup per track, asking every source at once (lyrics-lookup.luau): LRCLIB, and
-- NetEase and Kugou with lyrics_backup. The first usable result shows at once and
-- better ones replace it; the best is cached in <data>/lyrics. Misses and instrumentals
-- are asked again after a week, failures every 30 s up to three times.
local util = require("./service-util.luau")
local media = require("./media.luau")
local query = require("./lyrics-query.luau")
local lookup = require("./lyrics-lookup.luau")

local M = {}

local MISS_RETRY_MS = 7 * 86400000
-- Longer than this is a stream, podcast or long video: not looked up at all.
local MAX_TRACK_MS = 20 * 60000
-- A lookup where a source failed and nothing was found is retried this often, this
-- many times, before the miss is cached.
local RETRY_MS, RETRIES = 30000, 3
-- Cache entries from another version or source set are looked up again. 7: instrumental
-- no longer outranks lyrics, so older instrumental entries may be wrong.
local CACHE_VERSION = 7

local currentKey = nil
local shownKey = nil -- the key of the published lyrics
local failedAt = nil -- when the current track's lookup last failed
local failures = 0
-- key -> the source set of the lookup running for it, so a forced check or a return to
-- the track never starts a second one.
local running = {}

local function keyOf(q) return string.lower(`{q.artist}|{q.title}|{q.album}|{q.durationS}`) end
local function cachePath(key) return util.dir("lyrics") .. "/" .. util.hash(key) .. ".json" end
local function backup() return noctalia.getConfig("lyrics_backup") ~= false end
local function sources() return backup() and "lrclib,netease,kugou" or "lrclib" end

-- Misses and instrumentals are asked again after a week: an instrumental may be a
-- source matching the wrong release.
local function fresh(cached)
  if not cached then return false end
  if cached.status == "synced" and not cached.loose and cached.v == CACHE_VERSION then return true end
  if cached.v ~= CACHE_VERSION or cached.sources ~= sources() then return false end
  if cached.status ~= "none" and cached.status ~= "instrumental" then return true end
  return noctalia.nowMs() - (cached.at or 0) < MISS_RETRY_MS
end

local function publish(key, value)
  value.key = key
  shownKey = key
  util.publish("lyrics", value)
end

-- Looks the shown track up when it changed; force looks it up again (a lyrics setting
-- changed, retry after a failure).
function M.check(force)
  if noctalia.getConfig("lyrics") == false then
    currentKey = nil
    return publish("", { status = "off" })
  end
  local track = media.current(noctalia.state.get("players"), noctalia.state.get("active"))
  if not track or track.title == "" then
    currentKey = nil
    return publish("", { status = "idle" })
  end
  local key = keyOf(query.exact(track))
  if key == currentKey and not force then return end
  if key ~= currentKey then failures = 0 end
  currentKey, failedAt = key, nil

  if (track.lengthMs or 0) > MAX_TRACK_MS then return publish(key, { status = "none" }) end
  local cached = util.decode(noctalia.readFile(cachePath(key)) or "")
  if fresh(cached) then return publish(key, cached) end

  local src = sources()
  if running[key] == src then
    if shownKey ~= key then publish(key, { status = "loading" }) end
    return
  end
  running[key] = src
  publish(key, { status = "loading" })
  -- Any usable result shows at once; better ones replace it as they arrive. An
  -- instrumental waits for the end, so it never flashes before lyrics arrive.
  lookup.run(track, backup(), function(found)
    if currentKey == key and found.status ~= "instrumental" then publish(key, table.clone(found)) end
  end, function(found, failed)
    if running[key] == src then running[key] = nil end
    if failed and failures < RETRIES then
      -- Retried only while the track is still shown; otherwise its next play asks again.
      if currentKey == key then
        failures += 1
        failedAt = noctalia.nowMs()
        publish(key, { status = "error" })
      end
      return
    end
    local value = found or { status = "none" }
    value.at, value.v, value.sources = noctalia.nowMs(), CACHE_VERSION, src
    noctalia.writeFile(cachePath(key), noctalia.json.encode(value) or "")
    if currentKey == key then publish(key, value) end
  end)
end

-- Settings changed: looks the track up again only when a lyrics setting did (dragging
-- an overlay slider used to start a lookup per step).
local seenConfig = nil
function M.configChanged()
  local now = `{noctalia.getConfig("lyrics") ~= false}|{sources()}`
  if now == seenConfig then return end
  seenConfig = now
  M.check(true)
end

-- Looks the current track up again after a failure, every RETRY_MS.
function M.retry()
  if failedAt and noctalia.nowMs() - failedAt >= RETRY_MS then M.check(true) end
end

return M
