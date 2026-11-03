--!nonstrict
-- Bar widget: the shown player's cover (or a status glyph), title and artist, and a
-- spectrum meter fed by the host while audio plays. Scroll changes that player's volume;
-- click, middle and right click are [widget.actions] defaults in plugin.toml.
local media = require("./media.luau")
local control = require("./control.luau")

local SPECTRUM_FRAME_MS = 33 -- ~30 fps is plenty for a bar meter
local VOLUME_STEP = 0.05

local LYRIC_TICK_MS = 250

local players = noctalia.state.get("players") or {}
local active = noctalia.state.get("active") or ""
local lyrics = noctalia.state.get("lyrics")
local sleep = noctalia.state.get("sleep")
local shownLine = 0
local tickMs = nil
local shownSleep = 0 -- sleep timer minutes the tooltip shows
local spectrum = {}
local audible = false
local lastFrame = 0

local function setting(key, fallback)
  local v = noctalia.getConfig(key)
  if v == nil then return fallback end
  return v
end

local function cover(p)
  if setting("show_art", true) and p and p.art ~= "" then
    return ui.image({ path = p.art, width = 18, height = 18, radius = 4, fit = "cover" })
  end
  return ui.glyph({ name = p and p.status == "Playing" and "music" or media.statusGlyph(p), size = 16,
    color = p and p.status == "Playing" and "primary" or "on_surface" })
end

local function meter(vertical)
  local bars = {}
  for i, v in ipairs(spectrum) do
    local size = 2 + math.floor(math.max(0, math.min(1, v)) * 14 + 0.5)
    bars[i] = ui.box({ width = vertical and size or 3, height = vertical and 3 or size, radius = 1.5, fill = "primary" })
  end
  local props = { gap = 1, align = "center", height = not vertical and 18 or nil, width = vertical and 18 or nil }
  return vertical and ui.column(props, bars) or ui.row(props, bars)
end

-- The current lyric line with bar_lyrics, while synced lyrics play; else nil.
local function lyricLine(p)
  if not setting("bar_lyrics", false) or p.status ~= "Playing" then return nil end
  local line = lyrics and lyrics.lines and lyrics.lines[shownLine]
  return line and line.text ~= "" and line.text or nil
end

local function text(p)
  local line = lyricLine(p)
  if line then return line end
  local s = media.title(p)
  if setting("show_artist", true) and p.artists ~= "" then s = `{s} – {p.artists}` end
  return s
end

local function tooltip(p)
  local rows = { { key = media.playerName(p), value = p.status } }
  if p.title ~= "" then rows[#rows + 1] = { key = "Title", value = p.title } end
  if p.artists ~= "" then rows[#rows + 1] = { key = "Artist", value = p.artists } end
  if p.album ~= "" then rows[#rows + 1] = { key = "Album", value = p.album } end
  if #players > 1 then rows[#rows + 1] = { key = "Players", value = tostring(#players) } end
  local left = media.sleepLeft(sleep)
  if left > 0 then rows[#rows + 1] = { key = "Sleep timer", value = `{left} min` } end
  return rows
end

local function render()
  local p = media.current(players, active)
  local show = p ~= nil and (p.status == "Playing" or not setting("hide_when_idle", false))
  barWidget.setVisible(show)
  if not show then return end
  -- Lyrics need a quick tick; everything else arrives through state.
  local following = setting("bar_lyrics", false) and p.status == "Playing" and lyrics and lyrics.status == "synced"
  local interval = following and LYRIC_TICK_MS or 60000
  if interval ~= tickMs then
    tickMs = interval
    noctalia.setUpdateInterval(interval)
  end
  shownLine = following and media.lyricIndex(lyrics, media.position(p)) or 0
  local vertical = barWidget.isVertical()
  local children = { cover(p) }
  local width = tonumber(setting("max_width", 240)) or 240
  if not vertical and width > 0 then
    children[#children + 1] = ui.label({ text = text(p), maxWidth = width, maxLines = 1,
      color = p.status == "Playing" and "on_surface" or "on_surface_variant" })
  end
  if setting("audio_spectrum", true) and audible and p.status == "Playing" and #spectrum > 0 then
    children[#children + 1] = meter(vertical)
  end
  local props = { gap = 6, align = "center" }
  barWidget.render(vertical and ui.column(props, children) or ui.row(props, children))
  shownSleep = media.sleepLeft(sleep)
  barWidget.setTooltip(tooltip(p))
end

-- The host's bands averaged down to the configured bar count.
local function resample(values, n)
  if #values <= n then return values end
  local out = {}
  for i = 1, n do
    local first, last = math.floor((i - 1) * #values / n) + 1, math.floor(i * #values / n)
    local sum = 0
    for j = first, last do sum += values[j] end
    out[i] = sum / math.max(1, last - first + 1)
  end
  return out
end

function onAudioSpectrum(valuesCsv, stateCsv)
  local now = noctalia.nowMs()
  if now - lastFrame < SPECTRUM_FRAME_MS then return end
  lastFrame = now
  local values = {}
  for v in string.gmatch(valuesCsv or "", "[^,]+") do values[#values + 1] = tonumber(v) or 0 end
  local wasAudible = audible
  audible = string.sub(stateCsv or "0", 1, 1) == "1"
  spectrum = resample(values, tonumber(setting("audio_spectrum_bands", 10)) or 10)
  if audible or wasAudible then render() end
end

function onScroll(axis, steps)
  if axis ~= "vertical" then return end
  local p = media.current(players, active)
  if not p or not p.volume then return end
  control.volume(p, p.volume - steps * VOLUME_STEP)
end

noctalia.state.watch("players", function(v) players = v or {}; render() end)
noctalia.state.watch("active", function(v) active = v or ""; render() end)
noctalia.state.watch("lyrics", function(v) lyrics = v; render() end)
noctalia.state.watch("sleep", function(v) sleep = v; render() end)
function update()
  local p = media.current(players, active)
  local lineMoved = p and lyrics and media.lyricIndex(lyrics, media.position(p)) ~= shownLine
  if lineMoved or media.sleepLeft(sleep) ~= shownSleep then render() end
end
function onConfigChanged() render() end
-- `noctalia msg plugin edward/encore:widget focused click` toggles the panel.
function onIpc(event) if event == "click" then noctalia.togglePanel("edward/encore:panel") end end
render()
