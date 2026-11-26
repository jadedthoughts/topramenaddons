# Top Ramen addons for WoW Forever

Addons by Top Ramen for World of Warcraft: Forever, plus a small Windows launcher that installs them and keeps them up to date.

Built by **Crayon Ponyfish**.

| Addon | Command | What it does |
|---|---|---|
| Top Ramen Gear | `/trg` | Gear window for your class, by spec: best gear in your bags, a hunt list for upcoming dungeon drops, and upgrade comparisons with other addon users |
| Top Ramen Crafting | `/trc` | Crafting planner: what to craft to level up, what makes money, what to buy |
| Top Ramen Explorer | `/tre` | Finds the spots you still need for the Adventure > Explorer achievements |
| Top Ramen Farm | `/trfarm` | Farming tracker: loot tally, vendor value vs. auction house, sortable columns, and a Vendor items button that sells the items you tick |
| Top Ramen ThunderCats | `/trtc` | Plays a ThunderCats clip when you cast Shifting Power: shuffle the clips you tick or always play one, with previews, a volume slider and a "Sometimes stay quiet" setting so it isn't overdone. Clips are not included; put your own in `Interface\AddOns\TopRamenThunderCats_Sounds` |
| Top Ramen Map *(test)* | `/trmap` | Big live minimap and whole-dungeon overview. Needs the Forever Dungeon Journal addon for its map images |

**Opening them:** every Top Ramen addon shares one bowl button on the minimap. Click it for a menu of the addons you have, right-click to reopen the last one, and drag it to move it. Each row has a **Macro** button that makes a macro for your action bar. You can also type `/tr` for the menu, `/tr button` to hide or show the minimap button, or set a hotkey under Esc → Key Bindings → AddOns.

**AH upgrades (Top Ramen Gear):** the AH tab of `/trg` scans the whole auction house (the game allows it every 15 minutes) and lists the 5 biggest upgrades for each slot for your spec, with a star on the biggest upgrade and a coin on the best value per gold. Find puts an item in the auction house search so you can buy it there. Top Ramen Crafting and Gear share their scans.

**Party loot (Top Ramen Gear):** when a loot roll starts in a group, a small window shows how big an upgrade the item is for everyone who has Top Ramen Gear, for the spec they've picked in their Gear window, with a star on the biggest upgrade. Party members without the addon show as "Needs TR Gear Addon". Drag the window anywhere and it remembers; `/trg rolltest` shows it with an item from your bags.

**Test addons** are still being worked on. They only appear in the launcher when you tick **Show test addons** at the bottom of its window.

## Install with the launcher (easiest)

1. Download **[TopRamenLauncher.zip](https://github.com/jadedthoughts/topramenaddons/raw/main/releases/TopRamenLauncher.zip)**, open it, and drag **TopRamenLauncher.exe** to your Desktop (or any folder).
2. Double-click it. Windows may say "Windows protected your PC" because the file isn't signed: click **More info → Run anyway**.
3. The launcher finds your `World of Warcraft\_forever_\Interface\AddOns` folder by itself. If it can't, click **Change…** and pick it.
4. Click **Install** or **Update** next to each addon, or **Update all**. Then `/reload` in game (restart the game for an addon that's new to you).

Open the launcher whenever you want to check for updates. When a new launcher is out, click **Update launcher** in its window (version 1.4.0 and later) and it replaces itself and reopens. It doesn't run in the background, and it closes when you close its window.

## On a Mac

1. Download **[TopRamenLauncher-mac.zip](https://github.com/jadedthoughts/topramenaddons/raw/main/releases/TopRamenLauncher-mac.zip)** and open it.
2. Drag **Top Ramen Launcher** into your **Applications** folder. (It needs to live there to update itself.)
3. Open it. The first time, macOS says it can't check the app: click **Done**, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Top Ramen Launcher, and confirm. You only do this once.
4. It finds `World of Warcraft/_forever_/Interface/AddOns` in Applications by itself, or click **Change…** to pick it.

The window opens in Chrome, Edge or Brave as its own app window if one is installed, or in Safari otherwise.

## Install by hand

Download an addon's zip from [`releases/`](releases/) and unzip it into `World of Warcraft\_forever_\Interface\AddOns\`.

## For the maintainer: publishing an update

1. Copy the changed addon folder into `addons/` and raise `## Version:` in its `.toc`.
2. Run `python3 tools/build_release.py`. This builds `releases/<Addon>-<version>.zip` and updates `manifest.json`, which is what the launcher reads.
3. Commit and push. Launchers see the new version within a few minutes.

**Players' own files:** an addon can list folders of the player's own files in its `.toc`, for example `## X-TR-Keep: Sounds`. The launcher (1.13.0 and later) carries those folders over when it updates the addon. Top Ramen ThunderCats also reads clips from `Interface\AddOns\TopRamenThunderCats_Sounds`, a separate folder no update ever touches.

**Test or released?** `channels.json` lists the addons that are still in testing. Only people who tick "Show test addons" see those. To release one to everyone, remove its name from that list and run the build again. Addons listed under `hidden` stay in the repository but the launcher doesn't offer them at all.

To release a new launcher: raise `launcher/VERSION` and push. The **Sign launcher** GitHub workflow builds it on Windows, signs it with Azure Artifact Signing (so Windows Smart App Control allows it), and commits the signed `.exe`, `.zip` and `manifest.json`. Older launchers then show a "new launcher available" notice. Don't commit an unsigned build from `tools/build_launcher.sh` over the signed one: that script is only for local testing.

## What the launcher touches

Only the Top Ramen addon folders inside your AddOns folder. It downloads each zip from this repository, checks its SHA-256 checksum, unpacks it beside the old copy and swaps it in, so a failed update leaves your addon as it was. Your settings live in `WTF\...\SavedVariables` and are never touched. Its own settings and log are in `%LOCALAPPDATA%\TopRamenLauncher`.
