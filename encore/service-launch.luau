--!nonstrict
-- Opening apps and playing favourites, for `command` requests from the surfaces:
--   command = { action = "open", app = id?, uri = spotify:...?, at }
-- Starts the app when it is not running (on Hyprland's hidden workspace with
-- open_in_background), then waits for its player and plays: OpenUri for a favourite,
-- Play otherwise (with play_on_open). A just-started player often ignores the first
-- request, so it is repeated every few seconds until the player reports Playing.
-- Also publishes `hidden`: the classes of windows on the hidden workspace.
local util = require("./service-util.luau")
local media = require("./media.luau")
local control = require("./control.luau")
local hyprland = require("./hyprland.luau")

local M = {}

local WAIT_MS = 90000 -- for the player to appear and play
local RETRY_MS = 3000
local TRIES = 5

local pending = nil
local lastAt = 0

local function setting(key) return noctalia.getConfig(key) ~= false end

local function findApp(id, uri)
  for _, app in ipairs(noctalia.state.get("apps") or {}) do
    if id and app.id == id then return app end
    if not id and uri and (app.wmClass == "spotify" or string.find(app.id, "spotify", 1, true)) then return app end
  end
  return nil
end

function M.command(cmd)
  if type(cmd) ~= "table" or cmd.action ~= "open" or (cmd.at or 0) <= lastAt then return end
  lastAt = cmd.at
  local app = findApp(cmd.app, cmd.uri)
  if not app then
    noctalia.log(`encore: no app to open for {cmd.app or cmd.uri}`)
    return
  end
  local running = media.playerFor(noctalia.state.get("players"), app)
  if not running then hyprland.exec(app.command, setting("open_in_background")) end
  pending = { app = app, uri = cmd.uri, play = cmd.uri ~= nil or setting("play_on_open"),
    untilMs = noctalia.nowMs() + WAIT_MS, tries = 0, sentAt = nil, activated = false }
  M.step()
end

-- Advances the pending open; runs on every players change and every service tick.
function M.step()
  if not pending then return end
  local now = noctalia.nowMs()
  if now > pending.untilMs then
    noctalia.log(`encore: {pending.app.name} did not start playing`)
    pending = nil
    return
  end
  local p = media.playerFor(noctalia.state.get("players"), pending.app)
  if not p then return end
  if not pending.activated then
    pending.activated = true
    control.makeActive(p)
  end
  if not pending.play or (pending.tries > 0 and p.status == "Playing") or pending.tries >= TRIES then
    pending = nil
    return
  end
  if pending.sentAt and now - pending.sentAt < RETRY_MS then return end
  pending.tries += 1
  pending.sentAt = now
  if pending.uri then control.openUri(p, pending.uri) else control.play(p) end
end

function M.checkHidden()
  hyprland.hidden(function(classes) util.publish("hidden", classes) end)
end

return M
