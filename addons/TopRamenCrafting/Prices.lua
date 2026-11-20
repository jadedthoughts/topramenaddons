-- Top Ramen Crafting: our own price data, so the planner doesn't need Auctionator.
--   Full scan:  one request for every listing on the auction house (the game allows it every 15 minutes)
--   Quick scan: a search for each material and product your recipes use (no cooldown)
--   Vendors:    what a vendor charges, recorded whenever you open one
-- Read-only: scanning never bids or buys.

local _, ns = ...
ns = ns or {}

local Prices = {}
ns.Prices = Prices

local FULL_SCAN_COOLDOWN = 15 * 60
local CHUNK = 1500            -- listings processed per frame during a full scan
local QUICK_TIMEOUT = 4       -- seconds to wait for one search
local KEEP_UNITS = 1000       -- price levels are kept until this many units are covered...
local KEEP_LEVELS = 20        -- ...or this many levels, whichever comes first

local scan = nil              -- the scan in progress: { kind, done, total, started, ... }
local ahOpen = false
local events = CreateFrame("Frame")

local function say(msg) if ns.say then ns.say(msg) else print("Top Ramen: " .. msg) end end
local function refresh() if ns.RefreshWindow then ns.RefreshWindow() end end
local function after(sec, fn) if C_Timer then C_Timer.After(sec, fn) else fn() end end
-- shared by the Top Ramen addons (Gear also does full scans): when any of them last asked for one,
-- so neither asks again inside the game's 15 minutes, and each reads the other's results
local shared = _G.TopRamenAH or {}
_G.TopRamenAH = shared

local function db()
  local d = ns.db and ns.db() or {}
  d.vendor = d.vendor or {}
  d.ah = d.ah or {}
  return d
end

-- prices are kept per realm and faction: { items = { [itemID] = { p = copper each, q = units listed, t = time } }, fullScanAt, lastFullAttempt }
local function realm()
  local _, faction = UnitFactionGroup("player")
  local key = (GetRealmName and GetRealmName() or "?") .. "-" .. (faction or "")
  local d = db()
  d.ah[key] = d.ah[key] or { items = {} }
  d.ah[key].items = d.ah[key].items or {}
  return d.ah[key]
end

-- levels: { {unitPrice, quantity}, ... } in any order; stored flat and cheapest first: { price1, qty1, price2, qty2, ... }
local function compactLevels(levels)
  if not levels then return nil end
  table.sort(levels, function(a, b) return a[1] < b[1] end)
  local flat, units = {}, 0
  for _, lv in ipairs(levels) do
    if #flat >= KEEP_LEVELS * 2 or units >= KEEP_UNITS then break end
    local n = #flat
    if n > 0 and flat[n - 1] == lv[1] then flat[n] = flat[n] + lv[2]
    else flat[n + 1] = lv[1]; flat[n + 2] = lv[2] end
    units = units + lv[2]
  end
  return flat
end

local function record(id, price, qty, t, levels)
  if not id or not price or price <= 0 then return end
  realm().items[id] = { p = math.floor(price + 0.5), q = qty, t = t or time(), l = compactLevels(levels) }
end

-- a single search from the shopping panel also refreshes that item's price and price levels
-- levels: { {unitPrice, quantity}, ... }
function Prices.recordSearch(id, price, qty, levels) record(id, price, qty, nil, levels) end

---------------------------------------------------------------------------
-- lookups used by the planner
---------------------------------------------------------------------------
-- our auction price for an item: copper each, age in whole days, units listed when seen, and the price levels
-- (flat: price1, qty1, price2, qty2 ... cheapest first). nil if never seen.
function Prices.lookup(id)
  local e = realm().items[id]
  if not e then return nil end
  return e.p, math.floor((time() - (e.t or 0)) / 86400), e.q, e.l
end

-- every item from the scans: fn(itemID, entry) with entry = { p, q, t, l }
function Prices.forEach(fn)
  for id, e in pairs(realm().items) do fn(id, e) end
end

function Prices.vendorPrice(id)
  return db().vendor[id]
end

function Prices.isAHOpen()
  return ahOpen or (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or false
end

function Prices.isScanning() return scan ~= nil end

-- how far along the scan in progress is, 0..1 (nil when not scanning).
-- Full scan: the wait for the auction house's data has no progress from the game, so it's estimated
-- from time spent (creeping toward 50%); reading the listings fills the rest exactly.
local FULL_WAIT_GUESS = 45 -- seconds the auction house usually takes to send everything
function Prices.progress()
  if not scan then return nil end
  if scan.kind == "quick" then return (scan.done or 0) / math.max(1, scan.total or 1) end
  if not scan.total then
    local waited = (GetTime and GetTime() or time()) - (scan.clock or 0)
    return math.min(0.49, 0.5 * waited / FULL_WAIT_GUESS)
  end
  return 0.5 + 0.5 * (scan.done or 0) / math.max(1, scan.total)
end

local function ago(t)
  local s = time() - t
  if s < 90 then return "just now" end
  if s < 3600 then return math.floor(s / 60) .. " min ago" end
  if s < 129600 then return math.floor(s / 3600 + 0.5) .. " hours ago" end
  return math.floor(s / 86400 + 0.5) .. " days ago"
end

-- when our prices were last refreshed by a full or quick scan (nil = never)
function Prices.lastScanAt()
  local r = realm()
  local t = math.max(r.fullScanAt or 0, r.quickScanAt or 0)
  return t > 0 and t or nil
end

-- freshness of our auction prices: "ok" (15 min or less), "aging" (up to 24 hours), "old" (older or never), and how long ago
function Prices.freshness()
  local t = Prices.lastScanAt()
  if not t then return "old", nil end
  local age = time() - t
  if age <= 15 * 60 then return "ok", age end
  if age <= 24 * 3600 then return "aging", age end
  return "old", age
end

-- seconds until the game allows another full scan (0 = now)
function Prices.fullScanWait()
  local last = math.max(realm().lastFullAttempt or 0, shared.tried or 0)
  if last == 0 then return 0 end
  return math.max(0, FULL_SCAN_COOLDOWN - (time() - last))
end

-- one line for the planner window about our scan data
function Prices.statusText()
  if scan then
    if scan.kind == "full" then
      if scan.total then return ("Full scan: reading listings %d of %d..."):format(scan.done or 0, scan.total) end
      return "Full scan: waiting for the auction house to send every listing (this can take up to a minute)..."
    end
    return ("Quick scan: %d of %d items..."):format(scan.done or 0, scan.total or 0)
  end
  local r = realm()
  local n = 0
  for _ in pairs(r.items) do n = n + 1 end
  if n == 0 then return nil end
  local parts = {}
  if r.fullScanAt then parts[#parts + 1] = "full scan " .. ago(r.fullScanAt) end
  if r.quickScanAt then parts[#parts + 1] = "quick scan " .. ago(r.quickScanAt) end
  local wait = Prices.fullScanWait()
  local line = "Top Ramen prices: " .. n .. " items (" .. table.concat(parts, ", ") .. ")"
  if wait > 0 then line = line .. "; next full scan allowed in " .. math.ceil(wait / 60) .. " min" end
  return line
end

---------------------------------------------------------------------------
-- full scan
---------------------------------------------------------------------------
local function finishScan(msg)
  scan = nil
  if not ahOpen then events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE") end
  events:UnregisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  events:UnregisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  if msg then say(msg) end
  refresh()
end

local function readReplicate()
  local A = C_AuctionHouse
  local total = A.GetNumReplicateItems() or 0
  scan.total, scan.done = total, 0
  local best, qty, skipped = {}, {}, 0
  local byPrice = {} -- itemID -> { [price each] = units }
  local i = 0 -- listings are numbered from 0
  local function step()
    if not scan then return end
    local stop = math.min(total, i + CHUNK)
    while i < stop do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = A.GetReplicateItemInfo(i)
      if itemID and (buyout or 0) > 0 and (count or 0) > 0 then
        local each = buyout / count
        if not best[itemID] or each < best[itemID] then best[itemID] = each end
        qty[itemID] = (qty[itemID] or 0) + count
        local each_c = math.floor(each + 0.5)
        local m = byPrice[itemID]
        if not m then m = {}; byPrice[itemID] = m end
        m[each_c] = (m[each_c] or 0) + count
      elseif not itemID then
        skipped = skipped + 1
      end
      i = i + 1
    end
    scan.done = i
    if i < total then
      refresh()
      after(0, step)
      return
    end
    local t, items = time(), 0
    for id, p in pairs(best) do
      local levels = {}
      for price, n in pairs(byPrice[id] or {}) do levels[#levels + 1] = { price, n } end
      record(id, p, qty[id], t, levels)
      items = items + 1
    end
    realm().fullScanAt = t
    finishScan((scan and scan.passive and "prices updated from Top Ramen Gear's full scan: %d listings, %d items%s." or
      "full scan done: %d listings, prices for %d items%s."):format(total, items,
      skipped > 0 and (" (" .. skipped .. " listings had no item ID yet and were skipped)") or ""))
  end
  step()
end

function Prices.fullScan()
  local A = C_AuctionHouse
  if not (A and A.ReplicateItems) then say("this version of the game has no full auction house scan."); return end
  if not Prices.isAHOpen() then say("open the auction house first, then click Full scan."); return end
  if scan then say("a scan is already running."); return end
  local wait = Prices.fullScanWait()
  if wait > 0 then
    -- Top Ramen Gear scanned since our last full scan: its results are still here to read
    if (shared.tried or 0) > (realm().fullScanAt or 0) and (A.GetNumReplicateItems() or 0) > 0 then
      scan = { kind = "full", passive = true, started = time() }
      say("using the full scan Top Ramen Gear made " .. ago(shared.tried) .. ".")
      readReplicate()
      return
    end
    say("the game only allows a full scan every 15 minutes. Next one in " .. math.ceil(wait / 60) ..
      " min. Quick scan checks just your recipe materials right now.")
    return
  end
  scan = { kind = "full", started = time(), clock = GetTime and GetTime() or time() }
  local mine = scan
  realm().lastFullAttempt = time()
  shared.tried = time()
  events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  say("full scan started. It can take up to a minute; keep the auction house open.")
  local ok, err = pcall(A.ReplicateItems)
  if not ok then finishScan("full scan failed: " .. tostring(err)); return end
  refresh()
  after(90, function()
    if scan and scan == mine and not scan.total then
      realm().lastFullAttempt = nil
      finishScan("the auction house didn't send the full scan. It may still be on its 15-minute cooldown; try Quick scan.")
    end
  end)
end

---------------------------------------------------------------------------
-- quick scan: one search per item
---------------------------------------------------------------------------
local function wantedItems()
  local ids, list = {}, {}
  local c = ns.charData and ns.charData()
  for _, p in pairs(c and c.professions or {}) do
    for _, r in pairs(p.recipes or {}) do
      for _, rg in ipairs(r.reagents or {}) do if (rg.id or 0) > 0 then ids[rg.id] = true end end
      if (r.out or 0) > 0 then ids[r.out] = true end
    end
  end
  for id in pairs(ids) do
    -- vendor goods don't need searching
    if not db().vendor[id] and not (ns.VENDOR_LIST_PRICE and ns.VENDOR_LIST_PRICE[id]) then list[#list + 1] = id end
  end
  table.sort(list)
  return list
end

local quickNext

local function quickResult(id, price, qty, levels)
  if not scan or scan.kind ~= "quick" or scan.current ~= id then return end
  if price then record(id, price, qty, nil, levels); scan.found = scan.found + 1 end
  scan.current = nil
  scan.done = scan.done + 1
  refresh()
  after(0.1, quickNext)
end

quickNext = function()
  if not scan or scan.kind ~= "quick" then return end
  if not Prices.isAHOpen() then finishScan("quick scan stopped: the auction house closed."); return end
  local A = C_AuctionHouse
  if scan.done >= scan.total then
    realm().quickScanAt = time()
    finishScan(("quick scan done: prices for %d of %d items (the rest aren't listed right now)."):format(scan.found, scan.total))
    return
  end
  if A.IsThrottledMessageSystemReady and not A.IsThrottledMessageSystemReady() then after(0.3, quickNext); return end
  local id = scan.list[scan.done + 1]
  scan.current = id
  local mine = scan
  after(QUICK_TIMEOUT, function() if scan and scan == mine and scan.current == id then quickResult(id, nil) end end)
  local ok = pcall(A.SendSearchQuery, A.MakeItemKey(id), {}, true)
  if not ok then quickResult(id, nil) end
end

function Prices.quickScan()
  local A = C_AuctionHouse
  if not (A and A.SendSearchQuery and A.MakeItemKey) then say("this version of the game has no auction house search."); return end
  if not Prices.isAHOpen() then say("open the auction house first, then click Quick scan."); return end
  if scan then say("a scan is already running."); return end
  local list = wantedItems()
  if #list == 0 then say("no recipes recorded yet: open your profession windows first."); return end
  scan = { kind = "quick", list = list, total = #list, done = 0, found = 0 }
  events:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  events:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  say("quick scan: checking " .. #list .. " items your recipes use...")
  refresh()
  quickNext()
end

---------------------------------------------------------------------------
-- vendors
---------------------------------------------------------------------------
local function readMerchant()
  local n = GetMerchantNumItems and GetMerchantNumItems() or 0
  local d, saved = db(), 0
  for i = 1, n do
    local id = GetMerchantItemID and GetMerchantItemID(i)
    local price, stack, available, extended
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
      local info = C_MerchantFrame.GetItemInfo(i)
      if info then price, stack, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
    else
      local _
      _, _, price, stack, available, _, _, extended = GetMerchantItemInfo(i)
    end
    -- unlimited stock bought with gold only
    if id and (price or 0) > 0 and not extended and (available == nil or available < 0) then
      d.vendor[id] = price / math.max(1, stack or 1)
      saved = saved + 1
    end
  end
  if saved > 0 then refresh() end
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_SHOW" }) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    -- listen for full scans from either addon while the auction house is open
    pcall(events.RegisterEvent, events, "REPLICATE_ITEM_LIST_UPDATE")
    -- remember our own last scan for the other addons (after a /reload the shared note is empty)
    shared.tried = math.max(shared.tried or 0, realm().lastFullAttempt or 0)
    refresh()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
    if not scan then events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE") end
    if scan then finishScan(scan.kind == "full" and "full scan stopped: the auction house closed." or "quick scan stopped: the auction house closed.") end
    refresh()
  elseif event == "MERCHANT_SHOW" then
    after(0.3, readMerchant)
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    if scan and scan.kind == "full" and not scan.total then
      readReplicate()
    elseif not scan and (shared.tried or 0) > (realm().fullScanAt or 0) and time() - (shared.tried or 0) < 600 then
      -- Top Ramen Gear asked for a full scan: update our prices from it too (once it has all arrived)
      scan = { kind = "full", passive = true, started = time() }
      after(2, function() if scan and scan.passive and not scan.total then readReplicate() end end)
    end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local id = arg1
    if scan and scan.kind == "quick" and scan.current == id then
      local A = C_AuctionHouse
      local n = A.GetNumCommoditySearchResults(id) or 0
      if n == 0 then quickResult(id, nil); return end
      local first = A.GetCommoditySearchResultInfo(id, 1)
      local qty, levels = 0, {}
      for i = 1, n do
        local r = A.GetCommoditySearchResultInfo(id, i)
        if r then qty = qty + (r.quantity or 0); levels[#levels + 1] = { r.unitPrice or 0, r.quantity or 0 } end
      end
      quickResult(id, first and first.unitPrice, qty, levels)
    end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local key = arg1
    local id = type(key) == "table" and key.itemID
    if scan and scan.kind == "quick" and id and scan.current == id then
      local A = C_AuctionHouse
      local n = A.GetNumItemSearchResults(key) or 0
      local best, qty, levels = nil, 0, {}
      for i = 1, n do
        local r = A.GetItemSearchResultInfo(key, i)
        if r and (r.buyoutAmount or 0) > 0 then
          local each = r.buyoutAmount / math.max(1, r.quantity or 1)
          if not best or each < best then best = each end
          qty = qty + (r.quantity or 1)
          levels[#levels + 1] = { math.floor(each + 0.5), r.quantity or 1 }
        end
      end
      quickResult(id, best, qty, levels)
    end
  end
end)
