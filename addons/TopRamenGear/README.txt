Top Ramen Feral Druid Gear Companion
====================================

Exports your equipped and bag gear, with exact in-game stats, for
Top Ramen: Feral Druid Gear Advisor.

GEAR WINDOW (new in 1.5)
Type /trg to open it. Switch between Bear Tank and Cat DPS at the top.
Each row is a slot: what you're wearing, and the best thing in your bags for it.
   Gold + star  = the best choice
   Red          = what you're wearing should be swapped for the gold item
Rings and trinkets are judged as a pair; the weapon row compares a two-hander
with a one-hander plus off-hand. Items above your level aren't suggested.
Hover any item for its tooltip; shift-click to link it in chat.
Drag the title to move the window, and the corner grip to resize it; long lists
scroll with the mouse wheel. Size and position are remembered.
The Dungeons tab (or /trg dungeons): pick a dungeon to list every drop and quest
reward there that beats what you're wearing (any level), best first, with the boss or quest it
comes from. Loot lists come live from the DungeonJournal addon (needs it enabled).
Filters: "Usable within 5 levels" hides items you can't wear soon, and "Also show items
that aren't upgrades". Choose which start turned on (and how many levels) in Settings.

The Settings tab (or /trg settings) has every option as a checkbox, slider or button:
tooltip lines, Bear focus, caps, and the Export gear / Export dungeon loot buttons.

TOOLTIP UPGRADE LINES (new in 1.4)
Hover any item a Druid can use (bags, loot, vendors, the Auction House, chat links)
and the tooltip shows how much it gains or loses versus what you're wearing:
   TR Bear: +12.4  ·  3 targets +15.1
   TR Cat:  -3.2
Green = upgrade, red = downgrade. Works in DialogueUI's quest windows too: the lines
appear in its reward tooltips, and its green upgrade arrow follows the Top Ramen scores. Rings and trinkets are compared with the weaker of
your two. Scores use the same weights and rules as the website.

TALENTS (new in 1.8)
Your learned talents are read from the game, at the rank you have, and any that change
item stats are applied to the scores automatically. For Forever Druids that's Heart of
the Wild (Bear Stamina, Cat Strength, Intellect), Natural Instinct (crit is worth more)
and Living Spirit. Hit chance from talents lowers the hit you still need from gear.
Settings > Gear talents (/trg talents) lists the talents that change gear scores;
Settings > My talents (/trg talents all) lists every talent read, with your rank. Untick "Include talents in scores" in Settings to
see scores without talents.

BALANCE (new in 1.11)
A Balance button sits next to Bear Tank and Cat DPS on the Gear and Dungeons tabs, and
a "TR Balance" tooltip line can be turned on in Settings (Specs to show). Scoring follows
the Wowhead Forever Balance guide: spell hit up to the cap (17%, less Nature's Reach),
spell power, spell penetration, crit (doubled by Vengeance), haste, Intellect (with its
spell crit at your level), Spirit. Nature and Arcane damage count about half each.

LIVE STAT VALUES (new in 1.10)
Some stat values are worked out from your character instead of being fixed numbers,
so they keep up as you level, gear up and learn Dire Bear Form:
   Armor (Bear)  - from your armor, health and level (the game's armor formula) and
                   your bear form's bonus to item armor, read from the spell
   Agility       - attack power (Cat), armor, and crit and dodge at your level's ratio
/trg stats shows the level, form, armor and health the scores are using.

Options (type /trg help in game):
   /trg tip            tooltip lines on/off
   /trg bear, /trg cat show or hide that line
   /trg 3t             show or hide the Bear 3-target score
   /trg focus 40       Bear focus: -100 (all survival) to 100 (all threat)
   /trg hitcap 8       hit cap in percent
Settings are saved between sessions.

INSTALL
1. Quit WoW (or be at the character screen).
2. Copy the folder "TopRamenGear" into your Forever AddOns folder:
     World of Warcraft\_forever_\Interface\AddOns\
   (If you don't see a _forever_ folder, use the folder your SimulationCraft addon is in.)
3. Start the game. On the character screen, click AddOns and make sure
   "Top Ramen Feral Druid Gear Companion" is ticked. If it says "Out of date",
   tick "Load out of date AddOns".

USE
1. In game, type /trg export   (/topramengear, /topramen and /ramen also work)
2. A window opens with the text already selected. Press Ctrl+C.
3. Paste into the app (Ctrl+V). Results update right away.

That's all you need: the export includes your gear and your character stats
(health, Agility, Attack Power, crit, dodge, armor, weapon damage), so you don't
need /simc as well.

DUNGEON LOOT
Type /topramengear loot to export dungeon loot with exact in-game stats (Druid-usable
items only). On Forever the Adventure Guide is empty, so the addon reads the loot
lists of the DungeonJournal addon instead: install and enable it first. Paste the
export into "Loot data" on the app's Dungeons tab. The first run can take up to
20 seconds while the game loads item data from the server; if it says some items
weren't loaded, run /topramengear loot again.

The addon only reads item information. It never changes, moves or uses anything.
