# CamTool

Cinematic replay cameras for Assetto Corsa. Place cameras around a lap, give
them keyframes, let them track a car, animate FOV and depth of field — the
tool people use to cut replay footage into something worth watching.

Originally written by **kasperski95**, who gave permission to put it on GitHub
so the work could continue. Maintained since by **tmeedend**.

## Two apps in this download

They are separate apps and they install side by side. Neither touches the
other's files, so you can switch between them in the same session.

| | CamTool 2 | CamTool 3 |
|---|---|---|
| State | Stable, what most people use | **Beta** — being rebuilt |
| Needs | Assetto Corsa | Assetto Corsa **and Custom Shaders Patch** |
| Written in | Python, the app list's `CamTool_2` | Lua, in CSP's app list as `CamTool 3` |
| Camera files | `apps/python/CamTool_2/data/` | `apps/lua/CamTool3/data/` |

**CamTool 3 reads CamTool 2's camera files and never writes to them.** Saving a
set you opened from CamTool 2 makes a copy in CamTool 3's own folder; the
original is left exactly as it was. That is on purpose, and it is why trying
CamTool 3 costs you nothing.

If you have no Custom Shaders Patch, or if CamTool 3 is missing something you
need, use CamTool 2. It is still here and still maintained.

## Installing

Unzip into your Assetto Corsa folder — the one with `AssettoCorsa.exe` in it.
The archive already has the right shape, so everything lands where the game
expects:

```
…/steamapps/common/assettocorsa/
  apps/python/CamTool_2/…
  apps/lua/CamTool3/…
  content/gui/icons/…
```

Then, in game:

- **CamTool 2** — enable it in Settings → General → UI Modules, then open it
  from the app bar on the right of the screen.
- **CamTool 3** — it appears in the Custom Shaders Patch app list. You need
  CSP installed for it to show up at all.

Both are for **replays**. Start a replay first; there is nothing for them to
do in a live session.

## What is new in CamTool 3

It is a rewrite, not a new coat of paint. The parts worth knowing about:

- **One panel, no tabs.** Every parameter of a camera on screen at once.
- **A ribbon of the whole lap**, with a ruler carrying distances and the
  track's own corner names. Drag the ruler to move the replay.
- **A map of the circuit** showing which camera covers which stretch.
- **No global keyboard hook.** CamTool 2 installed one, and it cost latency on
  every key in the game, for everyone — including people not using the app.

It is a beta: it does not yet do everything CamTool 2 does. Report what is
missing.

## Licence

GPL v3 — see [LICENSE](LICENSE). Same licence as the original.

## Working on it

```
git clone https://github.com/tmeedend/camtool
```

The repository is laid out **as the game folder is**, so it can be cloned or
extracted straight over an Assetto Corsa install.

Tests run outside the game, and are expected to be green before anything is
proposed:

```
cd apps/lua/CamTool3 && luajit tests/run.lua          # CamTool 3
cd apps/python/CamTool_2 && vermin --no-tips -t=3.3- --violations classes files ui CamTool_2.py
```

`docs/` is where the reasoning lives: `etat.md` for where the work has got to,
`legacy.md` for what was learned about CamTool 2, `ui-interactions.md` for the
rules the interface obeys.

For CamTool 2's performance work and its F1 camera option, see the
[release thread](https://www.racedepartment.com/downloads/camtool-2-extension-perf-fix-and-more-features.41614/).
