# Top Ramen addons for WoW Forever

Addons by Top Ramen for World of Warcraft: Forever, plus a small Windows launcher that installs them and keeps them up to date.

| Addon | Command | What it does |
|---|---|---|
| Top Ramen Gear | `/trg` | Druid gear window (Bear, Cat, Balance, Restoration) and upgrade scores on item tooltips |
| Top Ramen Crafting | `/trc` | Crafting planner: what to craft to level up, what makes money, what to buy |
| Top Ramen Explorer | `/tre` | Finds the spots you still need for the Adventure > Explorer achievements |
| Top Ramen Farm | `/trfarm` | Farming tracker: loot tally, vendor value vs. auction house |

## Install with the launcher (easiest)

1. Download **[TopRamenLauncher.exe](https://raw.githubusercontent.com/jadedthoughts/topramenaddons/main/releases/TopRamenLauncher.exe)**.
2. Double-click it. Windows may say "Windows protected your PC" because the file isn't signed: click **More info → Run anyway**.
3. The launcher finds your `World of Warcraft\_forever_\Interface\AddOns` folder by itself. If it can't, click **Change…** and pick it.
4. Click **Install** or **Update** next to each addon, or **Update all**. Then `/reload` in game (restart the game for an addon that's new to you).

Open the launcher whenever you want to check for updates. It doesn't run in the background, and it closes when you close its window.

## Install by hand

Download an addon's zip from [`releases/`](releases/) and unzip it into `World of Warcraft\_forever_\Interface\AddOns\`.

## For the maintainer: publishing an update

1. Copy the changed addon folder into `addons/` and raise `## Version:` in its `.toc`.
2. Run `python3 tools/build_release.py`. This builds `releases/<Addon>-<version>.zip` and updates `manifest.json`, which is what the launcher reads.
3. Commit and push. Launchers see the new version within a few minutes.

To rebuild the launcher: raise `launcher/VERSION`, run `sh tools/build_launcher.sh` (needs Go), then `python3 tools/build_release.py`, and push. Older launchers will show a "new launcher available" notice.

## What the launcher touches

Only the Top Ramen addon folders inside your AddOns folder. It downloads each zip from this repository, checks its SHA-256 checksum, unpacks it beside the old copy and swaps it in, so a failed update leaves your addon as it was. Your settings live in `WTF\...\SavedVariables` and are never touched. Its own settings and log are in `%LOCALAPPDATA%\TopRamenLauncher`.
