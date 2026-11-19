-- Top Ramen Explorer: finds the places you still need for Adventure > Explorer.
--
-- Two sources, both from the game itself:
--   1. The achievement data: which zones and which named areas you still need.
--   2. The zone maps: every patch of a zone map you haven't uncovered yet is an
--      area you haven't discovered. The addon samples each zone map on a grid,
--      groups the undiscovered samples into "spots", and points you at them.
local ADDON, ns = ...

ns.GOLD, ns.GREEN, ns.RED, ns.GREY, ns.WHITE = "|cffe0b04a", "|cff40d040", "|cffff5050", "|cff9d9d9d", "|cffffffff"
local GOLD, GREEN, GREY = ns.GOLD, ns.GREEN, ns.GREY

local GRID = 48 -- samples per side when scanning a zone map (48 x 48 = 2304 checks)

function ns.Print(msg) print(GOLD .. "Top Ramen Explorer|r: " .. tostring(msg)) end

---------------------------------------------------------------------------
-- saved settings
---------------------------------------------------------------------------
local DEFAULTS = { pins = true, autoNext = true, ignore = {}, found = {}, shared = {} }

local function initDB()
  TopRamenExplorerDB = TopRamenExplorerDB or {}
  for k, v in pairs(DEFAULTS) do
    if TopRamenExplorerDB[k] == nil then TopRamenExplorerDB[k] = (type(v) == "table") and {} or v end
  end
  ns.db = TopRamenExplorerDB
end

---------------------------------------------------------------------------
-- zone maps: name -> uiMapID
---------------------------------------------------------------------------
local zoneByName, zoneNames = nil, {}

local function norm(s) return (s or ""):lower():gsub("^the ", ""):gsub("[%s%p]", "") end

-- The Forever client can carry two maps with the same zone name: the classic one (Kalimdor 1414,
-- Eastern Kingdoms 1415) and the modern one (12, 13). Zones of the map family you are standing in
-- win, so "Stonetalon Mountains" resolves to the map you actually see.
local CLASSIC, MODERN = { 1414, 1415 }, { 12, 13 }

local function buildZones()
  if zoneByName then return end
  zoneByName = {}
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  -- climb from where you stand: remember your continent and the top map
  local id = C_Map.GetBestMapForUnit("player")
  local root, continent = id, nil
  local guard = 0
  while id and id > 0 and guard < 10 do
    local info = C_Map.GetMapInfo(id)
    if not info then break end
    if info.mapType == Enum.UIMapType.Continent and not continent then continent = id end
    root = id
    id = info.parentMapID
    guard = guard + 1
  end
  local first, second = CLASSIC, MODERN
  if continent == 12 or continent == 13 then first, second = MODERN, CLASSIC end
  local roots = {}
  if continent then roots[#roots + 1] = continent end
  for _, r in ipairs(first) do roots[#roots + 1] = r end
  for _, r in ipairs(second) do roots[#roots + 1] = r end
  roots[#roots + 1] = root
  for _, r in ipairs(roots) do
    if r and C_Map.GetMapInfo(r) then
      local kids = C_Map.GetMapChildrenInfo(r, Enum.UIMapType.Zone, true) or {}
      for _, z in ipairs(kids) do
        local key = norm(z.name)
        if not zoneByName[key] then
          zoneByName[key] = z.mapID
          zoneNames[z.mapID] = z.name
        end
      end
    end
  end
end

function ns.ZoneName(mapID)
  if zoneNames[mapID] then return zoneNames[mapID] end
  local info = C_Map.GetMapInfo(mapID)
  return info and info.name or ("map " .. tostring(mapID))
end

-- "Explore Stonetalon Mountains" -> "Stonetalon Mountains"
local function zoneNameOf(achName)
  local n = achName or ""
  for _, prefix in ipairs({ "^Explore ", "^Explorer of ", "^Exploring " }) do
    local stripped, hits = n:gsub(prefix, "")
    if hits > 0 then return stripped end
  end
  return n
end

local function zoneForAchievement(name)
  buildZones()
  return zoneByName[norm(zoneNameOf(name))] or zoneByName[norm(name)]
end

-- the Explorer achievement for a map, matched by the zone's NAME, so it works on whichever
-- copy of the map (classic or modern) you are looking at
function ns.AchFor(mapID)
  if not (mapID and ns.achByName) then return nil end
  return ns.achByName[norm(ns.ZoneName(mapID))]
end

function ns.SameZone(a, mapID)
  return a and mapID and a.zoneName and norm(a.zoneName) == norm(ns.ZoneName(mapID)) or false
end

---------------------------------------------------------------------------
-- achievements: Adventure > Explorer
---------------------------------------------------------------------------
local CRITERIA_ACHIEVEMENT = 8 -- criteria that are "complete another achievement"

local function findExplorerCategories()
  local list = GetCategoryList and GetCategoryList() or {}
  local best, fallback = nil, nil
  for _, cat in ipairs(list) do
    local title, parent = GetCategoryInfo(cat)
    if title and title:find("^Explor") then
      local ptitle = (parent and parent > 0) and GetCategoryInfo(parent) or nil
      if ptitle == "Adventure" then best = best or cat else fallback = fallback or cat end
    end
  end
  local top = best or fallback
  if not top then return {} end
  -- the category itself plus anything filed under it (Eastern Kingdoms, Kalimdor...)
  local cats = { top }
  for _, cat in ipairs(list) do
    local _, parent = GetCategoryInfo(cat)
    if parent == top then cats[#cats + 1] = cat end
  end
  return cats, (GetCategoryInfo(top))
end

-- ns.achievements: list of { id, name, done, zone = uiMapID|nil, meta = bool,
--   criteria = { { name, done } }, have, need }
-- remember where you were standing when an area pops (saved account-wide, so alts get it)
local function recordDiscoveries(prev, list)
  if not (prev and ns.db) then return end
  local here = ns.PlayerZone()
  for _, a in ipairs(list) do
    local old = prev[a.id]
    if old and ns.SameZone(a, here) then
      for _, c in ipairs(a.criteria) do
        -- skip areas the "Discovered:" message already saved a moment ago
        if c.done and old[c.name] == false and not ns.Lookup(ns.db.found, ns.ZoneName(here), c.name) then
          local x, y = ns.PlayerXY(here)
          if x then
            local zone = ns.ZoneName(here)
            ns.db.found[zone] = ns.db.found[zone] or {}
            ns.db.found[zone][c.name] = { math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10 }
            ns.Print(string.format("%s%s|r discovered - spot saved at %.1f, %.1f.", ns.GREEN, c.name, x * 100, y * 100))
          end
        end
      end
    end
  end
end

local function doneMap(list)
  local m = {}
  for _, a in ipairs(list or {}) do
    m[a.id] = {}
    for _, c in ipairs(a.criteria) do m[a.id][c.name] = c.done and true or false end
  end
  return m
end

-- loose lookup: "The Mor'shan Rampart" == "Mor'shan Rampart" == "morshan rampart"
local function lookup(tbl, zoneName, area)
  if not tbl then return nil end
  local z = tbl[zoneName]
  if not z then
    local nz = norm(zoneName)
    for k, v in pairs(tbl) do if norm(k) == nz then z = v break end end
  end
  if not z then return nil end
  if z[area] then return z[area] end
  local na = norm(area)
  for k, v in pairs(z) do if norm(k) == na then return v end end
end
ns.Lookup = lookup

-- the best spot for an area, most trusted first:
--   found by you > shared by another player > confirmed list > Wowhead comment (unverified)
-- returns x, y, kind, note   (kind = "found" | "shared" | "confirmed" | "unverified")
function ns.KnownSpot(zoneName, area)
  local f = ns.db and lookup(ns.db.found, zoneName, area)
  if f then return f[1], f[2], "found", "Confirmed: you found it here." end
  local s = ns.db and lookup(ns.db.shared, zoneName, area)
  if s then return s[1], s[2], "shared", "Confirmed by another player (imported)." end
  local k = lookup(ns.KNOWN, zoneName, area)
  if k then return k[1], k[2], "confirmed", k[3] end
  local u = lookup(ns.UNVERIFIED, zoneName, area)
  if u then return u[1], u[2], "unverified", "Unverified: from a classic-era Wowhead comment. Your discovery will replace it." end
  local c = lookup(ns.CATACLYSM, zoneName, area)
  if c then return c[1], c[2], "cataclysm", "Cataclysm: from a Wowhead comment posted after Cataclysm changed the map. May be off on Forever." end
end

-- how a spot of each kind is labelled in titles and lists
function ns.KindTag(kind)
  if kind == "unverified" then return " (unverified)" end
  if kind == "cataclysm" then return " (Cataclysm)" end
  return ""
end

function ns.Tip(zoneName, area)
  local k = lookup(ns.KNOWN, zoneName, area)
  if k and k[3] then return k[3] end
  return lookup(ns.TIPS, zoneName, area)
end

function ns.ReadAchievements()
  local prev = ns.achievements and doneMap(ns.achievements)
  local out, byZone, byName, seen = {}, {}, {}, {}
  local cats, title = findExplorerCategories()
  ns.categoryTitle = title

  local function readOne(id, name, done)
    if not id or seen[id] then return end
    seen[id] = true
    local a = { id = id, name = name, done = done, criteria = {}, have = 0, need = 0, subs = {} }
    for c = 1, (GetAchievementNumCriteria(id) or 0) do
      local cname, ctype, cdone, _, _, _, _, assetID = GetAchievementCriteriaInfo(id, c)
      if ctype == CRITERIA_ACHIEVEMENT then
        a.meta = true
        if assetID and assetID > 0 then a.subs[#a.subs + 1] = assetID end
      end
      a.criteria[#a.criteria + 1] = { name = cname, done = cdone }
      a.need = a.need + 1
      if cdone then a.have = a.have + 1 end
    end
    if not a.meta then
      a.zoneName = zoneNameOf(name)
      a.zone = zoneForAchievement(name)
      byName[norm(a.zoneName)] = a
      if a.zone then byZone[a.zone] = a end
    end
    out[#out + 1] = a
  end

  for _, cat in ipairs(cats) do
    for i = 1, (GetCategoryNumAchievements(cat, true) or 0) do
      local id, name, _, done = GetAchievementInfo(cat, i)
      readOne(id, name, done)
    end
  end
  -- follow the continent achievements (Explore Kalimdor...) down to every zone they need,
  -- in case a zone's achievement is filed somewhere else
  local i = 1
  while out[i] do
    for _, sub in ipairs(out[i].subs) do
      if not seen[sub] then
        local id, name, _, done = GetAchievementInfo(sub)
        readOne(id, name, done)
      end
    end
    i = i + 1
  end

  table.sort(out, function(x, y)
    if (x.meta and true or false) ~= (y.meta and true or false) then return x.meta and true or false end
    return (x.name or "") < (y.name or "")
  end)
  ns.achievements, ns.achByZone, ns.achByName = out, byZone, byName
  recordDiscoveries(prev, out)
  return out
end

function ns.MissingAreas(a)
  local t = {}
  for _, c in ipairs(a and a.criteria or {}) do
    if not c.done then t[#t + 1] = c.name end
  end
  return t
end

---------------------------------------------------------------------------
-- scanning a zone map for undiscovered patches
---------------------------------------------------------------------------
ns.spots = {} -- [mapID] = { list of { x, y, cells, edge } }

local function canScan()
  return C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition and CreateVector2D
end
ns.CanScan = canScan

local function explored(mapID, x, y)
  local ok, ids = pcall(C_MapExplorationInfo.GetExploredAreaIDsAtPosition, mapID, CreateVector2D(x, y))
  return ok and ids and #ids > 0
end

local function key(mapID, x, y) return string.format("%d:%.2f:%.2f", mapID, x, y) end
ns.SpotKey = key

function ns.ScanZone(mapID)
  if not (mapID and canScan()) then return nil end
  local seen, anyExplored = {}, false
  for gx = 1, GRID do
    seen[gx] = {}
    for gy = 1, GRID do
      local e = explored(mapID, (gx - 0.5) / GRID, (gy - 0.5) / GRID)
      seen[gx][gy] = e
      if e then anyExplored = true end
    end
  end

  local spots = {}
  if not anyExplored then
    -- nothing uncovered yet: walking in will reveal the first area
    spots[1] = { x = 0.5, y = 0.5, cells = GRID * GRID, edge = false, fresh = true }
    ns.spots[mapID] = spots
    return spots
  end

  -- group neighbouring undiscovered samples
  local group = {}
  for gx = 1, GRID do group[gx] = {} end
  for sx = 1, GRID do
    for sy = 1, GRID do
      if not seen[sx][sy] and not group[sx][sy] then
        local cells, edge, stack = {}, false, { { sx, sy } }
        group[sx][sy] = true
        while #stack > 0 do
          local c = table.remove(stack)
          local cx, cy = c[1], c[2]
          cells[#cells + 1] = c
          if cx == 1 or cy == 1 or cx == GRID or cy == GRID then edge = true end
          for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nx, ny = cx + d[1], cy + d[2]
            if nx >= 1 and ny >= 1 and nx <= GRID and ny <= GRID and not seen[nx][ny] and not group[nx][ny] then
              group[nx][ny] = true
              stack[#stack + 1] = { nx, ny }
            end
          end
        end

        -- the cells next to land you've already uncovered are the ones you can reach
        local frontier = {}
        for _, c in ipairs(cells) do
          local cx, cy = c[1], c[2]
          for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nx, ny = cx + d[1], cy + d[2]
            if nx >= 1 and ny >= 1 and nx <= GRID and ny <= GRID and seen[nx][ny] then
              frontier[#frontier + 1] = c
              break
            end
          end
        end

        -- a big patch touching the map edge is the dark border around the zone, not an area
        if #frontier > 0 and not (edge and #cells > GRID * GRID * 0.12) then
          -- aim for the middle of the patch (interior) or the middle of its reachable rim (edge)
          local pool = edge and frontier or cells
          local mx, my = 0, 0
          for _, c in ipairs(pool) do mx, my = mx + c[1], my + c[2] end
          mx, my = mx / #pool, my / #pool
          local bestC, bestD = pool[1], math.huge
          for _, c in ipairs(pool) do
            local d = (c[1] - mx) ^ 2 + (c[2] - my) ^ 2
            if d < bestD then bestC, bestD = c, d end
          end
          local x, y = (bestC[1] - 0.5) / GRID, (bestC[2] - 0.5) / GRID
          if not ns.db.ignore[key(mapID, x, y)] then
            spots[#spots + 1] = { x = x, y = y, cells = #cells, edge = edge }
          end
        end
      end
    end
  end
  ns.spots[mapID] = spots
  return spots
end

---------------------------------------------------------------------------
-- where you are and how far
---------------------------------------------------------------------------
function ns.PlayerZone()
  return C_Map.GetBestMapForUnit("player")
end

function ns.PlayerXY(mapID)
  local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
  if pos then return pos:GetXY() end
end

function ns.Yards(mapID, x1, y1, x2, y2)
  if not (x1 and x2) then return nil end
  local w, h
  if C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(mapID) end
  if not w or w == 0 then return nil end
  return math.sqrt(((x2 - x1) * w) ^ 2 + ((y2 - y1) * h) ^ 2)
end

-- spots in a zone: confirmed spots for areas you still need first, then the map scan's,
-- closest first (enclosed patches before map-edge ones)
function ns.SortedSpots(mapID)
  local scanned = ns.spots[mapID] or ns.ScanZone(mapID) or {}
  local list = {}
  local a = ns.AchFor(mapID)
  if a and not a.done then
    local zone = ns.ZoneName(mapID)
    for _, area in ipairs(ns.MissingAreas(a)) do
      local x, y, kind, note = ns.KnownSpot(zone, area)
      if x and not ns.db.ignore[key(mapID, x / 100, y / 100)] then
        list[#list + 1] = { x = x / 100, y = y / 100, known = true, kind = kind, name = area, note = note,
          unverified = (kind == "unverified" or kind == "cataclysm"), edge = false }
      end
    end
  end
  for _, s in ipairs(scanned) do
    -- drop scan spots sitting on top of a confirmed spot
    local dup = false
    for _, k in ipairs(list) do
      if k.known and math.abs(k.x - s.x) < 0.04 and math.abs(k.y - s.y) < 0.04 then dup = true break end
    end
    if not dup then list[#list + 1] = s end
  end
  local px, py = ns.PlayerXY(mapID)
  for _, s in ipairs(list) do
    s.dist = px and math.sqrt((s.x - px) ^ 2 + (s.y - py) ^ 2) or 0
  end
  -- confirmed spots, then unverified ones, then the map scan's; nearest first within each
  local function rank(s)
    if s.known and not s.unverified then return 1 end
    if s.kind == "unverified" then return 2 end
    if s.kind == "cataclysm" then return 3 end
    return s.edge and 5 or 4
  end
  table.sort(list, function(p, q)
    local rp, rq = rank(p), rank(q)
    if rp ~= rq then return rp < rq end
    return p.dist < q.dist
  end)
  return list
end

---------------------------------------------------------------------------
-- the guide: one waypoint at a time
---------------------------------------------------------------------------
ns.guide = nil -- { mapID, x, y }
local tomtomUID

local function clearWaypoint()
  if tomtomUID and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomUID) end
  tomtomUID = nil
  if C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
end

local function setWaypoint(mapID, x, y, title)
  clearWaypoint()
  if TomTom and TomTom.AddWaypoint then
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, mapID, x, y,
      { title = title, persistent = false, minimap = true, world = true, crazy = true })
    if ok and uid then tomtomUID = uid; return "TomTom" end
  end
  -- no TomTom: the game's own map pin, tracked so it shows on screen
  if C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) and UiMapPoint then
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x, y))
    if ok then
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
      return "map pin"
    end
  end
  return nil
end

function ns.GuideTo(mapID, spot, quiet)
  if not spot then return end
  local zone = ns.ZoneName(mapID)
  local title = spot.name and (spot.name .. ns.KindTag(spot.kind) .. " - " .. zone)
    or ("Undiscovered: " .. zone)
  local how = setWaypoint(mapID, spot.x, spot.y, title)
  ns.guide = { mapID = mapID, x = spot.x, y = spot.y, name = spot.name }
  if not quiet then
    ns.Print(string.format("next: %s at %s%.1f, %.1f|r%s", spot.name or ("undiscovered spot in " .. zone), GOLD,
      spot.x * 100, spot.y * 100, how and (" (" .. how .. ")") or " (no waypoint support - use the coordinates)"))
    if spot.note and spot.kind ~= "found" then print("  " .. GREY .. spot.note .. "|r") end
  end
  ns.Refresh()
end

-- guide to the closest spot in the zone you're in
function ns.GuideNext(quiet)
  local mapID = ns.PlayerZone()
  if not mapID then ns.Print("can't tell which zone you're in.") return end
  local list = ns.SortedSpots(mapID)
  local a = ns.AchFor(mapID)
  if #list == 0 and not canScan() and not quiet then
    ns.Print("this client doesn't report map exploration and there are no saved spots here. The window still lists the area names you need.")
    return
  end
  if #list == 0 or (a and a.done) then
    ns.StopGuide(true)
    if not quiet then
      if a and not a.done then
        ns.Print("no spots left on the map for " .. ns.ZoneName(mapID) .. ", but the achievement still needs: " ..
          table.concat(ns.MissingAreas(a), ", ") .. ". Look for a dark patch at the zone's edge, or a cave or building.")
      elseif not a then
        ns.Print("no Explorer achievement matches " .. ns.ZoneName(mapID) ..
          ", so the addon can't tell which areas you still need. Run /tre probe and send the output.")
      else
        ns.Print(GREEN .. ns.ZoneName(mapID) .. " looks fully explored.|r")
      end
    end
    ns.Refresh()
    return
  end
  ns.GuideTo(mapID, list[1], quiet)
end

function ns.StopGuide(quiet)
  clearWaypoint()
  ns.guide = nil
  if not quiet then ns.Print("guide stopped.") end
  ns.Refresh()
end

---------------------------------------------------------------------------
-- marking: drop a waypoint on every trigger spot at once (like typing /way for each)
---------------------------------------------------------------------------
ns.marks = {} -- TomTom waypoint handles
ns.shownZones = {} -- [mapID] = true for zones whose spots show on the world map (marked)

local function hasTomTom() return TomTom and TomTom.AddWaypoint end

-- returns how many spots were marked
function ns.MarkZone(mapID, quiet)
  local spots = mapID and ns.SortedSpots(mapID) or {}
  local a = ns.AchFor(mapID)
  if #spots == 0 or (a and a.done) then return 0 end
  local zone = ns.ZoneName(mapID)
  ns.shownZones[mapID] = true
  if hasTomTom() then
    for _, s in ipairs(spots) do
      local title = s.name and (s.name .. ns.KindTag(s.kind))
        or ((s.edge and "Undiscovered (map edge): " or "Undiscovered: ") .. zone)
      local ok, uid = pcall(TomTom.AddWaypoint, TomTom, mapID, s.x, s.y,
        { title = title, persistent = false, minimap = true, world = true, crazy = false })
      if ok and uid then ns.marks[#ns.marks + 1] = uid end
    end
  elseif not quiet then
    -- no TomTom: the game only allows one map pin, so print the /way lines instead
    ns.Print("TomTom isn't loaded, so here are the spots for " .. zone .. ":")
    for _, s in ipairs(spots) do
      print(string.format("  /way %.1f %.1f %s%s", s.x * 100, s.y * 100, s.name or "undiscovered",
        ns.KindTag(s.kind)))
    end
  end
  return #spots
end

-- every area of the zone's achievement, found or not (areas you have are labelled "(found)")
function ns.MarkWholeZone(mapID)
  local a = mapID and ns.AchFor(mapID)
  local zone = mapID and ns.ZoneName(mapID) or "this zone"
  if not a then ns.Print("no Explorer achievement matches " .. zone .. ". Try /tre probe.") return 0 end
  ns.shownZones[mapID] = true
  local spots, noCoords = {}, {}
  for _, c in ipairs(a.criteria) do
    local x, y, kind = ns.KnownSpot(zone, c.name)
    if not x and a.zoneName then x, y, kind = ns.KnownSpot(a.zoneName, c.name) end
    if x then
      spots[#spots + 1] = { x = x / 100, y = y / 100,
        title = c.name .. (c.done and " (found)" or "") .. ns.KindTag(kind) }
    else
      noCoords[#noCoords + 1] = c.name
    end
  end
  if hasTomTom() then
    for _, s in ipairs(spots) do
      local ok, uid = pcall(TomTom.AddWaypoint, TomTom, mapID, s.x, s.y,
        { title = s.title, persistent = false, minimap = true, world = true, crazy = false })
      if ok and uid then ns.marks[#ns.marks + 1] = uid end
    end
    ns.Print(string.format("marked %d of %d areas in %s.", #spots, #a.criteria, zone))
  else
    ns.Print("TomTom isn't loaded, so here is every area in " .. zone .. ":")
    for _, s in ipairs(spots) do print(string.format("  /way %.1f %.1f %s", s.x * 100, s.y * 100, s.title)) end
  end
  if #noCoords > 0 then
    print("  " .. GREY .. "No coordinates yet for: " .. table.concat(noCoords, ", ") .. "|r")
  end
  ns.Refresh()
  return #spots
end

function ns.MarkAllZones()
  local zones, total = 0, 0
  for _, a in ipairs(ns.achievements or ns.ReadAchievements()) do
    if a.zone and not a.done then
      local n = ns.MarkZone(a.zone, true)
      if n > 0 then zones, total = zones + 1, total + n end
    end
  end
  if not hasTomTom() then ns.Print("marking every zone needs TomTom. Use Mark zone to print one zone's /way lines.") return end
  ns.Print(string.format("marked %d spots across %d zones. Open the world map to see them.", total, zones))
  ns.Refresh()
end

function ns.ClearMarks(quiet)
  local n = #ns.marks
  if TomTom and TomTom.RemoveWaypoint then
    for _, uid in ipairs(ns.marks) do pcall(TomTom.RemoveWaypoint, TomTom, uid) end
  end
  wipe(ns.marks)
  wipe(ns.shownZones)
  -- also the guide's waypoint and the game's own map pin (which survives a /reload)
  clearWaypoint()
  ns.guide = nil
  if not quiet then ns.Print("cleared " .. n .. " waypoints, the guide pin and the map markers.") end
  ns.Refresh()
end

-- has the guided spot been found? A confirmed spot counts when the achievement ticks it off
-- (its patch of map can already look uncovered); a scanned spot counts when the map uncovers it.
function ns.GuideReached()
  local g = ns.guide
  if not g then return false end
  if g.name then
    local a = ns.AchFor(g.mapID)
    if not a or a.done then return true end
    for _, n in ipairs(ns.MissingAreas(a)) do if n == g.name then return false end end
    return true
  end
  return canScan() and explored(g.mapID, g.x, g.y)
end

-- re-read every Explorer achievement from the game and rescan the maps from scratch
function ns.FullRefresh()
  zoneByName = nil
  wipe(zoneNames)
  wipe(ns.spots)
  local list = ns.ReadAchievements()
  local done, left = 0, 0
  for _, a in ipairs(list) do
    if a.done then done = done + 1 end
    for _, c in ipairs(a.criteria) do if not c.done and not a.meta then left = left + 1 end end
  end
  local mapID = ns.PlayerZone()
  if mapID then ns.ScanZone(mapID) end
  ns.Print(string.format("refreshed: %d/%d achievements done, %d areas still needed.", done, #list, left))
  -- if the guided spot got uncovered meanwhile, move on
  if ns.GuideReached() then
    ns.GuideNext()
    return
  end
  ns.Refresh()
end

-- mark the current spot as unreachable/not real and move on
function ns.IgnoreCurrent()
  local g = ns.guide
  if not g then ns.Print("no spot is being guided.") return end
  ns.db.ignore[key(g.mapID, g.x, g.y)] = true
  ns.spots[g.mapID] = nil
  ns.Print("spot ignored. (/tre unignore to bring them all back)")
  ns.GuideNext()
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local pending = false
local function refreshSoon()
  if pending then return end
  pending = true
  C_Timer.After(0.75, function()
    pending = false
    ns.ReadAchievements()
    local mapID = ns.PlayerZone()
    if mapID then ns.spots[mapID] = nil end
    -- keep guiding: when the current spot gets uncovered, move to the next one
    if ns.guide and ns.db.autoNext then
      local g = ns.guide
      if g.mapID ~= mapID or ns.GuideReached() then
        ns.GuideNext(false)
        return
      end
    end
    ns.Refresh()
  end)
end

ns.Refresh = function() end -- replaced by Window.lua / Pins.lua

-- save where you stand for an area; returns true if saved
function ns.SaveSpot(area, quiet)
  local here = ns.PlayerZone()
  local x, y = ns.PlayerXY(here)
  if not (here and x and area and area ~= "") then return false end
  local zone = ns.ZoneName(here)
  ns.db.found[zone] = ns.db.found[zone] or {}
  ns.db.found[zone][area] = { math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10 }
  if not quiet then
    ns.Print(string.format("%s%s|r - spot saved at %.1f, %.1f (%s).", GREEN, area, x * 100, y * 100, zone))
  end
  return true
end

-- the game's "Discovered: <area>" message, turned into a Lua pattern from its own text
local discoveredPatterns
local function discoveredArea(msg)
  if not discoveredPatterns then
    discoveredPatterns = {}
    for _, fmt in ipairs({ _G.ERR_ZONE_EXPLORED, _G.ERR_ZONE_EXPLORED_XP }) do
      if type(fmt) == "string" then
        local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "%%d+")
        discoveredPatterns[#discoveredPatterns + 1] = "^" .. p .. "$"
      end
    end
    -- fallback for clients without those globals
    discoveredPatterns[#discoveredPatterns + 1] = "^Discovered:? (.-):? %d+ experience gained%.?$"
    discoveredPatterns[#discoveredPatterns + 1] = "^Discovered: (.+)$"
  end
  for _, p in ipairs(discoveredPatterns) do
    local area = type(msg) == "string" and msg:match(p)
    if area then return area end
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_LOGIN" then
    initDB()
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
      "MAP_EXPLORATION_UPDATED", "CRITERIA_UPDATE", "ACHIEVEMENT_EARNED", "UI_INFO_MESSAGE" }) do
      pcall(self.RegisterEvent, self, e)
    end
    if ns.InitPins then ns.InitPins() end
    refreshSoon()
    return
  end
  if event == "UI_INFO_MESSAGE" then
    -- the moment an area is discovered: save exactly where you are standing
    local _, msg = ...
    local area = discoveredArea(msg)
    if area then
      ns.SaveSpot(area)
      refreshSoon()
    end
    return
  end
  refreshSoon()
end)

---------------------------------------------------------------------------
-- slash commands
---------------------------------------------------------------------------
local function help()
  ns.Print("commands:")
  print("  " .. GOLD .. "/tre|r - open or close the window")
  print("  " .. GOLD .. "/tre guide|r - waypoint to the closest undiscovered spot in this zone (keeps going as you find them)")
  print("  " .. GOLD .. "/tre next|r - skip this spot: ignore it and go to the next one")
  print("  " .. GOLD .. "/tre stop|r - stop guiding")
  print("  " .. GOLD .. "/tre mark|r - drop a waypoint on every spot in this zone (/tre markall for every zone)")
  print("  " .. GOLD .. "/tre markwhole|r - a waypoint on every area in this zone, found or not")
  print("  " .. GOLD .. "/tre clear|r - remove those waypoints")
  print("  " .. GOLD .. "/tre refresh|r - re-read your Explorer achievements and rescan the maps")
  print("  " .. GOLD .. "/tre found|r - list the trigger spots saved as areas popped")
  print("  " .. GOLD .. "/tre save <area>|r - save where you stand as the spot for an area (if one popped but wasn't saved)")
  print("  " .. GOLD .. "/tre export|r - your confirmed spots as text to give to other players")
  print("  " .. GOLD .. "/tre import|r - paste in another player's confirmed spots")
  print("  " .. GOLD .. "/tre missing|r - list the area names this zone still needs")
  print("  " .. GOLD .. "/tre pins|r - show or hide spots on the world map")
  print("  " .. GOLD .. "/tre unignore|r - bring back every skipped spot")
  print("  " .. GOLD .. "/tre probe|r - show what the game reports, for troubleshooting")
end

local function probe()
  ns.ReadAchievements()
  local mapID = ns.PlayerZone()
  ns.Print("probe:")
  local zones, metas = 0, 0
  for _, a in ipairs(ns.achievements or {}) do if a.meta then metas = metas + 1 else zones = zones + 1 end end
  print("  category: " .. tostring(ns.categoryTitle) .. ", achievements read: " .. #(ns.achievements or {}) ..
    " (" .. zones .. " zones, " .. metas .. " continent/meta)")
  local info = mapID and C_Map.GetMapInfo(mapID)
  print("  zone: " .. tostring(mapID) .. " " .. (mapID and ns.ZoneName(mapID) or "?") ..
    ", parent map: " .. tostring(info and info.parentMapID) ..
    ", matched achievement: " .. tostring(ns.AchFor(mapID) and ns.AchFor(mapID).name))
  local a = ns.AchFor(mapID)
  if a then
    print("  areas: " .. a.have .. "/" .. a.need .. " done; still needed: " .. table.concat(ns.MissingAreas(a), ", "))
  else
    -- show what zone achievements were read, to see why nothing matched
    local names = {}
    for _, z in ipairs(ns.achievements or {}) do
      if not z.meta and #names < 8 then names[#names + 1] = tostring(z.zoneName) end
    end
    print("  zone achievements seen (first 8): " .. table.concat(names, ", "))
  end
  print("  map exploration API: " .. (canScan() and GREEN .. "yes|r" or ns.RED .. "no|r") ..
    ", world size: " .. tostring(C_Map.GetMapWorldSize and C_Map.GetMapWorldSize(mapID or 0)) ..
    ", TomTom: " .. (TomTom and "yes" or "no"))
  if mapID and canScan() then
    local spots = ns.ScanZone(mapID) or {}
    print("  spots found here: " .. #spots)
  end
  print("  guiding: " .. (ns.guide and (tostring(ns.guide.name or "map spot") ..
    string.format(" at %.1f, %.1f", ns.guide.x * 100, ns.guide.y * 100)) or "no"))
end

SLASH_TOPRAMENEXPLORER1 = "/tre"
SLASH_TOPRAMENEXPLORER2 = "/topramenexplorer"
SlashCmdList.TOPRAMENEXPLORER = function(msg)
  local cmd = (msg or ""):lower():match("^%s*(%S*)")
  if cmd == "" then ns.ToggleWindow()
  elseif cmd == "guide" or cmd == "go" then ns.GuideNext()
  elseif cmd == "next" or cmd == "skip" then ns.IgnoreCurrent()
  elseif cmd == "stop" then ns.StopGuide()
  elseif cmd == "refresh" or cmd == "r" then ns.FullRefresh()
  elseif cmd == "mark" then
    local mapID = ns.PlayerZone()
    local n = ns.MarkZone(mapID)
    if TomTom then ns.Print("marked " .. n .. " spots in " .. (mapID and ns.ZoneName(mapID) or "this zone") .. ".") end
    ns.Refresh()
  elseif cmd == "save" then
    local area = (msg or ""):match("^%s*%S+%s+(.-)%s*$")
    if not area or area == "" then
      ns.Print("usage: /tre save <area name>   e.g.  /tre save Sun Rock Retreat")
    elseif ns.SaveSpot(area) then
      wipe(ns.spots)
      ns.Refresh()
    else
      ns.Print("can't read your position here.")
    end
  elseif cmd == "markall" then ns.MarkAllZones()
  elseif cmd == "markwhole" or cmd == "markfull" then ns.MarkWholeZone(ns.PlayerZone())
  elseif cmd == "clear" then ns.ClearMarks()
  elseif cmd == "export" or cmd == "share" then ns.ShowExport()
  elseif cmd == "import" then ns.ShowImport()
  elseif cmd == "found" then
    local n = 0
    ns.Print("spots you've saved (zone / area / x, y):")
    local zones = {}
    for z in pairs(ns.db.found) do zones[#zones + 1] = z end
    table.sort(zones)
    for _, z in ipairs(zones) do
      for area, p in pairs(ns.db.found[z]) do
        print(string.format("  %s / %s / %.1f, %.1f", z, area, p[1], p[2]))
        n = n + 1
      end
    end
    if n == 0 then print("  none yet - they're saved automatically as areas pop.") end
  elseif cmd == "missing" then
    ns.ReadAchievements()
    local mapID = ns.PlayerZone()
    local a = mapID and ns.AchFor(mapID)
    if not a then ns.Print("no Explorer achievement matches " .. (mapID and ns.ZoneName(mapID) or "this zone") .. ".")
    elseif a.done then ns.Print(GREEN .. a.name .. " is done.|r")
    else ns.Print(a.name .. " (" .. a.have .. "/" .. a.need .. ") still needs: " .. table.concat(ns.MissingAreas(a), ", ")) end
  elseif cmd == "pins" then
    ns.db.pins = not ns.db.pins
    ns.Print("world map spots " .. (ns.db.pins and "on" or "off") .. ".")
    ns.Refresh()
  elseif cmd == "unignore" then
    wipe(ns.db.ignore); wipe(ns.spots)
    ns.Print("all skipped spots are back.")
    ns.Refresh()
  elseif cmd == "probe" then probe()
  else help() end
end
