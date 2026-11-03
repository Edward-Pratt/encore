--!nonstrict
-- Panel shell: state, keys and lifecycle. The player half and the lyrics pane are
-- their own modules, both rendered from ctx. The frame tick re-renders only when the
-- shown second or the current lyric line changes.
local media = require("./media.luau")
local control = require("./control.luau")
local player = require("./panel-player.luau")
local lyricsPane = require("./panel-lyrics.luau")
local apps = require("./panel-apps.luau")

local SEEK_STEP_MS = 10000

local isOpen = false
local S = {}
local ctx
local lastSecond, lastLine, lastSleep = -1, -1, 0
local pane = "lyrics" -- or "favourites"
local render

local function loadState()
  S.players = noctalia.state.get("players") or {}
  S.active = noctalia.state.get("active") or ""
  S.lyrics = noctalia.state.get("lyrics")
  S.apps = noctalia.state.get("apps") or {}
  S.hidden = noctalia.state.get("hidden") or {}
  S.sleep = noctalia.state.get("sleep")
  S.overlay = noctalia.state.get("overlay")
end
loadState()

-- Lyrics or Favourites below the player; the switch shows only with favourites set.
local function lowerPane(p)
  if not apps.hasFavourites() then
    pane = "lyrics"
    return lyricsPane.render(ctx, p)
  end
  local function tab(id, label, glyph)
    return ui.button({ key = "pane-" .. id, text = label, glyph = glyph, variant = "ghost", controlSize = "sm", flexGrow = 1,
      selected = pane == id, onClick = function() pane = id; render() end })
  end
  return ui.column({ flexGrow = 1, gap = 6 }, {
    ui.row({ gap = 4 }, { tab("lyrics", "Lyrics", "microphone-2"), tab("favourites", "Favourites", "star") }),
    pane == "favourites" and apps.favouritesPane() or lyricsPane.render(ctx, p),
  })
end

render = function()
  if not isOpen then return end
  local p = media.current(S.players, S.active)
  ctx.now = noctalia.nowMs()
  ctx.position = media.position(p, ctx.now)
  ctx.line = lyricsPane.lineIndex(S.lyrics, ctx.position)
  lastSecond, lastLine = math.floor(ctx.position / 1000), ctx.line
  lastSleep = media.sleepLeft(S.sleep, ctx.now)
  if not p then
    panel.render(ui.column({ flexGrow = 1, padding = 4 }, { apps.launchView(ctx) }))
    return
  end
  panel.render(ui.column({ flexGrow = 1, gap = 14, align = "stretch" }, {
    player.render(ctx, p),
    lowerPane(p),
  }))
end

ctx = { S = S, render = render, close = function() panel.close() end, now = 0, position = 0, line = 0 }

for _, k in ipairs({ "players", "active", "lyrics", "apps", "hidden", "sleep", "overlay" }) do
  noctalia.state.watch(k, function()
    loadState()
    render()
  end)
end

function onKey(chord, pressed)
  if not pressed then return end
  local p = media.current(S.players, S.active)
  if not p then return end
  if chord == "Space" then
    control.playPause(p)
  elseif (chord == "left" or chord == "right") and p.canSeek then
    control.seek(p, media.position(p) + (chord == "left" and -SEEK_STEP_MS or SEEK_STEP_MS))
  end
end

function onFrameTick()
  if player.dragging() then return end
  -- The sleep countdown moves even while paused.
  if media.sleepLeft(S.sleep) ~= lastSleep then return render() end
  local p = media.current(S.players, S.active)
  if not p or p.status ~= "Playing" then return end
  local position = media.position(p)
  if math.floor(position / 1000) ~= lastSecond or lyricsPane.lineIndex(S.lyrics, position) ~= lastLine then render() end
end

function onConfigChanged() render() end

function onOpen()
  isOpen = true
  loadState()
  panel.setNeedsFrameTick(true)
  render()
end

function onClose()
  isOpen = false
  panel.setNeedsFrameTick(false)
end
