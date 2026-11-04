--!nonstrict
-- Position samples: a player's position is published as positionMs at sampledAt, and
-- the surfaces extrapolate it while the player plays. merge(old, new) runs on every read
-- of a player. Pure, and plain Lua 5 so tests/pure.lua can run it.

local M = {}

-- A new position this close to the extrapolated one keeps the old sample, so a resync
-- of a steadily playing track wakes nobody.
M.DRIFT_MS = 1000
-- A player that says Playing but whose position moved less than STILL_MS in STALL_MS is
-- stalled: Spotify does this while it loads, or stuck with nothing to play.
M.STALL_MS = 3000
M.STILL_MS = 250

-- Adjusts `new` (a fresh read) against `old` (the published record of the same player):
-- keeps the old sample when the new one only confirms it, and sets new.stalled when the
-- position stands still while Playing, so surfaces stop moving the seek bar.
function M.merge(old, new)
  if not old or old.status ~= "Playing" or new.status ~= "Playing" or old.title ~= new.title then return end
  local elapsed = new.sampledAt - old.sampledAt
  local still = math.abs(new.positionMs - old.positionMs) < M.STILL_MS
  if still and (old.stalled or elapsed >= M.STALL_MS) then
    new.stalled = true
    new.positionMs, new.sampledAt = old.positionMs, old.sampledAt
    return
  end
  -- Moving again after a stall: the new sample stands.
  if old.stalled then return end
  if math.abs(old.positionMs + elapsed - new.positionMs) < M.DRIFT_MS then
    new.positionMs, new.sampledAt = old.positionMs, old.sampledAt
  end
end

-- The position at `now`, extrapolated from the sample while playing and not stalled.
function M.at(p, now)
  if not p then return 0 end
  local ms = p.positionMs or 0
  if p.status == "Playing" and not p.stalled then ms = ms + now - (p.sampledAt or 0) end
  if (p.lengthMs or 0) > 0 then ms = math.min(ms, p.lengthMs) end
  return math.max(0, ms)
end

return M
