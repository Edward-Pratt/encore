--!nonstrict
-- The lyrics overlay layer: the current synced line on a slim translucent pill, with
-- the cover beside it and, when the lyrics have word timing, the sung words lit in the
-- accent colour (karaoke). New lines replace the text in place; the pill only fades in
-- when it appears, and short gaps between lines keep the last line up, so it never
-- flashes. Draws nothing before the first line or in long instrumental gaps. Size,
-- background, cover, next line, highlighting and the spot it sits in are settings
-- (overlay_*); the layer's anchors and margins are set by service-overlay.luau.
-- Click-through (plugin.toml), so it never takes input.
local media = require("./media.luau")
local wrap = require("./lyric-wrap.luau")
local place = require("./overlay-place.luau")

local FADE_MS = 180
-- An empty line shorter than this (a breath between lines) keeps the last line up.
local HOLD_GAP_MS = 6000

local players = noctalia.state.get("players") or {}
local active = noctalia.state.get("active") or ""
local lyrics = noctalia.state.get("lyrics")
local shownLine, shownWord = -1, -1
local fade = 1 -- 0..1 opacity of the pill, run from 0 when it appears
local visible = false -- whether the last render drew a line

local function setting(key, fallback)
  local v = noctalia.getConfig(key)
  if v == nil then return fallback end
  return v
end

local function lineAt(index)
  local line = lyrics and lyrics.status == "synced" and lyrics.lines and lyrics.lines[index]
  return line and line.text ~= "" and line or nil
end

-- The line to show at `index`: itself, or in a short gap the last line before it.
local function displayIndex(index)
  if lineAt(index) or index <= 1 then return index end
  local lines = lyrics and lyrics.lines or {}
  local gap, nextLine = lines[index], lines[index + 1]
  if gap and (not nextLine or nextLine.t - gap.t <= HOLD_GAP_MS) and lineAt(index - 1) then return index - 1 end
  return index
end

-- The next line with text after `index`, skipping empty ones.
local function nextAfter(index)
  for i = index + 1, index + 3 do
    local line = lineAt(i)
    if line then return line end
  end
  return nil
end

-- How many of the line's words have started at the position.
local function sungWords(line, positionMs)
  local n = 0
  for _, w in ipairs(line and line.words or {}) do
    if w.t <= positionMs then n += 1 end
  end
  return n
end

local TEXT_WIDTH = 900 -- px a lyric may take before it wraps
local MAX_LINES = 3 -- the most lines one lyric wraps to; the layer is sized for this
-- The line as one wrapping label, or as rows of word labels with the sung ones lit.
local function lineNodes(line, size, sung)
  local mode = setting("overlay_highlight", "words")
  if mode == "words" and line.words then
    local rows = {}
    for _, indexes in ipairs(wrap.rows(line.words, size, TEXT_WIDTH)) do
      local row = {}
      for _, i in ipairs(indexes) do
        local w = line.words[i]
        row[#row + 1] = ui.label({ text = w.text, fontSize = size, fontWeight = "medium",
          color = i <= sung and "primary" or "on_surface/0.75" })
        if w.space then row[#row + 1] = ui.spacer({ width = math.floor(size * 0.28) }) end
      end
      rows[#rows + 1] = ui.row({ align = "center", justify = "center" }, row)
    end
    return ui.column({ align = "center", gap = 1 }, rows)
  end
  return ui.label({ text = line.text, fontSize = size, fontWeight = "medium", maxLines = MAX_LINES,
    -- Without word timing, "words" lights the whole line, as "line" does.
    maxWidth = TEXT_WIDTH, textAlign = "center", color = mode == "none" and "on_surface" or "primary" })
end

local function render(p, positionMs)
  local line = lineAt(shownLine)
  visible = line ~= nil
  if not line then
    layer.render(ui.column({ flexGrow = 1 }, {}))
    return
  end
  local size = tonumber(setting("overlay_size", 16)) or 16
  local text = { lineNodes(line, size, sungWords(line, positionMs)) }
  local nextLine = setting("overlay_next_line", false) and nextAfter(shownLine)
  if nextLine then
    text[2] = ui.label({ text = nextLine.text, fontSize = math.floor(size * 0.78), color = "on_surface_variant",
      maxLines = 2, maxWidth = TEXT_WIDTH, textAlign = "center" })
  end
  local pill = {}
  if setting("overlay_cover", true) and p.art ~= "" then
    local c = math.floor(size * 1.35)
    pill[1] = ui.image({ path = p.art, width = c, height = c, radius = c / 2, fit = "cover" })
  end
  pill[#pill + 1] = ui.column({ gap = 2, align = "center" }, text)
  local alpha = (tonumber(setting("overlay_background", 80)) or 80) / 100
  local spot = place.of(setting("overlay_position", "bottom"))
  layer.render(ui.column({ flexGrow = 1, align = place.flex(spot.h), justify = place.flex(spot.v) }, {
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
  local index = displayIndex(media.lyricIndex(lyrics, position))
  local word = sungWords(lineAt(index), position + (tonumber(noctalia.getConfig("lyrics_offset_ms")) or 0))
  local changed = force or index ~= shownLine or word ~= shownWord
  -- Fade in only when a line appears on an empty overlay, never between lines.
  if index ~= shownLine and not visible and lineAt(index) then fade = 0 end
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
