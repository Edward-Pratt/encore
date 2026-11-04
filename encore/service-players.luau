--!nonstrict
-- Players: reads every MPRIS player from noctalia's dev.noctalia.Mpris service and
-- publishes `players` and `active`. A busctl monitor stream of the players' own signals
-- says when to read again; a slow resync covers a stream that died or missed a change.
-- Position is published as a sample (positionMs at sampledAt) that the surfaces
-- extrapolate while playing, never as a ticking value (position-sample.luau).
local util = require("./service-util.luau")
local art = require("./service-art.luau")
local sample = require("./position-sample.luau")

local M = {}

local CALL = { "busctl", "--user", "--json=short", "call", "dev.noctalia.Mpris", "/dev/noctalia/Mpris", "dev.noctalia.Mpris" }
M.RESYNC_MS = 10000
local SENTINEL = "encore-monitor-exited"
-- The players' signals, noctalia's own (active player changes) and players coming and
-- going. The echo tells the service the stream ended, since runStream has no close event.
local MONITOR = "busctl --user --json=short monitor"
  .. " --match \"type='signal',path='/org/mpris/MediaPlayer2'\""
  .. " --match \"type='signal',sender='dev.noctalia.Mpris'\""
  .. " --match \"type='signal',member='NameOwnerChanged',arg0namespace='org.mpris.MediaPlayer2'\""
  .. "; echo " .. SENTINEL

local inFlight, again = false, false
M.lastFetch = 0
M.streaming = false
local raw = nil -- the last player list as read, before art paths
local active = ""
local published = {} -- bus -> the published record, for the drift check
-- bus -> CanQuit, read once per bus from the player itself (noctalia's list lacks it).
-- false while the read runs.
local canQuit = {}

local function call(method)
  local argv = table.clone(CALL)
  argv[#argv + 1] = method
  return argv
end

-- busctl --json=short wraps every value as { type, data }.
local function unwrap(dict)
  local out = {}
  for k, v in pairs(dict or {}) do out[k] = type(v) == "table" and v.data or v end
  return out
end

local function record(p, now)
  return {
    bus = p.bus_name or "",
    identity = p.identity or "",
    desktop = p.desktop_entry or "",
    title = p.title or "",
    artists = table.concat(p.artists or {}, ", "),
    album = p.album or "",
    artUrl = p.art_url or "",
    url = p.source_url or "",
    lengthMs = math.floor((tonumber(p.length_us) or 0) / 1000),
    positionMs = math.floor((tonumber(p.position_us) or 0) / 1000),
    sampledAt = now,
    status = p.playback_status or "Stopped", -- Playing | Paused | Stopped
    canControl = p.can_control == true,
    canPlay = p.can_play == true,
    canPause = p.can_pause == true,
    canNext = p.can_go_next == true,
    canPrevious = p.can_go_previous == true,
    canSeek = p.can_seek == true,
    shuffle = p.shuffle == true,
    loop = p.loop_status or "None", -- None | Track | Playlist
    volume = tonumber(p.volume),
  }
end

local function readCanQuit(bus, done)
  canQuit[bus] = false
  noctalia.runAsync({ "busctl", "--user", "get-property", bus, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2", "CanQuit" },
    function(r)
      canQuit[bus] = noctalia.string.trim(r.stdout) == "b true"
      if canQuit[bus] then done() end
    end, 3000)
end

local function publishAll()
  if not raw then return end
  local list, byBus = {}, {}
  for _, p in ipairs(raw) do
    local r = table.clone(p)
    r.art = art.path(r.artUrl, publishAll) or ""
    if canQuit[r.bus] == nil then readCanQuit(r.bus, publishAll) end
    r.canQuit = canQuit[r.bus] == true
    sample.merge(published[r.bus], r)
    list[#list + 1] = r
    byBus[r.bus] = r
  end
  published = byBus
  util.publish("players", list)
  util.publish("active", active)
end

local function finish(players, activeBus)
  inFlight = false
  if players then
    raw, active = players, activeBus or ""
    publishAll()
  end
  if again then
    again = false
    M.fetch()
  end
end

-- One read of the player list and the active player. Bursts of signals coalesce: a
-- request during a read schedules exactly one more read after it.
function M.fetch()
  if inFlight then
    again = true
    return
  end
  inFlight = true
  M.lastFetch = noctalia.nowMs()
  local started = noctalia.runAsync(call("GetPlayers"), function(r)
    local now = noctalia.nowMs()
    local reply = r.exitCode == 0 and util.decode(r.stdout) or nil
    if not reply then return finish(nil) end
    local players = {}
    for _, dict in ipairs(reply.data and reply.data[1] or {}) do
      local p = record(unwrap(dict), now)
      if p.bus ~= "" then players[#players + 1] = p end
    end
    local ok = noctalia.runAsync(call("GetActivePlayer"), function(r2)
      local a = r2.exitCode == 0 and util.decode(r2.stdout) or nil
      local found = a and a.data and a.data[1] == true
      finish(players, found and unwrap(a.data[2]).bus_name or "")
    end, 3000)
    if not ok then finish(players, active) end
  end, 3000)
  if not started then inFlight = false end
end

local RESTART_MS = 30000
local startedAt = -RESTART_MS

-- Starts the monitor, or restarts one that ended, at most every RESTART_MS.
function M.ensureStream()
  if M.streaming or noctalia.nowMs() - startedAt < RESTART_MS then return end
  startedAt = noctalia.nowMs()
  M.streaming = noctalia.runStream(MONITOR, function(line)
    if line == SENTINEL then
      M.streaming = false
      noctalia.log("encore: busctl monitor ended; restarting it")
    elseif string.find(line, "\"type\":\"signal\"", 1, true) then
      M.fetch()
    end
  end)
  if not M.streaming then noctalia.log("encore: could not start busctl monitor") end
end

return M
