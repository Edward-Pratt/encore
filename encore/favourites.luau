--!nonstrict
-- Favourites from the `favourites` setting: one per entry, a Spotify link or spotify:
-- URI, optionally named as "Name = link". Pure, and plain Lua 5 so tests/pure.lua can run
-- it without noctalia.

local M = {}

local KINDS = { playlist = "Playlist", album = "Album", artist = "Artist", track = "Track", show = "Podcast", episode = "Episode" }

-- "https://open.spotify.com/intl-de/playlist/ID?si=x" or "spotify:playlist:ID" -> "spotify:playlist:ID".
function M.uri(link)
  link = string.match(link or "", "^%s*(.-)%s*$")
  local kind, id = string.match(link, "^spotify:(%a+):([%w]+)$")
  if kind then return "spotify:" .. kind .. ":" .. id, kind end
  local path = string.match(link, "^https?://open%.spotify%.com(/[^?#]*)")
  if not path then return nil end
  -- The first known kind in the path: "/intl-de/playlist/ID" has a locale before it.
  local parts = {}
  for part in string.gmatch(path, "[^/]+") do parts[#parts + 1] = part end
  for i = 1, #parts - 1 do
    if KINDS[parts[i]] and string.match(parts[i + 1], "^[%w]+$") then
      return "spotify:" .. parts[i] .. ":" .. parts[i + 1], parts[i]
    end
  end
  return nil
end

-- { { name, uri } } in setting order; entries that are not Spotify links are skipped.
function M.parse(list)
  local out = {}
  for _, item in ipairs(type(list) == "table" and list or {}) do
    local name, link = nil, item
    if not M.uri(item) then
      name, link = string.match(item, "^%s*(.-)%s*=%s*(%S+)%s*$")
      if name == "" then name = nil end
    end
    local uri, kind = M.uri(link)
    if uri then
      out[#out + 1] = { name = name or ((KINDS[kind] or kind) .. " " .. string.sub(uri, -6)), uri = uri }
    end
  end
  return out
end

return M
