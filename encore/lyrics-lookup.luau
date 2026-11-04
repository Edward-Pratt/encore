--!nonstrict
-- One lyrics lookup across all sources at once. Each source is a lane that runs its
-- own steps in order (exact query, then the cleaned one) and stops at a hit of the right
-- length; the lanes run side by side, so a slow or failing source (LRCLIB answers 503 at
-- times) never holds the others up. Every result that beats the best so far goes to
-- onBetter at once, so lyrics show as soon as any source has them; a word-timed hit of
-- the right length ends the lookup early. onDone(best, failed) runs once, when all lanes
-- are done or that best possible hit arrived; failed means nothing was found and some
-- source failed. An instrumental flag ranks below any lyrics: a source often matches an
-- instrumental release of the song, so it never replaces lyrics another source found.
-- Plain Lua 5 syntax, so tests/pure.lua can run it with stub sources.
local query = require("./lyrics-query.luau")
local lrclib = require("./lyrics-lrclib.luau")
local netease = require("./lyrics-netease.luau")
local kugou = require("./lyrics-kugou.luau")

local M = {}

local function hasWords(found)
  for _, l in ipairs(found.lines or {}) do
    if l.words then return true end
  end
  return false
end

-- Lower is better: right-length word timing, right-length lines, other-length word
-- timing, other-length lines, plain lyrics, instrumental.
local function rank(found)
  if not found then return 99 end
  if found.status == "instrumental" then return 6 end
  if found.status ~= "synced" then return 5 end
  return (found.loose and 3 or 1) + (hasWords(found) and 0 or 1)
end
M.rank = rank

local function lane(steps)
  local list = {}
  for _, group in ipairs(steps) do
    for _, s in ipairs(group) do list[#list + 1] = s end
  end
  return list
end

function M.run(track, backup, onBetter, onDone)
  local exact, cleaned = query.exact(track), query.cleaned(track)
  local function both(source, ...)
    local groups = { source.steps(exact, ...) }
    if cleaned then groups[2] = source.steps(cleaned) end
    return lane(groups)
  end
  local lanes = { both(lrclib, true) }
  if backup then
    lanes[2] = both(netease)
    lanes[3] = both(kugou)
  end

  local best, errors, running, finished = nil, 0, #lanes, false
  local function finish()
    if finished then return end
    finished = true
    onDone(best, best == nil and errors > 0)
  end
  local function offer(found)
    if finished or rank(found) >= rank(best) then return end
    best = found
    onBetter(found)
    if rank(found) == 1 then finish() end
  end

  for _, steps in ipairs(lanes) do
    local i, laneBest = 0, 99
    local function step(found, failed)
      if finished then return end
      if failed then errors = errors + 1 end
      if found then
        offer(found)
        laneBest = math.min(laneBest, rank(found))
      end
      i = i + 1
      -- A lane stops at a hit of the right length; a cleaned query can only do worse.
      if i <= #steps and laneBest > 2 then return steps[i].run(step) end
      running = running - 1
      if running == 0 then finish() end
    end
    step(nil, false)
  end
end

return M
