-- Tests for the pure modules: `lua tests/pure.lua` from the repo root.
local function load(name) return dofile("encore/" .. name .. ".luau") end
local lrc = load("lrc")
local query = load("lyrics-query")
local desktop = load("desktop-entry")
local fav = load("favourites")
local b64 = load("base64")
local yrc = load("yrc")
local wrap = load("lyric-wrap")
local place = load("overlay-place")

local failures = 0
local function eq(got, want, what)
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(what, tostring(got), tostring(want)))
  end
end

local lines = lrc.parse("[ar:Someone]\n[00:12.50]First\r\n[00:05.00][01:00.1] Chorus \n[00:20]Bare\nno stamp\n[00:30.123]Ms\n[00:40.00]")
eq(#lines, 6, "line count")
eq(lines[1].t, 5000, "first is earliest")
eq(lines[1].text, "Chorus", "text trimmed")
eq(lines[2].t, 12500, "centiseconds")
eq(lines[3].t, 20000, "no fraction")
eq(lines[4].t, 30123, "milliseconds")
eq(lines[5].t, 40000, "empty line kept")
eq(lines[5].text, "", "empty text")
eq(lines[6].t, 60100, "tenths, second stamp")

eq(lrc.lineAt(lines, 0), 0, "before first")
eq(lrc.lineAt(lines, 5000), 1, "on first stamp")
eq(lrc.lineAt(lines, 19999), 2, "between")
eq(lrc.lineAt(lines, 99999), 6, "after last")
eq(lrc.lineAt({}, 100), 0, "no lines")

local credited = lrc.stripCredits(lrc.parse("[00:00.00] 作词 : Stuart Adamson\n[00:01.00]编曲：Someone\n"
  .. "[00:33.96]Between the father and his son\n[00:40.00]Time: 4 o'clock\n"))
eq(#credited, 2, "credits dropped")
eq(credited[1].text, "Between the father and his son", "lyric kept")
eq(credited[2].text, "Time: 4 o'clock", "ASCII label kept")

local e = query.exact({ artists = " Daft Punk ", title = "One More Time", album = "Discovery", lengthMs = 320400 })
eq(e.artist, "Daft Punk", "exact artist")
eq(e.durationS, 320, "duration rounded")
eq(query.cleaned({ artists = "Daft Punk", title = "One More Time", lengthMs = 1 }), nil, "clean already")

local c = query.cleaned({ artists = "DaftPunkVEVO", title = "Daft Punk - One More Time (Official Video)" })
eq(c.artist, "Daft Punk", "artist from title")
eq(c.title, "One More Time", "noise stripped")

c = query.cleaned({ artists = "Daft Punk - Topic", title = "One More Time" })
eq(c.artist, "Daft Punk", "topic channel")
eq(c.title, "One More Time", "title kept")

c = query.cleaned({ artists = "Band", title = "Song (Live at Wembley) [HD]" })
eq(c.title, "Song", "all brackets dropped in the fallback")

c = query.cleaned({ artists = "Big Country", title = "Fields Of Fire - 2006 Remaster" })
eq(c.artist, "Big Country", "version tail: artist kept")
eq(c.title, "Fields Of Fire", "version tail dropped")
c = query.cleaned({ artists = "The Undertones", title = "You've Got My Number (Why Don't You Use It!)" })
eq(c.title, "You've Got My Number", "alternative title dropped")
c = query.cleaned({ artists = "Big Country", title = "Big Country - Fields Of Fire" })
eq(c.title, "Fields Of Fire", "artist named in the title")
eq(query.cleaned({ artists = "Sips - Live!", title = "Bank Heist - Obenseuer" }), nil, "no split for a non-channel artist")

eq(query.cleaned({ artists = "X", title = "(Official Video)" }), nil, "nothing left")

local entry = desktop.parse("[Desktop Entry]\nName=Spotify\nExec=spotify-launcher %U\nIcon=spotify-client\n"
  .. "StartupWMClass=spotify\nCategories=Audio;Music;Player;AudioVideo;\n[Desktop Action new]\nName=Other\nExec=other\n")
eq(entry.name, "Spotify", "entry name, not the action's")
eq(entry.exec, "spotify-launcher %U", "entry exec")
eq(entry.categories.Music, true, "categories")
eq(entry.wmClass, "spotify", "wm class")
eq(entry.hidden, nil, "not hidden")
eq(desktop.parse("[Desktop Entry]\nName=X\n"), nil, "no exec")
eq(desktop.parse("[Desktop Entry]\nExec=x\nNoDisplay=true\n").hidden, true, "hidden")
eq(desktop.command("spotify-launcher %U"), "spotify-launcher", "field code dropped")
eq(desktop.command("app --x %f --y 100%%"), "app --x --y 100%", "literal percent kept")

eq(fav.uri("spotify:playlist:37i9dQ"), "spotify:playlist:37i9dQ", "uri as is")
eq(fav.uri("https://open.spotify.com/intl-de/album/4m2880?si=abc"), "spotify:album:4m2880", "locale link")
eq(fav.uri("https://example.com/playlist/x"), nil, "not spotify")
local favs = fav.parse({ "Chill = https://open.spotify.com/playlist/AAA?si=x", "spotify:album:BBBBBBBB",
  "https://open.spotify.com/playlist/CCC?si=1", "junk", "Name=spotify:track:DDD" })
eq(#favs, 4, "junk skipped")
eq(favs[1].name, "Chill", "named")
eq(favs[1].uri, "spotify:playlist:AAA", "named uri")
eq(favs[2].name, "Album BBBBBB", "default name")
eq(favs[3].uri, "spotify:playlist:CCC", "unnamed link with ?si=")
eq(favs[4].name, "Name", "no spaces around =")
eq(fav.kind("spotify:album:X1"), "album", "kind")
eq(fav.webUrl("spotify:playlist:37i9dQ"), "https://open.spotify.com/playlist/37i9dQ", "web url")
eq(fav.webUrl("spotify:collection:tracks"), nil, "no web page for Liked Songs")

local y = yrc.parse('{"t":0,"c":[{"tx":"作词: "},{"tx":"Someone"}]}\n'
  .. "[37330,3900](37330,570,0)Between (37900,120,0)the (38020,540,0)ci(38300,200,0)ty\n"
  .. "[28000,9300](28000,1550,0)(Oh) (29550,1550,0)father\n[50000,100]\n")
eq(#y, 2, "yrc: json and empty lines skipped")
eq(y[1].t, 28000, "yrc sorted")
eq(y[1].words[1].text, "(Oh)", "yrc word with parentheses")
eq(y[2].text, "Between the city", "yrc line text keeps syllables together")
eq(y[2].words[3].text, "ci", "yrc syllable")
eq(y[2].words[3].space, false, "no space inside a word")
eq(y[2].words[2].space, true, "space after a word")
eq(y[2].words[4].t, 38300, "yrc word time")

local enh = lrc.parse("[00:12.00]<00:12.00>Some <00:12.40>words<00:13.00>\n[00:20.00]Plain line\n")
eq(enh[1].text, "Some words", "enhanced LRC text without stamps")
eq(#enh[1].words, 2, "enhanced LRC words")
eq(enh[1].words[2].t, 12400, "enhanced LRC word time")
eq(enh[2].words, nil, "plain line has no words")

local function w(text, space) return { text = text, space = space } end
-- 100 px at size 10 with 0.56 per char: 17 characters a row.
local rows = wrap.rows({ w("aaaa", true), w("bbbb", true), w("cccc", true), w("dd", false), w("ee", true), w("ffff", false) }, 10, 100)
eq(#rows, 2, "wrap: two rows")
eq(#rows[1], 3, "wrap: first row holds three words")
eq(rows[2][1], 4, "wrap: break before the syllable pair")
eq(rows[2][2], 5, "wrap: syllables stay together")
eq(#wrap.rows({ w("short", true), w("line", false) }, 16, 900), 1, "wrap: short line one row")
eq(#wrap.rows({ w("éééééééééé", true), w("ééééééééé", false) }, 10, 100), 2, "wrap: counts characters, not bytes")
eq(#wrap.rows({}, 16, 900), 0, "wrap: no words")

local spot = place.of("top-left")
eq(spot.v .. "/" .. spot.h, "top/left", "place: corner")
spot = place.of("bottom")
eq(spot.v .. "/" .. spot.h, "bottom/center", "place: edge centre")
spot = place.of("center")
eq(spot.v .. "/" .. spot.h, "center/center", "place: centre")
spot = place.of(nil)
eq(spot.v .. "/" .. spot.h, "bottom/center", "place: default")
spot = place.of("sideways")
eq(spot.v .. "/" .. spot.h, "bottom/center", "place: unknown value")
eq(place.flex("left"), "start", "place: flex start")
eq(place.flex("bottom"), "end", "place: flex end")
eq(place.flex("center"), "center", "place: flex centre")

eq(b64.decode("TWFu"), "Man", "base64 full block")
eq(b64.decode("TWE="), "Ma", "base64 one pad")
eq(b64.decode("TQ=="), "M", "base64 two pads")
eq(b64.decode("W3RpOkZp\nZWxkc10="), "[ti:Fields]", "base64 with newline")
eq(b64.decode("5L2c6K+N"), "作词", "base64 utf-8")
eq(b64.decode("@@@@"), nil, "base64 bad input")

if failures > 0 then
  print(failures .. " failed")
  os.exit(1)
end
print("ok")
