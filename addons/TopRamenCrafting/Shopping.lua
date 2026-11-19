-- Top Ramen Crafting: the shopping panel beside the auction house.
-- Lists what the planner's Shopping list says to buy at the auction house. Click a material to search it,
-- then Buy (the game quotes the real price) and Confirm. Every purchase takes your own click; the panel never
-- buys more than you still need.

local _, ns = ...
local UI = ns.UI

local PANEL_W = 380
local ROW_H = 22
local LIST_ROWS = 6          -- materials visible at once (the rest scroll)
local LEVEL_ROWS = 8         -- price levels visible at once (the rest scroll)
local LEVEL_H = 18
local WARN_OVER_SCAN = 1.25   -- warn when a quote is this much above your scanned price

local panel, rows = nil, {}
local sel = nil               -- the selected material: { id, name, need, state, ... }
local events = CreateFrame("Frame")

local GOLD, DIM, GOOD, BAD, WARN = "|cffffd100", "|cff8f877a", "|cff4ade80", "|cfff87171", "|cffe6b84f"

local function say(msg) ns.say(msg) end
local function after(sec, fn) if C_Timer then C_Timer.After(sec, fn) else fn() end end

local function coins(c)
  if not c then return DIM .. "?|r" end
  c = math.floor(c + 0.5)
  local g, s, cc = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local out = {}
  if g > 0 then out[#out + 1] = "|cffffd100" .. g .. "g|r" end
  if s > 0 or g > 0 then out[#out + 1] = "|cffc7c7cf" .. s .. "s|r" end
  out[#out + 1] = "|cffc27c3a" .. cc .. "c|r"
  return table.concat(out, " ")
end

local function A() return C_AuctionHouse end
local function ahOpen() return ns.Prices and ns.Prices.isAHOpen() end

---------------------------------------------------------------------------
-- what to buy right now (auction house items only)
---------------------------------------------------------------------------
local function toBuy()
  local list, total = {}, 0
  local shop = ns.CurrentShopping and ns.CurrentShopping() or { buy = {} }
  for _, b in ipairs(shop.buy or {}) do
    if b.where == "ah" then
      local it = ns.itemData(b.id)
      list[#list + 1] = { id = b.id, name = it and it.name or ("item " .. b.id), quality = it and it.quality or 1,
        need = b.buy, price = b.price, have = b.have, total = b.total, maxPrice = b.maxPrice, flip = b.flip }
      if b.buy > 0 and b.total then total = total + b.total end
    end
  end
  return list, total, shop.prof
end

---------------------------------------------------------------------------
-- searching and buying the selected material
---------------------------------------------------------------------------
local render

local function setState(state, msg)
  if not sel then return end
  sel.state, sel.msg = state, msg
  render()
end

local function search(entry)
  sel = { id = entry.id, name = entry.name, need = entry.need, qty = entry.need, scanPrice = entry.price, state = "searching",
          maxPrice = entry.maxPrice, flip = entry.flip }
  local a = A()
  if not (a and a.SendSearchQuery) then setState("error", "This game has no auction house search."); return end
  if a.IsThrottledMessageSystemReady and not a.IsThrottledMessageSystemReady() then
    sel.state = "waiting"; render()
    after(0.3, function() if sel and sel.id == entry.id and sel.state == "waiting" then search(entry) end end)
    return
  end
  render()
  local ok, err = pcall(a.SendSearchQuery, a.MakeItemKey(entry.id), {}, true)
  if not ok then setState("error", "Search failed: " .. tostring(err)) end
  local id = entry.id
  after(6, function() if sel and sel.id == id and sel.state == "searching" then setState("error", "No answer from the auction house. Click the item to search again.") end end)
end

-- what buying `want` costs, walking up the price levels: units you'd get, total, highest price each, levels used
local function costFor(want)
  local got, cost, maxUnit, used = 0, 0, 0, 0
  for i, lv in ipairs(sel.levels or {}) do
    if got >= want then break end
    local take = math.min(want - got, lv.quantity)
    got, cost, maxUnit, used = got + take, cost + take * lv.unitPrice, lv.unitPrice, i
  end
  return got, cost, maxUnit, used
end

local function readCommodity(id)
  local a = A()
  local n = a.GetNumCommoditySearchResults(id) or 0
  local levels, available = {}, 0
  for i = 1, n do
    local r = a.GetCommoditySearchResultInfo(id, i)
    if r and (r.quantity or 0) > 0 then
      levels[#levels + 1] = { unitPrice = r.unitPrice or 0, quantity = r.quantity }
      available = available + r.quantity
    end
  end
  sel.kind, sel.levels, sel.available = "commodity", levels, available
  sel.qty = sel.qty or sel.need
  sel.cheapest = levels[1] and levels[1].unitPrice or nil
  -- vendor flips: buy only what's listed below what a vendor pays
  if sel.maxPrice then
    local below = 0
    for _, l in ipairs(levels) do if l.unitPrice <= sel.maxPrice then below = below + l.quantity else break end end
    sel.need, sel.qty, sel.flipAvailable = below, below, below
  end
  if sel.cheapest and ns.Prices then
    local lv = {}
    for _, l in ipairs(levels) do lv[#lv + 1] = { l.unitPrice, l.quantity } end
    ns.Prices.recordSearch(id, sel.cheapest, available, lv)
  end
  if available == 0 then setState("none", "None listed right now.") else setState("results") end
end

local function readItems(key)
  local a = A()
  local n = a.GetNumItemSearchResults(key) or 0
  local list = {}
  for i = 1, n do
    local r = a.GetItemSearchResultInfo(key, i)
    if r and (r.buyoutAmount or 0) > 0 then list[#list + 1] = r end
  end
  table.sort(list, function(x, y) return x.buyoutAmount / math.max(1, x.quantity or 1) < y.buyoutAmount / math.max(1, y.quantity or 1) end)
  sel.kind, sel.listings = "item", list
  sel.levels = {}
  for _, r in ipairs(list) do sel.levels[#sel.levels + 1] = { unitPrice = r.buyoutAmount / math.max(1, r.quantity or 1), quantity = r.quantity or 1 } end
  sel.available = 0
  for _, r in ipairs(list) do sel.available = sel.available + (r.quantity or 1) end
  if list[1] and ns.Prices then
    local lv = {}
    for _, l in ipairs(sel.levels) do lv[#lv + 1] = { math.floor(l.unitPrice + 0.5), l.quantity } end
    ns.Prices.recordSearch(sel.id, list[1].buyoutAmount / math.max(1, list[1].quantity or 1), sel.available, lv)
  end
  if #list == 0 then setState("none", "None listed with a buyout right now.") else setState("results") end
end

-- step 1: ask the game for the real price
local function buy()
  if not sel or sel.state ~= "results" then return end
  local a = A()
  if sel.kind == "commodity" then
    local got, cost = costFor(sel.qty or sel.need)
    if got <= 0 then return end
    sel.quoteQty, sel.estimate = got, cost
    setState("quoting")
    local ok, err = pcall(a.StartCommoditiesPurchase, sel.id, sel.quoteQty)
    if not ok then setState("error", "Couldn't start the purchase: " .. tostring(err)); return end
    local id = sel.id
    after(5, function()
      if sel and sel.id == id and sel.state == "quoting" then
        setState("error", "The auction house didn't answer the purchase. Click Open in AH to buy it in the auction window.")
      end
    end)
  else
    local r = sel.listings[1]
    sel.quote, sel.quoteQty, sel.auction = r.buyoutAmount, r.quantity or 1, r.auctionID
    setState("confirm")
  end
end

-- step 2: your click confirms it
local function confirm()
  if not sel or sel.state ~= "confirm" then return end
  if (GetMoney and GetMoney() or 0) < (sel.quote or 0) then setState("error", "Not enough gold for this purchase."); return end
  local a = A()
  setState("buying")
  local ok, err
  if sel.kind == "commodity" then
    ok, err = pcall(a.ConfirmCommoditiesPurchase, sel.id, sel.quoteQty)
  else
    ok, err = pcall(a.PlaceBid, sel.auction, sel.quote)
  end
  if not ok then setState("error", "Purchase failed: " .. tostring(err)); return end
  -- never assume it worked: without word from the auction house, say so
  local id = sel.id
  after(5, function()
    if sel and sel.id == id and sel.state == "buying" then
      setState("error", "No word from the auction house. Check your bags; if it didn't arrive, click Open in AH to buy it there.")
    end
  end)
end

-- hand the item to the auction window's own buy screen, quantity filled in where the game allows
-- show any item on the auction window's own buy screen, quantity filled in where the game allows
local function showInAH(id, qty, name)
  local f, a = AuctionHouseFrame, A()
  if not (f and f:IsShown()) then say("open the auction house first."); return false end
  name = name or (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
  local opened = pcall(function()
    if AuctionHouseFrameDisplayMode and f.SetDisplayMode then f:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy) end
    f:SelectBrowseResult({ itemKey = a.MakeItemKey(id) })
  end)
  if not opened and f.SearchBar then
    pcall(function() f.SearchBar:SetSearchText(name); f.SearchBar:StartSearch() end)
  end
  after(0.6, function()
    pcall(function()
      local cb = f.CommoditiesBuyFrame
      local bd = cb and (cb.GetBuyDisplay and cb:GetBuyDisplay() or cb.BuyDisplay)
      if bd and bd.SetQuantitySelected then bd:SetQuantitySelected(qty) end
    end)
  end)
  say("opened " .. name .. " in the auction window" .. (qty and (" (" .. qty .. " wanted)") or "") .. ". Buy it there with the game's buttons.")
  return true
end
ns.ShowInAH = showInAH

local function openInAH()
  if not sel then return end
  local a = A()
  if sel.state == "confirm" and sel.kind == "commodity" and a.CancelCommoditiesPurchase then pcall(a.CancelCommoditiesPurchase) end
  showInAH(sel.id, sel.qty or sel.need, sel.name)
  setState("results")
end

local function cancel()
  if sel and sel.state == "confirm" and sel.kind == "commodity" and A().CancelCommoditiesPurchase then
    pcall(A().CancelCommoditiesPurchase)
  end
  if sel then setState("results") end
end

---------------------------------------------------------------------------
-- the panel
---------------------------------------------------------------------------
local function build()
  panel = CreateFrame("Frame", "TopRamenShopPanel", UIParent, "BackdropTemplate")
  UI.Skin(panel, UI.C.bg, UI.C.trim, 2, 0.97)
  panel:SetSize(PANEL_W, 560)
  panel:SetFrameStrata("HIGH")
  panel:EnableMouse(true)
  panel:Hide()
  local head = UI.Header(panel, "Shopping")
  panel.head = head

  panel.forText = UI.Text(panel, "GameFontHighlightSmall", UI.C.muted)
  panel.forText:SetPoint("TOPLEFT", 12, -(UI.HEAD_H + 8))
  panel.forText:SetPoint("RIGHT", panel, "RIGHT", -12, 0)

  local well = UI.Panel(panel, UI.C.well)
  well:SetPoint("TOPLEFT", 8, -(UI.HEAD_H + 28)); well:SetPoint("RIGHT", panel, "RIGHT", -8, 0); well:SetHeight(ROW_H * LIST_ROWS + 8)
  -- every material, scrolling when there are more than fit
  local ls = CreateFrame("ScrollFrame", "TopRamenShopListScroll", panel, "UIPanelScrollFrameTemplate")
  ls:SetPoint("TOPLEFT", 12, -(UI.HEAD_H + 32)); ls:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
  ls:SetHeight(ROW_H * LIST_ROWS)
  panel.list = CreateFrame("Frame", nil, ls)
  panel.list:SetSize(PANEL_W - 44, ROW_H)
  ls:SetScrollChild(panel.list)
  panel.listScroll = ls
  -- shown instead of rows when there's nothing to buy (wraps over several lines)
  panel.empty = UI.Text(panel, "GameFontHighlightSmall", UI.C.muted)
  panel.empty:SetPoint("TOPLEFT", 16, -(UI.HEAD_H + 38)); panel.empty:SetPoint("RIGHT", panel, "RIGHT", -40, 0)
  panel.empty:SetJustifyV("TOP")
  if panel.empty.SetSpacing then panel.empty:SetSpacing(3) end
  panel.empty:Hide()

  -- the selected material: name, quantity, unit and total price, price levels
  local top = UI.HEAD_H + 44 + ROW_H * LIST_ROWS
  panel.detail = UI.Text(panel, "GameFontHighlight", UI.C.text)
  panel.detail:SetPoint("TOPLEFT", 12, -top)
  panel.detail:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
  if panel.detail.SetSpacing then panel.detail:SetSpacing(3) end

  panel.qtyLabel = UI.Text(panel, "GameFontNormal", UI.C.gold)
  -- below the two detail lines (name / how many for sale)
  panel.qtyLabel:SetPoint("TOPLEFT", 12, -(top + 48)); panel.qtyLabel:SetText("Quantity")
  panel.qty = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  panel.qty:SetSize(84, 24); panel.qty:SetPoint("LEFT", panel.qtyLabel, "RIGHT", 14, 0)
  panel.qty:SetAutoFocus(false); panel.qty:SetNumeric(true); panel.qty:SetMaxLetters(5); panel.qty:SetJustifyH("CENTER")
  local function applyQty(self)
    local v = tonumber(self:GetText())
    if sel and v and v > 0 then sel.qty = v end
    self:ClearFocus(); render()
  end
  panel.qty:SetScript("OnEnterPressed", applyQty)
  panel.qty:SetScript("OnEditFocusLost", function(self) local v = tonumber(self:GetText()); if sel and v and v > 0 then sel.qty = v end; render() end)
  panel.qty:SetScript("OnEscapePressed", function(self) self:ClearFocus(); render() end)
  -- one click to buy only the part that's at a good price
  panel.goodOnly = UI.Button(panel, 110, 22, "Only", function()
    if sel and sel.good and sel.good > 0 then sel.qty = sel.good; render() end
  end)
  panel.goodOnly:SetPoint("LEFT", panel.qty, "RIGHT", 10, 0)
  panel.goodOnly:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Buy only the good-price part")
    GameTooltip:AddLine("Sets the quantity to the units within 25% of the cheapest listing. Buy those now and wait for the rest to come down.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  panel.goodOnly:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.goodOnly:Hide()
  panel.prices = UI.Text(panel, "GameFontHighlight", UI.C.text)
  panel.prices:SetPoint("TOPLEFT", 12, -(top + 80)); panel.prices:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
  if panel.prices.SetSpacing then panel.prices:SetSpacing(4) end

  -- price levels, cheapest first; the ones your quantity would buy are highlighted
  -- (below the quantity, the unit/total price and room for one warning line)
  local ltop = top + 150
  local lwell = UI.Panel(panel, UI.C.well)
  lwell:SetPoint("TOPLEFT", 8, -ltop); lwell:SetPoint("RIGHT", panel, "RIGHT", -8, 0); lwell:SetHeight(LEVEL_H * (LEVEL_ROWS + 1) + 6)
  panel.lvHead1 = UI.Text(panel, "GameFontHighlightSmall", UI.C.muted)
  panel.lvHead1:SetPoint("TOPLEFT", 16, -(ltop + 4)); panel.lvHead1:SetText("Price each")
  panel.lvHead2 = UI.Text(panel, "GameFontHighlightSmall", UI.C.muted)
  panel.lvHead2:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -36, -(ltop + 4)); panel.lvHead2:SetText("Available"); panel.lvHead2:SetJustifyH("RIGHT")
  local vs = CreateFrame("ScrollFrame", "TopRamenShopLevelScroll", panel, "UIPanelScrollFrameTemplate")
  vs:SetPoint("TOPLEFT", 10, -(ltop + 4 + LEVEL_H)); vs:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
  vs:SetHeight(LEVEL_H * LEVEL_ROWS)
  panel.levelList = CreateFrame("Frame", nil, vs)
  panel.levelList:SetSize(PANEL_W - 44, LEVEL_H)
  vs:SetScrollChild(panel.levelList)
  panel.levelScroll = vs
  panel.levels = {}

  -- buttons and totals sit under the price levels, so nothing overlaps
  local btop = ltop + LEVEL_H * (LEVEL_ROWS + 1) + 16
  panel.buy = UI.Button(panel, 132, 28, "Buy", function() buy() end)
  panel.buy:SetPoint("TOPLEFT", 12, -btop)
  panel.confirm = UI.Button(panel, 160, 28, "Confirm", function() confirm() end)
  panel.confirm:SetPoint("TOPLEFT", 12, -btop)
  panel.cancel = UI.Button(panel, 90, 28, "Cancel", function() cancel() end)
  panel.cancel:SetPoint("LEFT", panel.confirm, "RIGHT", 8, 0)
  panel.again = UI.Button(panel, 120, 28, "Search again", function() if sel then search({ id = sel.id, name = sel.name, need = sel.need, price = sel.scanPrice }) end end)
  panel.again:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -btop)
  panel.inAH = UI.Button(panel, 90, 28, "Open in AH", function() openInAH() end)
  panel.inAH:SetPoint("RIGHT", panel.again, "LEFT", -6, 0)
  panel.inAH:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Open in the auction window")
    GameTooltip:AddLine("Shows this item on the auction house's own buy screen, with your quantity filled in where possible. Buy it there with the game's buttons.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  panel.inAH:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local tline = UI.Line(panel)
  tline:SetPoint("TOPLEFT", 10, -(btop + 40)); tline:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -(btop + 40))
  panel.total = UI.Text(panel, "GameFontHighlightSmall", UI.C.text)
  panel.total:SetPoint("TOPLEFT", 12, -(btop + 50))
  panel.total:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
  panel.minHeight = btop + 76
  panel:SetHeight(panel.minHeight)

  panel:SetScript("OnShow", function() render() end)
end

local function getLevel(i)
  local lv = panel.levels[i]
  if lv then return lv end
  local f = CreateFrame("Frame", nil, panel.levelList)
  f:SetHeight(LEVEL_H)
  f:SetPoint("TOPLEFT", 0, -(i - 1) * LEVEL_H); f:SetPoint("RIGHT", panel.levelList, "RIGHT", 0, 0)
  local hl = f:CreateTexture(nil, "ARTWORK")
  hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.18)
  local price = UI.Text(f, "GameFontHighlightSmall", UI.C.text)
  price:SetPoint("LEFT", 6, 0)
  local avail = UI.Text(f, "GameFontHighlightSmall", UI.C.text)
  avail:SetPoint("RIGHT", -4, 0); avail:SetJustifyH("RIGHT")
  lv = { frame = f, hl = hl, price = price, avail = avail }
  panel.levels[i] = lv
  return lv
end

local function getRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, panel.list)
  r:SetHeight(ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); r:SetPoint("RIGHT", panel.list, "RIGHT", 0, 0)
  r.hl = r:CreateTexture(nil, "BACKGROUND")
  r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.82, 0, 0.12); r.hl:Hide()
  r.name = UI.Text(r, "GameFontHighlightSmall", UI.C.text)
  r.name:SetPoint("LEFT", 4, 0); r.name:SetWidth(PANEL_W - 170)
  r.need = UI.Text(r, "GameFontHighlightSmall", UI.C.text)
  r.need:SetPoint("RIGHT", -4, 0); r.need:SetWidth(120); r.need:SetJustifyH("RIGHT")
  r:SetScript("OnClick", function(self) if self.entry and self.entry.need > 0 then search(self.entry) end end)
  r:SetScript("OnEnter", function(self)
    if not self.entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.entry.id) end
    GameTooltip:AddLine(self.entry.need > 0 and "Click to search the auction house." or "You have enough.", 1, 1, 1)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

render = function()
  if not (panel and panel:IsShown()) then return end
  local list, total, prof = toBuy()
  panel.forText:SetText(prof and ("For your " .. prof .. " shopping list") or "Pick crafts in the planner (/trc) to build a list.")
  local shown = 0
  for i, e in ipairs(list) do
    local r = getRow(i)
    r.entry = e
    local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
    r.name:SetText(((q and q.hex) or "|cffffffff") .. e.name .. "|r")
    if e.need > 0 then r.need:SetText(GOLD .. "buy " .. e.need .. "|r  " .. DIM .. coins(e.price) .. "|r")
    else r.need:SetText(GOOD .. "done|r  |TInterface\\RaidFrame\\ReadyCheck-Ready:14|t") end
    if sel and sel.id == e.id then r.hl:Show() else r.hl:Hide() end
    r:Show()
    shown = i
  end
  for i = shown + 1, #rows do rows[i]:Hide() end
  if #list == 0 then
    panel.empty:SetText("Nothing to buy at the auction house.\nTick crafts on the planner's Skill-up plan or Money makers tab (/trc) to build a list.")
    panel.empty:Show()
  else
    panel.empty:Hide()
  end
  panel.list:SetHeight(math.max(1, math.max(#list, 1) * ROW_H))

  -- the selected material
  panel.buy:Hide(); panel.confirm:Hide(); panel.cancel:Hide(); panel.again:Hide()
  panel.inAH:SetShown(sel ~= nil and sel.state ~= "searching" and sel.state ~= "waiting" and sel.state ~= "confirm")
  local d = ""
  local showQty, prices, usedLevels, goodButton = false, "", 0, nil
  if sel then
    -- the amount still needed may have dropped since (bought, or found in the bank)
    for _, e in ipairs(list) do if e.id == sel.id then sel.need = e.need end end
    d = GOLD .. sel.name .. "|r  " .. DIM .. "need " .. sel.need .. "|r\n"
    local st = sel.state
    if st == "searching" or st == "waiting" then d = d .. "Searching the auction house..."
    elseif st == "none" then d = d .. WARN .. (sel.msg or "None listed.") .. "|r"; panel.again:Show()
    elseif st == "error" then d = d .. BAD .. (sel.msg or "Something went wrong.") .. "|r"; panel.again:Show()
    elseif st == "results" then
      if sel.need <= 0 then
        d = d .. GOOD .. "You have enough now.|r"
      elseif sel.kind == "commodity" then
        showQty = true
        local got, cost, maxUnit, used = costFor(sel.qty or sel.need)
        usedLevels = used
        prices = ("Unit price  %s\nTotal price  %s"):format(coins(got > 0 and cost / got or nil), coins(cost))
        d = d .. sel.available .. " for sale, cheapest " .. coins(sel.cheapest) .. " each."
        if got < (sel.qty or sel.need) then d = d .. " " .. WARN .. "Only " .. got .. " available.|r" end
        -- how many of what you need are at a good price (within 25% of the cheapest listing; for a vendor flip,
        -- at or below the most you can pay and still profit from the vendor)
        local good, limit = 0, sel.maxPrice or (sel.cheapest or 0) * 1.25
        for _, lv in ipairs(sel.levels) do
          if lv.unitPrice > limit or good >= sel.need then break end
          good = good + math.min(lv.quantity, sel.need - good)
        end
        sel.good = good
        if sel.maxPrice then
          prices = prices .. "\n" .. (good > 0 and (GOOD .. good .. " listed at or below " .. coins(sel.maxPrice) .. ", the most that still profits from a vendor.|r")
            or (BAD .. "None are below what a vendor pays any more.|r"))
          if (sel.qty or 0) > good then prices = prices .. "\n" .. WARN .. "Buying more than " .. good .. " loses money.|r" end
        elseif good > 0 and good < sel.need then
          prices = prices .. "\n" .. WARN .. "Good price for " .. good .. " (up to " .. coins(math.floor(limit)) .. "); the rest cost more.|r"
          goodButton = good
        elseif sel.scanPrice and maxUnit > sel.scanPrice * WARN_OVER_SCAN then
          prices = prices .. "\n" .. WARN .. "Some cost well above your scanned " .. coins(sel.scanPrice) .. " each.|r"
        end
        panel.buy:SetText("Buy Now"); panel.buy:Show(); panel.again:Show()
      else
        local r = sel.listings[1]
        d = d .. ("%d listing(s). Cheapest: %d for %s"):format(#sel.listings, r.quantity or 1, coins(r.buyoutAmount))
        if sel.maxPrice and r.buyoutAmount and r.buyoutAmount / math.max(1, r.quantity or 1) > sel.maxPrice then
          d = d .. "\n" .. BAD .. "That's more than a vendor pays: no profit.|r"
        end
        panel.buy:SetText("Buy cheapest"); panel.buy:Show(); panel.again:Show()
      end
    elseif st == "quoting" then d = d .. "Getting the exact price from the auction house..."
    elseif st == "confirm" then
      d = d .. ("Buy %d for %s total (%s each)?"):format(sel.quoteQty, coins(sel.quote), coins((sel.quote or 0) / math.max(1, sel.quoteQty)))
      if sel.estimate and sel.kind == "commodity" and sel.quote > sel.estimate * 1.1 then
        d = d .. "\n" .. WARN .. "That's more than the " .. coins(sel.estimate) .. " shown a moment ago: prices changed.|r"
      end
      if (GetMoney and GetMoney() or 0) < (sel.quote or 0) then d = d .. "\n" .. BAD .. "You don't have enough gold.|r" end
      panel.confirm:SetText("Confirm " .. coins(sel.quote)); panel.confirm:Show(); panel.cancel:Show()
    elseif st == "buying" then d = d .. "Buying..."
    elseif st == "bought" then
      d = d .. GOOD .. "Bought.|r" .. (sel.need > 0 and (" Still need " .. sel.need .. ".") or "")
      if sel.need > 0 then panel.again:SetText("Search again"); panel.again:Show() end
    end
    if st == "confirm" or st == "quoting" or st == "buying" then usedLevels = select(4, costFor(sel.quoteQty or sel.qty or sel.need)) end
  else
    d = DIM .. "Click a material above to search the auction house for it.|r"
  end
  panel.detail:SetText(d)
  -- quantity box, unit/total price, price levels
  if goodButton and (sel.qty or sel.need) ~= goodButton then
    panel.goodOnly:SetText("Only " .. goodButton); panel.goodOnly:Show()
  else
    panel.goodOnly:Hide()
  end
  if showQty then
    panel.qtyLabel:Show(); panel.qty:Show()
    if not panel.qty:HasFocus() then panel.qty:SetText(tostring(sel.qty or sel.need)) end
  else
    panel.qtyLabel:Hide(); panel.qty:Hide()
  end
  panel.prices:SetText(prices)
  local levels = sel and sel.levels or {}
  for i, lv in ipairs(levels) do
    local row = getLevel(i)
    row.price:SetText(coins(lv.unitPrice)); row.avail:SetText(tostring(lv.quantity))
    row.price:Show(); row.avail:Show(); row.frame:Show()
    if i <= usedLevels then row.hl:Show() else row.hl:Hide() end
  end
  for i = #levels + 1, #panel.levels do panel.levels[i].frame:Hide() end
  panel.levelList:SetHeight(math.max(1, #levels * LEVEL_H))
  local hasLevels = #levels > 0
  panel.lvHead1:SetShown(hasLevels); panel.lvHead2:SetShown(hasLevels)
  local money = GetMoney and GetMoney() or 0
  panel.total:SetText("Left to buy here: " .. coins(total) .. "    Your gold: " .. coins(money))
end

function ns.ShowShopPanel()
  if not panel then build() end
  panel:ClearAllPoints()
  if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 6, 0)
    local h = AuctionHouseFrame:GetHeight()
    panel:SetHeight(math.max(panel.minHeight, h or 0)) -- at least tall enough for everything
  else
    panel:SetPoint("CENTER")
  end
  panel:Show()
  render()
end

function ns.RefreshShopPanel() if panel and panel:IsShown() then render() end end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
                     "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
                     "AUCTION_HOUSE_PURCHASE_COMPLETED", "BAG_UPDATE_DELAYED", "PLAYER_MONEY" }) do
  pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "AUCTION_HOUSE_SHOW" then
    sel = nil
    after(0.2, ns.ShowShopPanel)
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if sel and sel.state == "confirm" and sel.kind == "commodity" and A() and A().CancelCommoditiesPurchase then pcall(A().CancelCommoditiesPurchase) end
    sel = nil
    if panel then panel:Hide() end
  elseif not sel then
    if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then ns.RefreshShopPanel() end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if sel.state == "searching" and a1 == sel.id then readCommodity(a1) end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    if sel.state == "searching" and type(a1) == "table" and a1.itemID == sel.id then readItems(a1) end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    -- a1 = price each, a2 = total for the quantity asked
    if sel.state == "quoting" then sel.quote = a2 or ((a1 or 0) * (sel.quoteQty or 0)); setState("confirm") end
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    if sel.state == "quoting" then setState("error", "The price changed or there aren't enough left. Search again.") end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if sel.state == "buying" then say("bought " .. sel.quoteQty .. " " .. sel.name .. " for " .. coins(sel.quote) .. "."); setState("bought") end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if sel.state == "buying" then setState("error", "The purchase failed. Search again.") end
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    if sel.state == "buying" then say("bought " .. sel.name .. " for " .. coins(sel.quote) .. "."); setState("bought") end
  elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then
    ns.RefreshShopPanel()
  end
end)
