--!nonstrict
-- Starting apps, and hiding and showing them, through Hyprland. Background apps go to
-- the special workspace `encore`, out of sight until toggled. Hyprland 0.56+ with a Lua
-- config takes only Lua dispatch syntax and older ones only the classic syntax, so each
-- call tries Lua first. Without Hyprland, apps start as plain processes.

local M = {}

M.WORKSPACE = "encore"

function M.available() return noctalia.getenv("HYPRLAND_INSTANCE_SIGNATURE") ~= nil and noctalia.commandExists("hyprctl") end

-- Runs a Lua dispatch, then the classic one if that was not "ok"; done(ok) is optional.
local function dispatch(lua, classic, done)
  noctalia.runAsync({ "hyprctl", "dispatch", lua }, function(r)
    if noctalia.string.trim(r.stdout) == "ok" then
      if done then done(true) end
      return
    end
    noctalia.runAsync({ "hyprctl", "dispatch", table.unpack(classic) }, function(r2)
      local ok = noctalia.string.trim(r2.stdout) == "ok"
      if not ok then noctalia.log(`encore: hyprctl dispatch failed: {noctalia.string.trim(r2.stdout)}`) end
      if done then done(ok) end
    end, 3000)
  end, 3000)
end

-- Starts a shell command line, on the hidden workspace when background is set.
function M.exec(command, background)
  if not M.available() then
    noctalia.runAsync({ "sh", "-c", command })
    return
  end
  local rules = background and string.format(", { workspace = %q }", `special:{M.WORKSPACE} silent`) or ""
  local classic = background and `[workspace special:{M.WORKSPACE} silent] {command}` or command
  dispatch(string.format("hl.dsp.exec_cmd(%q%s)", command, rules), { "exec", classic }, function(ok)
    if not ok then noctalia.runAsync({ "sh", "-c", command }) end
  end)
end

-- Shows the hidden workspace over the focused monitor, or hides it again.
function M.toggle()
  dispatch(string.format("hl.dsp.workspace.toggle_special(%q)", M.WORKSPACE), { "togglespecialworkspace", M.WORKSPACE })
end

-- Moves a window (by address) to a workspace without following it there.
local function move(address, workspace, done)
  dispatch(string.format("hl.dsp.window.move({ workspace = %q, window = %q, follow = false })",
    workspace, `address:{address}`),
    { "movetoworkspacesilent", `{workspace},address:{address}` }, done)
end

function M.hide(address, done) move(address, `special:{M.WORKSPACE}`, done) end

-- Moves windows (by address) to the focused monitor's workspace. Hyprland 0.57 reports
-- an id only for a numbered workspace, which `name:7` does not find, so: the id when
-- there is one, else `name:`. The hidden workspace, when shown there, is closed once
-- they are moved, or it would cover them. done(ok) after the last move.
function M.bring(addresses, done)
  noctalia.runAsync({ "hyprctl", "monitors", "-j" }, function(r)
    local monitors = r.exitCode == 0 and noctalia.json.decode(r.stdout) or nil
    local focused
    for _, m in ipairs(type(monitors) == "table" and monitors or {}) do
      if m.focused then focused = m end
    end
    local ws = focused and type(focused.activeWorkspace) == "table" and focused.activeWorkspace or {}
    local target = type(ws.id) == "number" and tostring(ws.id) or (ws.name or "") ~= "" and `name:{ws.name}` or nil
    if not target then
      noctalia.log("encore: no focused workspace to bring a window to")
      if done then done(false) end
      return
    end
    local overlay = type(focused.specialWorkspace) == "table" and focused.specialWorkspace.name == `special:{M.WORKSPACE}`
    local left, moved = #addresses, false
    for _, address in ipairs(addresses) do
      move(address, target, function(ok)
        moved = moved or ok
        left -= 1
        if left > 0 then return end
        if moved and overlay then M.toggle() end
        if done then done(moved) end
      end)
    end
  end, 3000)
end

-- done({ { class, address, workspace } }) for every window: class lowercased, workspace
-- its name ("special:encore" for the hidden one). Empty without Hyprland.
function M.clients(done)
  if not M.available() then return done({}) end
  noctalia.runAsync({ "hyprctl", "clients", "-j" }, function(r)
    local clients = r.exitCode == 0 and noctalia.json.decode(r.stdout) or nil
    local out = {}
    for _, c in ipairs(type(clients) == "table" and clients or {}) do
      out[#out + 1] = { class = string.lower(c.class or ""), address = c.address or "",
        workspace = type(c.workspace) == "table" and c.workspace.name or "" }
    end
    done(out)
  end, 3000)
end

return M
