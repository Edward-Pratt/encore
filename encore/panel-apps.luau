--!nonstrict
-- The panel's launch parts: an Open button per music app that is not running, the
-- toggle for apps on the hidden workspace, the favourites list, and the view shown
-- when no player runs. Opening goes through the service (control.open).
local media = require("./media.luau")
local control = require("./control.luau")
local hyprland = require("./hyprland.luau")
local favourites = require("./favourites.luau")

local M = {}

local KIND_GLYPH = { playlist = "playlist", album = "disc", artist = "user", track = "music", show = "microphone",
  episode = "microphone", liked = "heart" }

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

local function spotifyInstalled(ctx) return media.spotifyApp(ctx.S.apps) ~= nil end

-- The Favourites tab shows with Spotify installed or any favourite set.
function M.hasFavourites(ctx)
  return spotifyInstalled(ctx) or #ctx.S.favourites > 0
end

-- The favourite being renamed (its uri) and the name typed so far.
local editing, draft = nil, ""

-- True while a favourite's name is being edited: the panel then leaves the arrow keys
-- to the text field instead of seeking.
function M.renaming() return editing ~= nil end

-- A closed panel drops an unfinished rename.
function M.cancelRename() editing = nil end

local function stopEditing(ctx, save)
  if save and editing then control.renameFavourite(editing, draft) end
  editing = nil
  ctx.render()
end

local function editRow(ctx, f)
  return ui.row({ key = "fav-edit-" .. f.uri, gap = 6, align = "center", paddingV = 2, paddingH = 6 }, {
    ui.input({ key = "fav-input-" .. f.uri, value = f.name, focus = true, flexGrow = 1, controlSize = "sm",
      placeholder = "Name (empty restores it)", submitOnEnter = true,
      onChange = function(text) draft = text end,
      onSubmit = function(text) draft = text; stopEditing(ctx, true) end }),
    ui.button({ glyph = "check", variant = "ghost", controlSize = "sm", tooltip = "Save name",
      onClick = function() stopEditing(ctx, true) end }),
    ui.button({ glyph = "arrow-back-up", variant = "ghost", controlSize = "sm", tooltip = "Cancel",
      onClick = function() stopEditing(ctx, false) end }),
  })
end

local function favouriteRows(ctx)
  local rows = {}
  for i, f in ipairs(ctx.S.favourites) do
    if f.uri == editing then
      rows[#rows + 1] = editRow(ctx, f)
    else
      local kind = f.uri == "spotify:collection:tracks" and "liked" or favourites.kind(f.uri)
      rows[#rows + 1] = ui.row({ key = "fav-" .. f.uri, gap = 10, align = "center", paddingV = 4, paddingH = 6, radius = 8,
        tooltip = favourites.playable(f.uri) and f.uri or "Opens in Spotify; Spotify cannot be told to play it", onClick = function() control.open(nil, f.uri) end }, {
        ui.glyph({ name = KIND_GLYPH[kind] or "music", size = 16, color = "primary" }),
        ui.label({ text = f.name, fontSize = 13, flexGrow = 1, maxLines = 1 }),
        ui.button({ key = "fav-ren-" .. i, glyph = "pencil", variant = "ghost", controlSize = "sm", tooltip = "Rename",
          onClick = function()
            editing, draft = f.uri, f.name
            ctx.render()
          end }),
        ui.button({ key = "fav-rm-" .. i, glyph = "x", variant = "ghost", controlSize = "sm", visible = f.saved == true,
          tooltip = "Remove from favourites", onClick = function() control.removeFavourite(f.uri) end }),
        ui.glyph({ name = favourites.playable(f.uri) and "player-play" or "external-link", size = 14, color = "on_surface_variant" }),
      })
    end
  end
  return rows
end

-- Copy a link in Spotify (Share > Copy link), then this saves it.
local function pasteButton()
  return ui.button({ key = "fav-paste", glyph = "clipboard-plus", text = "Paste link", variant = "ghost", controlSize = "sm",
    tooltip = "In Spotify, Share > Copy link on a playlist, album, artist or track, then click here",
    onClick = function() control.addFavourite(noctalia.clipboardText() or "") end })
end

-- The Favourites pane: a row per favourite (click plays it in Spotify) and Paste link.
function M.favouritesPane(ctx)
  local rows = favouriteRows(ctx)
  if #rows == 0 then
    rows = { ui.label({ text = "Copy a Spotify link (Share > Copy link) and click Paste link, or add links in "
      .. "Encore's settings.", fontSize = 12, color = "on_surface_variant" }) }
  end
  return ui.column({ flexGrow = 1, gap = 6, padding = 10, radius = 12, fill = "surface_container" }, {
    ui.row({ justify = "end" }, { pasteButton() }),
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
  local favs = favouriteRows(ctx)
  if #favs > 0 then
    rows[#rows + 1] = ui.label({ text = "Favourites", fontSize = 12, fontWeight = "bold", color = "on_surface_variant" })
    rows[#rows + 1] = ui.scroll({ flexGrow = 1, gap = 2 }, favs)
  end
  return ui.column({ flexGrow = 1, gap = 10 }, rows)
end

return M
