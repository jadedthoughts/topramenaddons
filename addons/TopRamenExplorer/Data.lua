-- Top Ramen Explorer: confirmed trigger spots on WoW Forever's maps.
-- KNOWN[zone name][area name] = { x, y, note }   (x, y on the 0-100 map scale)
-- Only spots confirmed in game go here. Spots you discover yourself are saved
-- automatically (account-wide) and used on your other characters.
local _, ns = ...

ns.KNOWN = {
  ["Ashenvale"] = {
    ["The Howling Vale"] = { 52.7, 37.7, "Cave. Take the Felwood road to about 54,32, then the path west that curls south up to the cave." },
  },
  ["Stonetalon Mountains"] = {
    ["The Charred Vale"] = { 35.1, 55.9, "Confirmed in game; it can also trigger at other edges of the vale." },
  },
}

-- tips with no exact spot yet, shown next to the area name
ns.TIPS = {
  ["Elwynn Forest"] = {
    ["Stormwind City"] = "Go 30-40 yards inside the Stormwind gates; outside the walls doesn't count.",
  },
}
