-- Generated from ForeverDungeonJournal's FDJ.DUNGEON_MAPS (boss spots, floors,
-- entrances, level changes, turn-ins). Areas are placed on the names printed on
-- each map (approximate); maps without printed names start empty: Ctrl-click in game.
local _, ns = ...
ns.DUNGEONS = ns.DUNGEONS or {}
local D = ns.DUNGEONS

D["Alcaz Prison"] = {
  floors = {
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\AlcazPrisonMap", texRight = 1, texBottom = 0.667, label = "1" },
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\AlcazPrisonMap2", texRight = 1, texBottom = 0.667, label = "2" },
  },
  areas = {
    { name = "Main Unit", floor = 1, x = 0.45, y = 0.45, r = 0.3 },
    { name = "Matarius Cell", floor = 1, x = 0.73, y = 0.33, r = 0.06 },
    { name = "Maximum Security Unit", floor = 2, x = 0.5, y = 0.5, r = 0.3 },
  },
  markers = {
    { floor = 1, x = 0.353, y = 0.16, label = "Entrance" },
    { floor = 1, x = 0.33, y = 0.552, label = "Way to level 2", to = 2, color = { 0.3, 0.85, 1 } },
  },
  bosses = {
    { name = "Overseer Wrex", floor = 1, x = 0.642, y = 0.338, portrait = 7914 },
    { name = "The Questioner", floor = 1, x = 0.247, y = 0.173, portrait = 140092 },
    { name = "Tidemistress Ca'zass", floor = 1, x = 0.355, y = 0.714, portrait = 4973 },
    { name = "Katerina the Cleaner", floor = 2, x = 0.39, y = 0.715, portrait = 2317 },
    { name = "Blazeroar", floor = 2, x = 0.661, y = 0.714, portrait = 6374 },
  },
}

D["Blackfathom Deeps"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\BlackFathomDeeps\\BlackFathomDeeps1_", mapID = 221, label = "1", patches = { { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\BlackFathomDeeps1_s1", x0 = 0.0818, y0 = 0.3728, x1 = 0.1158, y1 = 0.4237 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\BlackFathomDeeps1_s2", x0 = 0.3114, y0 = 0.5793, x1 = 0.3453, y1 = 0.6302 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\BlackFathomDeeps1_s3", x0 = 0.5289, y0 = 0.5479, x1 = 0.5629, y1 = 0.5988 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\BlackFathomDeeps1_1", x0 = 0.2146, y0 = 0.0075, x1 = 0.4391, y1 = 0.1093 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\BlackFathomDeeps1_2", x0 = 0.4691, y0 = 0.0075, x1 = 0.8044, y1 = 0.1093 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\BlackFathomDeeps1_3", x0 = 0.4242, y0 = 0.0075, x1 = 0.489, y1 = 0.0719 } } },
    { tiles = "Interface\\WorldMap\\BlackFathomDeeps\\BlackFathomDeeps2_", mapID = 222, label = "2", patches = { { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\BlackFathomDeeps2_s1", x0 = 0.509, y0 = 0.7934, x1 = 0.5429, y1 = 0.8443 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\BlackFathomDeeps2_s2", x0 = 0.8263, y0 = 0.8398, x1 = 0.8603, y1 = 0.8907 } } },
    { tiles = "Interface\\WorldMap\\BlackFathomDeeps\\BlackFathomDeeps3_", mapID = 223, label = "3", patches = { { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\BlackFathomDeeps3_s1", x0 = 0.5569, y0 = 0.2799, x1 = 0.5908, y1 = 0.3308 } } },
  },
  areas = {
    { name = "The Pool of Ask'ar", floor = 1, x = 0.32, y = 0.52, r = 0.16 },
    { name = "The Drowned Sacellum", floor = 1, x = 0.5, y = 0.32, r = 0.08 },
    { name = "Moonshrine Ruins", floor = 2, x = 0.38, y = 0.66, r = 0.09 },
    { name = "Moonshrine Sanctum", floor = 2, x = 0.55, y = 0.79, r = 0.06 },
    { name = "Aku'mai's Lair", floor = 2, x = 0.84, y = 0.8, r = 0.09 },
    { name = "The Forgotten Pool", floor = 3, x = 0.55, y = 0.32, r = 0.12 },
  },
  markers = {
    { floor = 1, x = 0.455, y = 0.085, label = "Entrance" },
    { floor = 1, x = 0.615, y = 0.7, label = "Way to level 2", to = 2, color = { 0.3, 0.85, 1 } },
    { floor = 2, x = 0.47, y = 0.7, label = "Way to level 3", to = 3, color = { 0.3, 0.85, 1 } },
  },
  bosses = {
    { name = "Ghamoo-ra", floor = 1, x = 0.325, y = 0.605, portrait = 5027 },
    { name = "Lady Sarevess", floor = 1, x = 0.11, y = 0.385, portrait = 4979 },
    { name = "Gelihast", floor = 1, x = 0.54, y = 0.575, portrait = 1773 },
    { name = "Lorgus Jett", floor = 2, x = 0.325, y = 0.7, portrait = 12822 },
    { name = "Lorgus Jett", floor = 2, x = 0.385, y = 0.194, portrait = 12822, alt = true },
    { name = "Lorgus Jett", floor = 2, x = 0.442, y = 0.231, portrait = 12822, alt = true },
    { name = "Baron Aquanis", floor = 2, x = 0.42, y = 0.72, portrait = 110 },
    { name = "Twilight Lord Kelris", floor = 2, x = 0.525, y = 0.81, portrait = 4939 },
    { name = "Aku'mai", floor = 2, x = 0.855, y = 0.86, portrait = 2837 },
    { name = "Old Serra'kis", floor = 3, x = 0.585, y = 0.29, portrait = 1816 },
  },
}

D["Blackmaw Hold"] = {
  floors = {
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\BlackmawHoldGroveMap", texRight = 1, texBottom = 0.667, label = "Blackmaw Grove" },
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\BlackmawHoldFesteringGrottoMap", texRight = 1, texBottom = 0.667, label = "Festering Grotto" },
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\BlackmawHoldGroveMap", texRight = 1, texBottom = 0.667, label = "Blackmaw Grove" },
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\BlackmawHoldFallenGroveMap", texRight = 1, texBottom = 0.667, label = "Depths of the Fallen Grove" },
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\BlackmawHoldEldersMap", texRight = 1, texBottom = 0.667, label = "Depths of the Elders" },
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\BlackmawHoldBurrowMap", texRight = 1, texBottom = 0.667, label = "Depths of the Burrow" },
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\BlackmawHoldForbiddenMagicMap", texRight = 1, texBottom = 0.667, label = "Depths of Forbidden Magic" },
  },
  areas = {
    { name = "Blackmaw Stillwater", floor = 1, x = 0.28, y = 0.32, r = 0.1 },
    { name = "Blackmaw Grove", floor = 1, x = 0.32, y = 0.63, r = 0.13 },
    { name = "Bonesnout's Thicket", floor = 1, x = 0.78, y = 0.62, r = 0.13 },
    { name = "Festering Grotto", floor = 2, x = 0.5, y = 0.45, r = 0.3 },
    { name = "Depths of the Fallen Grove", floor = 4, x = 0.25, y = 0.55, r = 0.25 },
    { name = "Depths of the Elders", floor = 5, x = 0.6, y = 0.5, r = 0.27 },
    { name = "Depths of the Burrow", floor = 6, x = 0.4, y = 0.55, r = 0.25 },
    { name = "Depths of Forbidden Magic", floor = 7, x = 0.62, y = 0.52, r = 0.25 },
  },
  markers = {
    { floor = 1, x = 0.183, y = 0.74, label = "Entrance" },
    { floor = 1, x = 0.71, y = 0.328, label = "Way to Festering Grotto", to = 2, color = { 0.3, 0.85, 1 } },
    { floor = 2, x = 0.578, y = 0.791, label = "Way to Blackmaw Grove", to = 3, color = { 0.3, 0.85, 1 } },
    { floor = 3, x = 0.787, y = 0.512, label = "Way to Depths of the Fallen Grove", to = 4, color = { 0.3, 0.85, 1 } },
    { floor = 4, x = 0.313, y = 0.298, label = "Way to Depths of the Elders", to = 5, color = { 0.3, 0.85, 1 } },
    { floor = 5, x = 0.654, y = 0.675, label = "Way to Depths of the Burrow", to = 6, color = { 0.3, 0.85, 1 } },
    { floor = 6, x = 0.651, y = 0.329, label = "Way to Depths of Forbidden Magic", to = 7, color = { 0.3, 0.85, 1 } },
  },
  bosses = {
    { name = "Impaan the Imprisoner", floor = 1, x = 0.424, y = 0.7, portrait = 130432 },
    { name = "Moontouched Wanderer", floor = 1, x = 0.589, y = 0.842, portrait = 12235 },
    { name = "Bonesnout the Unbroken", floor = 1, x = 0.711, y = 0.773, portrait = 130427 },
    { name = "Withermaw", floor = 2, x = 0.715, y = 0.269, portrait = 140708 },
    { name = "Unbound Spirit", floor = 4, x = 0.585, y = 0.35, portrait = 131644 },
    { name = "Elder Shaman Bloodmane", floor = 5, x = 0.447, y = 0.363, portrait = 130440 },
    { name = "Blackmaw Behemoth", floor = 6, x = 0.558, y = 0.347, portrait = 130436 },
    { name = "Varrox Bleakhoof", floor = 7, x = 0.638, y = 0.586, portrait = 130447 },
  },
}

D["Blackrock Depths"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\BlackrockDepths\\BlackrockDepths1_", mapID = 242, label = "1" },
    { tiles = "Interface\\WorldMap\\BlackrockDepths\\BlackrockDepths2_", mapID = 243, label = "2" },
  },
  areas = {
    { name = "Hall of Crafting", floor = 1, x = 0.63, y = 0.2, r = 0.06 },
    { name = "Shadowforge City", floor = 1, x = 0.45, y = 0.3, r = 0.1 },
    { name = "Dark Iron Highway", floor = 1, x = 0.32, y = 0.52, r = 0.1 },
    { name = "Detention Block", floor = 1, x = 0.5, y = 0.72, r = 0.11 },
    { name = "The Lyceum", floor = 2, x = 0.68, y = 0.1, r = 0.06 },
    { name = "The Imperial Seat", floor = 2, x = 0.88, y = 0.11, r = 0.06 },
    { name = "Summoners' Tomb", floor = 2, x = 0.54, y = 0.23, r = 0.05 },
    { name = "Molten Core", floor = 2, x = 0.67, y = 0.33, r = 0.04 },
    { name = "Mold Foundry", floor = 2, x = 0.43, y = 0.33, r = 0.05 },
    { name = "Chamber of Enchantment", floor = 2, x = 0.58, y = 0.42, r = 0.05 },
    { name = "The Grim Guzzler", floor = 2, x = 0.48, y = 0.59, r = 0.06 },
    { name = "Shadowforge City", floor = 2, x = 0.6, y = 0.56, r = 0.07 },
    { name = "West Garrison", floor = 2, x = 0.36, y = 0.74, r = 0.05 },
    { name = "The Domicile", floor = 2, x = 0.6, y = 0.72, r = 0.05 },
    { name = "Ring of Law", floor = 2, x = 0.5, y = 0.87, r = 0.06 },
    { name = "Shrine of Thaurissan", floor = 2, x = 0.62, y = 0.86, r = 0.04 },
    { name = "East Garrison", floor = 2, x = 0.41, y = 0.88, r = 0.04 },
  },
  markers = {
    { floor = 1, x = 0.329, y = 0.794, label = "Entrance" },
  },
  bosses = {
    { name = "High Interrogator Gerstahn", floor = 1, x = 0.474, y = 0.922, portrait = 8761 },
    { name = "Lord Roccor", floor = 1, x = 0.556, y = 0.67, portrait = 5781 },
    { name = "Houndmaster Grebmar", floor = 1, x = 0.535, y = 0.573, portrait = 9212 },
    { name = "Bael'Gar", floor = 1, x = 0.251, y = 0.534, portrait = 12162 },
    { name = "Lord Incendius", floor = 1, x = 0.564, y = 0.311, portrait = 1204 },
    { name = "Fineous Darkvire", floor = 1, x = 0.635, y = 0.211, portrait = 8704 },
    { name = "Gorosh the Dervish", floor = 2, x = 0.53, y = 0.868, portrait = 8760 },
    { name = "Grizzle", floor = 2, x = 0.547, y = 0.883, portrait = 7873 },
    { name = "Eviscerator", floor = 2, x = 0.547, y = 0.913, portrait = 523 },
    { name = "Ok'thor the Breaker", floor = 2, x = 0.53, y = 0.928, portrait = 11538 },
    { name = "Anub'shiah", floor = 2, x = 0.513, y = 0.913, portrait = 3004 },
    { name = "Hedrum the Creeper", floor = 2, x = 0.513, y = 0.883, portrait = 8271 },
    { name = "Pyromancer Loregrain", floor = 2, x = 0.549, y = 0.948, portrait = 8762 },
    { name = "Warder Stilgiss", floor = 2, x = 0.602, y = 0.659, portrait = 9089 },
    { name = "General Angerforge", floor = 2, x = 0.363, y = 0.823, portrait = 8756 },
    { name = "Golem Lord Argelmach", floor = 2, x = 0.364, y = 0.651, portrait = 8759 },
    { name = "Hurley Blackbreath", floor = 2, x = 0.505, y = 0.704, portrait = 8658 },
    { name = "Plugger Spazzring", floor = 2, x = 0.477, y = 0.657, portrait = 8652 },
    { name = "Phalanx", floor = 2, x = 0.458, y = 0.564, portrait = 8177 },
    { name = "Ambassador Flamelash", floor = 2, x = 0.538, y = 0.485, portrait = 8329 },
    { name = "The Seven", floor = 2, x = 0.538, y = 0.247, portrait = 8687 },
    { name = "Magmus", floor = 2, x = 0.796, y = 0.118, portrait = 12162 },
    { name = "Princess Moira Bronzebeard", floor = 2, x = 0.948, y = 0.118, portrait = 8705 },
    { name = "Emperor Dagran Thaurissan", floor = 2, x = 0.88, y = 0.118, portrait = 8807 },
  },
}

D["City of Dalaran"] = {
  floors = {
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\DalaranUnderbellyMap", texRight = 1, texBottom = 0.6665, label = "1" },
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\DalaranCityMap", texRight = 1, texBottom = 0.6665, label = "2" },
  },
  areas = {
    { name = "The Underbelly", floor = 1, x = 0.55, y = 0.5, r = 0.2 },
    { name = "Cantrips & Crows", floor = 1, x = 0.4, y = 0.62, r = 0.06 },
    { name = "The Violet Citadel", floor = 2, x = 0.54, y = 0.22, r = 0.1 },
    { name = "Runeweaver Square", floor = 2, x = 0.57, y = 0.52, r = 0.08 },
    { name = "The Eventide", floor = 2, x = 0.38, y = 0.55, r = 0.07 },
    { name = "The Violet Hold", floor = 2, x = 0.34, y = 0.8, r = 0.08 },
    { name = "Krasus' Landing", floor = 2, x = 0.57, y = 0.85, r = 0.06 },
  },
  markers = {
    { floor = 1, x = 0.19, y = 0.838, label = "Entrance" },
    { floor = 1, x = 0.778, y = 0.564, label = "Way to level 2", to = 2, color = { 0.3, 0.85, 1 } },
  },
  bosses = {
    { name = "Atrexis the Grave Knight", floor = 1, x = 0.535, y = 0.505, portrait = 145787 },
    { name = "Lyn the Ignored", floor = 1, x = 0.68, y = 0.177, portrait = 130235 },
    { name = "Mana Devourer", floor = 2, x = 0.416, y = 0.73, portrait = 129895 },
    { name = "Fel Ancient", floor = 2, x = 0.513, y = 0.549, portrait = 129894 },
    { name = "Unstable Sentinel", floor = 2, x = 0.614, y = 0.413, portrait = 129954 },
    { name = "Arcanic Enigma", floor = 2, x = 0.669, y = 0.503, portrait = 129900 },
    { name = "Arcane Anomaly", floor = 2, x = 0.527, y = 0.843, portrait = 129891 },
    { name = "Shade of the Archmage", floor = 2, x = 0.52, y = 0.24, portrait = 130061 },
  },
}

D["Dire Maul: East"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\DireMaul\\DireMaul6_", mapID = 240, label = "1" },
    { tiles = "Interface\\WorldMap\\DireMaul\\DireMaul5_", mapID = 239, label = "2" },
  },
  areas = {
    { name = "The Shrine of Eldretharr", floor = 1, x = 0.6, y = 0.24, r = 0.12 },
    { name = "The Conservatory", floor = 1, x = 0.4, y = 0.7, r = 0.12 },
    { name = "The Hidden Reach", floor = 2, x = 0.66, y = 0.36, r = 0.1 },
  },
  markers = {
    { floor = 1, x = 0.281, y = 0.554, label = "Entrance" },
  },
  bosses = {
    { name = "Lethtendris", floor = 2, x = 0.438, y = 0.481, portrait = 14378 },
    { name = "Zevrim Thornhoof", floor = 1, x = 0.575, y = 0.743, portrait = 11335 },
    { name = "Hydrospawn", floor = 1, x = 0.536, y = 0.715, portrait = 5489 },
    { name = "Alzzin the Wildshaper", floor = 1, x = 0.566, y = 0.288, portrait = 14416 },
  },
}

D["Dire Maul: North"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\DireMaul\\DireMaul1_", mapID = 235 },
  },
  areas = {
    { name = "Gordok's Seat", floor = 1, x = 0.33, y = 0.25, r = 0.08 },
    { name = "Halls of Destruction", floor = 1, x = 0.25, y = 0.56, r = 0.08 },
  },
  markers = {
    { floor = 1, x = 0.717, y = 0.924, label = "Entrance" },
  },
  bosses = {
    { name = "Guard Mol'dar", floor = 1, x = 0.695, y = 0.76, portrait = 11561 },
    { name = "Stomper Kreeg", floor = 1, x = 0.612, y = 0.692, portrait = 11545 },
    { name = "Guard Fengus", floor = 1, x = 0.494, y = 0.78, portrait = 11561 },
    { name = "Guard Slip'kik", floor = 1, x = 0.266, y = 0.571, portrait = 11561 },
    { name = "Captain Kromcrush", floor = 1, x = 0.318, y = 0.506, portrait = 11564 },
    { name = "Cho'Rush the Observer", floor = 1, x = 0.3, y = 0.29, portrait = 11537 },
    { name = "King Gordok", floor = 1, x = 0.319, y = 0.229, portrait = 11583 },
  },
}

D["Dire Maul: West"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\DireMaul\\DireMaul2_", mapID = 236, label = "1" },
    { tiles = "Interface\\WorldMap\\DireMaul\\DireMaul3_", mapID = 237, label = "2" },
    { tiles = "Interface\\WorldMap\\DireMaul\\DireMaul4_", mapID = 238, label = "3" },
  },
  areas = {
    { name = "Court of the Highborne", floor = 1, x = 0.36, y = 0.48, r = 0.14 },
    { name = "Court of the Highborne", floor = 2, x = 0.4, y = 0.5, r = 0.14 },
    { name = "Prison of Immol'thar", floor = 3, x = 0.35, y = 0.55, r = 0.2 },
    { name = "The Athenaeum", floor = 3, x = 0.7, y = 0.18, r = 0.07 },
  },
  markers = {
    { floor = 1, x = 0.935, y = 0.507, label = "Entrance" },
  },
  bosses = {
    { name = "Tendris Warpwood", floor = 1, x = 0.336, y = 0.536, portrait = 14383 },
    { name = "Illyanna Ravenoak", floor = 1, x = 0.203, y = 0.776, portrait = 11270 },
    { name = "Magister Kalendris", floor = 2, x = 0.338, y = 0.45, portrait = 14384 },
    { name = "Tsu'zee", floor = 2, x = 0.322, y = 0.143, portrait = 11250 },
    { name = "Immol'thar", floor = 3, x = 0.349, y = 0.575, portrait = 14173 },
    { name = "Prince Tortheldrin", floor = 3, x = 0.622, y = 0.231, portrait = 11256 },
  },
}

D["Excavation Site: Wetlands"] = {
  floors = {
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\ExcavationSiteMap", texRight = 1, texBottom = 0.667 },
  },
  areas = {
    { name = "Lost Dig Site", floor = 1, x = 0.12, y = 0.5, r = 0.07 },
    { name = "Stalker's Thicket", floor = 1, x = 0.33, y = 0.38, r = 0.08 },
    { name = "Lost Marsh", floor = 1, x = 0.58, y = 0.45, r = 0.13 },
    { name = "Site of the Guardian", floor = 1, x = 0.36, y = 0.7, r = 0.08 },
  },
  markers = {
    { floor = 1, x = 0.888, y = 0.258, label = "Entrance" },
    { floor = 1, x = 0.262, y = 0.668, label = "Quest turn-in: Ardin Grassman", color = { 1, 0.82, 0 } },
    { floor = 1, x = 0.074, y = 0.497, label = "Quest turn-in: Daewyn Songblade", color = { 1, 0.82, 0 } },
  },
  bosses = {
    { name = "Saltspine", floor = 1, x = 0.55, y = 0.361, portrait = 144209 },
    { name = "Shadetooth", floor = 1, x = 0.305, y = 0.484, portrait = 144210 },
    { name = "Relic Guardian", floor = 1, x = 0.324, y = 0.687, portrait = 144224 },
    { name = "Highland Horror", floor = 1, x = 0.082, y = 0.405, portrait = 9010, quest = true },
  },
}

D["Hall of Thanes"] = {
  floors = {
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\HallOfThanesMap", texRight = 1, texBottom = 0.667 },
  },
  areas = {
    { name = "Reliquary of Kings", floor = 1, x = 0.5, y = 0.25, r = 0.1 },
    { name = "Dark Iron Ingress", floor = 1, x = 0.68, y = 0.46, r = 0.07 },
    { name = "Anvilmar's Rest", floor = 1, x = 0.5, y = 0.7, r = 0.1 },
  },
  markers = {
    { floor = 1, x = 0.51, y = 0.944, label = "Entrance" },
  },
  bosses = {
    { name = "Faldrim Anvilmar", floor = 1, x = 0.509, y = 0.668, portrait = 142826 },
    { name = "Magmatus", floor = 1, x = 0.748, y = 0.478 },
    { name = "Plunder", floor = 1, x = 0.51, y = 0.515, portrait = 142840 },
    { name = "Durgen Dirgehammer", floor = 1, x = 0.509, y = 0.17, portrait = 142837 },
  },
}

D["Maraudon"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\Maraudon\\Maraudon1_", mapID = 280, label = "1" },
    { tiles = "Interface\\WorldMap\\Maraudon\\Maraudon2_", mapID = 281, label = "2" },
  },
  areas = {
    { name = "The Noxious Hollow", floor = 1, x = 0.38, y = 0.15, r = 0.07 },
    { name = "Foulspore Cavern", floor = 1, x = 0.22, y = 0.3, r = 0.09 },
    { name = "Poison Falls", floor = 1, x = 0.25, y = 0.58, r = 0.1 },
    { name = "Vyletongue Seat", floor = 1, x = 0.4, y = 0.74, r = 0.06 },
    { name = "The Wicked Grotto", floor = 1, x = 0.63, y = 0.68, r = 0.1 },
    { name = "Earth Song Falls", floor = 2, x = 0.28, y = 0.47, r = 0.12 },
    { name = "Zaetar's Grave", floor = 2, x = 0.32, y = 0.84, r = 0.1 },
  },
  markers = {
    { floor = 1, x = 0.618, y = 0.281, label = "Entrance (orange side)", color = { 1, 0.55, 0.1 } },
    { floor = 1, x = 0.764, y = 0.659, label = "Entrance (purple side)", color = { 0.78, 0.45, 1 } },
    { floor = 2, x = 0.245, y = 0.143, label = "Quest turn-in: Celebras the Redeemed", color = { 1, 0.82, 0 } },
  },
  bosses = {
    { name = "Noxxion", floor = 1, x = 0.362, y = 0.098, portrait = 11172 },
    { name = "Razorlash", floor = 1, x = 0.166, y = 0.344, portrait = 12389 },
    { name = "Lord Vyletongue", floor = 1, x = 0.378, y = 0.704, portrait = 12334 },
    { name = "Meshlok the Harvester", floor = 1, x = 0.246, y = 0.874, portrait = 9014 },
    { name = "Celebras the Cursed", floor = 2, x = 0.245, y = 0.143, portrait = 12350 },
    { name = "Landslide", floor = 2, x = 0.408, y = 0.487, portrait = 12293 },
    { name = "Tinkerer Gizlock", floor = 2, x = 0.484, y = 0.686, portrait = 7125 },
    { name = "Rotgrip", floor = 2, x = 0.413, y = 0.817, portrait = 13589 },
    { name = "Princess Theradras", floor = 2, x = 0.258, y = 0.788, portrait = 12292 },
  },
}

D["Ragefire Chasm"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\Ragefire\\Ragefire1_", mapID = 213, patches = { { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\Ragefire1_s1", x0 = 0.5259, y0 = 0.2725, x1 = 0.5599, y1 = 0.3234 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\Ragefire1_s2", x0 = 0.3752, y0 = 0.5584, x1 = 0.4092, y1 = 0.6093 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\Ragefire1_s3", x0 = 0.6806, y0 = 0.6213, x1 = 0.7146, y1 = 0.6722 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\Ragefire1_s4", x0 = 0.3253, y0 = 0.7904, x1 = 0.3593, y1 = 0.8413 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\Ragefire1_1", x0 = 0.015, y0 = 0.012, x1 = 0.5948, y1 = 0.1497 } } },
  },
  areas = {},
  markers = {
    { floor = 1, x = 0.61, y = 0.075, label = "Entrance" },
  },
  bosses = {
    { name = "Oggleflint", floor = 1, x = 0.561, y = 0.378, portrait = 11611 },
    { name = "Taragaman the Hungerer", floor = 1, x = 0.405, y = 0.57, portrait = 7970 },
    { name = "Jergosh the Invoker", floor = 1, x = 0.34, y = 0.815, portrait = 11429 },
    { name = "Bazzalan", floor = 1, x = 0.422, y = 0.842, portrait = 2007 },
  },
}

D["Razorfen Downs"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\RazorfenDowns\\RazorfenDowns1_", mapID = 300 },
  },
  areas = {
    { name = "The Murder Pens", floor = 1, x = 0.75, y = 0.2, r = 0.07 },
    { name = "The Caller's Chamber", floor = 1, x = 0.58, y = 0.33, r = 0.06 },
    { name = "The Bone Pile", floor = 1, x = 0.85, y = 0.48, r = 0.07 },
    { name = "Spiral of Thorns", floor = 1, x = 0.44, y = 0.65, r = 0.14 },
  },
  markers = {
    { floor = 1, x = 0.234, y = 0.185, label = "Entrance" },
  },
  bosses = {
    { name = "Tuten'kash", floor = 1, x = 0.589, y = 0.342, portrait = 7845 },
    { name = "Mordresh Fire Eye", floor = 1, x = 0.86, y = 0.467, portrait = 8055 },
    { name = "Glutton", floor = 1, x = 0.345, y = 0.664, portrait = 7864 },
    { name = "Amnennar the Coldbringer", floor = 1, x = 0.455, y = 0.582, portrait = 7971 },
  },
}

D["Ruins of Lordaeron"] = {
  floors = {
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\RuinsOfLordaeronMap", texRight = 1, texBottom = 0.667 },
  },
  areas = {
    { name = "Market Street", floor = 1, x = 0.35, y = 0.42, r = 0.07 },
    { name = "King's Alley", floor = 1, x = 0.7, y = 0.4, r = 0.06 },
    { name = "Lordamere Overlook", floor = 1, x = 0.55, y = 0.63, r = 0.07 },
    { name = "Lordaeron Graveyard", floor = 1, x = 0.38, y = 0.73, r = 0.07 },
  },
  markers = {
    { floor = 1, x = 0.612, y = 0.214, label = "Entrance" },
    { floor = 1, x = 0.612, y = 0.272, label = "Quest turn-in: Captain Truman", color = { 1, 0.82, 0 } },
  },
  bosses = {
    { name = "Witherfang", floor = 1, x = 0.668, y = 0.36, portrait = 144189 },
    { name = "The Baron", floor = 1, x = 0.615, y = 0.65, portrait = 144188 },
    { name = "Viktor the Vile", floor = 1, x = 0.437, y = 0.788, portrait = 139455 },
    { name = "The Abandoned", floor = 1, x = 0.395, y = 0.665, portrait = 138667 },
    { name = "Bjork", floor = 1, x = 0.345, y = 0.22, portrait = 144170 },
    { name = "Rath'mael", floor = 1, x = 0.52, y = 0.6, portrait = 144175 },
    { name = "Lordaeron Captain", floor = 1, x = 0.5, y = 0.3, portraitTex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\LordaeronCaptainPortrait" },
  },
}

D["Scholomance"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\ScholomanceOLD\\ScholomanceOLD1_", mapID = 306, label = "1" },
    { tiles = "Interface\\WorldMap\\ScholomanceOLD\\ScholomanceOLD2_", mapID = 307, label = "2" },
    { tiles = "Interface\\WorldMap\\ScholomanceOLD\\ScholomanceOLD3_", mapID = 308, label = "3" },
    { tiles = "Interface\\WorldMap\\ScholomanceOLD\\ScholomanceOLD4_", mapID = 309, label = "4" },
  },
  areas = {},
  markers = {
    { floor = 1, x = 0.39, y = 0.652, label = "Entrance" },
  },
  bosses = {
    { name = "Kirtonos the Herald", floor = 2, x = 0.495, y = 0.043, portrait = 143673 },
    { name = "Marduk Blackpool", floor = 2, x = 0.444, y = 0.639, portrait = 10248 },
    { name = "Vectus", floor = 2, x = 0.482, y = 0.662, portrait = 2606 },
    { name = "Rattlegore", floor = 3, x = 0.313, y = 0.646, portrait = 12073 },
    { name = "Instructor Malicia", floor = 3, x = 0.721, y = 0.706, portrait = 11069 },
    { name = "Doctor Theolen Krastinov", floor = 3, x = 0.889, y = 0.462, portrait = 10901 },
    { name = "Lorekeeper Polkelt", floor = 3, x = 0.72, y = 0.225, portrait = 11492 },
    { name = "Ras Frostwhisper", floor = 4, x = 0.406, y = 0.884, portrait = 7919 },
    { name = "The Ravenian", floor = 4, x = 0.675, y = 0.521, portrait = 10433 },
    { name = "Lord Alexei Barov", floor = 4, x = 0.844, y = 0.308, portrait = 11072 },
    { name = "Lady Illucia Barov", floor = 4, x = 0.67, y = 0.061, portrait = 11835 },
    { name = "Darkmaster Gandling", floor = 4, x = 0.682, y = 0.302, portrait = 11070 },
  },
}

D["Shadowfang Keep"] = {
  floors = {
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\Maps\\ShadowfangKeep1Fresh", texRight = 0.9785, texBottom = 0.6523, mapID = 310, label = "1" },
    { tiles = "Interface\\WorldMap\\ShadowfangKeep\\ShadowfangKeep7_", mapID = 316, label = "2", patches = { { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\ShadowfangKeep7_s1", x0 = 0.5659, y0 = 0.8024, x1 = 0.5998, y1 = 0.8533 } } },
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\Maps\\ShadowfangKeep313Fresh", texRight = 0.9785, texBottom = 0.6523, mapID = 313, label = "3" },
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\Maps\\ShadowfangKeep6Fresh", texRight = 0.9785, texBottom = 0.6523, mapID = 315, label = "4" },
  },
  areas = {},
  markers = {
    { floor = 1, x = 0.705, y = 0.605, label = "Entrance" },
    { floor = 1, x = 0.358, y = 0.675, label = "Way to level 2", to = 2, color = { 0.3, 0.85, 1 } },
    { floor = 2, x = 0.43, y = 0.357, label = "Way to level 3", to = 3, color = { 0.3, 0.85, 1 } },
    { floor = 3, x = 0.432, y = 0.744, label = "Way to level 4", to = 4, color = { 0.3, 0.85, 1 } },
    { floor = 1, x = 0.558, y = 0.622, label = "Quest turn-in: Deathstalker Vincent", color = { 1, 0.82, 0 } },
  },
  bosses = {
    { name = "Rethilgore", floor = 1, x = 0.67, y = 0.715, portrait = 524 },
    { name = "Fel Steed / Shadow Charger", floor = 1, x = 0.322, y = 0.595, portrait = 1951 },
    { name = "Commander Springvale", floor = 1, x = 0.279, y = 0.6, portrait = 3223 },
    { name = "Razorclaw the Butcher", floor = 1, x = 0.327, y = 0.447, portrait = 524 },
    { name = "Baron Silverlaine", floor = 1, x = 0.162, y = 0.807, portrait = 3222 },
    { name = "Deathsworn Captain", floor = 2, x = 0.63, y = 0.525, portrait = 3224 },
    { name = "Odo the Blindwatcher", floor = 2, x = 0.583, y = 0.828, portrait = 522 },
    { name = "Fenrus the Devourer", floor = 3, x = 0.543, y = 0.538, portrait = 2352 },
    { name = "Arugal's Voidwalker", floor = 3, x = 0.593, y = 0.538, portrait = 1131 },
    { name = "Wolf Master Nandos", floor = 4, x = 0.59, y = 0.533, portrait = 11179 },
    { name = "Archmage Arugal", floor = 4, x = 0.625, y = 0.191, portrait = 2353 },
  },
}

D["Shaper's Terrace"] = {
  floors = {
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\ShapersTerraceMap", texRight = 1, texBottom = 0.667 },
  },
  areas = {
    { name = "Tribunal of Ages", floor = 1, x = 0.15, y = 0.15, r = 0.08 },
    { name = "Regrowth Vestibule", floor = 1, x = 0.55, y = 0.25, r = 0.07 },
    { name = "The Path of the Shaper", floor = 1, x = 0.22, y = 0.38, r = 0.1 },
    { name = "Loris' Tarpits", floor = 1, x = 0.45, y = 0.52, r = 0.08 },
    { name = "Isiz's Pillar", floor = 1, x = 0.88, y = 0.52, r = 0.06 },
    { name = "Pillar of Assimilation", floor = 1, x = 0.72, y = 0.62, r = 0.09 },
    { name = "Prismatic Talus", floor = 1, x = 0.86, y = 0.85, r = 0.07 },
  },
  markers = {
    { floor = 1, x = 0.238, y = 0.693, label = "Entrance" },
  },
  bosses = {
    { name = "Titanosaur", floor = 1, x = 0.083, y = 0.404, portrait = 142989 },
    { name = "Cinder", floor = 1, x = 0.138, y = 0.629, portrait = 143035 },
    { name = "Vitrix", floor = 1, x = 0.51, y = 0.3, portrait = 147098 },
    { name = "Izha'Rel and Tor'Rel", floor = 1, x = 0.645, y = 0.387 },
    { name = "Direhorn Matriarch", floor = 1, x = 0.846, y = 0.602, portrait = 144515 },
    { name = "Thunderhoof", floor = 1, x = 0.628, y = 0.736, portrait = 144514 },
    { name = "Bolt", floor = 1, x = 0.426, y = 0.702, portrait = 143063 },
    { name = "Venomridge", floor = 1, x = 0.373, y = 0.624, portrait = 144511 },
    { name = "Snowtalon", floor = 1, x = 0.107, y = 0.14, portrait = 143122 },
    { name = "Nanaya", floor = 1, x = 0.734, y = 0.59, portrait = 143832 },
  },
}

D["Stratholme: Living"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\Stratholme\\Stratholme1_", mapID = 317 },
  },
  areas = {
    { name = "Crusaders' Square", floor = 1, x = 0.33, y = 0.22, r = 0.08 },
    { name = "Market Row", floor = 1, x = 0.6, y = 0.2, r = 0.08 },
    { name = "Festival Lane", floor = 1, x = 0.85, y = 0.25, r = 0.07 },
    { name = "The Hoard", floor = 1, x = 0.06, y = 0.46, r = 0.06 },
    { name = "King's Square", floor = 1, x = 0.68, y = 0.48, r = 0.1 },
    { name = "The Crimson Throne", floor = 1, x = 0.22, y = 0.84, r = 0.06 },
  },
  markers = {
    { floor = 1, x = 0.675, y = 0.877, label = "Entrance" },
  },
  bosses = {
    { name = "Skul", floor = 1, x = 0.574, y = 0.652, portrait = 2606 },
    { name = "Hearthsinger Forresten", floor = 1, x = 0.605, y = 0.327, portrait = 10482 },
    { name = "The Unforgiven", floor = 1, x = 0.734, y = 0.204, portrait = 10771 },
    { name = "Timmy the Cruel", floor = 1, x = 0.495, y = 0.18, portrait = 571 },
    { name = "Postmaster Malown", floor = 1, x = 0.558, y = 0.684, portrait = 10669 },
    { name = "Cannon Master Willey", floor = 1, x = 0.042, y = 0.51, portrait = 10674 },
    { name = "Archivist Galford", floor = 1, x = 0.272, y = 0.75, portrait = 10544 },
    { name = "Balnazzar", floor = 1, x = 0.204, y = 0.818, portrait = 10691 },
  },
}

D["Stratholme: Undead"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\Stratholme\\Stratholme2_", mapID = 318 },
  },
  areas = {
    { name = "Slaughter Square", floor = 1, x = 0.42, y = 0.17, r = 0.08 },
    { name = "The Gauntlet", floor = 1, x = 0.65, y = 0.38, r = 0.1 },
    { name = "Elders' Square", floor = 1, x = 0.63, y = 0.68, r = 0.08 },
  },
  markers = {
    { floor = 1, x = 0.658, y = 0.902, label = "Entrance" },
  },
  bosses = {
    { name = "Magistrate Barthilas", floor = 1, x = 0.566, y = 0.161, portrait = 10433 },
    { name = "Stonespine", floor = 1, x = 0.649, y = 0.489, portrait = 7856 },
    { name = "Nerub'enkan", floor = 1, x = 0.572, y = 0.461, portrait = 9793 },
    { name = "Baroness Anastari", floor = 1, x = 0.745, y = 0.469, portrait = 10698 },
    { name = "Maleki the Pallid", floor = 1, x = 0.674, y = 0.227, portrait = 10546 },
    { name = "Ramstein the Gorger", floor = 1, x = 0.456, y = 0.198, portrait = 12818 },
    { name = "Baron Rivendare", floor = 1, x = 0.372, y = 0.199, portrait = 10729 },
  },
}

D["Sunken Temple"] = {
  floors = {
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\SunkenTempleMap", texRight = 1, texBottom = 0.667 },
  },
  areas = {},
  markers = {
    { floor = 1, x = 0.499, y = 0.13, label = "Entrance" },
    { floor = 1, x = 0.4985, y = 0.5908, label = "Statue 1 (south) — activate in order to summon Atal'alarion", color = { 0.6, 1, 0.6 } },
    { floor = 1, x = 0.4985, y = 0.3094, label = "Statue 2 (north) — activate in order to summon Atal'alarion", color = { 0.6, 1, 0.6 } },
    { floor = 1, x = 0.4207, y = 0.5234, label = "Statue 3 (south-west) — activate in order to summon Atal'alarion", color = { 0.6, 1, 0.6 } },
    { floor = 1, x = 0.5763, y = 0.5234, label = "Statue 4 (south-east) — activate in order to summon Atal'alarion", color = { 0.6, 1, 0.6 } },
    { floor = 1, x = 0.4207, y = 0.3887, label = "Statue 5 (north-west) — activate in order to summon Atal'alarion", color = { 0.6, 1, 0.6 } },
    { floor = 1, x = 0.5763, y = 0.3887, label = "Statue 6 (north-east) — activate in order to summon Atal'alarion", color = { 0.6, 1, 0.6 } },
  },
  bosses = {
    { name = "Atal'alarion", floor = 1, x = 0.499, y = 0.455, portrait = 7873 },
    { name = "Avatar of Hakkar", floor = 1, x = 0.24, y = 0.453, portrait = 8053 },
    { name = "Jammal'an the Prophet", floor = 1, x = 0.76, y = 0.454, portrait = 6708 },
    { name = "Ogom the Wretched", floor = 1, x = 0.79, y = 0.395, portrait = 6709 },
    { name = "Dreamscythe & Weaver", floor = 1, x = 0.5, y = 0.383 },
    { name = "Morphaz & Hazzas", floor = 1, x = 0.498, y = 0.865 },
    { name = "Shade of Eranikus", floor = 1, x = 0.666, y = 0.873, portrait = 7806 },
  },
}

D["The Deadmines"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_", mapID = 291, label = "1", patches = { { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\TheDeadmines1_s1", x0 = 0.3313, y0 = 0.5898, x1 = 0.3653, y1 = 0.6407 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\TheDeadmines1_s2", x0 = 0.4721, y0 = 0.8413, x1 = 0.506, y1 = 0.8922 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\TheDeadmines1_1", x0 = 0.3194, y0 = 0.015, x1 = 0.6996, y1 = 0.1347 } } },
    { tiles = "Interface\\WorldMap\\TheDeadmines\\TheDeadmines2_", mapID = 292, label = "2", patches = { { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\TheDeadmines2_s1", x0 = 0.1088, y0 = 0.7365, x1 = 0.1427, y1 = 0.7874 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\TheDeadmines2_s2", x0 = 0.5908, y0 = 0.3428, x1 = 0.6248, y1 = 0.3937 }, { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\TheDeadmines2_s3", x0 = 0.565, y0 = 0.416, x1 = 0.611, y1 = 0.484, alpha = 1 } } },
  },
  areas = {
    { name = "Goblin Foundry", floor = 1, x = 0.61, y = 0.62, r = 0.08 },
    { name = "Mast Room", floor = 1, x = 0.42, y = 0.85, r = 0.07 },
    { name = "Goblin Foundry", floor = 2, x = 0.12, y = 0.8, r = 0.08 },
    { name = "Ironclad Cove", floor = 2, x = 0.48, y = 0.5, r = 0.22 },
  },
  markers = {
    { floor = 1, x = 0.295, y = 0.135, label = "Entrance" },
    { floor = 1, x = 0.615, y = 0.61, label = "Way to level 2", to = 2, color = { 0.3, 0.85, 1 } },
  },
  bosses = {
    { name = "Rhahk'Zor", floor = 1, x = 0.365, y = 0.61, portrait = 14403 },
    { name = "Miner Johnson", floor = 1, x = 0.535, y = 0.52, portrait = 556 },
    { name = "Sneed's Shredder", floor = 1, x = 0.475, y = 0.865, portrait = 1269 },
    { name = "Sneed", floor = 1, x = 0.535, y = 0.865, portrait = 7125 },
    { name = "Gilnid", floor = 2, x = 0.122, y = 0.755, portrait = 7124 },
    { name = "Mr. Smite", floor = 2, x = 0.515, y = 0.17, portrait = 2026 },
    { name = "Captain Greenskin", floor = 2, x = 0.575, y = 0.35, portrait = 7113 },
    { name = "Edwin VanCleef", floor = 2, x = 0.605, y = 0.452, portrait = 2029 },
    { name = "Cookie", floor = 2, x = 0.665, y = 0.43, portrait = 1305 },
  },
}

D["The Stockade"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\TheStockade\\TheStockade1_", mapID = 225, patches = { { tex = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\MapPatches\\TheStockade1_s1", x0 = 0.7685, y0 = 0.4311, x1 = 0.8024, y1 = 0.482 } } },
  },
  areas = {},
  markers = {
    { floor = 1, x = 0.5, y = 0.815, label = "Entrance" },
  },
  bosses = {
    { name = "Targorr the Dread", floor = 1, x = 0.44, y = 0.445, portrait = 517 },
    { name = "Targorr the Dread", floor = 1, x = 0.499, y = 0.205, portrait = 517, alt = true },
    { name = "Targorr the Dread", floor = 1, x = 0.31, y = 0.413, portrait = 517, alt = true },
    { name = "Targorr the Dread", floor = 1, x = 0.569, y = 0.544, portrait = 517, alt = true },
    { name = "Kam Deepfury", floor = 1, x = 0.692, y = 0.288, portrait = 825 },
    { name = "Hamhock", floor = 1, x = 0.78, y = 0.457, portrait = 3250 },
    { name = "Bazil Thredd", floor = 1, x = 0.864, y = 0.527, portrait = 1621 },
    { name = "Dextren Ward", floor = 1, x = 0.215, y = 0.261, portrait = 2149 },
    { name = "Bruegal Ironknuckle", floor = 1, x = 0.291, y = 0.444, portrait = 2142 },
  },
}

D["Uldaman"] = {
  floors = {
    { tiles = "Interface\\WorldMap\\Uldaman\\Uldaman1_", mapID = 230, label = "1" },
    { tiles = "Interface\\WorldMap\\Uldaman\\Uldaman2_", mapID = 231, label = "2" },
  },
  areas = {
    { name = "The Stone Vault", floor = 1, x = 0.25, y = 0.22, r = 0.06 },
    { name = "Hall of the Crafters", floor = 1, x = 0.45, y = 0.19, r = 0.07 },
    { name = "Dig Three", floor = 1, x = 0.28, y = 0.36, r = 0.05 },
    { name = "Temple Hall", floor = 1, x = 0.47, y = 0.43, r = 0.05 },
    { name = "Echomok Cavern", floor = 1, x = 0.28, y = 0.58, r = 0.06 },
    { name = "Hall of the Keepers", floor = 1, x = 0.59, y = 0.7, r = 0.08 },
    { name = "Map Chamber", floor = 1, x = 0.4, y = 0.75, r = 0.06 },
    { name = "Dig Two", floor = 1, x = 0.57, y = 0.92, r = 0.05 },
    { name = "Khaz'goroth's Seat", floor = 2, x = 0.55, y = 0.5, r = 0.1 },
  },
  markers = {
    { floor = 1, x = 0.679, y = 0.725, label = "Entrance" },
  },
  bosses = {
    { name = "The Lost Dwarves", floor = 1, x = 0.584, y = 0.92, portrait = 5710 },
    { name = "Revelosh", floor = 1, x = 0.534, y = 0.725, portrait = 5945 },
    { name = "Ironaya", floor = 1, x = 0.372, y = 0.739, portrait = 6089 },
    { name = "Obsidian Sentinel", floor = 1, x = 0.287, y = 0.601, portrait = 5285 },
    { name = "Ancient Stone Keeper", floor = 1, x = 0.475, y = 0.44, portrait = 10798 },
    { name = "Galgann Firehammer", floor = 1, x = 0.267, y = 0.327, portrait = 6059 },
    { name = "Grimlok", floor = 1, x = 0.219, y = 0.256, portrait = 11165 },
    { name = "Archaedas", floor = 2, x = 0.553, y = 0.504, portrait = 5988 },
  },
}

D["Upper Blackrock Spire"] = {
  floors = {
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\UpperBlackrockSpireMap", texRight = 1, texBottom = 0.667 },
  },
  areas = {
    { name = "Hall of Binding", floor = 1, x = 0.13, y = 0.27, r = 0.07 },
    { name = "The Rookery", floor = 1, x = 0.17, y = 0.4, r = 0.07 },
    { name = "Dragonspire Hall", floor = 1, x = 0.15, y = 0.75, r = 0.08 },
    { name = "Blackrock Stadium", floor = 1, x = 0.61, y = 0.33, r = 0.08 },
    { name = "Hall of Blackhand", floor = 1, x = 0.45, y = 0.4, r = 0.07 },
    { name = "The Furnace", floor = 1, x = 0.78, y = 0.6, r = 0.07 },
    { name = "Spire Throne", floor = 1, x = 0.45, y = 0.72, r = 0.07 },
  },
  markers = {
    { floor = 1, x = 0.186, y = 0.855, label = "Entrance" },
  },
  bosses = {
    { name = "Pyroguard Emberseer", floor = 1, x = 0.131, y = 0.289, portrait = 2172 },
    { name = "Solakar Flamewreath", floor = 1, x = 0.226, y = 0.416, portrait = 9581 },
    { name = "Jed Runewatcher", floor = 1, x = 0.479, y = 0.438, portrait = 9686 },
    { name = "Goraluk Anvilcrack", floor = 1, x = 0.43, y = 0.438, portrait = 10222 },
    { name = "Gyth", floor = 1, x = 0.615, y = 0.394, portrait = 9806 },
    { name = "Warchief Rend Blackhand", floor = 1, x = 0.615, y = 0.433, portrait = 9778 },
    { name = "The Beast", floor = 1, x = 0.794, y = 0.506, portrait = 10193 },
    { name = "Lord Valthalak", floor = 1, x = 0.807, y = 0.564, portrait = 14308 },
    { name = "General Drakkisath", floor = 1, x = 0.459, y = 0.73, portrait = 10115 },
  },
}

D["Zul'Farrak"] = {
  floors = {
    { art = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\ZulFarrakMap", texRight = 1, texBottom = 0.667 },
  },
  areas = {},
  markers = {
    { floor = 1, x = 0.552, y = 0.88, label = "Entrance" },
  },
  bosses = {
    { name = "Antu'sul", floor = 1, x = 0.646, y = 0.276, portrait = 7353 },
    { name = "Witch Doctor Zum'rah", floor = 1, x = 0.442, y = 0.176, portrait = 6434 },
    { name = "Shadowpriest Sezz'ziz", floor = 1, x = 0.296, y = 0.174, portrait = 6441 },
    { name = "Sergeant Bly", floor = 1, x = 0.31, y = 0.16, portrait = 6433 },
    { name = "Theka the Martyr", floor = 1, x = 0.528, y = 0.269, portrait = 6696 },
    { name = "Hydromancer Velratha", floor = 1, x = 0.289, y = 0.366, portrait = 6685 },
    { name = "Gahz'rilla", floor = 1, x = 0.312, y = 0.414, portrait = 7271 },
    { name = "Zerillis", floor = 1, x = 0.548, y = 0.401, portrait = 9293 },
    { name = "Sandarr Dunereaver", floor = 1, x = 0.524, y = 0.428, portrait = 9291 },
    { name = "Chief Ukorz Sandscalp", floor = 1, x = 0.422, y = 0.329, portrait = 6439 },
    { name = "Ruuzlu", floor = 1, x = 0.423, y = 0.329, portrait = 6687 },
  },
}
