--!nonstrict
-- Starting apps, and showing the hidden ones, through Hyprland. Background apps go to
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
      if not ok then noctalia.log(`encore: hyprctl dispatch failed: {noctalia.string.trim(r.stdout)}`) end
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

-- done({ class }) with the lowercased classes of the windows on the hidden workspace.
function M.hidden(done)
  if not M.available() then return done({}) end
  noctalia.runAsync({ "hyprctl", "clients", "-j" }, function(r)
    local clients = r.exitCode == 0 and noctalia.json.decode(r.stdout) or nil
    local out = {}
    for _, c in ipairs(type(clients) == "table" and clients or {}) do
      if type(c.workspace) == "table" and c.workspace.name == `special:{M.WORKSPACE}` then
        out[#out + 1] = string.lower(c.class or "")
      end
    end
    done(out)
  end, 3000)
end

return M
