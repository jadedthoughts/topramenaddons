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

-- slots in the order of the character sheet
local ORDER = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
  "finger", "trinket", "weapon2h", "weapon1h", "offweapon", "shield", "offhand", "ranged", "relic" }
local SLOTNAME = { head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back", chest = "Chest", wrist = "Wrist",
  hands = "Hands", waist = "Waist", legs = "Legs", feet = "Feet", finger = "Rings", trinket = "Trinkets",
  weapon2h = "Two-hand weapons", weapon1h = "One-hand weapons", offhand = "Off-hand", relic = "Relic",
  ranged = "Ranged", offweapon = "Off-hand weapons", shield = "Shields" }

local page, scroll, content, specs
local rows, heads = {}, {}
local reading = nil -- { total, done } while a scan is being read
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
local function ahOpen()
  return (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown()) or false
end
local function within() return ns.db.ahWithin ~= false end
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
  local found, i = {}, 0 -- link -> { p = cheapest buyout, n = listings }
  local function step()
    local stop = math.min(total, i + CHUNK)
    while i < stop do
      local link = A.GetReplicateItemLink and A.GetReplicateItemLink(i)
      if link and wearable(link) then
        local _, _, count, _, _, _, _, _, _, buyout = A.GetReplicateItemInfo(i)
        if (buyout or 0) > 0 then
          local each = buyout / math.max(1, count or 1)
          local e = found[link]
          if not e then found[link] = { p = each, n = 1 } else
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
    d.items, d.t, d.listings = found, time(), total
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
  say("scanning the auction house. It can take up to a minute; keep it open.")
  if ns.RenderAH then ns.RenderAH() end
end

---------------------------------------------------------------------------
-- the upgrades: top 5 per slot
---------------------------------------------------------------------------
local function upgrades(mode)
  local d = data()
  local lvl = ns.Level() or 60
  local bySlot, loading = {}, 0
  local seen = {} -- the same item listed several times: keep the cheapest
  for link, e in pairs(d.items or {}) do
    local it = ns.ItemStats(link)
    if not it then
      if not ns.ItemStatsKnownBad(link) and not GetInfo(link) then loading = loading + 1 end
    else
      local rl = it.rl or 0
      local okLevel = (not within()) or (rl <= lvl and rl >= lvl - 5)
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
  end
  return out, loading
end
ns.AHUpgrades = upgrades

-- put the item in the auction house search (you buy it there)
local function find(it)
  local f, A = AuctionHouseFrame, C_AuctionHouse
  if not (f and f:IsShown()) then say("open the auction house first."); return end
  local ok = pcall(function()
    if AuctionHouseFrameDisplayMode and f.SetDisplayMode then f:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy) end
    f.SearchBar:SetSearchText(it.name)
    f.SearchBar:StartSearch()
  end)
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

local function layoutRow(r, w)
  r:SetWidth(w)
  r.find:ClearAllPoints(); r.find:SetPoint("RIGHT", -8, 0)
  r.price:ClearAllPoints(); r.price:SetPoint("RIGHT", r.find, "LEFT", -10, 0); r.price:SetWidth(110)
  r.gain:ClearAllPoints(); r.gain:SetPoint("RIGHT", r.price, "LEFT", -14, 0)
  r.bar:ClearAllPoints(); r.bar:SetPoint("RIGHT", r.gain, "LEFT", -8, 0)
  r.marks:ClearAllPoints(); r.marks:SetPoint("RIGHT", r.bar, "LEFT", -10, 0)
  ns.PlaceCell(r.item, 8, math.max(160, w - 8 - 56 - 110 - 14 - 50 - 8 - 70 - 10 - 44 - 20))
end

function ns.RenderAH()
  if not page or not page:IsVisible() then return end
  local mode = ns.CurrentMode()
  if specs then specs:Update(mode) end -- highlight the spec in use, like the Gear and Dungeons tabs
  local d = data()
  local lvl = ns.Level() or 60
  page.within.text:SetText(("Only items within 5 levels of yours (%d-%d)"):format(math.max(1, lvl - 5), lvl))
  page.within:SetChecked(within())

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
  if not reading and wait > 0 then status = status .. HX.dim .. " · next scan in " .. math.ceil(wait / 60) .. " min|r" end
  if not ahOpen() and d.t then status = status .. HX.dim .. " · open the auction house to scan again or Find|r" end
  page.status:SetText(status)

  local groups, loading = upgrades(mode)
  local w = scroll:GetWidth()
  if not w or w < 100 then w = 700 end
  content:SetWidth(w)
  local y, nh, nr = 0, 0, 0
  for _, g in ipairs(groups) do
    nh = nh + 1
    local h = heading(nh)
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y); h:SetWidth(w)
    h.text:SetText(SLOTNAME[g.slot] or g.slot)
    h:Show()
    y = y + HEADH + 4
    local maxG = g.list[1].g
    for _, x in ipairs(g.list) do
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
  content:SetHeight(math.max(10, y))

  if nr == 0 then
    page.empty:SetText(d.items and (loading > 0 and "Loading item details..." or
      "No upgrades on the auction house for this spec" .. (within() and " within 5 levels of yours." or ".")) or
      "Open the auction house and click Scan. Gear reads every listing and lists the 5 biggest upgrades for each slot.")
    page.empty:Show()
  else
    page.empty:Hide()
  end
  page.scan:SetEnabled(ahOpen() and not reading)

  local foot = UI.STAR .. " biggest upgrade in the slot  ·  " .. COIN .. " best value (upgrade per gold)"
  if loading > 0 then foot = foot .. HX.dim .. "  ·  " .. loading .. " items still loading|r" end
  if ns.SetFooter then ns.SetFooter(foot) end
end

function ns.BuildAH(p, specSwitcher)
  UI = ns.UI; C, HX = UI.C, UI.HEX
  page, specs = p, specSwitcher
  local HEAD_H = 58

  p.scan = UI.Button(p, 96, 32, "Scan", function() ns.AHScan() end,
    "Reads every listing on the auction house (the game allows this every 15 minutes) and finds the upgrades for you. Read only: nothing is bought.")
  p.scan:SetPoint("TOPLEFT", 16 + (specs and specs:GetWidth() or 380) + 16, -(HEAD_H + 20))

  p.within = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  p.within:SetSize(22, 22)
  p.within:SetPoint("LEFT", p.scan, "RIGHT", 14, 0)
  local t = p.within.text or p.within.Text or p.within:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t:ClearAllPoints(); t:SetPoint("LEFT", p.within, "RIGHT", 2, 0); t:SetFontObject("GameFontHighlightSmall")
  p.within.text = t
  p.within:SetScript("OnClick", function(self) ns.db.ahWithin = self:GetChecked() and true or false; ns.RenderAH() end)

  p.status = UI.Text(p, "GameFontHighlightSmall", C.muted)
  p.status:SetPoint("TOPLEFT", 16, -(HEAD_H + 64))
  p.status:SetPoint("RIGHT", -18, 0)
  p.status:SetWordWrap(false)

  scroll, content = ns.MakeScroll(p, "TopRamenGearAHScroll", -(HEAD_H + 84))
  p.empty = UI.Text(p, "GameFontHighlight", C.muted)
  p.empty:SetPoint("TOP", scroll, "TOP", 0, -40)
  p.empty:SetWidth(520)

  p:SetScript("OnShow", function() ns.RenderAH() end)
  return function() ns.RenderAH() end -- relayout when the window is resized
end

-- the auction house: listen for full scans (yours or Top Ramen Crafting's) and keep the tab up to date
local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE" }) do pcall(ev.RegisterEvent, ev, e) end
local pendingRead = false
ev:SetScript("OnEvent", function(_, event)
  if event == "REPLICATE_ITEM_LIST_UPDATE" then
    -- the data can arrive in parts: read once it has settled
    if pendingRead then return end
    pendingRead = true
    C_Timer.After(2, function() pendingRead = false; readScan() end)
  else
    -- remember our own last scan for Crafting (after a /reload the shared note is empty)
    if event == "AUCTION_HOUSE_SHOW" and ns.db then shared.tried = math.max(shared.tried or 0, data().tried or 0) end
    if ns.RenderAH then ns.RenderAH() end
  end
end)
