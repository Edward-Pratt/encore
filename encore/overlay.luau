--!nonstrict
-- The lyrics overlay layer: the current synced line on a slim translucent pill, with
-- the cover beside it and, when the lyrics have word timing, the sung words lit in the
-- accent colour (karaoke). Fades in at each new line; draws nothing before the first
-- line or in instrumental gaps. Size, background, cover, next line and highlighting
-- are settings (overlay_*); position and offset are applied to the layer by
-- service-overlay.luau. Click-through (plugin.toml), so it never takes input.
local media = require("./media.luau")

local FADE_MS = 180

local players = noctalia.state.get("players") or {}
local active = noctalia.state.get("active") or ""
local lyrics = noctalia.state.get("lyrics")
local shownLine, shownWord = -1, -1
local fade = 1 -- 0..1 opacity of the current line

local function setting(key, fallback)
  local v = noctalia.getConfig(key)
  if v == nil then return fallback end
  return v
end

local function lineAt(index)
  local line = lyrics and lyrics.status == "synced" and lyrics.lines and lyrics.lines[index]
  return line and line.text ~= "" and line or nil
end

-- How many of the line's words have started at the position.
local function sungWords(line, positionMs)
  local n = 0
  for _, w in ipairs(line and line.words or {}) do
    if w.t <= positionMs then n += 1 end
  end
  return n
end

-- The line as one label, or as a row of word labels with the sung ones lit.
local function lineNodes(line, size, sung)
  local mode = setting("overlay_highlight", "words")
  if mode == "words" and line.words then
    local row = {}
    for i, w in ipairs(line.words) do
      row[#row + 1] = ui.label({ text = w.text, fontSize = size, fontWeight = "medium",
        color = i <= sung and "primary" or "on_surface/0.75" })
      if w.space then row[#row + 1] = ui.spacer({ width = math.floor(size * 0.28) }) end
    end
    return ui.row({ align = "center" }, row)
  end
  return ui.label({ text = line.text, fontSize = size, fontWeight = "medium", maxLines = 1, maxWidth = 1000,
    color = mode == "line" and "primary" or "on_surface" })
end

local function render(p, positionMs)
  local line = lineAt(shownLine)
  if not line then
    layer.render(ui.column({ flexGrow = 1 }, {}))
    return
  end
  local size = tonumber(setting("overlay_size", 16)) or 16
  local text = { lineNodes(line, size, sungWords(line, positionMs)) }
  local nextLine = setting("overlay_next_line", false) and lineAt(shownLine + 1)
  if nextLine then
    text[2] = ui.label({ text = nextLine.text, fontSize = math.floor(size * 0.78), color = "on_surface_variant",
      maxLines = 1, maxWidth = 1000 })
  end
  local pill = {}
  if setting("overlay_cover", true) and p.art ~= "" then
    local c = math.floor(size * 1.35)
    pill[1] = ui.image({ path = p.art, width = c, height = c, radius = c / 2, fit = "cover" })
  end
  pill[#pill + 1] = ui.column({ gap = 2, align = "start" }, text)
  local alpha = (tonumber(setting("overlay_background", 80)) or 80) / 100
  local top = setting("overlay_position", "bottom") == "top"
  layer.render(ui.column({ flexGrow = 1, align = "center", justify = top and "start" or "end" }, {
    ui.row({ key = "pill", gap = math.floor(size * 0.6), align = "center", opacity = fade,
      paddingH = math.floor(size * 0.95), paddingV = math.floor(size * 0.45), radius = 999,
      -- Always set: the host keeps a prop a later render leaves out.
      fill = string.format("surface/%.2f", alpha), border = alpha > 0 and "outline_variant/0.35" or "outline_variant/0",
      borderWidth = alpha > 0 and 1 or 0 }, pill),
  }))
end

-- Re-renders when the line or the sung word changes, through each fade-in, and when
-- forced (new state).
local function tick(deltaMs, force)
  local p = media.current(players, active)
  if not p then return end
  local position = media.position(p)
  local index = media.lyricIndex(lyrics, position)
  local word = sungWords(lineAt(index), position + (tonumber(noctalia.getConfig("lyrics_offset_ms")) or 0))
  local changed = force or index ~= shownLine or word ~= shownWord
  if index ~= shownLine then fade = 0 end
  shownLine, shownWord = index, word
  if fade < 1 then
    fade = math.min(1, fade + (tonumber(deltaMs) or 16) / FADE_MS)
    changed = true
  end
  if changed then render(p, position + (tonumber(noctalia.getConfig("lyrics_offset_ms")) or 0)) end
end

function onFrameTick(deltaMs) tick(deltaMs) end

local function refresh() tick(0, true) end

noctalia.state.watch("players", function(v) players = v or {}; refresh() end)
noctalia.state.watch("active", function(v) active = v or ""; refresh() end)
noctalia.state.watch("lyrics", function(v) lyrics = v; refresh() end)
layer.setNeedsFrameTick(true)
refresh()
