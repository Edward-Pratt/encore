--!nonstrict
-- The sleep timer, published as `sleep = { endsAt }` (0 when off). Set by a `command`
-- { action = "sleep", minutes } (0 cancels) or the service IPC; when it runs out, every
-- playing player is paused. Kept in the service so it runs with the panel closed, and
-- read back from state on start so a service reload keeps it.
local util = require("./service-util.luau")
local control = require("./control.luau")

local M = {}

local endsAt = 0
local lastAt = 0

local saved = noctalia.state.get("sleep")
if type(saved) == "table" and (tonumber(saved.endsAt) or 0) > noctalia.nowMs() then endsAt = saved.endsAt end

local function publish() util.publish("sleep", { endsAt = endsAt }) end
publish()

function M.set(minutes)
  minutes = math.max(0, tonumber(minutes) or 0)
  endsAt = minutes > 0 and noctalia.nowMs() + minutes * 60000 or 0
  publish()
end

function M.command(cmd)
  if type(cmd) ~= "table" or cmd.action ~= "sleep" or (cmd.at or 0) <= lastAt then return end
  lastAt = cmd.at
  M.set(cmd.minutes)
end

-- Runs on every service tick.
function M.check()
  if endsAt == 0 or noctalia.nowMs() < endsAt then return end
  endsAt = 0
  publish()
  for _, p in ipairs(noctalia.state.get("players") or {}) do
    if p.status == "Playing" and p.canPause then control.pause(p) end
  end
  noctalia.osd.show("zzz", "Sleep timer: paused")
end

return M
