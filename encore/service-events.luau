--!nonstrict
-- Reactions to player changes, found by comparing each published `players` list with
-- the one before: pausing the other players when one starts (pause_others). The first
-- list only seeds the comparison, so a restart or reload stays silent. (No track-change
-- popup: noctalia's own media OSD already announces every track.)
local control = require("./control.luau")

local M = {}

local previous = nil -- bus -> status, from the last list

-- A player that started (or appeared already playing) pauses every other playing one.
-- When several start at once, noctalia's active player wins.
local function pauseOthers(list, active)
  local winner = nil
  for _, p in ipairs(list) do
    if p.status == "Playing" and previous[p.bus] ~= "Playing" and (not winner or p.bus == active) then winner = p end
  end
  if not winner then return end
  for _, p in ipairs(list) do
    if p.bus ~= winner.bus and p.status == "Playing" and p.canPause then control.pause(p) end
  end
end

function M.onPlayers(list)
  list = type(list) == "table" and list or {}
  if previous and noctalia.getConfig("pause_others") == true then
    pauseOthers(list, noctalia.state.get("active") or "")
  end
  previous = {}
  for _, p in ipairs(list) do previous[p.bus] = p.status end
end

return M
