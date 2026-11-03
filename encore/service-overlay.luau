--!nonstrict
-- The lyrics overlay: whether it is on (kept in <data>/overlay.json across restarts) and
-- whether the layer shows. It shows only while it is on, the shown player plays and its
-- synced lyrics are loaded or loading, so it disappears on pause and for tracks without
-- synced lyrics. Published as `overlay = { enabled }`.
local util = require("./service-util.luau")
local media = require("./media.luau")

local M = {}

local LAYER = "lyrics"
local FILE = util.DATA .. "/overlay.json"

local saved = util.decode(noctalia.readFile(FILE) or "")
local enabled = saved ~= nil and saved.enabled == true
local shown = false
local lastAt = 0

-- The layer's monitor, edge, distance from it and height, from the overlay_* settings.
local function props()
  local o = noctalia.string.trim(noctalia.getConfig("overlay_output") or "")
  local edge = noctalia.getConfig("overlay_position") == "top" and "top" or "bottom"
  local size = tonumber(noctalia.getConfig("overlay_size")) or 16
  local nextLine = noctalia.getConfig("overlay_next_line") == true
  return {
    output = o ~= "" and o or "focused",
    anchors = { edge },
    margins = { [edge] = tonumber(noctalia.getConfig("overlay_offset")) or 70 },
    height = math.ceil(size * (nextLine and 3.6 or 2.6)) + 16,
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
