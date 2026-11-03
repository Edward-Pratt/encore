--!nonstrict
-- The lyrics overlay: whether it is on (kept in <data>/overlay.json across restarts) and
-- whether the layer shows. It shows only while it is on, the shown player plays and its
-- synced lyrics are loaded or loading, so it disappears on pause and for tracks without
-- synced lyrics. Published as `overlay = { enabled }`.
local util = require("./service-util.luau")
local media = require("./media.luau")
local place = require("./overlay-place.luau")

local M = {}

local LAYER = "lyrics"
local FILE = util.DATA .. "/overlay.json"

local saved = util.decode(noctalia.readFile(FILE) or "")
local enabled = saved ~= nil and saved.enabled == true
local shown = false
local lastAt = 0

-- The layer's monitor, anchors, distance from the edges it touches and height, from
-- the overlay_* settings. With no anchor on an axis the compositor centres it there.
local function props()
  local o = noctalia.string.trim(noctalia.getConfig("overlay_output") or "")
  local spot = place.of(noctalia.getConfig("overlay_position"))
  local size = tonumber(noctalia.getConfig("overlay_size")) or 16
  local nextLine = noctalia.getConfig("overlay_next_line") == true
  local offset = tonumber(noctalia.getConfig("overlay_offset")) or 70
  local anchors, margins = {}, {}
  for _, side in ipairs({ spot.v, spot.h }) do
    if side ~= "center" then
      anchors[#anchors + 1] = side
      margins[side] = offset
    end
  end
  return {
    output = o ~= "" and o or "focused",
    anchors = anchors,
    margins = margins,
    -- Room for a lyric wrapped to three lines (and two for the next one); the space it
    -- does not use is transparent and click-through.
    height = math.ceil(size * (3 * 1.35 + (nextLine and 2 * 1.1 or 0) + 1.2)) + 16,
  }
end

util.publish("overlay", { enabled = enabled })

-- Shows or hides the layer to match the players and lyrics; cheap when nothing changed.
function M.update(force)
  local p = media.current(noctalia.state.get("players"), noctalia.state.get("active"))
  local lyrics = noctalia.state.get("lyrics")
  local status = type(lyrics) == "table" and lyrics.status or ""
  local want = enabled and p ~= nil and p.status == "Playing" and (status == "synced" or status == "loading")
  if want == shown and not force then return end
  shown = want
  if want then
    noctalia.layer.configure(LAYER, props())
    noctalia.layer.show(LAYER)
  else
    noctalia.layer.hide(LAYER)
  end
end

function M.set(on)
  enabled = on == true
  noctalia.writeFile(FILE, noctalia.json.encode({ enabled = enabled }) or "")
  util.publish("overlay", { enabled = enabled })
  M.update()
end

function M.toggle() M.set(not enabled) end

-- command = { action = "overlay", at }: toggles it.
function M.command(cmd)
  if type(cmd) ~= "table" or cmd.action ~= "overlay" or (cmd.at or 0) <= lastAt then return end
  lastAt = cmd.at
  M.toggle()
end

-- Changed overlay settings move or resize a shown overlay.
function M.configChanged()
  if shown then noctalia.layer.configure(LAYER, props()) end
end

return M
