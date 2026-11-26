-- Top Ramen Gear: the AH tab of the /trg window
-- Scan reads the whole auction house at once (the game's full scan, allowed every 15 minutes) and keeps every
-- listing you could wear. The tab then shows the 5 biggest upgrades for each slot, for the spec picked above:
--   star = the biggest upgrade in that slot, coin = the best value (upgrade per gold) in that slot.
-- Find puts the item in the auction house search so you can buy it there. Gear never bids or buys.
-- A full scan started by Top Ramen Crafting is picked up too (the game allows one every 15 minutes for both).
local _, ns = ...

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local RequestItem = (C_Item and C_Item.RequestLoadItemDataByID) or function() end

local PER_SLOT = 5
local CHUNK = 400             -- listings read per frame
local WAIT = 15 * 60          -- the game's full scan cooldown
local ROWH, HEADH = 44, 26
local COIN = "|TInterface\\MoneyFrame\\UI-GoldIcon:13:13|t"
-- the AH Database box, the same as Top Ramen Crafting's: freshness marks and colours
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local WAITING = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t"
local NOT_READY = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"
local GOOD, WARN, BAD = "|cff6fcf7a", "|cffe6b84f", "|cffe0705a"
local BOX_W = 144
local FULL_WAIT_GUESS = 45 -- seconds the auction house usually takes to send everything

-- slots in the order of the character sheet
local ORDER = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
  "finger", "trinket", "weapon2h", "weapon1h", "offweapon", "shield", "offhand", "ranged", "relic" }
local SLOTNAME = { head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back", chest = "Chest", wrist = "Wrist",
  hands = "Hands", waist = "Waist", legs = "Legs", feet = "Feet", finger = "Rings", trinket = "Trinkets",
  weapon2h = "Two-hand weapons", weapon1h = "One-hand weapons", offhand = "Off-hand", relic = "Relic",
  ranged = "Ranged", offweapon = "Off-hand weapons", shield = "Shields",
  pairs = "Main hand + off-hand pairs" }

local page, scroll, content, specs
local rows, heads, pairRows = {}, {}, {}
local HAND, pairs_ -- the pairs (set below)
local reading = nil -- { total, done } while a scan is being read
local waitingSince = nil -- GetTime() when we asked the game for a full scan, until it arrives
local UI, C, HX
-- shared with Top Ramen Crafting (it also does full scans): when either last asked for one,
-- so neither asks inside the game's 15 minutes, and each reads the other's results
local shared = _G.TopRamenAH or {}
_G.TopRamenAH = shared
local function lastTried() return math.max((ns.db and ns.db.ah and ns.db.ah.tried) or 0, shared.tried or 0) end

local function say(msg) print("|cffe0b04aTop Ramen:|r " .. msg) end
local function data()
  ns.db.ah = ns.db.ah or {}
  return ns.db.ah
end
local ahIsOpen = false -- set by AUCTION_HOUSE_SHOW / CLOSED
local function ahOpen()
  return ahIsOpen or (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown()) or false
end
ns.AHOpen = ahOpen
-- the level range you typed ("Only items within levels X and Y"): nil for an empty box.
-- Starts at your level - 5 and your level; both boxes empty or the box unticked = no level filter.
-- a scan saved by an earlier version used full item links: shrink it to short codes once
local function shrinkOld()
  local d = ns.db and ns.db.ah
  if not d or not d.items or d.small then return end
  local small = {}
  for k, e in pairs(d.items) do
    local colour = k:match("|c(%x%x%x%x%x%x%x%x)")
    local code = k:match("(item:[%-%d:]+)")
    if code and colour ~= "ff9d9d9d" and colour ~= "ffffffff" then
      local old = small[code]
      if not old then small[code] = { p = math.floor((e.p or 0) + 0.5), n = e.n or 1 }
      else old.n = old.n + (e.n or 1); if e.p < old.p then old.p = math.floor(e.p + 0.5) end end
    end
  end
  d.items, d.small = small, true
end
local function within() return ns.db.ahWithin ~= false end
local function range()
  if ns.db.ahMin == nil and ns.db.ahMax == nil and not ns.db.ahRangeSet then
    local lvl = ns.Level() or 60
    ns.db.ahMin, ns.db.ahMax, ns.db.ahRangeSet = math.max(1, lvl - 5), lvl, true
  end
  local lo, hi = tonumber(ns.db.ahMin), tonumber(ns.db.ahMax)
  if lo and hi and lo > hi then lo, hi = hi, lo end
  return lo, hi
end
local function levelOK(rl)
  if not within() then return true end
  local lo, hi = range()
  if lo and rl < lo then return false end
  if hi and rl > hi then return false end
  return true
end
local function filtering() local lo, hi = range(); return within() and (lo or hi) ~= nil end
local function now() return GetTime and GetTime() or time() end
-- scan progress 0..1 (nil when not scanning): waiting for the auction house fills the first half
-- (a guess from how long it usually takes), reading the listings fills the second half
local function progress()
  if reading then return 0.5 + 0.5 * (reading.done or 0) / math.max(1, reading.total or 1) end
  if waitingSince then
    if now() - waitingSince > 90 then
      waitingSince = nil
      say("the auction house didn't send the full scan. It may still be on the game's 15-minute cooldown; try again later.")
      return nil
    end
    return math.min(0.49, 0.5 * (now() - waitingSince) / FULL_WAIT_GUESS)
  end
end
local function ago(t)
  local s = time() - (t or 0)
  if s < 90 then return "just now" end
  if s < 3600 then return math.floor(s / 60 + 0.5) .. " min ago" end
  if s < 48 * 3600 then return math.floor(s / 3600 + 0.5) .. " h ago" end
  return math.floor(s / 86400 + 0.5) .. " days ago"
end
local function money(c)
  c = math.floor(c or 0)
  if GetCoinTextureString then return GetCoinTextureString(c) end
  return string.format("%dg %ds %dc", c / 10000, (c / 100) % 100, c % 100)
end

---------------------------------------------------------------------------
-- reading a full scan
---------------------------------------------------------------------------
-- could you wear it at all? (armor type, weapon type, slot: from the item's basic info, which is always there)
local function wearable(link)
  if not GetInstant then return true end
  local _, _, _, equipLoc, _, classID, subclassID = GetInstant(link)
  if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_BAG" or equipLoc == "INVTYPE_TABARD" or equipLoc == "INVTYPE_BODY" then return false end
  return ns.ClassSlot(equipLoc, classID, subclassID) ~= nil
end

local function readScan()
  local A = C_AuctionHouse
  if reading or not (A and A.GetNumReplicateItems) then return end
  local total = A.GetNumReplicateItems() or 0
  if total == 0 then return end
  local d0 = data()
  -- the same scan announced again: already read
  if d0.t and time() - d0.t < 60 and d0.listings == total then return end
  reading = { total = total, done = 0 }
  waitingSince = nil
  -- saved small, so the game loads quickly: the item's short code ("item:1234::...", no name or colour)
  -- -> { p = cheapest buyout, n = listings }; grey and white items are skipped (they're almost never upgrades)
  local found, i = {}, 0
  local function step()
    local stop = math.min(total, i + CHUNK)
    while i < stop do
      local link = A.GetReplicateItemLink and A.GetReplicateItemLink(i)
      local colour = link and link:match("|c(%x%x%x%x%x%x%x%x)")
      local code = link and link:match("(item:[%-%d:]+)")
      if code and colour ~= "ff9d9d9d" and colour ~= "ffffffff" and wearable(link) then
        local _, _, count, _, _, _, _, _, _, buyout = A.GetReplicateItemInfo(i)
        if (buyout or 0) > 0 then
          local each = math.floor(buyout / math.max(1, count or 1) + 0.5)
          local e = found[code]
          if not e then found[code] = { p = each, n = 1 } else
            e.n = e.n + 1
            if each < e.p then e.p = each end
          end
        end
      end
      i = i + 1
    end
    reading.done = i
    if i < total then
      if ns.RenderAH and page and page:IsVisible() then ns.RenderAH() end
      C_Timer.After(0, step)
      return
    end
    local n = 0
    for link in pairs(found) do
      n = n + 1
      local id = tonumber(link:match("item:(%d+)"))
      if id and not GetInfo(link) then RequestItem(id) end
    end
    local d = data()
    d.items, d.t, d.listings, d.small = found, time(), total, true
    reading = nil
    say(("auction house scan done: %d listings, %d items you could wear. Your upgrades are on the AH tab of /trg."):format(total, n))
    if ns.RenderAH then ns.RenderAH() end
  end
  step()
end

function ns.AHScan()
  local A = C_AuctionHouse
  if not (A and A.ReplicateItems) then say("this version of the game has no full auction house scan."); return end
  if not ahOpen() then say("open the auction house first, then click Scan."); return end
  if reading then say("still reading the last scan..."); return end
  local d = data()
  local wait = lastTried() + WAIT - time()
  -- a full scan someone already made (e.g. Top Ramen Crafting) is still there to read
  if wait > 0 then
    if (A.GetNumReplicateItems() or 0) > 0 and (d.t or 0) < lastTried() then readScan(); return end
    say("the game only allows a full scan every 15 minutes. Next one in " .. math.ceil(wait / 60) .. " min.")
    return
  end
  d.tried = time()
  shared.tried = d.tried
  local ok, err = pcall(A.ReplicateItems)
  if not ok then say("scan failed: " .. tostring(err)); d.tried = nil; return end
  waitingSince = now()
  say("scanning the auction house. It can take up to a minute; keep it open.")
  if ns.RenderAH then ns.RenderAH() end
end

---------------------------------------------------------------------------
-- the upgrades: top 5 per slot
---------------------------------------------------------------------------
-- 1.23.0: main hand + off-hand pairs. Every one-hander you could buy (or are wearing) is tried with every
-- off-hand you could buy (or are wearing): a held-in-hand item, a shield, or for dual wielders a second weapon.
-- Scored together against what you wear in both hands now, so a pair can be compared with a two-hander.
HAND = { weapon1h = true, offhand = true, shield = true, offweapon = true }
local PAIRS_SHOWN, POOL = 3, 12
pairs_ = function(mode, hands)
  local R = ns.CLASS_RULES[ns.PlayerClass() or "DRUID"] or {}
  if not (R.offhand or R.shield or R.dual) then return {} end
  local g = ns.Gear and ns.Gear() or {}
  local base = ns.BaseWithout({ [16] = true, [17] = true })
  local old = ns.Score({ g[16], ns.AsOffhand(g[17]) }, mode, base, 1)
  local co = coroutine.running()
  local mains, offs = {}, {}
  -- what you wear now can be one half of a pair (nothing to buy for that half)
  if g[16] and g[16].s == "weapon1h" then mains[#mains + 1] = { it = g[16], p = 0, worn = true } end
  if g[17] and g[16] and g[16].s ~= "weapon2h" then offs[#offs + 1] = { it = g[17], p = 0, worn = true } end
  for _, h in pairs(hands) do
    local it = h.it
    if it.s == "weapon1h" then
      if it.loc ~= "INVTYPE_WEAPONOFFHAND" then mains[#mains + 1] = h end
      -- a one-hander can go in the off hand too, for dual wielders ("Main Hand" ones can't)
      if R.dual and it.loc == "INVTYPE_WEAPON" then offs[#offs + 1] = h end
    elseif (it.s == "offhand" and R.offhand) or (it.s == "shield" and R.shield) or (it.s == "offweapon" and R.dual) then
      offs[#offs + 1] = h
    end
  end
  -- only the best few of each, by what each is worth on its own (pairs are tried every way after that)
  local function best(list, off)
    for i, h in ipairs(list) do
      h.solo = ns.Score({ off and ns.AsOffhand(h.it) or h.it }, mode, base, 1)
      if co and i % 40 == 0 then coroutine.yield() end
    end
    table.sort(list, function(a, b) return a.solo > b.solo end)
    local keep = {}
    for i, h in ipairs(list) do if i <= POOL or h.worn then keep[#keep + 1] = h end end
    return keep
  end
  mains, offs = best(mains, false), best(offs, true)
  local found, n = {}, 0
  for _, m in ipairs(mains) do
    for _, o in ipairs(offs) do
      local same = m.it.name == o.it.name
      -- one listing can't fill both hands; neither can the weapon you're already holding
      local ok = not (m.worn and o.worn) and not (same and (m.worn or o.worn or (m.n or 1) < 2))
      if ok then
        n = n + 1
        if co and n % 30 == 0 then coroutine.yield() end
        local gain = ns.Score({ m.it, ns.AsOffhand(o.it) }, mode, base, 1) - old
        if gain > 0.05 then
          found[#found + 1] = { m = m, o = o, g = gain, p = (m.worn and 0 or m.p) + (o.worn and 0 or o.p),
            later = (m.it.rl or 0) > (ns.Level() or 60) or (o.it.rl or 0) > (ns.Level() or 60) }
        end
      end
    end
  end
  table.sort(found, function(a, b) return a.g > b.g end)
  local out = {}
  for i = 1, math.min(PAIRS_SHOWN, #found) do out[i] = found[i] end
  if #out > 0 then
    local value
    for _, x in ipairs(out) do
      x.vpg = x.g / math.max(0.01, x.p / 10000)
      if not value or x.vpg > value.vpg then value = x end
    end
    out[1].star = true
    value.coin = true
  end
  return out
end

local function upgrades(mode)
  local d = data()
  local lvl = ns.Level() or 60
  local bySlot, loading = {}, 0
  local seen = {} -- the same item listed several times: keep the cheapest
  local hands = {} -- 1.23.0: every one-hander and off-hand in the level range (cheapest listing), for pairs
  local count, asked = 0, 0
  local co = coroutine.running()
  for code, e in pairs(d.items or {}) do
    -- a few hundred items per frame, so the game stays smooth
    count = count + 1
    if co and count % 150 == 0 then coroutine.yield() end
    -- the full link, from the short code we saved (asks the game for it if it isn't loaded yet)
    local link = code:find("|H", 1, true) and code or select(2, GetInfo(code))
    local it = link and ns.ItemStats(link)
    if not link then
      loading = loading + 1
      -- ask the game for missing items in batches, not thousands at once
      local id = tonumber(code:match("item:(%d+)"))
      if id and asked < 60 then RequestItem(id); asked = asked + 1 end
    elseif not it then
      if not ns.ItemStatsKnownBad(link) and not GetInfo(link) then loading = loading + 1 end
    else
      local rl = it.rl or 0
      local okLevel = levelOK(rl)
      if okLevel and HAND[it.s] then
        local h = hands[it.name]
        if not h then hands[it.name] = { it = it, p = e.p, n = e.n }
        else h.n = h.n + e.n; if e.p < h.p then h.it, h.p = it, e.p end end
      end
      if okLevel then
        local key = it.name
        local prev = seen[key]
        if not prev or e.p < prev.p then
          local g = ns.Gain(it, mode, 1)
          if g and g > 0.05 then
            local x = { it = it, g = g, p = e.p, n = e.n, later = rl > lvl }
            if prev then x.n = x.n + (prev.n or 0); prev.dead = true end
            seen[key] = x
            local s = it.s
            bySlot[s] = bySlot[s] or {}
            table.insert(bySlot[s], x)
          elseif prev then prev.n = prev.n + e.n end
        else
          prev.n = prev.n + e.n
        end
      end
    end
  end
  local out = {}
  for _, s in ipairs(ORDER) do
    local list = {}
    for _, x in ipairs(bySlot[s] or {}) do if not x.dead then list[#list + 1] = x end end
    table.sort(list, function(a, b) return a.g > b.g end)
    while #list > PER_SLOT do table.remove(list) end
    if #list > 0 then
      -- marks: biggest upgrade and best value (upgrade per gold) in the slot
      local value
      for _, x in ipairs(list) do
        x.vpg = x.g / math.max(0.01, x.p / 10000) -- per gold (anything under a silver counts as a silver)
        if not value or x.vpg > value.vpg then value = x end
      end
      list[1].star = true
      value.coin = true
      out[#out + 1] = { slot = s, list = list }
    end
    -- the pairs go right after the one-hand weapons (or where they would be)
    if s == "weapon1h" then
      local pl = pairs_(mode, hands)
      if #pl > 0 then out[#out + 1] = { slot = "pairs", pairs = pl } end
    end
  end
  return out, loading
end
ns.AHUpgrades = upgrades

-- The list is worked out once and kept until something changes it: a new scan, the spec, the level range,
-- your gear, level or settings. Working it out happens a bit per frame (no hitch), and while item details
-- are still arriving from the game it's redone at most every few seconds.
local result = { groups = {}, loading = 0 }
local resultKey, working, lastRun, stamp = nil, nil, 0, 0
local stuck = 0 -- passes in a row where no more items arrived: stop retrying after a few
function ns.AHChanged() stamp = stamp + 1 end
local function wantKey(mode)
  local d = data()
  return table.concat({ mode, tostring(ns.db.ahWithin), tostring(ns.db.ahMin), tostring(ns.db.ahMax),
    tostring(d.t), tostring(ns.Level()), tostring(stamp) }, "|")
end
local function compute(mode, key)
  if working then return end
  working = coroutine.create(function()
    local groups, loading = upgrades(mode)
    if resultKey == key and loading > 0 and loading >= (result.loading or 0) then stuck = stuck + 1 else stuck = 0 end
    result = { groups = groups, loading = loading }
    resultKey = key
  end)
  local function step()
    if not working then return end
    local ok, err = coroutine.resume(working)
    if not ok then working = nil; resultKey = key; say("AH list error: " .. tostring(err)); return end
    if coroutine.status(working) == "dead" then
      working, lastRun = nil, (GetTime and GetTime() or 0)
      if ns.RenderAH then ns.RenderAH(true) end
    else
      C_Timer.After(0, step)
    end
  end
  step()
end

-- put the item in the auction house search (you buy it there)
-- the item's real name: from the link's [Name] first (what you see), then the game's name for the item ID.
-- 1.21.1: the saved name could be the item code or ID, which the AH can't search for.
local function realName(it)
  local function good(n) return type(n) == "string" and n ~= "" and not n:match("^%d+$") and not n:find("item:", 1, true) and n end
  local n = good(it.link and it.link:match("|h%[(.-)%]|h"))
  if not n and it.id and C_Item and C_Item.GetItemNameByID then n = good(C_Item.GetItemNameByID(it.id)) end
  if not n and it.id then n = good((GetInfo(it.id))) end
  return n or good(it.name)
end

local function find(it)
  local f, A = AuctionHouseFrame, C_AuctionHouse
  if not (f and f:IsShown()) then say("open the auction house first."); return end
  local name = realName(it)
  if not name then
    if it.id and RequestItem then RequestItem(it.id) end
    say("still loading that item's name; click Find again in a moment."); return
  end
  local ok, err = pcall(function()
    if AuctionHouseFrameDisplayMode and f.SetDisplayMode then f:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy) end
    f.SearchBar:SetSearchText(name)
    f.SearchBar:StartSearch()
  end)
  if ok then say("searching the auction house for " .. (it.link or name) .. ".")
  else say("couldn't use the search box (" .. tostring(err) .. "); trying the item directly.") end
  if not ok and A and A.MakeItemKey then pcall(function() f:SelectBrowseResult({ itemKey = A.MakeItemKey(it.id) }) end) end
end

---------------------------------------------------------------------------
-- the page
---------------------------------------------------------------------------
local function heading(i)
  local h = heads[i]
  if h then return h end
  h = CreateFrame("Frame", nil, content)
  h:SetHeight(HEADH)
  h.text = UI.Text(h, "GameFontNormal", C.gold)
  h.text:SetPoint("BOTTOMLEFT", 4, 4)
  h.line = h:CreateTexture(nil, "ARTWORK")
  h.line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1); h.line:SetHeight(1)
  h.line:SetPoint("BOTTOMLEFT", 0, 0); h.line:SetPoint("BOTTOMRIGHT", 0, 0)
  heads[i] = h
  return h
end

local function row(i)
  local r = rows[i]
  if r then return r end
  r = UI.Frame(content, C.row)
  r:SetHeight(ROWH - 4)
  r.item = ns.MakeCell(r, 8, 300, 30, true)
  r.marks = UI.Text(r, "GameFontHighlight")
  r.bar = UI.Bar(r, 70)
  r.gain = UI.Text(r, "GameFontHighlight")
  r.price = UI.Text(r, "GameFontHighlightSmall")
  r.price:SetJustifyH("RIGHT")
  r.find = UI.Button(r, 56, 24, "Find", function() if r.x then find(r.x.it) end end,
    "Searches for this item in the auction house, so you can buy it there.")
  rows[i] = r
  return r
end

-- 1.23.0: a pair card: one framed box holding the main hand and the off-hand, joined by a gold bracket
-- with a "+", one combined upgrade and total price for both, and a Find button for each item to buy
local PAIRH = 2 * ROWH + 8
local function pairRow(i)
  local r = pairRows[i]
  if r then return r end
  r = UI.Frame(content, C.row)
  r:SetHeight(PAIRH - 4)
  -- the bracket: a gold line down the left joining both items, with a "+" in the middle
  r.br = r:CreateTexture(nil, "ARTWORK"); r.br:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.85); r.br:SetWidth(2)
  r.br:SetPoint("TOPLEFT", 12, -20); r.br:SetPoint("BOTTOMLEFT", 12, 20)
  r.t1 = r:CreateTexture(nil, "ARTWORK"); r.t1:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.85); r.t1:SetSize(8, 2)
  r.t1:SetPoint("TOPLEFT", r.br, "TOPLEFT", 0, 0)
  r.t2 = r:CreateTexture(nil, "ARTWORK"); r.t2:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.85); r.t2:SetSize(8, 2)
  r.t2:SetPoint("BOTTOMLEFT", r.br, "BOTTOMLEFT", 0, 0)
  r.plusBg = r:CreateTexture(nil, "OVERLAY"); r.plusBg:SetColorTexture(C.row[1], C.row[2], C.row[3], 1); r.plusBg:SetSize(14, 14)
  r.plusBg:SetPoint("CENTER", r.br, "CENTER", 1, 0)
  r.plus = UI.Text(r, "GameFontNormalLarge", C.gold); r.plus:SetText("+")
  r.plus:SetPoint("CENTER", r.br, "CENTER", 1, 1)
  r.cells, r.finds, r.prices = {}, {}, {}
  for k = 1, 2 do
    r.cells[k] = ns.MakeCell(r, 26, 300, 30, true)
    r.prices[k] = UI.Text(r, "GameFontHighlightSmall"); r.prices[k]:SetJustifyH("RIGHT"); r.prices[k]:SetWidth(100)
    r.finds[k] = UI.Button(r, 56, 24, "Find", function() local h = r.x and (k == 1 and r.x.m or r.x.o); if h then find(h.it) end end,
      "Searches for this item in the auction house, so you can buy it there.")
  end
  r.marks = UI.Text(r, "GameFontHighlight")
  r.bar = UI.Bar(r, 70)
  r.gain = UI.Text(r, "GameFontHighlight")
  r.total = UI.Text(r, "GameFontHighlightSmall", C.muted); r.total:SetJustifyH("RIGHT")
  pairRows[i] = r
  return r
end

local function layoutPair(r, w)
  r:SetWidth(w)
  for k = 1, 2 do
    local y = k == 1 and -5 or -(ROWH + 3)
    r.finds[k]:ClearAllPoints(); r.finds[k]:SetPoint("TOPRIGHT", -8, y - 5)
    r.prices[k]:ClearAllPoints(); r.prices[k]:SetPoint("RIGHT", r.finds[k], "LEFT", -10, 0)
    r.cells[k]:ClearAllPoints(); r.cells[k]:SetPoint("TOPLEFT", 26, y)
    r.cells[k]:SetWidth(math.max(160, w - 26 - 56 - 100 - 14 - 90 - 8 - 70 - 10 - 44 - 20))
  end
  -- the combined numbers sit between the items and the prices, centred on the card
  r.gain:ClearAllPoints(); r.gain:SetPoint("RIGHT", r, "RIGHT", -8 - 56 - 10 - 100 - 14, 6)
  r.total:ClearAllPoints(); r.total:SetPoint("TOPRIGHT", r.gain, "BOTTOMRIGHT", 0, -3)
  r.bar:ClearAllPoints(); r.bar:SetPoint("RIGHT", r.gain, "LEFT", -8, 0)
  r.marks:ClearAllPoints(); r.marks:SetPoint("RIGHT", r.bar, "LEFT", -10, 0)
end

local function layoutRow(r, w)
  r:SetWidth(w)
  r.find:ClearAllPoints(); r.find:SetPoint("RIGHT", -8, 0)
  r.price:ClearAllPoints(); r.price:SetPoint("RIGHT", r.find, "LEFT", -10, 0); r.price:SetWidth(110)
  r.gain:ClearAllPoints(); r.gain:SetPoint("RIGHT", r.price, "LEFT", -14, 0)
  r.bar:ClearAllPoints(); r.bar:SetPoint("RIGHT", r.gain, "LEFT", -8, 0)
  r.marks:ClearAllPoints(); r.marks:SetPoint("RIGHT", r.bar, "LEFT", -10, 0)
  ns.PlaceCell(r.item, 8, math.max(160, w - 8 - 56 - 110 - 14 - 50 - 8 - 70 - 10 - 44 - 20))
end

function ns.RenderAH(fromCompute)
  if not page or not page:IsVisible() then return end
  shrinkOld()
  local mode0 = ns.CurrentMode()
  local key = wantKey(mode0)
  if not fromCompute then
    local t = GetTime and GetTime() or 0
    -- start working it out again when something changed, or every few seconds while items are still loading
    if key ~= resultKey or (result.loading > 0 and stuck < 4 and t - lastRun > 3) then compute(mode0, key) end
  end
  local mode = ns.CurrentMode()
  if specs then specs:Update(mode) end -- highlight the spec in use, like the Gear and Dungeons tabs
  local d = data()
  local lvl = ns.Level() or 60
  page.within:SetChecked(within())
  range() -- fills in the starting range the first time
  if not page.minBox:HasFocus() then page.minBox:SetText(ns.db.ahMin and tostring(ns.db.ahMin) or "") end
  if not page.maxBox:HasFocus() then page.maxBox:SetText(ns.db.ahMax and tostring(ns.db.ahMax) or "") end
  local on = within()
  page.minBox:SetAlpha(on and 1 or 0.5); page.maxBox:SetAlpha(on and 1 or 0.5); page.andText:SetAlpha(on and 1 or 0.5)

  -- status line
  local status
  if reading then
    status = HX.gold .. ("Reading the scan... %d / %d listings"):format(reading.done, reading.total) .. "|r"
  elseif d.t then
    status = "Last scan " .. ago(d.t) .. HX.dim .. " · " .. (d.listings or 0) .. " listings|r"
  else
    status = HX.dim .. "No scan yet: open the auction house and click Scan.|r"
  end
  local wait = lastTried() + WAIT - time()
  if working and resultKey ~= key then status = status .. HX.dim .. " · working out your upgrades...|r" end
  if not reading and wait > 0 then status = status .. HX.dim .. " · next scan in " .. math.ceil(wait / 60) .. " min|r" end
  if not ahOpen() and d.t then status = status .. HX.dim .. " · open the auction house to scan again or Find|r" end
  page.status:SetText(status)

  local groups, loading = result.groups, result.loading
  if working then loading = math.max(loading, 1) end
  local w = scroll:GetWidth()
  if not w or w < 100 then w = 700 end
  content:SetWidth(w)
  local y, nh, nr, np = 0, 0, 0, 0
  for _, g in ipairs(groups) do
    nh = nh + 1
    local h = heading(nh)
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y); h:SetWidth(w)
    h.text:SetText((SLOTNAME[g.slot] or g.slot) .. (g.pairs and (HX.dim .. "  ·  scored together, the same scale as two-handers|r") or ""))
    h:Show()
    y = y + HEADH + 4
    if g.pairs then
      local maxG = g.pairs[1].g
      for i, x in ipairs(g.pairs) do
        np = np + 1
        local r = pairRow(np)
        r.x = x
        layoutPair(r, w)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y)
        for k, half in ipairs({ x.m, x.o }) do
          local cell, it = r.cells[k], half.it
          ns.SetCell(cell, { it }, { glow = x.star and not half.worn })
          local hand = HX.gold .. (k == 1 and "Main hand" or "Off hand") .. "|r"
          local lvlTxt = ((it.rl or 0) > lvl and HX.red or "") .. "Level " .. (it.rl or 0) .. ((it.rl or 0) > lvl and "|r" or "")
          if half.worn then
            cell.sub:SetText(hand .. HX.dim .. " · you're wearing this, keep it|r")
            r.prices[k]:SetText(HX.dim .. "worn|r")
            r.finds[k]:Hide()
          else
            cell.sub:SetText(hand .. HX.dim .. " · |r" .. lvlTxt .. HX.dim .. ((half.n or 1) > 1 and (" · " .. half.n .. " listed") or "") .. "|r")
            r.prices[k]:SetText(money(half.p))
            r.finds[k]:Show(); r.finds[k]:SetEnabled(ahOpen())
          end
        end
        local marks = {}
        if x.star then marks[#marks + 1] = UI.STAR end
        if x.coin then marks[#marks + 1] = COIN end
        r.marks:SetText(table.concat(marks, " "))
        r.bar:SetValue(maxG > 0 and x.g / maxG or 0)
        r.gain:SetText(ns.FmtGain(x.g))
        r.total:SetText("for both: " .. money(x.p))
        -- always trimmed in gold so the two items read as one card; brighter for the biggest upgrade
        r:SetBackdropColor(1, 0.82, 0, x.star and 0.07 or 0.03)
        r:SetBackdropBorderColor(1, 0.82, 0, x.star and 0.55 or 0.3)
        r:Show()
        y = y + PAIRH
      end
    end
    local maxG = g.list and g.list[1].g
    for _, x in ipairs(g.list or {}) do
      nr = nr + 1
      local r = row(nr)
      r.x = x
      layoutRow(r, w)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y)
      ns.SetCell(r.item, { x.it }, { glow = x.star })
      local sub = "Level " .. (x.it.rl or 0) .. (x.n > 1 and (" · " .. x.n .. " listed") or "")
      if x.later then sub = HX.red .. "Level " .. x.it.rl .. "|r" .. HX.dim .. (x.n > 1 and (" · " .. x.n .. " listed") or "") .. "|r" end
      r.item.sub:SetText(sub)
      local marks = {}
      if x.star then marks[#marks + 1] = UI.STAR end
      if x.coin then marks[#marks + 1] = COIN end
      r.marks:SetText(table.concat(marks, " "))
      r.bar:SetValue(maxG > 0 and x.g / maxG or 0)
      r.gain:SetText(ns.FmtGain(x.g))
      r.price:SetText(money(x.p))
      r.find:SetEnabled(ahOpen())
      ns.RowStyle(r, x.star and "gold" or nil)
      r:Show()
      y = y + ROWH
    end
    y = y + 6
  end
  for i = nh + 1, #heads do heads[i]:Hide() end
  for i = nr + 1, #rows do rows[i]:Hide() end
  for i = np + 1, #pairRows do pairRows[i]:Hide() end
  content:SetHeight(math.max(10, y))

  if nr == 0 and np == 0 then
    page.empty:SetText(d.items and (loading > 0 and "Loading item details..." or
      "No upgrades on the auction house for this spec" .. (filtering() and " in that level range." or ".")) or
      "Open the auction house and click Scan. Gear reads every listing and lists the 5 biggest upgrades for each slot.")
    page.empty:Show()
  else
    page.empty:Hide()
  end
  -- the AH Database box: when the scan was made, and how fresh it is
  local t, mark, color, when = d.t, NOT_READY, BAD, "never scanned"
  if t then
    local clock = date("%I:%M %p", t):gsub("^0", "")
    when = (date("%x", t) == date("%x")) and clock or (date("%b %d ", t):gsub(" 0", " ") .. clock)
    local age = time() - t
    if age <= 15 * 60 then mark, color = READY, GOOD elseif age <= 24 * 3600 then mark, color = WAITING, WARN end
  end
  if progress() then when, mark, color = "scanning...", WAITING, WARN end
  page.scan.text:SetText("AH Database\n" .. color .. when .. "|r  " .. mark)

  local foot = UI.STAR .. " biggest upgrade in the slot  ·  " .. COIN .. " best value (upgrade per gold)"
  if loading > 0 then foot = foot .. HX.dim .. "  ·  " .. loading .. " items still loading|r" end
  if ns.SetFooter then ns.SetFooter(foot) end
end

function ns.BuildAH(p, specSwitcher)
  UI = ns.UI; C, HX = UI.C, UI.HEX
  page, specs = p, specSwitcher
  local HEAD_H = 58

  -- the AH Database box (the same as Top Ramen Crafting's): click to scan; shows when, how fresh, and progress
  local box = CreateFrame("Button", nil, p, "BackdropTemplate")
  box:SetSize(BOX_W, 42)
  UI.Skin(box, C.row, C.line)
  box.iconBorder = UI.Frame(box, C.track, C.trim, 1)
  box.iconBorder:SetSize(34, 34)
  box.iconBorder:SetPoint("LEFT", 4, 0)
  box.icon = box.iconBorder:CreateTexture(nil, "ARTWORK")
  box.icon:SetPoint("TOPLEFT", 1, -1); box.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  box.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  box.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  box.text = UI.Text(box, "GameFontHighlightSmall")
  box.text:SetPoint("LEFT", box.iconBorder, "RIGHT", 6, 0)
  box.text:SetWidth(BOX_W - 48)
  box.text:SetJustifyH("LEFT")
  box:SetScript("OnClick", function() ns.AHScan() end)
  box:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("AH Database")
    GameTooltip:AddLine("Green check: scanned in the last 15 minutes. Yellow ?: up to a day old. Red X: older than a day, or never scanned.", 1, 1, 1, true)
    GameTooltip:AddLine("At the auction house, click to scan: reads every listing at once (the game allows this every 15 minutes) and finds your upgrades. Read only: nothing is bought.", 1, 1, 1, true)
    local d = data()
    if d.t then GameTooltip:AddLine("Last scan " .. ago(d.t) .. ": " .. (d.listings or 0) .. " listings.", 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
  end)
  box:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1); GameTooltip:Hide() end)
  -- scan progress: a green bar filling the box, with a white percentage on top
  box.bar = box:CreateTexture(nil, "OVERLAY", nil, 1)
  box.bar:SetPoint("TOPLEFT", 1, -1); box.bar:SetPoint("BOTTOMLEFT", 1, 1)
  box.bar:SetColorTexture(0.29, 0.87, 0.5, 0.55)
  box.pct = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  box.pct:SetPoint("CENTER", 0, 0)
  box.pct:SetTextColor(1, 1, 1)
  if box.pct.GetFont then local f, size = box.pct:GetFont(); if f then box.pct:SetFont(f, size or 16, "OUTLINE") end end
  box.bar:Hide(); box.pct:Hide()
  box:SetScript("OnUpdate", function(self, elapsed)
    self.tick = (self.tick or 0) + (elapsed or 0)
    if self.tick < 0.1 then return end
    self.tick = 0
    local v = progress()
    if v then
      self.bar:SetWidth(math.max(1, ((self:GetWidth() or BOX_W) - 2) * v))
      self.bar:Show()
      self.pct:SetText(math.floor(v * 100) .. "%")
      self.pct:Show()
      self.text:SetAlpha(0.35)
      self.wasBusy = true
    elseif self.wasBusy then
      self.wasBusy = nil
      self.bar:Hide(); self.pct:Hide(); self.text:SetAlpha(1)
      ns.RenderAH()
    end
  end)
  p.scan = box
  p.scan:SetPoint("TOPLEFT", 16 + (specs and specs:GetWidth() or 380) + 16, -(HEAD_H + 15))

  p.within = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  p.within:SetSize(22, 22)
  p.within:SetPoint("TOPLEFT", 12, -(HEAD_H + 60))
  local t = p.within.text or p.within.Text or p.within:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t:ClearAllPoints(); t:SetPoint("LEFT", p.within, "RIGHT", 2, 0); t:SetFontObject("GameFontHighlightSmall")
  p.within.text = t
  p.within:SetScript("OnClick", function(self) ns.db.ahWithin = self:GetChecked() and true or false; ns.RenderAH() end)
  t:SetText("Only items within levels")
  -- the two level boxes: type a number, Enter or click away to apply; empty = no limit on that side
  local function levelBox(key)
    local e = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    e:SetSize(30, 20)
    e:SetAutoFocus(false)
    e:SetNumeric(true)
    e:SetMaxLetters(2)
    e:SetJustifyH("CENTER")
    local function apply(self)
      local v = tonumber(self:GetText() or "")
      ns.db[key] = v
      ns.db.ahRangeSet = true
      ns.RenderAH()
    end
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", apply)
    e:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine("Required level range", 1, 0.82, 0)
      GameTooltip:AddLine("Only items whose required level is between the two numbers. Leave a box empty for no limit on that side; leave both empty (or untick) to show every level.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    e:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return e
  end
  p.minBox = levelBox("ahMin")
  p.minBox:SetPoint("LEFT", t, "RIGHT", 10, 0)
  p.andText = UI.Text(p, "GameFontHighlightSmall")
  p.andText:SetPoint("LEFT", p.minBox, "RIGHT", 6, 0)
  p.andText:SetText("and")
  p.maxBox = levelBox("ahMax")
  p.maxBox:SetPoint("LEFT", p.andText, "RIGHT", 10, 0)

  p.status = UI.Text(p, "GameFontHighlightSmall", C.muted)
  p.status:SetPoint("LEFT", p.maxBox, "RIGHT", 18, 0)
  p.status:SetPoint("RIGHT", p, "RIGHT", -18, 0)
  p.status:SetJustifyH("RIGHT")
  p.status:SetWordWrap(false)

  scroll, content = ns.MakeScroll(p, "TopRamenGearAHScroll", -(HEAD_H + 84))
  p.empty = UI.Text(p, "GameFontHighlight", C.muted)
  p.empty:SetPoint("TOP", scroll, "TOP", 0, -40)
  p.empty:SetWidth(520)

  p:SetScript("OnShow", function() ns.RenderAH() end)
  return function() ns.RenderAH() end -- relayout when the window is resized
end

-- the auction house: listen for full scans (yours or Top Ramen Crafting's) and keep the tab up to date
do
  local orig = ns.ClearScores
  if orig then ns.ClearScores = function(...) ns.AHChanged(); return orig(...) end end
end
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
  "PLAYER_EQUIPMENT_CHANGED", "CHARACTER_POINTS_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
local pendingRead = false
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_EQUIPMENT_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
    ns.AHChanged()
    if ns.RenderAH then ns.RenderAH() end
    return
  end
  if event == "PLAYER_LOGIN" then
    shrinkOld() -- a big scan saved by an earlier version: smaller from the next logout on
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    -- the data can arrive in parts: read once it has settled
    if pendingRead then return end
    pendingRead = true
    C_Timer.After(2, function() pendingRead = false; readScan() end)
  else
    -- remember our own last scan for Crafting (after a /reload the shared note is empty)
    if event == "AUCTION_HOUSE_SHOW" and ns.db then shared.tried = math.max(shared.tried or 0, data().tried or 0) end
    -- the AH tab only works while the auction house is open (it's no use anywhere else, and costs nothing when not shown)
    if event == "AUCTION_HOUSE_SHOW" then ahIsOpen = true elseif event == "AUCTION_HOUSE_CLOSED" then ahIsOpen = false end
    if ns.SetAHTab then ns.SetAHTab(ahIsOpen) end
    if ns.RenderAH then ns.RenderAH() end
  end
end)
