# Encore

A [noctalia](https://github.com/noctalia-dev) plugin for every media player: a bar widget
with a spectrum meter, a panel to switch players, seek and read synced lyrics, and a
launcher provider. The plugin's own [README](encore/README.md) covers its features,
settings and what it sends over the network.

## Install

Until Encore is in the community catalog, install it from this repository as a `path`
source:

```sh
git clone https://github.com/Edward-Pratt/encore ~/src/encore
noctalia msg plugins source add encore path ~/src/encore
noctalia msg plugins enable edward/encore
```

Then add the `Encore` widget to your bar.

## Layout

```
encore/      the plugin, in the community-plugins layout (dir name = id suffix)
docs/        DESIGN.md: data ownership, state contract, decisions
tests/       pure.lua, tests for the pure modules
```

## Development

With the repo added as a `path` source, edits to `.luau` files hot-reload. Changes to
`plugin.toml` need the plugin disabled and enabled again.

For editor type checking, put `noctalia.d.luau` from
[noctalia-dev/official-plugins](https://github.com/noctalia-dev/official-plugins) at the
repo root. It is gitignored.

```sh
lua tests/pure.lua              # LRC parser and lyrics queries
noctalia plugins lint encore   # settings against code
```

### Publishing an update

`main` is the development branch. A stable version is a `vX.Y.Z` tag: tag it with
[herald](https://github.com/Edward-Pratt/herald)'s `herald release patch` (or `minor`,
`major`). It sets `version` in `encore/plugin.toml` through `.github/bump-version` and
opens a pull request; once that's merged, the same command tags it, and
`.github/workflows/release.yml` publishes the GitHub release.
