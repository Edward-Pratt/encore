--!nonstrict
-- "mu" launcher provider: the shown player's controls first, then every other player
-- (activate one to make it noctalia's active player), music apps to open, favourites,
-- the hidden-workspace toggle and the panel.
local media = require("./media.luau")
local control = require("./control.luau")
local hyprland = require("./hyprland.luau")
local favourites = require("./favourites.luau")
local favs = noctalia.state.get("favourites") or {}

local players = noctalia.state.get("players") or {}
local active = noctalia.state.get("active") or ""
local apps = noctalia.state.get("apps") or {}
local hidden = noctalia.state.get("hidden") or {}
local sleep = noctalia.state.get("sleep")
local overlay = noctalia.state.get("overlay")
local actions = {} -- result id -> function
local lastQuery = ""

local function results(query)
  actions = {}
  local list = {}
  local function add(id, title, subtitle, glyph, run)
    local score = query ~= "" and noctalia.fuzzyScore(query, `{title} {subtitle}`) or nil
    if query ~= "" and not score then return end
    actions[id] = run
    list[#list + 1] = { id = id, title = title, subtitle = subtitle, glyph = glyph, score = score or (100 - #list) }
  end

  local p = media.current(players, active)
  if p then
    local now = media.title(p)
    add("toggle", p.status == "Playing" and "Pause" or "Play", now, p.status == "Playing" and "player-pause" or "player-play",
      function() control.playPause(p) end)
    if p.canNext then add("next", "Next track", now, "player-skip-forward", function() control.next(p) end) end
    if p.canPrevious then add("previous", "Previous track", now, "player-skip-back", function() control.previous(p) end) end
    if p.canQuit then add("quit", `Quit {media.playerName(p)}`, now, "power", function() control.quit(p) end) end
  end
  for i, other in ipairs(players) do
    if not p or other.bus ~= p.bus then
      add("player-" .. i, `Switch to {media.playerName(other)}`, media.title(other) .. " · " .. other.status,
        media.statusGlyph(other), function() control.makeActive(other) end)
    end
  end
  for _, app in ipairs(apps) do
    if not media.playerFor(players, app) then
      add("app-" .. app.id, `Open {app.name}`, "Starts it and plays", "player-play", function() control.open(app.id) end)
    end
  end
  for i, f in ipairs(favs) do
    add("fav-" .. i, `Play {f.name}`, "Favourite, in Spotify", "star", function() control.open(nil, f.uri) end)
  end
  local copied = noctalia.clipboardText()
  if copied and favourites.uri(copied) then
    add("fav-add", "Add copied Spotify link to favourites", copied, "clipboard-plus", function() control.addFavourite(copied) end)
  end
  if #hidden > 0 then
    add("hidden", "Show background apps", "Toggles Encore's hidden workspace", "app-window", function() hyprland.toggle() end)
  end
  local overlayOn = type(overlay) == "table" and overlay.enabled == true
  add("overlay", overlayOn and "Turn lyrics overlay off" or "Turn lyrics overlay on",
    "Synced lyrics floating over everything while playing", "picture-in-picture", function() control.toggleOverlay() end)
  local left = media.sleepLeft(sleep)
  if left > 0 then add("sleep-off", "Cancel sleep timer", `Pauses in {left} min`, "zzz", function() control.sleep(0) end) end
  for _, m in ipairs(media.SLEEP_PRESETS) do
    add("sleep-" .. m, `Sleep timer: {m} min`, "Pause everything after a while", "zzz", function() control.sleep(m) end)
  end
  add("panel", "Open Encore", "Player, lyrics and every media player", "music",
    function() noctalia.togglePanel("edward/encore:panel") end)
  return list
end

function onQuery(text)
  lastQuery = text or ""
  launcher.setResults(lastQuery, results(lastQuery))
end

function onActivate(id)
  local run = actions[id]
  if run then run() end
end

noctalia.state.watch("players", function(v) players = v or {}; onQuery(lastQuery) end)
noctalia.state.watch("active", function(v) active = v or ""; onQuery(lastQuery) end)
noctalia.state.watch("apps", function(v) apps = v or {}; onQuery(lastQuery) end)
noctalia.state.watch("hidden", function(v) hidden = v or {}; onQuery(lastQuery) end)
noctalia.state.watch("sleep", function(v) sleep = v; onQuery(lastQuery) end)
noctalia.state.watch("overlay", function(v) overlay = v; onQuery(lastQuery) end)
noctalia.state.watch("favourites", function(v) favs = v or {}; onQuery(lastQuery) end)
