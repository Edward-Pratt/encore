--!nonstrict
-- Desktop entry files: the [Desktop Entry] keys Encore needs, and the Exec line as a
-- runnable command. Pure, and plain Lua 5 so tests/pure.lua can run it without noctalia.

local M = {}

-- { name, exec, icon, wmClass, categories = { [name] = true }, hidden } or nil when the
-- file has no [Desktop Entry] group or no Exec.
function M.parse(text)
  local entry, inMain = { categories = {} }, false
  for line in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
    local group = string.match(line, "^%[(.+)%]%s*$")
    if group then
      inMain = group == "Desktop Entry"
    elseif inMain then
      local key, value = string.match(line, "^([%w%-]+)%s*=%s*(.-)%s*$")
      if key == "Name" then entry.name = value
      elseif key == "Exec" then entry.exec = value
      elseif key == "Icon" then entry.icon = value
      elseif key == "StartupWMClass" then entry.wmClass = value
      elseif key == "Categories" then
        for c in string.gmatch(value, "[^;]+") do entry.categories[c] = true end
      elseif (key == "NoDisplay" or key == "Hidden") and value == "true" then entry.hidden = true
      end
    end
  end
  if not entry.exec or entry.exec == "" then return nil end
  return entry
end

-- The Exec line without its field codes (%U, %f, ...); "%%" stays a literal "%".
function M.command(exec)
  local s = string.gsub(exec or "", "%%%%", "\1")
  s = string.gsub(s, "%s*%%[fFuUdDnNickvm]", "")
  s = string.gsub(s, "\1", "%%")
  return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

return M
