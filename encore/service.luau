--!nonstrict
-- The service: the only entry that reads player data, finds apps or fetches lyrics.
-- Wiring only; each source is its own service-*.luau module.
local players = require("./service-players.luau")
local lyrics = require("./service-lyrics.luau")
local apps = require("./service-apps.luau")
local launch = require("./service-launch.luau")
local favourites = require("./favourites.luau")
local hyprland = require("./hyprland.luau")
local events = require("./service-events.luau")
local sleep = require("./service-sleep.luau")
local overlay = require("./service-overlay.luau")

local TICK_MS = 2000

players.ensureStream()
players.fetch()
apps.scan()

-- Surfaces set `poke` after sending a control, so the result shows without waiting for
-- a signal (some players send none for volume or shuffle).
noctalia.state.watch("poke", function() players.fetch() end)
noctalia.state.watch("players", function(list)
  events.onPlayers(list)
  lyrics.check()
  launch.step()
  launch.checkHidden()
  overlay.update()
end)
noctalia.state.watch("active", function()
  lyrics.check()
  overlay.update()
end)
noctalia.state.watch("lyrics", function() overlay.update() end)
noctalia.state.watch("command", function(cmd)
  launch.command(cmd)
  sleep.command(cmd)
  overlay.command(cmd)
end)

function onConfigChanged()
  lyrics.check(true)
  overlay.configChanged()
end

-- `noctalia msg plugin edward/encore:service all open spotify-launcher` opens an app by
-- desktop id; `... open spotify:playlist:ID` (or a share link) plays it in Spotify.
-- `... hidden` shows or hides the background apps; `... sleep 30` sets the sleep timer
-- (0 cancels); `... overlay` turns the lyrics overlay on or off. All suit keybinds.
function onIpc(event, payload)
  if event == "open" and payload then
    local uri = favourites.uri(payload)
    launch.command({ action = "open", app = not uri and string.lower(payload) or nil, uri = uri, at = noctalia.nowMs() })
  elseif event == "hidden" then
    hyprland.toggle()
  elseif event == "sleep" then
    sleep.set(payload)
  elseif event == "overlay" then
    overlay.toggle()
  end
end

noctalia.setUpdateInterval(TICK_MS)
function update()
  players.ensureStream()
  launch.step()
  sleep.check()
  lyrics.retry()
  if noctalia.nowMs() - players.lastFetch >= players.RESYNC_MS then
    players.fetch()
    launch.checkHidden()
  end
  if noctalia.nowMs() - apps.lastScan >= apps.RESCAN_MS then apps.scan() end
end
