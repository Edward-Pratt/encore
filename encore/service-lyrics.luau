--!nonstrict
-- Lyrics for the shown track, published as `lyrics`:
--   { key, status = "off" | "idle" | "loading" | "synced" | "plain" | "instrumental" | "none" | "error",
--     lines = [{ t, text }] (synced), plain = string (plain),
--     source = "LRCLIB" | "NetEase" | "Kugou", loose = true when the version's length differs }
-- One lookup per track through a chain of sources: LRCLIB (exact match, then search),
-- then NetEase and Kugou (with lyrics_backup), then all again with the title cleaned of
-- video noise. A failing source only moves the chain on. A word-timed result of the
-- right length (or an instrumental) ends it; after a line-timed one, only sources that
-- can give word timing are still asked. Then: line-timed of the right length, synced of
-- another length (word-timed first), plain lyrics. Results are cached in <data>/lyrics; misses are
-- asked again after a week.
local util = require("./service-util.luau")
local media = require("./media.luau")
local query = require("./lyrics-query.luau")
local lrclib = require("./lyrics-lrclib.luau")
local netease = require("./lyrics-netease.luau")
local kugou = require("./lyrics-kugou.luau")

local M = {}

local MISS_RETRY_MS = 7 * 86400000
-- Longer than this is a stream, podcast or long video: not looked up at all.
local MAX_TRACK_MS = 20 * 60000
-- A lookup where a source failed and nothing was found is retried this often, this
-- many times, before the miss is cached.
local RETRY_MS, RETRIES = 30000, 3
-- Cache entries from another version or source set are looked up again unless synced.
local CACHE_VERSION = 4

local currentKey = nil
local failedAt = nil -- when the current track's lookup last failed
local failures = 0

local function keyOf(q) return string.lower(`{q.artist}|{q.title}|{q.album}|{q.durationS}`) end
local function cachePath(key) return util.dir("lyrics") .. "/" .. util.hash(key) .. ".json" end
local function backup() return noctalia.getConfig("lyrics_backup") ~= false end
local function sources() return backup() and "lrclib,netease,kugou" or "lrclib" end

local function fresh(cached)
  if not cached then return false end
  if cached.status == "instrumental" then return true end
  if cached.status == "synced" and not cached.loose and cached.v == CACHE_VERSION then return true end
  if cached.v ~= CACHE_VERSION or cached.sources ~= sources() then return false end
  return cached.status ~= "none" or noctalia.nowMs() - (cached.at or 0) < MISS_RETRY_MS
end

local function hasWords(found)
  for _, l in ipairs(found.lines or {}) do
    if l.words then return true end
  end
  return false
end

-- done(result or nil, failed): failed when some source failed and nothing was found.
local function lookup(track, done)
  local exact, cleaned = query.exact(track), query.cleaned(track)
  local steps = {}
  local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end
  for _, q in ipairs({ exact, cleaned }) do
    add(lrclib.steps(q, q == exact))
    if backup() then
      add(netease.steps(q))
      add(kugou.steps(q))
    end
  end
  local line, loose, plain, errors, i = nil, nil, nil, 0, 0
  local function step(found, failed)
    if failed then errors += 1 end
    if found then
      if found.status == "instrumental" or (found.status == "synced" and not found.loose and hasWords(found)) then
        return done(found, false)
      end
      if found.status == "synced" and not found.loose then line = line or found
      elseif found.status == "synced" then
        if not loose or (hasWords(found) and not hasWords(loose)) then loose = found end
      else plain = plain or found end
    end
    i += 1
    while i <= #steps and line and not steps[i].words do i += 1 end
    if i <= #steps then return steps[i].run(step) end
    local best = line or loose or plain
    done(best, best == nil and errors > 0)
  end
  step(nil, false)
end

local function publish(key, value)
  value.key = key
  util.publish("lyrics", value)
end

-- Looks the shown track up when it changed; force looks it up again (settings change,
-- retry after a failure).
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

  publish(key, { status = "loading" })
  lookup(track, function(found, failed)
    if failed and failures < RETRIES then
      failures += 1
      if currentKey == key then
        failedAt = noctalia.nowMs()
        publish(key, { status = "error" })
      end
      return
    end
    local value = found or { status = "none" }
    value.at, value.v, value.sources = noctalia.nowMs(), CACHE_VERSION, sources()
    noctalia.writeFile(cachePath(key), noctalia.json.encode(value) or "")
    if currentKey == key then publish(key, value) end
  end)
end

-- Looks the current track up again after a failure, every RETRY_MS.
function M.retry()
  if failedAt and noctalia.nowMs() - failedAt >= RETRY_MS then M.check(true) end
end

return M
