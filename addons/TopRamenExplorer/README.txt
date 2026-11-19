Top Ramen Explorer
==================

Finds the places you still need for the Adventure > Explorer achievements in
WoW Forever and walks you to them.

How it works
------------
- It reads the Explorer achievements straight from the game, so the zone list
  and the "Still needed" area names are exactly what the game tracks.
- About 360 UNVERIFIED spots from Wowhead achievement comments ship in
  Unverified.lua (orange, marked "?"). Only comments posted before Cataclysm
  are used, since Forever uses the original classic maps; nothing from
  Cataclysm or later. When you discover an area, your own spot replaces the
  unverified one.
- Cataclysm.lua holds about 195 more spots from comments posted after
  Cataclysm. They are only used where nothing classic-era exists (mostly
  Elwynn, Westfall, Duskwood, Redridge, Arathi, Tirisfal, the Plaguelands,
  Hinterlands, Burning Steppes, Swamp of Sorrows, Moonglade, Silithus), show
  purple, and are labelled "Cataclysm". Cataclysm redrew parts of the old
  world, so treat them as rough.
- Export (button, or /tre export) shows your confirmed spots as text. Click
  Copy, press Ctrl+C, and send the text to another player.
- Import (button, or /tre import) opens an empty box with the cursor in it:
  press Ctrl+V, then Import (Import and Clear stay greyed out until there's
  text). Their spots count as confirmed; spots you found yourself are kept.
  (WoW doesn't let addons use the clipboard, so you press the keys.)
- Confirmed spots come first. Every time an area pops, the addon saves where
  you were standing (account-wide, so your alts get it). A few confirmed spots
  also ship in Data.lua. These show blue in the window and on the map.
- For everything else, it checks each zone map on a 48 x 48 grid for ground you
  haven't uncovered yet. Each undiscovered patch becomes a "spot". Walk to a
  spot and the area discovers.

Using it
--------
/tre               open or close the window
/tre guide         waypoint to the closest spot in the zone you're in. When you
                   uncover it, the next one is picked automatically.
/tre next          skip the current spot (ignore it) and go to the next one
/tre stop          stop guiding
/tre mark          drop a TomTom waypoint on every spot in this zone, like
                   typing /way for each (window: Mark zone)
/tre markall       the same for every zone you haven't finished
                   (window: Mark all zones)
/tre markwhole     a waypoint on EVERY area of this zone's achievement, found
                   or not; found ones say "(found)" (window: Mark whole zone)
/tre clear         remove those waypoints (window: Clear waypoints)
/tre save <area>   save where you're standing as the spot for an area, e.g.
                   /tre save Sun Rock Retreat (areas are also saved
                   automatically the moment "Discovered: ..." appears)
/tre refresh       re-read your Explorer achievements and rescan the maps
                   (same as the Refresh button in the window)
/tre missing       print the area names this zone still needs
/tre found         list the trigger spots saved as areas popped
/tre pins          show or hide the spots on the world map
/tre unignore      bring back every skipped spot
/tre probe         print what the game reports, for troubleshooting

On the world map: blue dots are confirmed trigger spots, gold dots are enclosed patches (almost always a real area),
grey dots touch the map edge (may be unreachable), green is the one you're being
guided to. Click a dot to be guided there, right-click to ignore it.

Limits
------
- Dark ground that's never part of any area (mountains, cliffs) can show up
  as a spot. Use /tre next or right-click it on the map.
- An undiscovered area that runs into the dark border around a zone can merge
  with that border and get no spot. If the achievement still lists a name
  after the spots run out, look for the dark patch near the zone's edge on the
  world map.
- Tiny areas smaller than one grid square (about 30-60 yards) can be missed.
  The "Still needed" names in the window will tell you they're left.
