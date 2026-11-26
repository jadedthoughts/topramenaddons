-- Top Ramen Gear: proc rates for WoW Forever, measured by the WoWSims team
-- From WoWSims Forever (https://github.com/wowsims/forever), MIT License, Copyright (c) 2022 wowsims team:
-- tools/database/overrides/weapon_procs.go and gear_proc_rates.go at commit d514485 (26 Nov 2026).
-- src: "EV-n" = measured on Forever (their docs/evidence/EV-n, from Warcraft Logs and local combat logs);
-- "observed" = their looser fit; "vanilla-carryover" / "tbc-carryover" = an older version's rate, not yet
-- checked on Forever. The game files state no rate for these items; without this table Gear assumes 1 PPM.
-- ppm = procs per minute (chance per landed hit = ppm x speed / 60); chance = a flat chance per landed hit.
local _, ns = ...

ns.PROC_RATES = {
  [647] = { ppm = 1.05, src = "observed" }, -- Destiny
  [754] = { ppm = 1, src = "EV-0136" }, -- Shortsword of Vengeance
  [809] = { ppm = 1, src = "EV-0136" }, -- Bloodrazor
  [810] = { ppm = 4.6, src = "observed" }, -- Hammer of the Northern Wind
  [811] = { ppm = 1.9, src = "EV-0146" }, -- Axe of the Deep Woods
  [869] = { ppm = 2.75, src = "EV-0136" }, -- Dazzling Longsword
  [870] = { ppm = 0.9, src = "observed" }, -- Fiery War Axe
  [871] = { ppm = 1.75, src = "observed" }, -- Flurry Axe
  [880] = { ppm = 1.4, src = "vanilla-carryover" }, -- Staff of Horrors
  [899] = { ppm = 1.1, src = "observed" }, -- Venom Web Fang
  [934] = { ppm = 1.25, src = "EV-0136" }, -- Stalvan's Reaper
  [937] = { ppm = 1, src = "EV-0136" }, -- Black Duskwood Staff
  [1263] = { ppm = 0.95, src = "EV-0132" }, -- Brain Hacker
  [1265] = { ppm = 0.95, src = "EV-0136" }, -- Scorpion Sting
  [1318] = { ppm = 1.7, src = "observed" }, -- Night Reaver
  [1481] = { ppm = 2.05, src = "EV-0136" }, -- Grimclaw
  [1726] = { ppm = 0.85, src = "observed" }, -- Poison-tipped Bone Spear
  [1727] = { ppm = 1.05, src = "EV-0136" }, -- Sword of Decay
  [1982] = { ppm = 1.8, src = "observed" }, -- Nightblade
  [2000] = { ppm = 0.95, src = "observed" }, -- Archeus
  [2099] = { ppm = 4, src = "observed" }, -- Dwarven Hand Cannon
  [2163] = { ppm = 1.05, src = "observed" }, -- Shadowblade
  [2164] = { ppm = 1.5, src = "EV-0136" }, -- Gut Ripper
  [2243] = { ppm = 1, src = "vanilla-carryover" }, -- Hand of Edward the Odd
  [2256] = { ppm = 0.95, src = "observed" }, -- Skeletal Club
  [2291] = { ppm = 0.95, src = "EV-0136" }, -- Kang the Decapitator
  [2299] = { ppm = 0.95, src = "EV-0136" }, -- Burning War Axe
  [2825] = { ppm = 4.9, src = "EV-0136" }, -- Bow of Searing Arrows
  [2912] = { ppm = 1.05, src = "EV-0136" }, -- Claw of the Shadowmancer
  [2915] = { ppm = 0.95, src = "observed" }, -- Taran Icebreaker
  [2942] = { ppm = 1.95, src = "EV-0136" }, -- Iron Knuckles
  [3078] = { ppm = 2.1, src = "observed" }, -- Naga Heartpiercer
  [3194] = { ppm = 1.85, src = "observed" }, -- Black Malice
  [3336] = { ppm = 0.95, src = "observed" }, -- Flesh Piercer
  [3822] = { ppm = 2, src = "observed" }, -- Runic Darkblade
  [4090] = { ppm = 2.15, src = "EV-0183" }, -- Mug O' Hurt
  [4446] = { ppm = 3.9, src = "observed" }, -- Blackvenom Blade
  [4449] = { ppm = 2.1, src = "observed" }, -- Naraxis' Fang
  [5182] = { ppm = 0.5, src = "vanilla-carryover" }, -- Shiver Blade
  [5197] = { ppm = 1.95, src = "EV-0136" }, -- Cookie's Tenderizer
  [5243] = { ppm = 4.05, src = "EV-0136" }, -- Firebelcher
  [5752] = { ppm = 2.1, src = "observed" }, -- Wyvern Tailspike
  [5756] = { ppm = 2, src = "EV-0136" }, -- Sliverblade
  [6220] = { ppm = 1.55, src = "EV-0119" }, -- Meteor Shard
  [6469] = { ppm = 1.85, src = "observed" }, -- Venomstrike
  [6472] = { ppm = 1.75, src = "EV-0119" }, -- Stinging Viper
  [6622] = { ppm = 1.95, src = "EV-0175" }, -- Sword of Zeal
  [6660] = { ppm = 1.05, src = "observed" }, -- Julie's Dagger
  [6681] = { ppm = 3.1, src = "observed" }, -- Thornspike
  [6738] = { ppm = 1, src = "observed" }, -- Bleeding Crescent
  [6831] = { ppm = 2, src = "EV-0136" }, -- Black Menace
  [6904] = { ppm = 1.45, src = "EV-0119" }, -- Bite of Serra'kis
  [6909] = { ppm = 2, src = "observed" }, -- Strike of the Hydra
  [6953] = { ppm = 2.2, src = "EV-0136" }, -- Verigan's Fist
  [7710] = { ppm = 1.95, src = "EV-0136" }, -- Loksey's Training Stick
  [7717] = { ppm = 1, src = "EV-0119" }, -- Ravager
  [7730] = { ppm = 2, src = "observed" }, -- Cobalt Crusher
  [7753] = { ppm = 0.9, src = "EV-0136" }, -- Bloodspiller
  [7961] = { ppm = 2, src = "EV-0136" }, -- Phantom Blade
  [8006] = { ppm = 3.55, src = "EV-0136" }, -- The Ziggler
  [8190] = { ppm = 1, src = "observed" }, -- Hanzo Sword
  [8223] = { ppm = 1.05, src = "observed" }, -- Blade of the Basilisk
  [8225] = { ppm = 2.05, src = "EV-0136" }, -- Tainted Pierce
  [8708] = { ppm = 1.85, src = "observed" }, -- Hammer of Expertise
  [9372] = { ppm = 1.45, src = "EV-0136" }, -- Sul'thraze the Lasher
  [9379] = { ppm = 2.05, src = "EV-0136" }, -- Sang'thraze the Deflector
  [9412] = { ppm = 4, src = "observed" }, -- Galgann's Fireblaster
  [9418] = { ppm = 1.95, src = "EV-0003" }, -- Stoneslayer
  [9425] = { ppm = 1, src = "EV-0136" }, -- Pendulum of Doom
  [9446] = { ppm = 3.95, src = "EV-0136" }, -- Electrocutioner Leg
  [9453] = { ppm = 1.8, src = "EV-0119" }, -- Toxic Revenger
  [9467] = { ppm = 2, src = "EV-0136" }, -- Gahz'rilla Fang
  [9475] = { ppm = 1.8, src = "EV-0153" }, -- Diabolic Skiver
  [9477] = { ppm = 1, src = "EV-0136" }, -- The Chief's Enforcer
  [9478] = { ppm = 2, src = "EV-0022" }, -- Ripsaw
  [9485] = { ppm = 0.95, src = "observed" }, -- Vibroblade
  [9486] = { ppm = 1.8, src = "EV-0136" }, -- Supercharger Battle Axe
  [9639] = { ppm = 2, src = "EV-0022" }, -- The Hand of Antu'sul
  [9651] = { ppm = 1.9, src = "EV-0136" }, -- Gryphon Rider's Stormhammer
  [10567] = { ppm = 2.85, src = "observed" }, -- Quillshooter
  [10623] = { ppm = 2.95, src = "EV-0186" }, -- Winter's Bite
  [10626] = { ppm = 2, src = "observed" }, -- Ragehammer
  [10750] = { ppm = 1.5, src = "EV-0003" }, -- Lifeforce Dirk
  [10758] = { ppm = 1.95, src = "EV-0136" }, -- X'caliboar
  [10761] = { ppm = 2.95, src = "EV-0136" }, -- Coldrage Dagger
  [10772] = { ppm = 2, src = "EV-0136" }, -- Glutton's Cleaver
  [10797] = { ppm = 2.05, src = "EV-0136" }, -- Firebreather
  [10803] = { ppm = 2, src = "EV-0136" }, -- Blade of the Wretched
  [10804] = { ppm = 3.05, src = "EV-0136" }, -- Fist of the Damned
  [10805] = { ppm = 1.8, src = "EV-0136" }, -- Eater of the Dead
  [10847] = { ppm = 4.5, src = "EV-0021" }, -- Dragon's Call
  [11086] = { ppm = 2.9, src = "EV-0022" }, -- Jang'thraze the Protector
  [11121] = { ppm = 2.95, src = "EV-0136" }, -- Darkwater Talwar
  [11635] = { ppm = 1.95, src = "observed" }, -- Hookfang Shanker
  [11744] = { ppm = 3.2, src = "EV-0003" }, -- Bloodfist
  [11803] = { ppm = 2, src = "EV-0003" }, -- Force of Magma
  [11809] = { ppm = 1.9, src = "EV-0136" }, -- Flame Wrath
  [11816] = { ppm = 2, src = "EV-0153" }, -- Angerforge's Battle Axe
  [11817] = { ppm = 2, src = "EV-0136" }, -- Lord General's Sword
  [11902] = { ppm = 2, src = "observed" }, -- Linken's Sword of Mastery
  [11920] = { ppm = 3.65, src = "EV-0153" }, -- Wraith Scythe
  [12463] = { ppm = 1.5, src = "EV-0003" }, -- Drakefang Butcher
  [12469] = { ppm = 4.8, src = "EV-0145" }, -- Mutilator
  [12531] = { ppm = 2.8, src = "observed" }, -- Searing Needle
  [12582] = { ppm = 1.7, src = "EV-0003" }, -- Keris of Zul'Serak
  [12583] = { ppm = 1, src = "observed" }, -- Blackhand Doomsaw
  [12590] = { ppm = 0.55, src = "EV-0136" }, -- Felstriker
  [12592] = { ppm = 1, src = "EV-0125" }, -- Blackblade of Shahram
  [12777] = { ppm = 1, src = "vanilla-carryover" }, -- Blazing Rapier
  [12790] = { ppm = 1, src = "vanilla-carryover" }, -- Arcanite Champion
  [12791] = { ppm = 1.95, src = "observed" }, -- Barman Shanker
  [12792] = { ppm = 1, src = "vanilla-carryover" }, -- Volcanic Hammer
  [12794] = { ppm = 0.9, src = "observed" }, -- Masterwork Stormhammer
  [12795] = { ppm = 1, src = "vanilla-carryover" }, -- Blood Talon
  [12797] = { ppm = 1, src = "vanilla-carryover" }, -- Frostguard
  [12798] = { ppm = 1, src = "tbc-carryover" }, -- Annihilator
  [12969] = { ppm = 0.9, src = "EV-0003" }, -- Seeping Willow
  [12974] = { ppm = 0.6, src = "EV-0119" }, -- The Black Knight
  [12992] = { ppm = 1.9, src = "EV-0136" }, -- Searing Blade
  [13016] = { ppm = 1, src = "EV-0136" }, -- Killmaim
  [13032] = { ppm = 1, src = "EV-0136" }, -- Sword of Corruption
  [13035] = { ppm = 1, src = "EV-0136" }, -- Serpent Slicer
  [13040] = { ppm = 2.7, src = "EV-0119" }, -- Heartseeking Crossbow
  [13051] = { ppm = 1, src = "observed" }, -- Witchfury
  [13053] = { ppm = 0.75, src = "vanilla-carryover" }, -- Doombringer
  [13054] = { ppm = 0.9, src = "observed" }, -- Grim Reaper
  [13057] = { ppm = 0.9, src = "observed" }, -- Bloodpike
  [13060] = { ppm = 3, src = "vanilla-carryover" }, -- The Needler
  [13146] = { ppm = 3.75, src = "observed" }, -- Shell Launcher Shotgun
  [13183] = { ppm = 1.7, src = "EV-0003" }, -- Venomspitter
  [13198] = { ppm = 2, src = "EV-0177" }, -- Hurd Smasher
  [13204] = { ppm = 3, src = "observed" }, -- Bashguuder
  [13218] = { ppm = 1.05, src = "observed" }, -- Fang of the Crystal Spider
  [13246] = { ppm = 1.05, src = "EV-0126" }, -- Argent Avenger
  [13285] = { ppm = 1.95, src = "EV-0136" }, -- The Blackrock Slicer
  [13286] = { ppm = 1.95, src = "observed" }, -- Rivenspike
  [13348] = { ppm = 1.1, src = "EV-0003" }, -- Demonshear
  [13361] = { ppm = 1.9, src = "EV-0121" }, -- Skullforge Reaver
  [13393] = { ppm = 2, src = "EV-0150" }, -- Malown's Slam
  [13399] = { ppm = 2.05, src = "observed" }, -- Gargoyle Shredder Talons
  [13401] = { ppm = 2.15, src = "EV-0136" }, -- The Cruel Hand of Timmy
  [13952] = { ppm = 2, src = "EV-0136" }, -- Iceblade Hacker
  [13953] = { ppm = 1.45, src = "observed" }, -- Silent Fang
  [13983] = { ppm = 1.9, src = "EV-0003" }, -- Gravestone War Axe
  [13984] = { ppm = 2, src = "observed" }, -- Darrowspike
  [14024] = { ppm = 2, src = "observed" }, -- Frightalon
  [14145] = { ppm = 2.05, src = "EV-0136" }, -- Cursed Felblade
  [14487] = { ppm = 1.95, src = "EV-0136" }, -- Bonechill Hammer
  [14531] = { ppm = 3, src = "observed" }, -- Frightskull Shaft
  [14541] = { ppm = 1.9, src = "EV-0179" }, -- Barovian Family Sword
  [15418] = { ppm = 1.85, src = "observed" }, -- Shimmering Platinum Warhammer
  [15814] = { ppm = 1.05, src = "observed" }, -- Hameya's Slayer
  [17073] = { ppm = 2.1, src = "vanilla-carryover" }, -- Earthshaker
  [17182] = { ppm = 0.7, src = "vanilla-carryover" }, -- Sulfuras, Hand of Ragnaros
  [17193] = { ppm = 1, src = "vanilla-carryover" }, -- Sulfuron Hammer
  [17223] = { ppm = 1.5, src = "vanilla-carryover" }, -- Thunderstrike
  [17704] = { ppm = 1.2, src = "vanilla-carryover" }, -- Edge of Winter
  [17705] = { ppm = 1, src = "EV-0022" }, -- Thrash Blade
  [17730] = { ppm = 1.2, src = "EV-0003" }, -- Gatorbite Axe
  [17733] = { ppm = 1, src = "vanilla-carryover" }, -- Fist of Stone
  [17738] = { ppm = 2.05, src = "observed" }, -- Claw of Celebras
  [17752] = { ppm = 1.95, src = "observed" }, -- Satyr's Lash
  [17753] = { ppm = 3.5, src = "EV-0003" }, -- Verdant Keeper's Aim
  [17766] = { ppm = 1.8, src = "EV-0003" }, -- Princess Theradras' Scepter
  [17943] = { ppm = 3.2, src = "EV-0003" }, -- Fist of Stone
  [18324] = { ppm = 1.95, src = "EV-0136" }, -- Waveslicer
  [18388] = { ppm = 1.7, src = "EV-0003" }, -- Stoneshatter
  [18483] = { ppm = 4.15, src = "EV-0136" }, -- Mana Channeling Wand
  [18498] = { ppm = 1.95, src = "observed" }, -- Hedgecutter
  [19019] = { ppm = 6, src = "vanilla-carryover" }, -- Thunderfury, Blessed Blade of the Windseeker
  [19099] = { ppm = 1.3, src = "observed" }, -- Glacial Blade
  [19100] = { ppm = 1.25, src = "observed" }, -- Electrified Dagger
  [19169] = { ppm = 2, src = "vanilla-carryover" }, -- Nightfall
  [19170] = { ppm = 0.4, src = "vanilla-carryover" }, -- Ebon Hand
  [19287] = { ppm = 2, src = "vanilla-carryover" }, -- Darkmoon Card
  [19323] = { ppm = 1.05, src = "observed" }, -- The Unstoppable Force
  [19324] = { ppm = 0.55, src = "observed" }, -- The Lobotomizer
  [21134] = { ppm = 0.4, src = "vanilla-carryover" }, -- Dark Edge of Insanity
  [267369] = { ppm = 2.25, src = "EV-0136" }, -- Wolfsbane
  [272999] = { ppm = 3.05, src = "EV-0136" }, -- Barbaric Crossbow
  [273819] = { ppm = 2.95, src = "EV-0136" }, -- Boneslicer
  [273841] = { ppm = 1.8, src = "EV-0136" }, -- Twilight Maul
  [274265] = { ppm = 2, src = "EV-0136" }, -- Brush Cutter
  [274270] = { ppm = 1.1, src = "EV-0003" }, -- Weed Whacker
  [274271] = { ppm = 1.9, src = "observed" }, -- Deadhead Blade
  [274293] = { ppm = 1, src = "EV-0136" }, -- Spellsever Crossbow
  [274425] = { ppm = 3.75, src = "EV-0119" }, -- White Obsidian Wand
  [274484] = { ppm = 2.05, src = "EV-0136" }, -- Axe of Inevitable Ruin
  [274952] = { ppm = 1.85, src = "observed" }, -- Jom-jom's Gabbar
  [274963] = { ppm = 1.45, src = "EV-0122" }, -- Rot-Covered Harpoon
  [275439] = { ppm = 1.95, src = "observed" }, -- Blunderflame Bone Bow
  [275441] = { ppm = 2.3, src = "EV-0003" }, -- Cremation Longbow
  [276419] = { ppm = 3.6, src = "EV-0003" }, -- Lightcrest Hammer
  [279480] = { ppm = 1.5, src = "EV-0022" }, -- Bigger Rock on Bigger Stick
  [279852] = { ppm = 1.85, src = "EV-0050" }, -- Rock on Stick
  [279876] = { ppm = 2, src = "EV-0153" }, -- Plaguefang
  [279895] = { ppm = 2.9, src = "EV-0136" }, -- Ironforge Greathammer
  [281665] = { ppm = 2.95, src = "EV-0136" }, -- Twilight Forgehammer
  [282561] = { ppm = 5.25, src = "observed" }, -- Siegebreaker's Blaster
  [282703] = { ppm = 4, src = "observed" }, -- Needletooth's Needletooth
  [284386] = { ppm = 0.75, src = "observed" }, -- Whipfang's Skinsearer
  [285102] = { ppm = 3.65, src = "observed" }, -- Darkmist Dirk
  [285332] = { ppm = 2.45, src = "observed" }, -- Puncturing Spear
  [286430] = { ppm = 2, src = "EV-0136" }, -- Toofbreaker
  [286650] = { ppm = 1.95, src = "EV-0136" }, -- Pyromancer's Baton
  [287005] = { ppm = 0.6, src = "EV-0024" }, -- Sword of Dismemberment
  [11684] = { chance = 0.03, src = "EV-0119" }, -- Ironfoe
  [13243] = { ppm = 0.5, src = "EV-0126" }, -- Argent Defender (when struck)
  [260205] = { ppm = 2.95, src = "EV-0131" }, -- Highborne Research Tablet
  [280032] = { chance = 0.15, src = "EV-0202" }, -- Bolt's Charged Eyeball
}
