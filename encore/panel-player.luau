--!nonstrict
-- The panel's player half: a chip per player (click one to make it noctalia's active
-- player), the cover and track, the seek bar, transport and volume. render(ctx) reads
-- ctx.S and ctx.now; sliders keep a draft while dragged and send on release.
local media = require("./media.luau")
local control = require("./control.luau")
local apps = require("./panel-apps.luau")

local M = {}

local seekDraft = nil -- seconds while the seek slider is dragged
local volumeDraft = nil -- 0..100 while the volume slider is dragged
-- What each slider was last rendered with. A slider reports onChange when a render
-- moves it too; only a value away from the rendered one starts a draft.
local seekShown, volumeShown = nil, nil

local function moved(value, shown, tolerance)
  local v = tonumber(value)
  if not v or (shown and math.abs(v - shown) < tolerance) then return nil end
  return v
end

local function muted(text, size)
  return ui.label({ text = text, fontSize = size or 11, color = "on_surface_variant", maxLines = 1 })
end

local function chips(ctx, p)
  local row = {}
  for _, other in ipairs(ctx.S.players) do
    row[#row + 1] = ui.button({ key = "chip-" .. other.bus, text = media.playerName(other), glyph = media.statusGlyph(other),
      variant = "ghost", controlSize = "sm", selected = other.bus == p.bus,
      tooltip = other.title ~= "" and other.title or nil,
      onClick = function() control.makeActive(other) end })
  end
  for _, button in ipairs(apps.chipButtons(ctx)) do row[#row + 1] = button end
  row[#row + 1] = ui.spacer({ flexGrow = 1 })
  row[#row + 1] = ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = ctx.close })
  return ui.row({ gap = 4, align = "center" }, row)
end

local function art(p)
  if p.art ~= "" then return ui.image({ path = p.art, width = 112, height = 112, radius = 12, fit = "cover" }) end
  local icon = media.icon(p, 48)
  return ui.column({ width = 112, height = 112, radius = 12, fill = "surface_container", align = "center", justify = "center" }, {
    icon and ui.image({ path = icon, width = 48, height = 48 }) or ui.glyph({ name = "music", size = 40, color = "on_surface_variant" }),
  })
end

local function track(p)
  -- Keyed per track: a retained row kept the old title's measured width after a change.
  return ui.row({ key = `track-{p.bus}-{p.title}-{p.artists}`, gap = 14, align = "center" }, {
    art(p),
    ui.column({ gap = 4, flexGrow = 1 }, {
      ui.label({ text = media.title(p), fontSize = 17, fontWeight = "bold", maxLines = 2 }),
      ui.label({ text = media.subtitle(p), fontSize = 12, color = "on_surface_variant", maxLines = 2 }),
      ui.row({ gap = 4, align = "center" }, {
        muted(`{media.playerName(p)} · {p.status}`, 10),
        ui.button({ key = "quit-" .. p.bus, glyph = "power", variant = "ghost", controlSize = "sm", visible = p.canQuit,
          tooltip = `Quit {media.playerName(p)}`, onClick = function() control.quit(p) end }),
      }),
    }),
  })
end

local function seek(ctx, p)
  local lengthS = (p.lengthMs or 0) / 1000
  local posS = seekDraft or ctx.position / 1000
  if lengthS <= 0 then return muted(p.status == "Playing" and "Live" or "", 10) end
  seekShown = not seekDraft and posS or seekShown
  return ui.column({ gap = 2 }, {
    ui.slider({ key = "seek-" .. p.bus, min = 0, max = lengthS, step = 1, value = posS, enabled = p.canSeek,
      onChange = function(v)
        local draft = seekDraft and tonumber(v) or moved(v, seekShown, 1.5)
        if draft then seekDraft = draft; ctx.render() end
      end,
      onDragEnd = function()
        if seekDraft then control.seek(p, seekDraft * 1000) end
        seekDraft = nil
      end }),
    ui.row({ align = "center" }, { muted(media.clock(posS * 1000), 10), ui.spacer({ flexGrow = 1 }), muted(media.clock(p.lengthMs), 10) }),
  })
end

local LOOP_GLYPH = { None = "repeat-off", Playlist = "repeat", Track = "repeat-once" }

local function transport(p)
  local ctl = p.canControl
  return ui.row({ gap = 8, align = "center", justify = "center" }, {
    ui.button({ glyph = "arrows-shuffle", variant = "ghost", selected = p.shuffle, enabled = ctl,
      tooltip = p.shuffle and "Shuffle on" or "Shuffle off", onClick = function() control.shuffle(p) end }),
    ui.button({ glyph = "player-skip-back", variant = "ghost", controlSize = "lg", enabled = p.canPrevious,
      tooltip = "Previous", onClick = function() control.previous(p) end }),
    ui.button({ glyph = p.status == "Playing" and "player-pause" or "player-play", variant = "primary", controlSize = "lg",
      enabled = p.canPlay or p.canPause, tooltip = "Play / pause (Space)", onClick = function() control.playPause(p) end }),
    ui.button({ glyph = "player-skip-forward", variant = "ghost", controlSize = "lg", enabled = p.canNext,
      tooltip = "Next", onClick = function() control.next(p) end }),
    ui.button({ glyph = LOOP_GLYPH[p.loop] or "repeat-off", variant = "ghost", selected = p.loop ~= "None", enabled = ctl,
      tooltip = `Repeat: {p.loop}`, onClick = function() control.loop(p) end }),
  })
end

-- Each click moves to the next preset above what is left; right click turns it off.
local function sleepButton(ctx)
  local left = media.sleepLeft(ctx.S.sleep, ctx.now)
  return ui.button({ key = "sleep", glyph = "zzz", text = left > 0 and `{left}m` or nil, variant = "ghost", controlSize = "sm",
    selected = left > 0,
    tooltip = left > 0 and `Pauses in {left} min. Click for longer, right click to cancel.` or "Sleep timer: pause after a while",
    onClick = function() control.sleep(media.nextSleep(left)) end,
    onRightClick = function() control.sleep(0) end })
end

local function overlayButton(ctx)
  local on = type(ctx.S.overlay) == "table" and ctx.S.overlay.enabled == true
  return ui.button({ key = "overlay", glyph = "picture-in-picture", variant = "ghost", controlSize = "sm", selected = on,
    tooltip = on and "Lyrics overlay on: synced lyrics float over everything while playing"
      or "Lyrics overlay: float synced lyrics over everything while playing",
    onClick = function() control.toggleOverlay() end })
end

local function volume(ctx, p)
  if not p.volume then
    return ui.row({ justify = "end" }, { sleepButton(ctx), overlayButton(ctx) })
  end
  local percent = volumeDraft or math.floor(p.volume * 100 + 0.5)
  volumeShown = not volumeDraft and percent or volumeShown
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = percent == 0 and "volume-3" or percent < 50 and "volume-2" or "volume", size = 16, color = "on_surface_variant" }),
    ui.slider({ key = "volume-" .. p.bus, min = 0, max = 100, step = 1, value = percent, flexGrow = 1, enabled = p.canControl,
      onChange = function(v)
        local draft = volumeDraft and tonumber(v) or moved(v, volumeShown, 0.5)
        if draft then volumeDraft = draft; ctx.render() end
      end,
      onDragEnd = function()
        if volumeDraft then control.volume(p, volumeDraft / 100) end
        volumeDraft = nil
      end }),
    ui.label({ text = `{percent}%`, fontSize = 11, color = "on_surface_variant", width = 34, textAlign = "end" }),
    sleepButton(ctx),
    overlayButton(ctx),
  })
end

-- True while a slider is dragged: the shell skips tick renders that would fight it.
function M.dragging() return seekDraft ~= nil or volumeDraft ~= nil end

function M.render(ctx, p)
  return ui.column({ gap = 12 }, { chips(ctx, p), track(p), seek(ctx, p), transport(p), volume(ctx, p) })
end

return M
