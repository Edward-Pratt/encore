--!nonstrict
-- Installed music apps, published as `apps`: every desktop entry in the Music category,
-- found in the XDG data dirs (user entries first, so they override system ones).
--   apps = [{ id, name, command, icon, wmClass }]   -- id and wmClass lowercased
local util = require("./service-util.luau")
local desktopEntry = require("./desktop-entry.luau")

local M = {}

M.RESCAN_MS = 10 * 60000
M.lastScan = -M.RESCAN_MS

local function dataDirs()
  local home = noctalia.getenv("HOME") or ""
  local dirs, seen = {}, {}
  local function add(d)
    if d ~= "" and not seen[d] then
      seen[d] = true
      dirs[#dirs + 1] = d
    end
  end
  add(noctalia.getenv("XDG_DATA_HOME") or (home .. "/.local/share"))
  for d in string.gmatch(noctalia.getenv("XDG_DATA_DIRS") or "/usr/local/share:/usr/share", "[^:]+") do add(d) end
  return dirs
end

local function quote(s) return "'" .. string.gsub(s, "'", "'\\''") .. "'" end

local function read(paths)
  local apps, seen = {}, {}
  for _, path in ipairs(paths) do
    local id = string.lower(string.match(path, "([^/]+)%.desktop$") or "")
    local entry = id ~= "" and not seen[id] and desktopEntry.parse(noctalia.readFile(path) or "")
    seen[id] = true
    if entry and not entry.hidden then
      apps[#apps + 1] = {
        id = id,
        -- "Spotify (Launcher)": the launcher package's name for Spotify.
        name = string.gsub(entry.name or id, "%s*%(Launcher%)$", ""),
        command = desktopEntry.command(entry.exec),
        icon = noctalia.appIconPath(id, 32) or (entry.icon and noctalia.appIconPath(entry.icon, 32)) or "",
        wmClass = string.lower(entry.wmClass or ""),
      }
    end
  end
  table.sort(apps, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
  return apps
end

-- One grep over every applications dir finds the Music entries; only those are read.
function M.scan()
  M.lastScan = noctalia.nowMs()
  local globs = {}
  for _, d in ipairs(dataDirs()) do globs[#globs + 1] = quote(d .. "/applications") .. "/*.desktop" end
  local cmd = "grep -l -s -E '^Categories=(.*;)?Music(;|$)' -- " .. table.concat(globs, " ") .. "; true"
  noctalia.runAsync({ "sh", "-c", cmd }, function(r)
    local paths = {}
    for line in string.gmatch(r.stdout or "", "[^\n]+") do paths[#paths + 1] = line end
    util.publish("apps", read(paths))
  end, 5000)
end

return M
