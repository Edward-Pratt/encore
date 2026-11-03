# Encore

Every media player on one bar widget and panel: switch players, seek, volume, synced
lyrics and a spectrum visualizer.

## Features

- **Bar widget**: the cover, title and artist of the shown player, and a live spectrum
  meter while it plays. Click opens the panel, middle click plays or pauses, right click
  switches to the next player, scroll changes its volume.
- **Panel**: a chip for every running player. Click one to make it noctalia's active
  player, so media keys, the OSD and the lockscreen follow it. Cover, seek bar,
  shuffle, previous, play/pause, next, repeat and volume. Space plays or pauses, Left
  and Right seek 10 seconds.
- **Synced lyrics** from [LRCLIB](https://lrclib.net), with NetEase Cloud Music and
  Kugou as backups: the current line is highlighted and kept in view; click a line to
  seek there. When no version has the player's length (another edit, or a player
  reporting a wrong length), the closest version is used and the panel says its timing
  may differ. Plain lyrics when no synced ones exist anywhere.
- **Lyrics overlay**: the current synced line on a slim pill with the cover, over
  everything (fullscreen games too), click-through. When the lyrics have word timing
  (NetEase has it for many tracks), each word lights up as it is sung. Toggle it from the panel, launcher or
  IPC; it shows only while a track with synced lyrics plays.
- **Open music apps, in the background**: every installed music app (such as Spotify)
  gets an Open button in the panel and launcher. On Hyprland it starts on a hidden
  workspace, so no window appears, and starts playing once it is ready. A button next to
  the players shows or hides it.
- **Favourites**: Spotify playlists, albums, artists or tracks from the settings, in their
  own panel tab and the launcher. One click starts Spotify if needed and plays it.
- **Quit**: a power button quits apps that allow it (Spotify does, browsers don't), handy
  for one running hidden in the background.
- **Sleep timer**: the zzz button next to the volume pauses everything after 15, 30, 45,
  60 or 90 minutes. Each click lengthens it, right click cancels.
- **Launcher**: type `mu` for play/pause, next, previous, switching player, quitting,
  opening apps, favourites, the sleep timer and the panel.
- **Light on resources**: no polling. Encore follows the players' D-Bus signals and
  reads noctalia's player list only when something changes.

Works with any MPRIS player: Spotify, browsers, mpv, VLC, MPD (through mpDris2) and
others.

## Requirements

- noctalia 5.4 or later
- `busctl` (systemd)
- For background apps: Hyprland (`hyprctl`). Elsewhere apps open normally.

## Settings

| Setting | Default | |
| --- | --- | --- |
| Fetch lyrics from lrclib.net | on | Off: no network requests at all |
| Backup lyrics sources | on | Asks NetEase (music.163.com) and Kugou (kugou.com) when LRCLIB has no synced lyrics |
| Lyrics timing (ms) | 0 | Positive shows lines earlier |
| Lyrics overlay monitor | focused | A connector such as `DP-1`, or `all` |
| Overlay text size | 16 | Pixels |
| Overlay position | bottom | Top, bottom or centre; left, centred or right |
| Overlay distance from edge | 70 | Pixels from the edges it sits against |
| Overlay background | 80 | Pill strength in %; 0 shows the text alone |
| Overlay highlighting | words | Words (karaoke, when timed), whole line, or none |
| Overlay cover | on | The album cover beside the lyric |
| Overlay next line | off | The upcoming line, dimmed, below |
| Open apps in the background | on | Hyprland: apps start on the hidden workspace `special:encore` |
| Play when opened | on | Press play once an opened app is ready |
| Favourites | none | Spotify share links or `spotify:` URIs, optionally `Name = link` |
| Pause other players | off | A player that starts pauses every other one |

Bar widget settings: album art, artist, title width (0 for cover only), lyrics on the
bar (the current synced line instead of the title), hide when nothing plays, spectrum
meter and its number of bars.

## Privacy

With lyrics on, Encore sends the playing track's artist, title, album and length to
`lrclib.net`, once per track. When LRCLIB has no synced lyrics and the backup sources are
on, the artist and title also go to NetEase Cloud Music (`music.163.com`) and Kugou
(`kugou.com`, with the length), both China-based. Tracks longer than 20 minutes are never sent. Results,
including "not found", are cached in the plugin's data directory. Album art served over
HTTP(S) is downloaded from the URL the player reports and cached there too.

## IPC

```sh
noctalia msg plugin edward/encore:widget focused click            # toggle the panel
noctalia msg plugin edward/encore:service all open spotify-launcher  # open an app by desktop id
noctalia msg plugin edward/encore:service all open spotify:playlist:ID   # play in Spotify (a share link works too)
noctalia msg plugin edward/encore:service all hidden                 # show or hide background apps
noctalia msg plugin edward/encore:service all sleep 30               # sleep timer in minutes, 0 cancels
noctalia msg plugin edward/encore:service all overlay                # lyrics overlay on or off
```

## License

MIT
