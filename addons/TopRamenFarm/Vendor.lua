-- Top Ramen Farm: the "Vendor items" button (bottom-left of the farm window while you talk to a merchant). It sells what the farm tracker
-- says is better sold to a vendor, and plays it safe about everything else.
--
-- It's manual: tick the items you want gone on the My bags tab, then click Vendor items.
-- Ticks are saved per character and clear once that item has been sold.

local _, ns = ...
local UI = ns.UI
local HX = UI.HEX

local Use = (C_Container and C_Container.UseContainerItem) or UseContainerItem
local SELL_GAP = 0.2 -- seconds between sales; selling everything in one frame makes some sales fail

local atMerchant = false
local ticker = nil

-- ticked items, saved per character: [itemID] = true
function ns.vendorPicks()
  local c = ns.char()
  c.vendorPick = c.vendorPick or {}
  return c.vendorPick
end
function ns.isVendorPick(id) return id and ns.vendorPicks()[id] or false end
function ns.setVendorPick(id, on)
  if id then ns.vendorPicks()[id] = on and true or nil end
end

-- should the item in this bag slot be sold? only if you ticked it (and a vendor will buy it)
local function pick(bag, slot)
  local id, count, _, bound, noValue = ns.slotInfo(bag, slot)
  if not id or noValue or not ns.isVendorPick(id) or ns.isQuestSlot(bag, slot) then return nil end
  local v = ns.itemValue(id, bound)
  if not v or v.quest or v.vendor <= 0 then return nil end
  return id, count or 1, v
end

-- everything we'd sell right now: { {bag, slot, id, n, link, value} }, total copper
function ns.vendorList()
  local list, total = {}, 0
  if not ns.NumSlots then return list, total end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (ns.NumSlots(bag) or 0) do
      local id, n, v = pick(bag, slot)
      if id then
        list[#list + 1] = { bag = bag, slot = slot, id = id, n = n, link = v.link, value = v }
        total = total + v.vendor * n
      end
    end
  end
  return list, total
end

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

-- the button lives in the farm window (Window.lua); this redraws it
local function update()
  if ns.Refresh then ns.Refresh(false) end
end

-- for the farm window: are we at a merchant, and are we selling right now?
function ns.VendorStatus() return atMerchant, ticker ~= nil end

local function finish(sold, made, why, need, done)
  if ticker then ticker:Cancel(); ticker = nil end
  -- an item whose every ticked stack sold is done: clear its tick
  for id, n in pairs(need or {}) do
    if (done[id] or 0) >= n then ns.setVendorPick(id, false) end
  end
  ns.say((why or "") .. "sold " .. plural(sold, "stack") .. " for " .. ns.coins(made) .. ".")
  update()
end

local function sellAll()
  if ticker or not atMerchant then return end
  local list = ns.vendorList()
  if #list == 0 then ns.say("nothing is ticked to sell."); return end
  local i, sold, made = 0, 0, 0
  local need, done = {}, {} -- stacks per item id: ticked / sold
  for _, e in ipairs(list) do need[e.id] = (need[e.id] or 0) + 1 end
  ticker = C_Timer.NewTicker(SELL_GAP, function()
    if not atMerchant then finish(sold, made, "stopped because the merchant window closed. ", need, done); return end
    i = i + 1
    local e = list[i]
    if not e then finish(sold, made, nil, need, done); return end
    -- only sell if the same item is still in that slot
    local id, count = ns.slotInfo(e.bag, e.slot)
    if id == e.id then
      Use(e.bag, e.slot)
      sold = sold + 1
      done[id] = (done[id] or 0) + 1
      made = made + e.value.vendor * (count or e.n)
    end
  end)
  update()
end

StaticPopupDialogs.TOPRAMENFARM_VENDOR = {
  text = "%s",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function() sellAll() end,
  timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
}

function ns.VendorPrompt()
  if not atMerchant then ns.say("talk to a merchant first."); return end
  if ticker then return end
  local list, total = ns.vendorList()
  if #list == 0 then
    ns.say("nothing is ticked to sell. Tick items on the My bags tab first.")
    if ns.ShowTab then ns.ShowTab("bags") end
    return
  end
  StaticPopup_Show("TOPRAMENFARM_VENDOR", "Sell the " .. plural(#list, "stack") .. " you ticked to this merchant for " .. ns.coins(total) .. "?" ..
    (#list > 12 and "\n\nThe merchant's Buyback tab only holds your last 12 sales." or ""))
end

function ns.VendorTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("|cffffd100Top Ramen Farm:|r Vendor items")
  local list, total = ns.vendorList()
  if #list == 0 then
    GameTooltip:AddLine("Nothing is ticked. Tick the items you want to sell on the My bags tab.", 1, 1, 1, true)
  else
    GameTooltip:AddDoubleLine("Sells " .. plural(#list, "stack") .. " for", ns.coins(total), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine(" ")
    table.sort(list, function(a, b) return a.value.vendor * a.n > b.value.vendor * b.n end)
    for k = 1, math.min(#list, 12) do
      local e = list[k]
      GameTooltip:AddDoubleLine((e.link or ("item " .. e.id)) .. (e.n > 1 and (" x" .. e.n) or ""), ns.coins(e.value.vendor * e.n), 1, 1, 1, 1, 1, 1)
    end
    if #list > 12 then GameTooltip:AddLine("...and " .. (#list - 12) .. " more", 0.72, 0.68, 0.61) end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Sells only what you ticked on the My bags tab. You confirm before anything is sold, and an item's tick clears once it's sold.", 0.72, 0.68, 0.61, true)
  GameTooltip:Show()
end

local queued = false
local function updateSoon()
  if queued then return end
  queued = true
  C_Timer.After(0.3, function() queued = false; update() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_CLOSED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:SetScript("OnEvent", function(_, event)
  if event == "MERCHANT_SHOW" then
    atMerchant = true
    update()
  elseif event == "MERCHANT_CLOSED" then
    atMerchant = false
    if StaticPopup_Hide then StaticPopup_Hide("TOPRAMENFARM_VENDOR") end
    update()
  elseif atMerchant and not ticker then
    updateSoon()
  end
end)
