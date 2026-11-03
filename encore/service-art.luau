--!nonstrict
-- Album art as a local file, since ui.image reads local files only. file:// URLs pass
-- through; http(s) art is downloaded once into <data>/art, named by a hash of the URL.
-- A finished download calls the onReady callback so players are published again.
local util = require("./service-util.luau")

local M = {}
local KEEP = 60 -- cached covers kept; the oldest go first

local pending = {} -- url -> true while downloading
local failed = {} -- url -> true: not retried until reload

local function extension(url)
  local ext = string.match(string.lower(url), "%.(%a+)$") or string.match(string.lower(url), "%.(%a+)%?")
  if ext == "png" or ext == "webp" or ext == "jpeg" or ext == "gif" then return ext end
  return "jpg"
end

local function prune(dir)
  local names = noctalia.listDir(dir)
  if not names or #names <= KEEP then return end
  local files = {}
  for _, name in ipairs(names) do
    local info = noctalia.fileInfo(dir .. "/" .. name)
    if info and not info.isDir then files[#files + 1] = { path = dir .. "/" .. name, mtime = info.mtime } end
  end
  table.sort(files, function(a, b) return a.mtime > b.mtime end)
  for i = KEEP + 1, #files do noctalia.removeFile(files[i].path) end
end

-- The local path for an art URL, or nil while it downloads or when there is none.
function M.path(url, onReady)
  if type(url) ~= "string" or url == "" then return nil end
  if string.sub(url, 1, 7) == "file://" then
    local path = noctalia.string.urlDecode(string.sub(url, 8))
    return noctalia.fileExists(path) and path or nil
  end
  if not string.match(url, "^https?://") or failed[url] then return nil end
  local dir = util.dir("art")
  local path = `{dir}/{util.hash(url)}.{extension(url)}`
  if noctalia.fileExists(path) then return path end
  if not pending[url] then
    pending[url] = true
    noctalia.download(url, path, function(ok)
      pending[url] = nil
      if not ok then
        failed[url] = true
        noctalia.removeFile(path)
        return
      end
      prune(dir)
      onReady()
    end)
  end
  return nil
end

return M
