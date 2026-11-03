--!nonstrict
-- The panel's launch parts: an Open button per music app that is not running, the
-- toggle for apps on the hidden workspace, the favourites list, and the view shown
-- when no player runs. Opening goes through the service (control.open).
local media = require("./media.luau")
local control = require("./control.luau")
local hyprland = require("./hyprland.luau")
local favourites = require("./favourites.luau")

local M = {}

local KIND_GLYPH = { playlist = "playlist", album = "disc", artist = "user", track = "music", show = "microphone", episode = "microphone" }

local function background() return noctalia.getConfig("open_in_background") ~= false and hyprland.available() end

local function notRunning(ctx)
  local out = {}
  for _, app in ipairs(ctx.S.apps) do
    if not media.playerFor(ctx.S.players, app) then out[#out + 1] = app end
  end
  return out
end

local function openTip(app) return background() and `Open {app.name} in the background` or `Open {app.name}` end

-- For the chips row: Open buttons, then the hidden-workspace toggle when it holds windows.
function M.chipButtons(ctx)
  local out = {}
  for _, app in ipairs(notRunning(ctx)) do
    out[#out + 1] = ui.button({ key = "open-" .. app.id, glyph = "plus", text = app.name, variant = "ghost", controlSize = "sm",
      tooltip = openTip(app), onClick = function() control.open(app.id) end })
  end
  if #ctx.S.hidden > 0 then
    out[#out + 1] = ui.button({ key = "hidden", glyph = "app-window", variant = "ghost", controlSize = "sm",
      tooltip = "Show or hide apps running in the background",
      onClick = function()
        hyprland.toggle()
        ctx.close()
      end })
  end
  return out
end

function M.hasFavourites()
  return #favourites.parse(noctalia.getConfig("favourites")) > 0
end

local function favouriteRows()
  local rows = {}
  for i, f in ipairs(favourites.parse(noctalia.getConfig("favourites"))) do
    local kind = string.match(f.uri, "^spotify:(%a+):")
    rows[#rows + 1] = ui.row({ key = "fav-" .. i, gap = 10, align = "center", paddingV = 6, paddingH = 6, radius = 8,
      tooltip = f.uri, onClick = function() control.open(nil, f.uri) end }, {
      ui.glyph({ name = KIND_GLYPH[kind] or "music", size = 16, color = "primary" }),
      ui.label({ text = f.name, fontSize = 13, flexGrow = 1, maxLines = 1 }),
      ui.glyph({ name = "player-play", size = 14, color = "on_surface_variant" }),
    })
  end
  return rows
end

-- The Favourites pane: one row per favourite; a click plays it in Spotify.
function M.favouritesPane()
  local rows = favouriteRows()
  if #rows == 0 then
    rows = { ui.label({ text = "Add Spotify playlists, albums or tracks in Encore's settings: paste a share link, "
      .. "or write Name = link.", fontSize = 12, color = "on_surface_variant" }) }
  end
  return ui.column({ flexGrow = 1, padding = 10, radius = 12, fill = "surface_container" }, {
    ui.scroll({ flexGrow = 1, gap = 2 }, rows),
  })
end

-- Shown when no player runs: every music app to open, then the favourites.
function M.launchView(ctx)
  local rows = {
    ui.row({ align = "center" }, {
      ui.label({ text = "Nothing is playing", fontSize = 17, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = ctx.close }),
    }),
  }
  for _, app in ipairs(ctx.S.apps) do
    rows[#rows + 1] = ui.row({ key = "app-" .. app.id, gap = 10, align = "center", padding = 8, radius = 10, fill = "surface_container" }, {
      app.icon ~= "" and ui.image({ path = app.icon, width = 28, height = 28 }) or ui.glyph({ name = "music", size = 24 }),
      ui.label({ text = app.name, fontSize = 14, flexGrow = 1 }),
      ui.button({ text = "Open", glyph = "player-play", variant = "primary", controlSize = "sm", tooltip = openTip(app),
        onClick = function() control.open(app.id) end }),
    })
  end
  if #ctx.S.apps == 0 then
    rows[#rows + 1] = ui.label({ text = "No music apps found. Anything that speaks MPRIS shows up here once it runs.",
      fontSize = 12, color = "on_surface_variant" })
  end
  local favs = favouriteRows()
  if #favs > 0 then
    rows[#rows + 1] = ui.label({ text = "Favourites", fontSize = 12, fontWeight = "bold", color = "on_surface_variant" })
    rows[#rows + 1] = ui.scroll({ flexGrow = 1, gap = 2 }, favs)
  end
  return ui.column({ flexGrow = 1, gap = 10 }, rows)
end

return M
