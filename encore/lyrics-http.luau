--!nonstrict
-- JSON GETs for the lyrics sources. done(value, failed): 404 and 400 mean "not found"
-- (value nil, failed false); anything else that is not a 200 counts as failed.

local M = {}

-- LRCLIB asks clients to name themselves; harmless for the others.
local HEADERS = { "User-Agent: encore (noctalia plugin; https://github.com/Edward-Pratt/encore)" }

function M.get(url, done)
  local ok = noctalia.http({ url = url, headers = HEADERS, follow_redirects = true }, function(r)
    if not r.ok or (r.status ~= 200 and r.status ~= 404 and r.status ~= 400) then
      noctalia.log(`encore: lyrics request failed ({r.ok and r.status or "network"}): {url}`)
      return done(nil, true)
    end
    local value = r.status == 200 and noctalia.json.decode(r.body or "") or nil
    done(type(value) == "table" and value or nil, false)
  end)
  if not ok then done(nil, true) end
end

function M.enc(s) return noctalia.string.urlEncode(s) end

return M
