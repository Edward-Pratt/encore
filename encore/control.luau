--!nonstrict
-- Controls for one player, sent to noctalia's dev.noctalia.Mpris (which also handles
-- players that only support relative seeks). Any surface calls these directly; each sets
-- `poke` when done so the service reads the result at once.

local M = {}

local BASE = { "busctl", "--user", "call", "dev.noctalia.Mpris", "/dev/noctalia/Mpris", "dev.noctalia.Mpris" }

local function call(method, signature, ...)
  local argv = table.clone(BASE)
  argv[#argv + 1] = method
  if signature then
    argv[#argv + 1] = signature
    for _, v in ipairs({ ... }) do argv[#argv + 1] = tostring(v) end
  end
  noctalia.runAsync(argv, function(r)
    if r.exitCode ~= 0 then noctalia.log(`encore: {method} failed: {noctalia.string.trim(r.stderr)}`) end
    noctalia.state.set("poke", noctalia.nowMs())
  end, 3000)
end

function M.playPause(p) call("PlayPausePlayer", "s", p.bus) end
function M.play(p) call("PlayPlayer", "s", p.bus) end
function M.pause(p) call("PausePlayer", "s", p.bus) end

-- Quits the player's app (only offered when it reports CanQuit).
function M.quit(p)
  noctalia.runAsync({ "busctl", "--user", "call", p.bus, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2", "Quit" },
    function(r)
      if r.exitCode ~= 0 then noctalia.log(`encore: Quit failed: {noctalia.string.trim(r.stderr)}`) end
      noctalia.state.set("poke", noctalia.nowMs())
    end, 3000)
end

-- Sets the sleep timer to `minutes` from now; 0 cancels it. See service-sleep.luau.
function M.sleep(minutes)
  noctalia.state.set("command", { action = "sleep", minutes = minutes, at = noctalia.nowMs() })
end

-- Saves a Spotify link (share link or spotify: URI) as a favourite, or removes a saved
-- one. See service-favourites.luau.
function M.addFavourite(link)
  noctalia.state.set("command", { action = "fav-add", link = link, at = noctalia.nowMs() })
end

function M.removeFavourite(uri)
  noctalia.state.set("command", { action = "fav-remove", uri = uri, at = noctalia.nowMs() })
end

-- Turns the lyrics overlay on or off. See service-overlay.luau.
function M.toggleOverlay()
  noctalia.state.set("command", { action = "overlay", at = noctalia.nowMs() })
end

-- Plays a URI (a spotify: link) in the player itself; dev.noctalia.Mpris has no OpenUri.
function M.openUri(p, uri)
  noctalia.runAsync({ "busctl", "--user", "call", p.bus, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player",
    "OpenUri", "s", uri }, function(r)
    if r.exitCode ~= 0 then noctalia.log(`encore: OpenUri failed: {noctalia.string.trim(r.stderr)}`) end
    noctalia.state.set("poke", noctalia.nowMs())
  end, 3000)
end
function M.next(p) call("NextPlayer", "s", p.bus) end
function M.previous(p) call("PreviousPlayer", "s", p.bus) end

function M.seek(p, ms)
  ms = math.max(0, math.floor(ms))
  if (p.lengthMs or 0) > 0 then ms = math.min(ms, p.lengthMs) end
  call("SetPositionPlayer", "sx", p.bus, ms * 1000)
end

function M.volume(p, value)
  call("SetVolumePlayer", "sd", p.bus, string.format("%.3f", math.max(0, math.min(1, value))))
end

function M.shuffle(p) call("SetShufflePlayer", "sb", p.bus, p.shuffle and "false" or "true") end

local NEXT_LOOP = { None = "Playlist", Playlist = "Track", Track = "None" }
function M.loop(p) call("SetLoopStatusPlayer", "ss", p.bus, NEXT_LOOP[p.loop] or "None") end

-- Asks the service to open an app (by `apps` id) and play, or to play a favourite's URI
-- in Spotify (starting it first when needed). See service-launch.luau.
function M.open(appId, uri)
  noctalia.state.set("command", { action = "open", app = appId, uri = uri, at = noctalia.nowMs() })
end

-- Makes this the player noctalia controls everywhere: its media keys, OSD and lockscreen.
function M.makeActive(p) call("SetActivePlayerPreference", "s", p.bus) end

return M
