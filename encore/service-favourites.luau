--!nonstrict
-- Spotify favourites, published as `favourites = [{ name, uri, saved }]`, in this order:
-- Liked Songs (with the liked_songs setting, when Spotify is installed), the entries in
-- the favourites setting, then links pasted from the panel or launcher (saved = true;
-- only those can be removed there). Pasted links live in <data>/favourites.json, since a
-- plugin cannot write its own settings. Entries without a name get Spotify's own
-- title from its public link preview (oEmbed), cached in the same file. Any favourite
-- can be renamed from the panel; renames are kept there too and win over every other
-- name (an empty rename restores it).
--   command = { action = "fav-add", link, at } | { action = "fav-remove", uri, at }
--           | { action = "fav-rename", uri, name, at }
local util = require("./service-util.luau")
local favourites = require("./favourites.luau")
local media = require("./media.luau")

local M = {}

local FILE = util.DATA .. "/favourites.json"
local OEMBED = "https://open.spotify.com/oembed?url="
-- Liked Songs as Spotify's desktop app opens it.
M.LIKED = "spotify:collection:tracks"

local store = util.decode(noctalia.readFile(FILE) or "") or {}
store.saved = type(store.saved) == "table" and store.saved or {}
store.names = type(store.names) == "table" and store.names or {}
store.renamed = type(store.renamed) == "table" and store.renamed or {}
local pending = {} -- uri -> true while its name is looked up
local lastAt = 0

local function save() noctalia.writeFile(FILE, noctalia.json.encode(store) or "") end

local function spotifyInstalled() return media.spotifyApp(noctalia.state.get("apps")) ~= nil end

local lookupName

function M.publish()
  local list, seen = {}, {}
  local function add(name, uri, saved)
    if seen[uri] then return end
    seen[uri] = true
    if not name and not store.names[uri] then lookupName(uri) end
    local fallback = (favourites.parse({ uri })[1] or {}).name or uri
    list[#list + 1] = { name = store.renamed[uri] or name or store.names[uri] or fallback, uri = uri, saved = saved }
  end
  if noctalia.getConfig("liked_songs") ~= false and spotifyInstalled() then add("Liked Songs", M.LIKED, false) end
  for _, f in ipairs(favourites.parse(noctalia.getConfig("favourites"))) do
    -- parse() names unnamed links "Playlist 1a2b3c"; a looked-up title is better.
    local named = f.name ~= (favourites.parse({ f.uri })[1] or {}).name
    add(named and f.name or nil, f.uri, false)
  end
  for _, f in ipairs(store.saved) do add(f.name, f.uri, true) end
  util.publish("favourites", list)
end

lookupName = function(uri)
  local url = favourites.webUrl(uri)
  if not url or pending[uri] then return end
  pending[uri] = true
  noctalia.http({ url = OEMBED .. noctalia.string.urlEncode(url) }, function(r)
    pending[uri] = nil
    local v = r.ok and r.status == 200 and util.decode(r.body) or nil
    if v and type(v.title) == "string" and v.title ~= "" then
      store.names[uri] = v.title
      save()
      M.publish()
    end
  end)
end

local function addLink(link)
  local uri = favourites.uri(link)
  if not uri then
    noctalia.osd.show("alert-circle", "Not a Spotify link")
    return
  end
  for _, f in ipairs(store.saved) do
    if f.uri == uri then return end
  end
  table.insert(store.saved, { uri = uri })
  save()
  M.publish()
  noctalia.osd.show("star", "Added to favourites")
end

local function remove(uri)
  for i, f in ipairs(store.saved) do
    if f.uri == uri then
      table.remove(store.saved, i)
      store.renamed[uri] = nil
      save()
      return M.publish()
    end
  end
end

local function rename(uri, name)
  if type(uri) ~= "string" or uri == "" then return end
  name = noctalia.string.trim(name or "")
  store.renamed[uri] = name ~= "" and name or nil
  save()
  M.publish()
end

function M.command(cmd)
  local actions = { ["fav-add"] = true, ["fav-remove"] = true, ["fav-rename"] = true }
  if type(cmd) ~= "table" or not actions[cmd.action] or (cmd.at or 0) <= lastAt then return end
  lastAt = cmd.at
  if cmd.action == "fav-add" then addLink(cmd.link or "")
  elseif cmd.action == "fav-rename" then rename(cmd.uri, cmd.name)
  else remove(cmd.uri) end
end

return M
