--!nonstrict
-- What every surface and the service agree on: which player is the one shown, where its
-- position is now, and how times and tracks are written.

local lrc = require("./lrc.luau")

local M = {}

-- The shown player: noctalia's active player, else the first playing, else the first.
function M.current(players, active)
  if type(players) ~= "table" or #players == 0 then return nil end
  for _, p in ipairs(players) do
    if p.bus == active then return p end
  end
  for _, p in ipairs(players) do
    if p.status == "Playing" then return p end
  end
  return players[1]
end

-- The position now, extrapolated from the published sample while playing.
function M.position(p, now)
  if not p then return 0 end
  local ms = p.positionMs or 0
  if p.status == "Playing" then ms += (now or noctalia.nowMs()) - (p.sampledAt or 0) end
  if (p.lengthMs or 0) > 0 then ms = math.min(ms, p.lengthMs) end
  return math.max(0, ms)
end

-- The synced lyric line playing at a position (0 before the first or without synced
-- lyrics), with the user's lyrics_offset_ms applied.
function M.lyricIndex(lyrics, positionMs)
  if type(lyrics) ~= "table" or lyrics.status ~= "synced" then return 0 end
  return lrc.lineAt(lyrics.lines or {}, positionMs + (tonumber(noctalia.getConfig("lyrics_offset_ms")) or 0))
end

M.SLEEP_PRESETS = { 15, 30, 45, 60, 90 }

-- Whole minutes left on the sleep timer (rounded up), 0 when it is off.
function M.sleepLeft(sleep, now)
  local endsAt = type(sleep) == "table" and tonumber(sleep.endsAt) or 0
  local left = endsAt - (now or noctalia.nowMs())
  return left > 0 and math.ceil(left / 60000) or 0
end

-- The next preset above what is left, so repeated clicks lengthen the timer; 0 (off)
-- after the longest.
function M.nextSleep(leftMinutes)
  for _, m in ipairs(M.SLEEP_PRESETS) do
    if m > leftMinutes then return m end
  end
  return 0
end

-- "3:07", or "1:02:09" past an hour.
function M.clock(ms)
  local s = math.floor((ms or 0) / 1000)
  local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s % 60) end
  return string.format("%d:%02d", m, s % 60)
end

function M.title(p)
  if not p then return "" end
  if p.title ~= "" then return p.title end
  return p.identity ~= "" and p.identity or p.bus
end

-- "Artist · Album", leaving out what the player did not report.
function M.subtitle(p)
  if not p then return "" end
  local parts = {}
  if p.artists ~= "" then parts[#parts + 1] = p.artists end
  if p.album ~= "" then parts[#parts + 1] = p.album end
  return table.concat(parts, " · ")
end

-- The player's own name, shortened: "Mozilla firefox" -> "Firefox".
function M.playerName(p)
  local name = p.identity ~= "" and p.identity or string.match(p.bus, "MediaPlayer2%.([^.]+)") or p.bus
  name = string.gsub(name, "^Mozilla%s+", "")
  return string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

-- A player's icon from its desktop entry, else nil (callers fall back to a glyph).
function M.icon(p, size)
  if p.desktop == "" then return nil end
  return noctalia.appIconPath(p.desktop, size)
end

-- Whether a player belongs to an app from `apps`: by desktop id, window class or name.
-- Spotify's player says desktop "spotify", its launcher entry is "spotify-launcher".
function M.isApp(p, app)
  local desktop, identity = string.lower(p.desktop or ""), string.lower(p.identity or "")
  return (desktop ~= "" and (desktop == app.id or desktop == app.wmClass)) or identity == string.lower(app.name or "")
end

function M.playerFor(players, app)
  for _, p in ipairs(type(players) == "table" and players or {}) do
    if M.isApp(p, app) then return p end
  end
  return nil
end

function M.statusGlyph(p)
  if not p then return "music-off" end
  if p.status == "Playing" then return "player-play" end
  if p.status == "Paused" then return "player-pause" end
  return "player-stop"
end

return M
