-- Overview data for each dungeon.
-- Map art and boss spots come from ForeverDungeonJournal. The map images are
-- loaded straight from that addon's folder (visible art is 1002x668 inside a
-- 1024x1024 texture), so Top Ramen Map doesn't ship copies of them.
-- Areas are the names the game shows above the minimap, placed on the
-- names printed on each map; they are approximate. Ctrl-click the overview
-- in game to place (or move) the area you're standing in.
-- portrait = display ID of the journal's boss portrait.
local _, ns = ...
ns.DUNGEONS = ns.DUNGEONS or {}
local D = ns.DUNGEONS
local FDJ = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\"
local MAPS = FDJ .. "Maps\\"
local TR, TB = 1002 / 1024, 668 / 1024

local function Floor(file, mapID, label)
  return { art = MAPS .. file, texRight = TR, texBottom = TB, mapID = mapID, label = label }
end

---------------------------------------------------------------------------
D["Wailing Caverns"] = {
  floors = { Floor("WailingCavernsFull", 279) },
  areas = {
    { name = "Pit of Fangs",           floor = 1, x = 0.140, y = 0.420, r = 0.120 },
    { name = "Dreamer's Rock",         floor = 1, x = 0.345, y = 0.140, r = 0.075 },
    { name = "Screaming Gully",        floor = 1, x = 0.400, y = 0.380, r = 0.110 },
    { name = "Crag of the Everliving", floor = 1, x = 0.630, y = 0.620, r = 0.130 },
    { name = "Winding Chasm",          floor = 1, x = 0.810, y = 0.330, r = 0.120 },
  },
  -- Walking net for dotted routes (floor 1). Corners, the area each is in,
  -- and which corners connect.
  entrance = "E",
  nodes = {
    E  = { 0.465, 0.590 },
    G1 = { 0.430, 0.450, "Screaming Gully" },
    A  = { 0.310, 0.430, "Screaming Gully" },
    K  = { 0.385, 0.350, "Screaming Gully" },
    G2 = { 0.495, 0.400, "Screaming Gully" },
    D1 = { 0.370, 0.240, "Dreamer's Rock" },
    M  = { 0.345, 0.130, "Dreamer's Rock" },
    P1 = { 0.215, 0.440, "Pit of Fangs" },
    P2 = { 0.130, 0.430, "Pit of Fangs" },
    C  = { 0.155, 0.570, "Pit of Fangs" },
    V  = { 0.545, 0.460, "Crag of the Everliving" },
    S  = { 0.615, 0.535, "Crag of the Everliving" },
    F  = { 0.580, 0.600, "Crag of the Everliving" },
    X1 = { 0.700, 0.450, "Crag of the Everliving" },
    X2 = { 0.770, 0.350, "Winding Chasm" },
    PY = { 0.856, 0.289, "Winding Chasm" },
    Y1 = { 0.790, 0.600 },
    Y2 = { 0.860, 0.700 },
    SK = { 0.927, 0.792 },
  },
  edges = {
    { "E", "G1" }, { "G1", "A" }, { "G1", "K" }, { "G1", "G2" }, { "K", "G2" },
    { "A", "P1" }, { "P1", "P2" }, { "P2", "C" },
    { "K", "D1" }, { "D1", "M" },
    { "G2", "V" }, { "V", "S" }, { "S", "F" }, { "S", "X1" },
    { "X1", "X2" }, { "X2", "PY" },
    { "X1", "Y1" }, { "Y1", "Y2" }, { "Y2", "SK" },
  },
  bosses = {
    { name = "Lady Anacondra",        portrait = 4313, floor = 1, x = 0.310, y = 0.430, node = "A" },
    { name = "Kresh",                 portrait = 5126, floor = 1, x = 0.385, y = 0.350, node = "K" },
    { name = "Lord Cobrahn",          portrait = 4213, floor = 1, x = 0.155, y = 0.570, node = "C" },
    { name = "Lord Pythas",           portrait = 4214, floor = 1, x = 0.856, y = 0.289, node = "PY" },
    { name = "Skum",                  portrait = 4203, floor = 1, x = 0.927, y = 0.792, node = "SK" },
    { name = "Deviate Faerie Dragon", portrait = 1267, floor = 1, x = 0.580, y = 0.600, node = "F", rare = true },
    { name = "Lord Serpentis",        portrait = 4215, floor = 1, x = 0.615, y = 0.535, node = "S" },
    { name = "Verdan the Everliving", portrait = 4256, floor = 1, x = 0.545, y = 0.460, node = "V" },
    { name = "Mutanus the Devourer",  portrait = 4088, floor = 1, x = 0.345, y = 0.130, node = "M" },
  },
}

---------------------------------------------------------------------------
-- No area names are printed on this map: place them in game with Ctrl-click.
D["Razorfen Kraul"] = {
  floors = { Floor("RazorfenKraul1", 301) },
  areas = {},
  bosses = {
    { name = "Roogug",               portrait = 6110, floor = 1, x = 0.646, y = 0.430 },
    { name = "Aggem Thorncurse",     portrait = 6097, floor = 1, x = 0.808, y = 0.521 },
    { name = "Death Speaker Jargba", portrait = 4644, floor = 1, x = 0.876, y = 0.419 },
    { name = "Earthcaller Halmgar",  portrait = 6102, floor = 1, x = 0.498, y = 0.473 },
    { name = "Overlord Ramtusk",     portrait = 4652, floor = 1, x = 0.576, y = 0.313 },
    { name = "Charlga Razorflank",   portrait = 4642, floor = 1, x = 0.221, y = 0.313 },
    { name = "Agathelos the Raging", portrait = 2450, floor = 1, x = 0.082, y = 0.686 },
  },
}

---------------------------------------------------------------------------
D["Scarlet Monastery: Graveyard"] = {
  floors = { Floor("ScarletMonastery1", 302) },
  areas = {
    { name = "Chamber of Atonement", floor = 1, x = 0.700, y = 0.620, r = 0.070 },
    { name = "Forlorn Cloister",     floor = 1, x = 0.400, y = 0.555, r = 0.150 },
    { name = "Honor's Tomb",         floor = 1, x = 0.245, y = 0.560, r = 0.050 },
  },
  bosses = {
    { name = "Interrogator Vishas", portrait = 2044,  floor = 1, x = 0.724, y = 0.600 },
    { name = "Bloodmage Thalnos",   portrait = 11396, floor = 1, x = 0.246, y = 0.566 },
  },
}

D["Scarlet Monastery: Library"] = {
  floors = { Floor("ScarletMonastery2", 303) },
  areas = {
    { name = "Huntsman's Cloister", floor = 1, x = 0.320, y = 0.560, r = 0.150 },
    { name = "Gallery of Treasures", floor = 1, x = 0.560, y = 0.250, r = 0.130 },
    { name = "Athenaeum",           floor = 1, x = 0.865, y = 0.620, r = 0.120 },
  },
  bosses = {
    { name = "Houndmaster Loksey", portrait = 2040, floor = 1, x = 0.302, y = 0.846 },
    { name = "Arcanist Doan",      portrait = 5266, floor = 1, x = 0.835, y = 0.740 },
  },
}

D["Scarlet Monastery: Armory"] = {
  floors = { Floor("ScarletMonastery3", 304) },
  areas = {
    { name = "Training Grounds",  floor = 1, x = 0.665, y = 0.830, r = 0.080 },
    { name = "Footman's Armory",  floor = 1, x = 0.725, y = 0.570, r = 0.075 },
    { name = "Crusader's Armory", floor = 1, x = 0.725, y = 0.330, r = 0.080 },
    { name = "Hall of Champions", floor = 1, x = 0.785, y = 0.110, r = 0.060 },
  },
  bosses = {
    { name = "Herod", portrait = 2041, floor = 1, x = 0.785, y = 0.118 },
  },
}

D["Scarlet Monastery: Cathedral"] = {
  floors = { Floor("ScarletMonastery4", 305) },
  areas = {
    { name = "Chapel Gardens",    floor = 1, x = 0.500, y = 0.700, r = 0.130 },
    { name = "Crusader's Chapel", floor = 1, x = 0.490, y = 0.260, r = 0.110 },
  },
  bosses = {
    { name = "High Inquisitor Fairbanks",  portrait = 2605, floor = 1, x = 0.555, y = 0.250 },
    { name = "Scarlet Commander Mograine", portrait = 2042, floor = 1, x = 0.490, y = 0.285 },
    { name = "High Inquisitor Whitemane",  portrait = 2043, floor = 1, x = 0.490, y = 0.165 },
  },
}

---------------------------------------------------------------------------
-- Four levels. Some rooms appear on two levels (the same name); the level
-- you're on is shown when the game tells it, else the one you last viewed.
D["Gnomeregan"] = {
  floors = {
    Floor("Gnomeregan1", 226, "1"), Floor("Gnomeregan2", 227, "2"),
    Floor("Gnomeregan3", 228, "3"), Floor("Gnomeregan4", 229, "4"),
  },
  areas = {
    { name = "The Hall of Gears", floor = 1, x = 0.490, y = 0.400, r = 0.100 },
    { name = "The Clean Zone",    floor = 1, x = 0.380, y = 0.680, r = 0.070 },
    { name = "The Dormitory",     floor = 1, x = 0.480, y = 0.860, r = 0.070 },
    { name = "Launch Bay",        floor = 2, x = 0.240, y = 0.650, r = 0.140 },
    { name = "The Hall of Gears", floor = 2, x = 0.750, y = 0.450, r = 0.100 },
    { name = "The Dormitory",     floor = 2, x = 0.780, y = 0.750, r = 0.080 },
    { name = "Launch Bay",        floor = 3, x = 0.275, y = 0.270, r = 0.090 },
    { name = "Engineering Labs",  floor = 3, x = 0.440, y = 0.760, r = 0.100 },
    { name = "Tinkers' Court",    floor = 4, x = 0.310, y = 0.290, r = 0.100 },
    { name = "Engineering Labs",  floor = 4, x = 0.670, y = 0.810, r = 0.070 },
  },
  bosses = {
    { name = "Grubbis",               portrait = 144378, floor = 1, x = 0.776, y = 0.671 },
    { name = "Viscous Fallout",       portrait = 5497,   floor = 2, x = 0.760, y = 0.469 },
    { name = "Electrocutioner 6000",  portrait = 6915,   floor = 2, x = 0.245, y = 0.684 },
    { name = "Crowd Pummeler 9-60",   portrait = 6774,   floor = 3, x = 0.434, y = 0.883 },
    { name = "Mekgineer Thermaplugg", portrait = 6980,   floor = 4, x = 0.315, y = 0.299 },
  },
}

---------------------------------------------------------------------------
-- The Drowned City (Forever). Two levels: the city, and Atal'Byzal below,
-- reached by swimming down. Boss spots and the swim/exit points are the
-- Journal's (OMGmacros's boss map and M's marked maps).
D["The Drowned City"] = {
  floors = {
    { art = FDJ .. "DrownedCityMap",          texRight = 1, texBottom = 683 / 1024, label = "City" },
    { art = FDJ .. "DrownedCityAtalByzalMap", texRight = 1, texBottom = 683 / 1024, label = "Atal'Byzal" },
  },
  areas = {
    { name = "Sunken Hollow",        floor = 1, x = 0.800, y = 0.500, r = 0.100 },
    { name = "Altar of the Serpent", floor = 1, x = 0.550, y = 0.290, r = 0.075 },
    { name = "Eternal Amphitheater", floor = 1, x = 0.320, y = 0.510, r = 0.080 },
    { name = "Abyssal Dais",         floor = 1, x = 0.170, y = 0.540, r = 0.070 },
    { name = "Deep Archives",        floor = 1, x = 0.550, y = 0.730, r = 0.100 },
    { name = "Atal'Byzal",           floor = 2, x = 0.500, y = 0.600, r = 0.220 },
  },
  -- Points of interest. to = the level a click takes you to.
  markers = {
    { floor = 1, x = 0.846, y = 0.521, label = "Entrance" },
    { floor = 1, x = 0.575, y = 0.599, label = "Swim down here to Atal'Byzal", to = 2, color = { 0.30, 0.85, 1.00 } },
    { floor = 1, x = 0.590, y = 0.837, label = "Swim down here to Atal'Byzal (by Umbra)", to = 2, color = { 0.30, 0.85, 1.00 } },
    { floor = 2, x = 0.679, y = 0.113, label = "Way up: shark exit (danger)", to = 1, color = { 1.00, 0.25, 0.20 } },
    { floor = 2, x = 0.262, y = 0.792, label = "Way up: safe exit", to = 1, color = { 0.35, 1.00, 0.40 } },
  },
  bosses = {
    { name = "Zul'Alai",             portrait = 144475, floor = 1, x = 0.697, y = 0.572 },
    { name = "Primeval Elemental",   portrait = 129945, floor = 2, x = 0.667, y = 0.550 },
    { name = "Umbra",                portrait = 144022, floor = 1, x = 0.545, y = 0.829 },
    { name = "\"Pyromancer\" Braxton", portrait = 142457, floor = 1, x = 0.495, y = 0.368 },
    { name = "Var'Taka",             portrait = 144487, floor = 1, x = 0.514, y = 0.689 },
    { name = "Captain Dreadrise",    portrait = 142144, floor = 1, x = 0.546, y = 0.344 },
    { name = "Deathless Marrow",     portrait = 142245, floor = 1, x = 0.349, y = 0.536 },
    { name = "Min'loth the Serpent", portrait = 142322, floor = 1, x = 0.196, y = 0.539 },
  },
}

---------------------------------------------------------------------------
-- Krol'dok Stronghold (Forever). Boss spots are the Journal's (falling/
-- Ekiroth's numbered map, bosses in fighting order, with M's Nar'gurk
-- correction). No area names are printed on this map: place them in game
-- with Ctrl-click. Tunk and Zalfan Moonshadow are quest targets, not bosses.
D["Krol'dok Stronghold"] = {
  floors = { { art = FDJ .. "KroldokMap", texRight = 1, texBottom = 683 / 1024 } },
  areas = {},
  markers = {
    { floor = 1, x = 0.205, y = 0.807, label = "Entrance" },
  },
  bosses = {
    { name = "Slavecrusher Grox",         portrait = 141217, floor = 1, x = 0.331, y = 0.703 },
    { name = "Twilight Commander Zarmok", portrait = 141219, floor = 1, x = 0.392, y = 0.734 },
    { name = "War Handler Ashka",         portrait = 141443, floor = 1, x = 0.621, y = 0.527 },
    { name = "Nar'gurk",                  portrait = 141215, floor = 1, x = 0.381, y = 0.526 },
    { name = "Bossman Toof",              portrait = 14424,  floor = 1, x = 0.617, y = 0.432 },
    { name = "Overlord Mugg",             portrait = 141218, floor = 1, x = 0.688, y = 0.242 },
    { name = "Tunk",              portrait = 144671, floor = 1, x = 0.691, y = 0.493, quest = true,
      note = "ogre blacksmith, starts the Key Ingredients chain" },
    { name = "Zalfan Moonshadow", portrait = 145448, floor = 1, x = 0.430, y = 0.495, quest = true,
      note = "Vengeance of the Highborne; he walks around" },
  },
}
