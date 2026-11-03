--!nonstrict
-- Spotify favourites, published as `favourites = [{ name, uri, saved }]`, in this order:
-- Liked Songs (with the liked_songs setting, when Spotify is installed), the entries in
-- the favourites setting, then links pasted from the panel or launcher (saved = true;
-- only those can be removed there). Pasted links live in <data>/favourites.json, since a
-- plugin cannot write its own settings. Entries without a name get Spotify's own
-- title from its public link preview (oEmbed), cached in the same file.
--   command = { action = "fav-add", link, at } | { action = "fav-remove", uri, at }
local util = require("./service-util.luau")
local favourites = require("./favourites.luau")

local M = {}

local FILE = util.DATA .. "/favourites.json"
local OEMBED = "https://open.spotify.com/oembed?url="
-- Liked Songs as Spotify's desktop app opens it.
M.LIKED = "spotify:collection:tracks"

local store = util.decode(noctalia.readFile(FILE) or "") or {}
store.saved = type(store.saved) == "table" and store.saved or {}
store.names = type(store.names) == "table" and store.names or {}
local pending = {} -- uri -> true while its name is looked up
local lastAt = 0

local function save() noctalia.writeFile(FILE, noctalia.json.encode(store) or "") end

local function spotifyInstalled()
  for _, app in ipairs(noctalia.state.get("apps") or {}) do
    if app.wmClass == "spotify" or string.find(app.id, "spotify", 1, true) then return true end
  end
  return false
end

local lookupName

function M.publish()
  local list, seen = {}, {}
  local function add(name, uri, saved)
    if seen[uri] then return end
    seen[uri] = true
    if not name and not store.names[uri] then lookupName(uri) end
    local fallback = (favourites.parse({ uri })[1] or {}).name or uri
    list[#list + 1] = { name = name or store.names[uri] or fallback, uri = uri, saved = saved }
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
      save()
      return M.publish()
    end
  end
end

function M.command(cmd)
  if type(cmd) ~= "table" or (cmd.action ~= "fav-add" and cmd.action ~= "fav-remove") or (cmd.at or 0) <= lastAt then return end
  lastAt = cmd.at
  if cmd.action == "fav-add" then addLink(cmd.link or "") else remove(cmd.uri) end
end

return M
