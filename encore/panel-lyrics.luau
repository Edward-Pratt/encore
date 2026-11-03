--!nonstrict
-- The panel's lyrics pane. Synced lyrics follow the position, the current line
-- highlighted and kept in view; clicking a line seeks there. Plain lyrics just scroll.
local media = require("./media.luau")
local control = require("./control.luau")

local M = {}

local LOOKAHEAD = 3 -- lines kept visible below the current one

local MESSAGES = {
  off = { "message-off", "Lyrics are turned off in Encore's settings." },
  idle = { "music", "Nothing is playing." },
  loading = { "loader-2", "Looking for lyrics…" },
  none = { "message-question", "No lyrics found for this track." },
  instrumental = { "piano", "Instrumental." },
  error = { "wifi-off", "Couldn't reach lrclib.net. Trying again shortly." },
}

local function offsetMs() return tonumber(noctalia.getConfig("lyrics_offset_ms")) or 0 end

-- The synced line index at the current position (0 before the first), for the shell's
-- change check as well as for rendering.
function M.lineIndex(lyrics, positionMs) return media.lyricIndex(lyrics, positionMs) end

local function message(status)
  local m = MESSAGES[status] or MESSAGES.none
  return ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 8 }, {
    ui.glyph({ name = m[1], size = 28, color = "on_surface_variant" }),
    ui.label({ text = m[2], fontSize = 12, color = "on_surface_variant", textAlign = "center" }),
  })
end

local function synced(lyrics, current, p)
  local rows = {}
  for i, line in ipairs(lyrics.lines) do
    local now = i == current
    rows[#rows + 1] = ui.row({ key = "l" .. i, paddingV = 2,
      onClick = p.canSeek and function() control.seek(p, line.t - offsetMs()) end or nil }, {
      ui.label({ text = line.text ~= "" and line.text or "♪", flexGrow = 1,
        fontSize = now and 16 or 13, fontWeight = now and "bold" or "normal",
        color = now and "primary" or i < current and "on_surface_variant" or "on_surface" }),
    })
  end
  local reveal = math.min(#lyrics.lines, math.max(1, current + LOOKAHEAD))
  return ui.scroll({ flexGrow = 1, gap = 2, paddingH = 4, revealKey = "l" .. reveal }, rows)
end

local function plain(lyrics)
  local rows = {}
  for line in string.gmatch((lyrics.plain or "") .. "\n", "([^\n]*)\n") do
    rows[#rows + 1] = ui.label({ text = line ~= "" and line or " ", fontSize = 13 })
  end
  return ui.scroll({ flexGrow = 1, gap = 2, paddingH = 4 }, rows)
end

function M.render(ctx, p)
  local lyrics = ctx.S.lyrics or { status = "idle" }
  local body
  if lyrics.status == "synced" and #(lyrics.lines or {}) > 0 then
    body = synced(lyrics, ctx.line, p)
  elseif lyrics.status == "plain" then
    body = plain(lyrics)
  else
    body = message(lyrics.status)
  end
  return ui.column({ flexGrow = 1, gap = 6, padding = 10, radius = 12, fill = "surface_container" }, {
    body,
    ui.label({ text = lyrics.source and (`Lyrics from {lyrics.source}` .. (lyrics.loose and " · another version, timing may differ" or "")) or "",
      visible = lyrics.source ~= nil,
      fontSize = 9, color = "on_surface_variant", textAlign = "end" }),
  })
end

return M
