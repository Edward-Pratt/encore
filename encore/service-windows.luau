--!nonstrict
-- Music apps' windows on Hyprland, for the hide and bring-back buttons. Publishes
--   hidden  = [class]                     -- lowercased classes of windows on special:encore
--   windows = [{ app, address, hidden }]  -- windows of `apps` entries: on special:encore
--                                         -- (hidden) or on a normal workspace
-- and handles `command`s from the surfaces:
--   { action = "windows", at }    -- read the windows again (the panel opening)
--   { action = "hide", app, at }  -- move that app's windows in sight to special:encore
--   { action = "bring", app, at } -- move its hidden windows to the focused workspace
-- Only `apps` entries (the Music category) get the buttons, so a browser playing music
-- is never hidden. Windows on other special workspaces (a scratchpad) are left.
local util = require("./service-util.luau")
local hyprland = require("./hyprland.luau")

local M = {}

local HIDDEN = `special:{hyprland.WORKSPACE}`
local lastAt = 0

-- The `apps` entry a window belongs to: its class is the entry's StartupWMClass or id.
local function appFor(apps, class)
  if class == "" then return nil end
  for _, app in ipairs(apps) do
    if class == app.wmClass or class == app.id then return app end
  end
  return nil
end

-- Reads every window, publishes `hidden` and `windows`, then done(windows) if given.
function M.check(done)
  hyprland.clients(function(clients)
    local apps = noctalia.state.get("apps") or {}
    local hidden, windows = {}, {}
    for _, c in ipairs(clients) do
      local isHidden = c.workspace == HIDDEN
      if isHidden then hidden[#hidden + 1] = c.class end
      local app = (isHidden or string.sub(c.workspace, 1, 8) ~= "special:") and appFor(apps, c.class)
      if app then windows[#windows + 1] = { app = app.id, address = c.address, hidden = isHidden } end
    end
    util.publish("hidden", hidden)
    util.publish("windows", windows)
    if done then done(windows) end
  end)
end

-- Moves the app's windows from a fresh read, so a closed or moved one is not chased:
-- those in sight with hide, the hidden ones otherwise (together, so the shown hidden
-- workspace is closed once).
local function moveApp(appId, hide)
  M.check(function(windows)
    local addresses = {}
    for _, w in ipairs(windows) do
      if w.app == appId and w.hidden ~= hide then addresses[#addresses + 1] = w.address end
    end
    if #addresses == 0 then return end
    if not hide then return hyprland.bring(addresses, function() M.check() end) end
    for _, address in ipairs(addresses) do hyprland.hide(address, function() M.check() end) end
  end)
end

function M.command(cmd)
  if type(cmd) ~= "table" or (cmd.at or 0) <= lastAt then return end
  if cmd.action == "windows" then
    lastAt = cmd.at
    M.check()
  elseif (cmd.action == "hide" or cmd.action == "bring") and cmd.app then
    lastAt = cmd.at
    moveApp(cmd.app, cmd.action == "hide")
  end
end

return M
