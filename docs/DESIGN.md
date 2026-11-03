# Design

Encore is a noctalia media plugin: a bar widget, a panel and a launcher provider for
every MPRIS player, with synced lyrics and a spectrum meter.

Target: noctalia 5.4, `plugin_api = 43`, for the `surface_container` / `outline_variant`
colour roles.

## Why another media plugin

The community catalog already has several. Encore differs in where its data comes from
and what it costs:

- **No polling.** Others spawn `busctl` or `playerctl` several times a second. Encore runs
  one `busctl monitor` stream of the players' own signals and reads the player list
  only when one arrives, plus a resync every 10 s. Position is published as a sample and
  extrapolated by each surface, so a playing track wakes nothing.
- **Noctalia's own player model.** Player data comes from noctalia's `dev.noctalia.Mpris`
  service, not from the players directly. Encore shows the player noctalia considers
  active, and picking a player in the panel makes it noctalia's active player, so media
  keys, the OSD and the lockscreen follow.
- **Every player at once.** The panel lists all players and controls each one.

## Layout

```
encore/                     repo root, added to noctalia as a `path` plugin source
  docs/DESIGN.md
  tests/pure.lua             tests for the pure modules, run with plain `lua`
  encore/                   the plugin (dir name = id suffix, community layout)
    plugin.toml
    service.luau            the only entry that reads player data or fetches lyrics; wiring only
    service-players.luau    busctl monitor stream, GetPlayers / GetActivePlayer, publishing
    service-art.luau        art URL -> local file (ui.image reads local files only)
    service-lyrics.luau     LRCLIB lookup chain and cache
    service-apps.luau       music apps from desktop entries
    service-launch.luau     opening apps and favourites, play-once-ready, hidden windows
    service-events.luau     reactions to player changes: pause others
    service-sleep.luau      sleep timer
    service-favourites.luau favourites: Liked Songs, the setting, pasted links and renames (<data>/favourites.json), names via oEmbed
    service-util.luau       data dir, publish-on-change, cache-name hash
    lyrics-lookup.luau      one lookup across all sources at once, best result wins
    lyrics-http.luau        JSON GETs for the lyrics sources
    lyrics-lrclib.luau      LRCLIB lookups (exact match, search)
    lyrics-netease.luau     NetEase Cloud Music lookup, a backup source
    lyrics-kugou.luau       Kugou lookup, a backup source (base64 LRC)
    base64.luau             base64 decoder (pure, plain Lua 5)
    yrc.luau                NetEase word-timed lyrics parser (pure, plain Lua 5)
    lyric-wrap.luau         breaks karaoke lines into rows that fit (pure, plain Lua 5)
    overlay-place.luau      overlay position setting -> anchors and alignment (pure, plain Lua 5)
    service-overlay.luau    lyrics overlay on/off (kept in <data>/overlay.json) and when it shows
    overlay.luau            the lyrics overlay layer
    lrc.luau                LRC parser, credit-line filter and line lookup (pure, plain Lua 5)
    lyrics-query.luau       exact and cleaned lyrics queries (pure, plain Lua 5)
    desktop-entry.luau      desktop entry parser, Exec without field codes (pure, plain Lua 5)
    favourites.luau         favourites setting and Spotify links -> spotify: URIs (pure, plain Lua 5)
    hyprland.luau           exec on the hidden workspace, toggle it, list its windows
    media.luau              shown player, extrapolated position, formatting; shared by all
    control.luau            busctl calls to dev.noctalia.Mpris; any surface calls these
    widget.luau             bar widget
    panel.luau              panel shell: state, keys, frame tick
    panel-player.luau       player chips, track, seek, transport, volume
    panel-lyrics.luau       lyrics pane
    panel-apps.luau         Open buttons, hidden toggle, favourites pane, launch view
    launcher.luau           "mu" launcher provider
    translations/en.json
```

## Ownership

| Data | How | When |
| --- | --- | --- |
| Players | `busctl call dev.noctalia.Mpris GetPlayers`, then `GetActivePlayer` | on any signal from the monitor stream, on `poke`, and every 10 s |
| Change signals | `busctl monitor` matching `PropertiesChanged` / `Seeked` on `/org/mpris/MediaPlayer2`, signals from `dev.noctalia.Mpris`, and `NameOwnerChanged` for `org.mpris.MediaPlayer2.*` | streamed |
| Art | `file://` passed through; `http(s)` downloaded to `<data>/art`, newest 60 kept | when a new art URL appears |
| Apps | one `grep` for `Categories=...Music` over every XDG `applications` dir, then those entries are read | at start and every 10 min |
| Hidden windows | `hyprctl clients -j`, windows on `special:encore` | on players change and every 10 s, Hyprland only |
| Lyrics | LRCLIB (`/api/get`, then `/api/search`), NetEase (search + `/api/song/lyric/v1`) and Kugou (search + download), all at once, each first with the player's fields and then with a cleaned title (video noise, version tails such as "- 2006 Remaster", bracketed alternative titles) | once per track; the first usable result shows at once and better ones replace it; the best is cached in `<data>/lyrics`; misses retried after 7 days, failures every 30 s up to 3 times |

Controls go straight from the surface to `dev.noctalia.Mpris` (`control.luau`), which
then sets `poke` so the service reads the result without waiting for a signal.

`runStream` has no close callback, so the monitor command ends with
`echo encore-monitor-exited`; the service sees that line and restarts the stream, at
most every 30 s. Noctalia kills the stream on hot reload.

Bursts of signals coalesce: a read requested during a read schedules exactly one more.

## State contract

All times are epoch milliseconds (`noctalia.nowMs()`).

```
players = [{ bus, identity, desktop, title, artists, album, art, artUrl, url,
             lengthMs, positionMs, sampledAt,   -- position = positionMs + (now - sampledAt) while Playing
             status = "Playing" | "Paused" | "Stopped",
             canControl, canPlay, canPause, canNext, canPrevious, canSeek,
             shuffle, loop = "None" | "Track" | "Playlist", volume,   -- volume nil when unknown
             canQuit }]             -- read once per bus from the player (noctalia's list lacks it)
active  = bus name of noctalia's active player, "" when none
lyrics  = { key, status = "off" | "idle" | "loading" | "synced" | "plain" | "instrumental" | "none" | "error",
            lines = [{ t, text, words? = [{ t, text, space }] }],   -- synced; words when word-timed
            plain,                   -- plain
            source,                  -- "LRCLIB" | "NetEase" | "Kugou"
            loose }                  -- true: the version's length is >15 s off the player's
overlay = { enabled }
apps    = [{ id, name, command, icon, wmClass }]   -- id, wmClass lowercased; command without field codes
hidden  = [class]                    -- lowercased classes of windows on special:encore
poke    = nowMs                      -- surface -> service: read players now
command = { action = "open", app?, uri?, at }       -- surface -> service: open an app / play a favourite
        | { action = "sleep", minutes, at }          -- set the sleep timer, 0 cancels
        | { action = "fav-add", link, at } | { action = "fav-remove", uri, at }
        | { action = "fav-rename", uri, name, at }   -- any favourite; "" restores its own name
favourites = [{ name, uri, saved }]  -- saved: pasted in the panel or launcher, removable there
sleep   = { endsAt }                 -- 0 when off; read back on service start, so a reload keeps it
```

The shown player (`media.current`) is `active`, else the first playing, else the first.

## Opening apps

`command` (or the service IPC `open <id|link>`) names an app or a Spotify URI. The
service starts the app when no player of it runs: through `hyprctl dispatch`, with the
Lua form `hl.dsp.exec_cmd(cmd, { workspace = "special:encore silent" })` first (Hyprland
0.56+ with a Lua config accepts nothing else) and the classic `exec [rules] cmd` second;
without Hyprland, `sh -c`. Hyprland applies the rule to the launched process tree, so
`spotify-launcher`'s child lands there too. It then waits up to 90 s for the app's player
(`media.isApp`: desktop id, window class or name; Spotify's player reports desktop
`spotify`, its launcher entry is `spotify-launcher`), makes it noctalia's active player,
and sends `OpenUri` for a favourite or `Play`, again every 3 s, up to five times, until
the player reports Playing. Spotify ignores requests while it starts.

## Decisions

- **Drift check.** A resync whose position is within 1 s of the extrapolated one keeps the
  old sample, so `players` is not republished every 10 s while a track plays.
- **Long tracks** (over 20 min) are not looked up: they are streams, podcasts or long
  videos, and sending their titles to LRCLIB is pointless. LRCLIB also answers 400 for
  them; a 400 counts as a miss, not an error.
- **Player events** compare each `players` list with the previous one. The first list
  only seeds it, so a reload is silent. A player that starts, or appears already
  playing, pauses the other playing ones (`pause_others`); when several start at once,
  noctalia's active player wins. Off by default, since it acts on players the user did
  not touch. There is no track-change popup: noctalia's media OSD already announces
  every track.
- **Sleep timer** lives in the service so it runs with the panel closed; when it ends it
  pauses every playing player. Presets 15/30/45/60/90 min; a click moves to the next
  preset above what is left.
- **Quit** calls `org.mpris.MediaPlayer2.Quit` on the player itself and is offered only
  where `CanQuit` is true, so browsers never get it.
- **Bar lyrics** tick the widget every 250 ms only while synced lyrics play, and render
  only when the line changes; otherwise the widget ticks once a minute.
- **Parallel lookup**: the sources are lanes that run side by side (`lyrics-lookup.luau`);
  each lane tries the exact query, then the cleaned one, and stops at a hit of the right
  length. Results rank: right-length word timing (ends the whole lookup), right-length
  lines, other-length word timing, other-length lines, plain. Sequential lookups made
  the overlay late and left the backups unused whenever LRCLIB was slow or answering 503.
- **Lengths**: every source returns its closest version and flags it `loose` when it is
  more than 15 s off. Players sometimes report a stale length at a track
  change (Spotify gave 169 s for a 211 s track), and a strict-only match then found
  nothing. Loose results are cached but looked up again on the next play.
- **No Musixmatch**: its API needs a token only its own apps get; Encore uses sources
  with public endpoints.
- **Lyrics sources**: a failing source (LRCLIB answers 503 at times) only ends its own
  lane. When nothing is found and a source failed, the lookup is retried every
  30 s, three times, before the miss is cached. Cache entries carry a version and the
  source set, so plain lyrics and misses are looked up again when the backups are switched on.
  NetEase lyrics start with credit lines ("作词 : Name"); `lrc.stripCredits` drops them.
- **Lyrics overlay** is an `overlay`-layer surface (above fullscreen windows), click-through
  and without keyboard, 1100x140 near the bottom edge. Minimal by design: the current
  line alone on a slim translucent pill with the cover. It fades in (180 ms) only when it
  appears; a new line replaces the text in place, and an empty line shorter than 6 s
  (a breath between lines) keeps the last line up, so it never flashes. Nothing before
  the first line or in longer instrumental gaps. Seven spots (corners, edge centres,
  centre): the layer is anchored to the edges the spot touches with the offset as their
  margins, unanchored axes are centred by the compositor, and the pill is aligned to
  the same side inside the layer. With word timing each word is its own
  label, lit in the accent colour once sung (a spacer stands in for spaces, since
  yrc words can be syllables). Lyrics without word timing light the whole line in
  "words" mode. Long lines wrap instead of being cut: a plain label to
  three lines, a karaoke line into rows broken at spaces from an estimated glyph width
  (`lyric-wrap.luau`). The layer is tall enough for three lines; the unused part is
  transparent and click-through. Size, background, cover, next line and highlighting are
  read on every render; position, offset and height go to the layer through
  `noctalia.layer.configure` (layers get no onConfigChanged).
- **Word timing** comes from NetEase's `yrc` (and enhanced LRC `<mm:ss.xx>` tags from any
  source). NetEase tries up to three releases of the song, closest length first, since
  the closest one may have no lyrics or no word timing. Kugou's word format (KRC) is
  encrypted and compressed, so Kugou gives lines only.
- **Overlay visibility**: the service shows the layer while the overlay is on, the shown
  player plays and its synced lyrics are loaded or loading, and hides it otherwise, so
  pausing or a track without synced lyrics removes it.
- **Lyrics offset** is applied by the panel, not the service, so changing it needs no
  new lookup. Positive values show lines earlier.
- **Spectrum** reaches the bar widget only (`onAudioSpectrum`); it is not mirrored into the
  panel, since that would wake every entry at 30 Hz. The widget renders it at most every
  33 ms and only while the shown player plays.
- **Panel ticks**: the frame tick re-renders only when the shown second or the current
  lyric line changes, and not while a slider is dragged.
