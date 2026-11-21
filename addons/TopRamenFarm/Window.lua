-- Top Ramen Farm: the window (/trfarm) and the little mini tracker shown while recording.

local _, ns = ...
local UI = ns.UI
local C = UI.C
local HX = UI.HEX

local WIDTH, HEIGHT = 780, 580
local MIN_W, MIN_H, MAX_W, MAX_H = 720, 440, 1600, 1100
local ROW_H = 22
local TOP_LIST = 200 -- where the list well starts, from the top of the window
local GOAL_H = 94    -- the Goal tab's settings sit at the top of the well; its list starts this much lower

local frame, mini
local W = {}
local tab = "loot"      -- "loot" | "bags" | "history" | "goal"
local bagSnap = nil     -- what's in your bags, re-read on every refresh of the My bags tab
local viewIndex = nil   -- a history session being looked at (nil = current, or the last one)
local rows = {}

---------------------------------------------------------------------------
-- sorting: click a column header to sort by it, click it again to flip the order.
-- Loot and My bags share one setting, History has its own; both are saved.
---------------------------------------------------------------------------
local DEFAULT_SORT = { loot = { key = "best", desc = true }, history = { key = "date", desc = true },
  goal = { key = "rate", desc = true } }
local TEXT_KEYS = { name = true } -- these start A to Z
local ASC_KEYS = { eta = true }   -- these start smallest first; every other column starts biggest / newest first

local function sortGroup()
  if tab == "history" or tab == "goal" then return tab end
  return "loot"
end

local function sortState()
  local st = ns.settings()
  st.sort = st.sort or {}
  local g = sortGroup()
  if type(st.sort[g]) ~= "table" or not st.sort[g].key then
    st.sort[g] = { key = DEFAULT_SORT[g].key, desc = DEFAULT_SORT[g].desc }
  end
  return st.sort[g]
end

local function setSort(key)
  local s = sortState()
  if s.key == key then s.desc = not s.desc
  else s.key, s.desc = key, not (TEXT_KEYS[key] or ASC_KEYS[key]) end
  ns.Refresh(false)
end

-- sorts list by valueOf(entry, key). Entries whose value is nil (item still loading) always go last.
local function sortList(list, valueOf, key, desc, tiebreak)
  table.sort(list, function(a, b)
    local x, y = valueOf(a, key), valueOf(b, key)
    if type(x) == "string" then x = x:lower() end
    if type(y) == "string" then y = y:lower() end
    if x ~= y then
      if x == nil then return false end
      if y == nil then return true end
      if desc then return x > y end
      return x < y
    end
    return tiebreak(a, b)
  end)
end

local function label(parent, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  return fs
end

local function tip(widget, title, text, anchor)
  widget:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, anchor or "ANCHOR_BOTTOM")
    GameTooltip:AddLine(title)
    if text then GameTooltip:AddLine(type(text) == "function" and text() or text, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function dateText(t)
  if not t then return "?" end
  return date("%b %d %H:%M", t)
end

-- which session the Loot tab shows, and how to describe it
local function shown()
  if tab == "bags" then
    bagSnap = bagSnap or ns.scanBags()
    return bagSnap, "bags"
  end
  local c = ns.char()
  if viewIndex and c.history[viewIndex] then return c.history[viewIndex], "history" end
  viewIndex = nil
  if c.session then return c.session, "current" end
  if c.history[1] then return c.history[1], "last" end
  return nil, "none"
end

---------------------------------------------------------------------------
-- columns
---------------------------------------------------------------------------
local LOOT_COLS = {          -- laid out from the right edge
  { key = "to", w = 74, title = "Sell to", justify = "CENTER" },
  { key = "best", w = 104, title = "Best total" },
  { key = "aEach", w = 92, title = "AH each" },
  { key = "vTot", w = 104, title = "Vendor total" },
  { key = "vEach", w = 88, title = "Vendor each" },
  { key = "qty", w = 44, title = "Qty" },
}
local HIST_COLS = {
  { key = "hr", w = 104, title = "Smart / hour" },
  { key = "smart", w = 104, title = "Sell smart" },
  { key = "vend", w = 104, title = "Vendor value" },
  { key = "gold", w = 96, title = "Coin looted" },
  { key = "dur", w = 70, title = "Time" },
}
local GOAL_COLS = {
  { key = "eta", w = 96, title = "To goal" },
  { key = "rate", w = 108, title = "Per hour" },
  { key = "value", w = 104, title = "Made" },
  { key = "time", w = 80, title = "Time" },
  { key = "runs", w = 52, title = "Runs" },
}
local MAX_CELLS = 6

local function colsFor()
  if tab == "history" then return HIST_COLS end
  if tab == "goal" then
    local smart = ns.goalKind() == "smart"
    GOAL_COLS[2].title = smart and "Smart / hour" or "Vendor / hour"
    GOAL_COLS[3].title = smart and "Sell smart" or "Vendor value"
    return GOAL_COLS
  end
  return LOOT_COLS
end

local function layoutCells(owner, cells, left, cols, leftPad)
  local x = 6
  for i = 1, MAX_CELLS do
    local cell, col = cells[i], cols[i]
    cell:ClearAllPoints()
    if col then
      cell:SetPoint("RIGHT", owner, "RIGHT", -x, 0)
      cell:SetWidth(col.w - 6)
      cell:SetJustifyH(col.justify or "RIGHT")
      cell:Show()
      x = x + col.w
    else
      cell:Hide()
    end
  end
  left:ClearAllPoints()
  left:SetPoint("LEFT", owner, "LEFT", leftPad or 6, 0)
  left:SetPoint("RIGHT", owner, "RIGHT", -x - 4, 0)
end

---------------------------------------------------------------------------
-- list rows
---------------------------------------------------------------------------
local function rowTooltip(row)
  local d = row.data
  if not d then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  if d.kind == "item" then
    if d.link then GameTooltip:SetHyperlink(d.link) else GameTooltip:AddLine(d.name or "Item") end
    local v = d.value
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffd100Top Ramen Farm|r")
    if v then
      GameTooltip:AddDoubleLine("Looted", tostring(d.n), 1, 1, 1, 1, 1, 1)
      GameTooltip:AddDoubleLine("Vendor each", ns.money(v.vendor), 1, 1, 1, 1, 1, 1)
      if not v.canAH then
        GameTooltip:AddLine(v.bound and "Soulbound: vendor only." or "Can't be sold on the auction house.", 0.72, 0.68, 0.61, true)
      elseif v.ah then
        local age = v.age and (v.age == 0 and "today" or (v.age .. (v.age == 1 and " day ago" or " days ago"))) or "age unknown"
        GameTooltip:AddDoubleLine("Auction house each", ns.money(v.ah), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("After the 5% AH cut", ns.money(v.ahNet), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine("Price from " .. (v.src or "?") .. ", " .. age .. ".", 0.72, 0.68, 0.61, true)
      else
        GameTooltip:AddLine("No auction price yet. Scan the auction house with Top Ramen Crafting (or Auctionator) to compare.", 0.72, 0.68, 0.61, true)
      end
    end
  elseif d.kind == "money" then
    GameTooltip:AddLine("Coin looted")
    GameTooltip:AddLine("Gold, silver and copper you looted straight from corpses and chests. Counts the same either way you sell.", 1, 1, 1, true)
  elseif d.kind == "history" then
    local s = d.session
    GameTooltip:AddLine(dateText(s.startedAt) .. " - " .. (s.endedAt and date("%H:%M", s.endedAt) or "?"))
    if s.zoneOrder and #s.zoneOrder > 0 then GameTooltip:AddLine(table.concat(s.zoneOrder, ", "), 1, 1, 1, true) end
    GameTooltip:AddLine("Click to see this session's loot.", 0.29, 0.87, 0.5)
    GameTooltip:AddLine("Shift + right-click to delete it.", 0.97, 0.44, 0.44)
  elseif d.kind == "zone" then
    local z = d.z
    GameTooltip:AddLine(z.name)
    GameTooltip:AddDoubleLine("Runs", tostring(z.runs), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Time farmed", ns.clock(z.sec), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Coin looted", ns.money(z.money), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Vendor value", ns.money(z.vendor), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Sell smart", ns.money(z.smart), 1, 1, 1, 1, 1, 1)
    if d.rate then GameTooltip:AddDoubleLine("Per hour", ns.money(d.rate), 1, 1, 1, 1, 1, 1) end
    if z.name:find(",") then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Runs from before zone tracking that crossed zones are grouped together here. New runs split their time and loot by zone.", 0.72, 0.68, 0.61, true)
    end
  end
  GameTooltip:Show()
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, W.content)
  r:SetHeight(ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.stripe = r:CreateTexture(nil, "BACKGROUND")
  r.stripe:SetAllPoints()
  r.stripe:SetColorTexture(C.row[1], C.row[2], C.row[3], 1)
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
  -- My bags tab: tick an item to sell it with Vendor items (unticked by default)
  r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
  r.check:SetSize(22, 22)
  r.check:SetPoint("LEFT", 2, 0)
  r.check:SetScript("OnClick", function(self)
    ns.setVendorPick(self.id, self:GetChecked())
    ns.Refresh(false)
  end)
  r.check:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Sell with Vendor items")
    GameTooltip:AddLine("Ticked items are sold when you click Vendor items at a merchant. The tick clears once the item is sold.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  r.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r.check:Hide()
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(18, 18)
  r.icon:SetPoint("LEFT", 4, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.left = label(r, "", "GameFontHighlightSmall")
  r.left:SetWordWrap(false)
  r.cells = {}
  for c = 1, MAX_CELLS do
    r.cells[c] = label(r, "", "GameFontHighlightSmall")
    r.cells[c]:SetWordWrap(false)
  end
  r:SetScript("OnEnter", rowTooltip)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self, button)
    local d = self.data
    if not d then return end
    if d.kind == "item" and IsModifiedClick and IsModifiedClick("CHATLINK") and d.link then
      if ChatEdit_InsertLink then ChatEdit_InsertLink(d.link) end
    elseif d.kind == "history" then
      if button == "RightButton" and IsShiftKeyDown() then
        ns.deleteHistory(d.index)
      elseif button == "LeftButton" then
        viewIndex, tab = d.index, "loot"
        ns.Refresh(true)
      end
    end
  end)
  rows[i] = r
  return r
end

local function sellToText(v)
  if not v then return HX.dim .. "...|r" end
  if v.sellTo == "ah" then return HX.gold .. "AH|r" end
  if v.sellTo == "vendor" then return "|cff9fd3ffVendor|r" end
  return HX.dim .. "no value|r"
end

local function lootSortValue(e, key)
  if key == "name" then return e.name end
  if key == "qty" then return e.n end
  local v = e.value
  if not v then return nil end
  if key == "vEach" then return v.vendor
  elseif key == "vTot" then return v.vendor * e.n
  elseif key == "aEach" then return v.ahNet or -1
  elseif key == "to" then return (v.sellTo == "ah" and 2) or (v.sellTo == "vendor" and 1) or 0
  end
  return v.best * e.n -- "best"
end

local function fillLoot(s)
  local list = {}
  if s and (s.money or 0) > 0 then
    list[#list + 1] = { kind = "money", n = s.money }
  end
  local items = {}
  for key, it in pairs(s and s.items or {}) do
    local id = it.id or key
    local v = ns.itemValue(id, it.bound)
    if not (tab == "bags" and v and (v.quest or v.vendor <= 0)) then
    items[#items + 1] = { kind = "item", id = id, n = it.n or 0, link = (v and v.link) or it.link, value = v,
      sortKey = v and v.best * (it.n or 0) or -1, name = v and v.name or ("item " .. id) }
    end
  end
  local srt = sortState()
  sortList(items, lootSortValue, srt.key, srt.desc, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  for _, e in ipairs(items) do list[#list + 1] = e end -- coin looted always stays on top
  return list
end

local function histSortValue(e, key)
  local s, snap = e.session, e.snap
  if key == "dur" then return s.elapsed or 0
  elseif key == "gold" then return snap.money or 0
  elseif key == "vend" then return snap.vendor or 0
  elseif key == "smart" then return snap.smart or 0
  elseif key == "hr" then return ns.perHour(snap.smart, s.elapsed) or -1
  end
  return s.startedAt or 0 -- "date"
end

local function fillHistory()
  local list = {}
  for i, s in ipairs(ns.char().history) do
    list[#list + 1] = { kind = "history", index = i, session = s, snap = s.snap or ns.totals(s) }
  end
  local srt = sortState()
  sortList(list, histSortValue, srt.key, srt.desc, function(a, b) return a.index < b.index end)
  return list
end

local function goalSortValue(e, key)
  if key == "name" then return e.name end
  if key == "runs" then return e.z.runs
  elseif key == "time" then return e.z.sec
  elseif key == "value" then return e.value
  elseif key == "eta" then return e.etaSec
  end
  return e.rate -- "rate"
end

-- one row per zone you've farmed, with how long the rest of your goal would take there
local function fillGoal()
  local kind = ns.goalKind()
  local total = ns.goalTotal()
  local need = math.max(0, total - ns.goalHave())
  local list = {}
  for _, z in ipairs(ns.goalZones()) do
    local rate = ns.perHour(z[kind], z.sec)
    list[#list + 1] = { kind = "zone", name = z.name, z = z, value = z[kind], rate = rate, need = need, total = total,
      etaSec = (rate and rate > 0 and total > 0) and (need / rate * 3600) or nil }
  end
  local srt = sortState()
  sortList(list, goalSortValue, srt.key, srt.desc, function(a, b) return a.name < b.name end)
  return list
end

local function drawRows(list)
  local cols = colsFor()
  local width = W.content:GetWidth()
  for i, d in ipairs(list) do
    local r = getRow(i)
    r.data = d
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", W.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetWidth(width)
    r.stripe:SetShown(i % 2 == 0)
    for c = 1, MAX_CELLS do r.cells[c]:SetText("") end
    local showCheck = tab == "bags" and d.kind == "item" and d.value ~= nil
    r.check:SetShown(showCheck)
    if showCheck then r.check.id = d.id; r.check:SetChecked(ns.isVendorPick(d.id) and true or false) end
    local pad = tab == "bags" and 24 or 0 -- room for the checkbox
    r.icon:SetPoint("LEFT", 4 + pad, 0)
    if d.kind == "zone" then
      r.icon:Show()
      r.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
      layoutCells(r, r.cells, r.left, cols, 28)
      local z = d.z
      r.left:SetText(HX.text .. z.name .. "|r")
      r.cells[5]:SetText(tostring(z.runs))
      r.cells[4]:SetText(ns.clock(z.sec))
      r.cells[3]:SetText(ns.money(d.value, false, true))
      r.cells[2]:SetText(d.rate and ns.money(d.rate, false, true) or HX.dim .. "-|r")
      if d.total <= 0 then r.cells[1]:SetText(HX.dim .. "-|r")
      elseif d.need <= 0 then r.cells[1]:SetText(HX.green .. "done|r")
      else r.cells[1]:SetText(d.rate and (HX.text .. ns.etaText(d.need, d.rate) .. "|r") or HX.dim .. "-|r") end
    elseif d.kind == "history" then
      r.icon:Hide()
      layoutCells(r, r.cells, r.left, cols, 8)
      local s = d.session
      local snap = s.snap or ns.totals(s)
      local where = ns.zonesText(s, 2)
      r.left:SetText(HX.text .. dateText(s.startedAt) .. "|r" .. (where ~= "" and (HX.muted .. "  " .. where .. "|r") or ""))
      r.cells[5]:SetText(ns.clock(s.elapsed))
      r.cells[4]:SetText(ns.money(snap.money))
      r.cells[3]:SetText(ns.money(snap.vendor, false, true))
      r.cells[2]:SetText(ns.money(snap.smart, false, true))
      local hr = ns.perHour(snap.smart, s.elapsed)
      r.cells[1]:SetText(hr and ns.money(hr, false, true) or HX.dim .. "-|r")
    else
      r.icon:Show()
      layoutCells(r, r.cells, r.left, cols, 28 + pad)
      if d.kind == "money" then
        r.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        r.left:SetText(HX.gold .. "Coin looted|r")
        r.cells[4]:SetText(ns.money(d.n))
        r.cells[2]:SetText(ns.money(d.n))
        r.cells[1]:SetText(HX.dim .. "-|r")
      else
        local v = d.value
        r.icon:SetTexture((v and v.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
        local q = v and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[v.quality]
        r.left:SetText(((q and q.hex) or "|cffffffff") .. d.name .. "|r")
        r.cells[6]:SetText(tostring(d.n))
        if v then
          r.cells[5]:SetText(v.vendor > 0 and ns.money(v.vendor) or HX.dim .. "-|r")
          r.cells[4]:SetText(v.vendor > 0 and ns.money(v.vendor * d.n) or HX.dim .. "-|r")
          if not v.canAH then r.cells[3]:SetText(HX.dim .. "n/a|r")
          elseif v.ah then
            local old = v.age and v.age > 3
            r.cells[3]:SetText((old and "|cffb8ae9c" or "") .. ns.money(v.ahNet) .. (old and "|r" or ""))
          else r.cells[3]:SetText(HX.dim .. "no price|r") end
          r.cells[2]:SetText(ns.money(v.best * d.n))
        else
          r.cells[5]:SetText(HX.dim .. "...|r")
        end
        r.cells[1]:SetText(sellToText(v))
      end
    end
    r:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide(); rows[i].data = nil end
  W.content:SetHeight(math.max(1, #list * ROW_H))
end

---------------------------------------------------------------------------
-- refresh
---------------------------------------------------------------------------
local function setBox(box, value, sub)
  box.value:SetText(value)
  box.sub:SetText(sub or "")
end

local function hourText(c, sec)
  local hr = ns.perHour(c, sec)
  if not hr then return HX.dim .. "per hour after the first minute|r" end
  return ns.money(hr, false, true) .. HX.muted .. " per hour|r"
end

local function updateStatus()
  if not frame then return end
  local s, mode = shown()
  local running = ns.isRunning()
  W.toggle:SetText(running and "|cfff87171\226\150\160|r  Stop farming" or "|cff4ade80\226\150\182|r  Start farming")
  if running then W.toggle:LockHighlight() else W.toggle:UnlockHighlight() end
  local where = s and ns.zonesText(s, 3) or ""
  if tab == "goal" then
    W.status:SetText(HX.gold .. "Saving up|r   " .. HX.muted .. "tick what you're saving for. The zones below are your saved runs, with the farm time left at each.|r")
  elseif mode == "bags" then
    W.status:SetText(HX.gold .. "What's in my bags|r   " .. HX.muted .. "everything sellable you're carrying right now" ..
      ((s.skipped or 0) > 0 and (" \194\183 " .. s.skipped .. " quest / no-value item" .. (s.skipped == 1 and "" or "s") .. " left out") or "") .. "|r")
  elseif mode == "current" then
    W.status:SetText(HX.green .. "\226\151\143 Recording|r   " .. HX.text .. ns.clock(ns.elapsed(s)) .. "|r" .. (where ~= "" and (HX.muted .. "  \194\183  " .. where .. "|r") or ""))
  elseif mode == "history" then
    W.status:SetText(HX.gold .. "Viewing a past session|r   " .. HX.muted .. dateText(s.startedAt) .. "  \194\183  " .. ns.clock(s.elapsed) .. (where ~= "" and ("  \194\183  " .. where) or "") .. "|r")
  elseif mode == "last" then
    W.status:SetText(HX.muted .. "\226\150\160 Stopped|r   " .. HX.muted .. "last session " .. dateText(s.startedAt) .. ", " .. ns.clock(s.elapsed) .. (where ~= "" and (" in " .. where) or "") .. ". Press Start farming for a new one.|r")
  else
    W.status:SetText(HX.muted .. "Not recording. Press Start farming, then go loot things.|r")
  end
end

local function updateBoxes()
  local s, mode = shown()
  local t = ns.totals(s)
  W.boxVendor.title:SetText("Vendor everything")
  W.boxSmart.title:SetText("Sell smart")
  W.boxDiff.title:SetText("AH over vendor")
  W.goalBar:Hide()
  if mode == "bags" then
    W.boxMoney.title:SetText("Sellable items")
    setBox(W.boxMoney, HX.text .. t.count .. "|r", HX.muted .. t.kinds .. (t.kinds == 1 and " kind of item" or " kinds of items") .. "|r")
    setBox(W.boxVendor, ns.money(t.vendor), HX.muted .. "if you vendor the lot|r")
    setBox(W.boxSmart, ns.money(t.smart), HX.muted .. "AH where it pays, vendor the rest|r")
  else
    local sec = s and ns.elapsed(s) or 0
    W.boxMoney.title:SetText("Coin looted")
    setBox(W.boxMoney, ns.money(t.money), hourText(t.money, sec))
    setBox(W.boxVendor, ns.money(t.vendor), hourText(t.vendor, sec))
    setBox(W.boxSmart, ns.money(t.smart), hourText(t.smart, sec))
  end
  local diff = t.smart - t.vendor
  local sub
  if t.count == 0 then sub = HX.dim .. (mode == "bags" and "nothing sellable|r" or "nothing looted yet|r")
  elseif t.ahWins == 0 then sub = HX.muted .. "vendor is your best bet|r"
  else sub = HX.muted .. t.ahWins .. (t.ahWins == 1 and " item sells" or " items sell") .. " better on the AH|r" end
  setBox(W.boxDiff, diff > 0 and ns.money(diff, true) or ns.money(0), sub)
  if tab == "goal" then
    local g = ns.goal()
    local total, parts = ns.goalTotal()
    local have = ns.goalHave()
    local need = math.max(0, total - have)
    local pct = total > 0 and math.min(100, math.floor(have / total * 100)) or 0
    local rate, from = ns.goalRate()
    W.boxMoney.title:SetText("Goal")
    setBox(W.boxMoney, total > 0 and ns.money(total, false, true) or (HX.dim .. "-|r"),
      HX.muted .. (#parts > 0 and table.concat(parts, " + ") or "tick what you're saving for") .. "|r")
    W.boxVendor.title:SetText("You have")
    setBox(W.boxVendor, ns.money(have, false, true), HX.muted .. (g.count == "gold" and "gold on hand"
      or g.count == "vendor" and "gold + bags, vendored" or "gold + bags, sold smart") .. "|r")
    W.boxSmart.title:SetText("Still needed")
    setBox(W.boxSmart, total <= 0 and (HX.dim .. "-|r") or need <= 0 and (HX.green .. "Goal reached!|r") or ns.money(need, false, true),
      total > 0 and (HX.muted .. pct .. "% of the way there|r") or "")
    W.goalBar:SetValue(pct)
    W.goalBar:SetShown(total > 0)
    W.boxDiff.title:SetText("Farm time left")
    local eta = ns.etaText(need, rate)
    setBox(W.boxDiff, total <= 0 and (HX.dim .. "-|r") or need <= 0 and (HX.green .. "none|r") or (eta and (HX.text .. eta .. "|r") or (HX.dim .. "?|r")),
      rate and (HX.muted .. "at " .. ns.money(rate, false, true) .. HX.muted .. " per hour, " .. from .. "|r") or (HX.dim .. "farm a run to estimate|r"))
  end
  if tab == "loot" then W.tabs.loot:SetText("Loot" .. (t.count > 0 and (" (" .. t.count .. ")") or "")) end
  W.tabs.history:SetText("History (" .. #ns.char().history .. ")")
  if tab ~= "loot" then
    local live = ns.session()
    local n = live and ns.totals(live).count or 0
    W.tabs.loot:SetText("Loot" .. (n > 0 and (" (" .. n .. ")") or ""))
  end
  local src = ns.priceSources()
  if #src == 0 then
    W.prices:SetText(HX.red .. "No auction prices:|r " .. HX.muted .. "install Top Ramen Crafting or Auctionator and scan the AH to compare against vendor.|r")
  else
    W.prices:SetText(HX.muted .. "AH prices from " .. table.concat(src, " + ") .. ", after the 5% cut." ..
      (t.loading > 0 and ("  Loading " .. t.loading .. " item" .. (t.loading == 1 and "" or "s") .. "...") or "") .. "|r")
  end
  return t
end

local function updateMini()
  if not mini then return end
  local running = ns.isRunning()
  local want = running and ns.settings().mini and not (frame and frame:IsShown())
  if not want then mini:Hide(); return end
  local s = ns.session()
  local t = ns.totals(s)
  local sec = ns.elapsed(s)
  mini.top:SetText(HX.green .. "\226\151\143|r " .. HX.text .. ns.clock(sec) .. "|r" .. HX.muted .. "  Top Ramen Farm|r")
  local hr = ns.perHour(t.smart, sec)
  local goal = ""
  local total = ns.goalTotal()
  if total > 0 then
    local need = total - ns.goalHave()
    if need <= 0 then goal = HX.green .. "   Goal reached!|r"
    else
      local eta = ns.etaText(need, (ns.goalRate()))
      if eta then goal = HX.muted .. "   Goal|r " .. HX.text .. eta .. "|r" end
    end
  end
  mini.bottom:SetText(HX.muted .. "Vendor|r " .. ns.money(t.vendor, false, true) .. HX.muted .. "   Smart|r " .. ns.money(t.smart, false, true) ..
    (hr and (HX.muted .. "   /hr|r " .. ns.money(hr, false, true)) or "") .. goal)
  mini:SetWidth(math.max(220, mini.bottom:GetStringWidth() + 24))
  mini:Show()
end

local function updateGoalPanel()
  local g = ns.goal()
  for _, def in ipairs(ns.GOALS) do
    local c = W.goalChecks[def.key]
    local done = ns.goalDone(def.key)
    c:SetChecked(g[def.key] and true or false)
    c.text:SetText((done and HX.dim or HX.text) .. def.label .. "|r " ..
      (done and (HX.green .. "have it|r") or ns.money(ns.goalCost(def), false, true)))
  end
  W.goalCustomCheck:SetChecked(g.useCustom and true or false)
  if not W.goalCustom:HasFocus() then W.goalCustom:SetText((g.custom or 0) > 0 and tostring(g.custom) or "") end
  local on, auto = ns.isHonored()
  W.goalHonored:SetChecked(on and true or false)
  local _, city = ns.detectHonored()
  local why
  if not auto then why = "set by you; right-click to go back to automatic"
  elseif not city then why = "couldn't read your reputation; tick it yourself"
  elseif on then why = "you're Honored with " .. city
  else why = "not Honored with " .. city .. " yet" end
  W.goalHonored.text:SetText(HX.text .. "Honored discount|r  " .. HX.muted .. "10% off the mount and epic mount  \194\183  " .. why .. "|r")
  for key, b in pairs(W.goalCount) do if key == g.count then b:LockHighlight() else b:UnlockHighlight() end end
end

-- the list moves down on the Goal tab to make room for its settings
local function placeList()
  local top = TOP_LIST + (tab == "goal" and GOAL_H or 0)
  if W.listTop == top then return end
  W.listTop = top
  W.header:ClearAllPoints()
  W.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -(top + 2))
  W.header:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
  W.hl:ClearAllPoints()
  W.hl:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -(top + 24))
  W.hl:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -(top + 24))
  W.scroll:ClearAllPoints()
  W.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -(top + 28))
  W.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 50)
  W.empty:ClearAllPoints()
  W.empty:SetPoint("TOP", frame, "TOP", 0, -(top + 60))
end

function ns.Refresh(full)
  if full ~= false and ns.goalBagsDirty then ns.goalBagsDirty() end
  updateMini()
  if not frame or not frame:IsShown() then return end
  if tab == "bags" and full ~= false then bagSnap = ns.scanBags() end
  placeList()
  W.goal:SetShown(tab == "goal")
  if tab == "goal" then updateGoalPanel() end
  updateStatus()
  updateBoxes()
  for name, b in pairs(W.tabs) do if name == tab then b:LockHighlight() else b:UnlockHighlight() end end
  local cols = colsFor()
  layoutCells(W.header, W.headerCells, W.headerLeft, cols, tab == "history" and 8 or (tab == "bags" and 52 or 28))
  -- column names: the one you're sorting by is gold with an arrow showing the direction
  local srt = sortState()
  local function headText(title, key)
    if srt.key ~= key then return HX.muted .. title .. "|r" end
    return HX.gold .. title .. "|r |TInterface\\Buttons\\" .. (srt.desc and "Arrow-Down-Up" or "Arrow-Up-Up") .. ":12:12:0:-3|t"
  end
  for i = 1, MAX_CELLS do
    local col, btn = cols[i], W.headerBtns[i]
    W.headerCells[i]:SetText(col and headText(col.title, col.key) or "")
    btn.key, btn.title = col and col.key, col and col.title
    btn:SetShown(col ~= nil)
  end
  local leftKey = tab == "history" and "date" or "name"
  local leftTitle = tab == "history" and "Session" or tab == "goal" and "Zone" or "Item"
  W.headerLeft:SetText(headText(leftTitle, leftKey))
  W.headerLeftBtn.key, W.headerLeftBtn.title = leftKey, leftTitle
  local s, mode = shown()
  W.back:SetShown(mode == "history" and tab == "loot")
  W.clearHist:SetShown(tab == "history" and #ns.char().history > 0)
  -- Vendor items: shown while you're talking to a merchant
  local atMerchant, selling = false, false
  if ns.VendorStatus then atMerchant, selling = ns.VendorStatus() end
  W.vendor:SetShown(atMerchant)
  if atMerchant then
    if selling then
      W.vendor:SetText("Selling..."); W.vendor:Disable()
    else
      local n = #ns.vendorList()
      W.vendor:SetText("Vendor items" .. (n > 0 and (" (" .. n .. ")") or ""))
      if n > 0 then W.vendor:Enable() else W.vendor:Disable() end
    end
  end
  -- footer buttons line up from the bottom-left corner; the price note takes the rest
  local fx = 12
  for _, b in ipairs({ W.vendor, W.back, W.clearHist }) do
    if b:IsShown() then
      b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", fx, 12)
      fx = fx + b:GetWidth() + 6
    end
  end
  W.prices:ClearAllPoints()
  W.prices:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 19)
  W.prices:SetPoint("LEFT", frame, "BOTTOMLEFT", math.max(170, fx + 10), 0)
  local list = tab == "history" and fillHistory() or tab == "goal" and fillGoal() or fillLoot(s)
  drawRows(list)
  -- the header box ticks / clears every item in the My bags list
  local ids, allTicked = {}, true
  if tab == "bags" then
    for _, d in ipairs(list) do
      if d.kind == "item" and d.value then
        ids[#ids + 1] = d.id
        if not ns.isVendorPick(d.id) then allTicked = false end
      end
    end
  end
  W.checkAll.ids = ids
  W.checkAll:SetShown(#ids > 0)
  W.checkAll:SetChecked(#ids > 0 and allTicked)
  if #list == 0 then
    W.empty:SetText(tab == "history" and (HX.muted .. "No saved sessions yet. Stop a farm run and it lands here.|r")
      or tab == "goal" and (HX.muted .. "No saved runs yet. Farm a run and stop it: each zone you farmed shows up here\nwith its gold per hour and the farm time left to your goal.|r")
      or tab == "bags" and (HX.muted .. "Nothing in your bags that a vendor will buy.|r")
      or (HX.muted .. (ns.isRunning() and "Recording... loot something and it shows up here." or "Press Start farming, then loot mobs, chests, herbs, ore or fish.") .. "|r"))
    W.empty:Show()
  else
    W.empty:Hide()
  end
end

---------------------------------------------------------------------------
-- opacity (same as the other Top Ramen windows)
---------------------------------------------------------------------------
function ns.ApplyOpacity()
  if not frame then return end
  local a = ns.settings().opacity or 0.92
  frame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], a)
end

function ns.SetOpacity(pct)
  pct = tonumber(pct)
  if not pct then
    ns.say("background opacity is " .. math.floor((ns.settings().opacity or 0.92) * 100 + 0.5) .. "%. Change it with /trfarm opacity 30-100.")
    return
  end
  ns.settings().opacity = math.max(0.3, math.min(1, pct / 100))
  ns.ApplyOpacity()
  ns.say("background opacity set to " .. math.floor(ns.settings().opacity * 100 + 0.5) .. "%.")
end

---------------------------------------------------------------------------
-- building the window
---------------------------------------------------------------------------
local function statBox(title, help, bagsTitle, bagsHelp)
  local b = UI.Frame(frame, C.row, C.line, 1)
  b:SetHeight(64)
  b.title = UI.Text(b, "GameFontHighlightSmall", C.muted)
  b.title:SetPoint("TOPLEFT", 10, -8)
  b.title:SetText(title)
  b.value = UI.Text(b, "GameFontNormalLarge", C.text)
  b.value:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -5)
  b.sub = UI.Text(b, "GameFontHighlightSmall", C.muted)
  b.sub:SetPoint("BOTTOMLEFT", 10, 8)
  b.sub:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.sub:SetWordWrap(false)
  b:EnableMouse(true)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local bags = tab == "bags"
    if tab == "goal" and self.goalTitle then
      GameTooltip:AddLine(self.goalTitle)
      GameTooltip:AddLine(self.goalHelp, 1, 1, 1, true)
    else
      GameTooltip:AddLine(bags and bagsTitle or title)
      GameTooltip:AddLine(bags and bagsHelp or help, 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function placeBoxes()
  local boxes = { W.boxMoney, W.boxVendor, W.boxSmart, W.boxDiff }
  local gap = 8
  local w = (frame:GetWidth() - 24 - gap * (#boxes - 1)) / #boxes
  for i, b in ipairs(boxes) do
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + (i - 1) * (w + gap), -94)
    b:SetWidth(w)
  end
end

local function savePos(f, store)
  local point, _, rel, x, y = f:GetPoint()
  store.point, store.rel, store.x, store.y = point, rel, x, y
end

local function build()
  local saved = ns.db().window
  frame = UI.Window("TopRamenFarmFrame")
  frame:Hide()
  frame:SetSize(math.max(MIN_W, math.min(MAX_W, saved.w or WIDTH)), math.max(MIN_H, math.min(MAX_H, saved.h or HEIGHT)))
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  else
    if frame.SetMinResize then frame:SetMinResize(MIN_W, MIN_H) end
    if frame.SetMaxResize then frame:SetMaxResize(MAX_W, MAX_H) end
  end
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self, ns.db().window) end)
  if saved.point then frame:SetPoint(saved.point, UIParent, saved.rel or saved.point, saved.x or 0, saved.y or 0)
  else frame:SetPoint("CENTER") end
  ns.ApplyOpacity()
  tinsert(UISpecialFrames, "TopRamenFarmFrame") -- Escape closes it

  UI.Grip(frame, function()
    local win = ns.db().window
    win.w, win.h = frame:GetWidth(), frame:GetHeight()
    savePos(frame, win)
  end)

  local head = UI.Header(frame, "Farm tracker")
  W.head = head

  W.toggle = UI.Button(head, 150, 30, "", function() ns.toggle() end)
  W.toggle:SetPoint("RIGHT", head.close, "LEFT", -6, 0)
  tip(W.toggle, "Start / stop farming", function()
    return ns.isRunning() and "Stops recording and saves this run to your History."
      or "Starts recording everything you loot (items and coin) until you stop it. Keeps going through /reload and logouts; time logged out doesn't count."
  end)

  W.status = label(frame, "", "GameFontHighlight")
  W.status:SetPoint("TOPLEFT", 16, -(UI.HEAD_H + 12))
  W.status:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
  W.status:SetWordWrap(false)

  W.boxMoney = statBox("Coin looted", "Gold, silver and copper looted directly. It's already in your bags, however you sell the items.",
    "Sellable items", "Items in your bags a vendor will buy. Quest items and items with no vendor price are left out.")
  W.boxVendor = statBox("Vendor everything", "Coin looted plus every item sold to a vendor. This is the floor: what the run is worth if you vendor the lot.",
    "Vendor everything", "What your bags are worth if you sell every item to a vendor.")
  W.boxSmart = statBox("Sell smart", "Coin looted plus each item sold wherever it pays more: the auction house (after its 5% cut) or a vendor.",
    "Sell smart", "Each item sold wherever it pays more: the auction house (after its 5% cut) or a vendor. Soulbound items count at vendor price.")
  W.boxDiff = statBox("AH over vendor", "How much more you make by putting the auction-house items up instead of vendoring them. Deposits aren't counted.",
    "AH over vendor", "How much more you'd make by putting the auction-house items up instead of vendoring them. Deposits aren't counted.")
  W.boxMoney.goalTitle, W.boxMoney.goalHelp = "Goal", "Everything you ticked below, minus anything you already have (riding skill, dual spec). Honored with your home city takes 10% off the mount and epic mount."
  W.boxVendor.goalTitle, W.boxVendor.goalHelp = "You have", "The gold you're carrying, plus your bags if you count them (choose below). Bags count only items a vendor will buy; quest items are left out."
  W.boxSmart.goalTitle, W.boxSmart.goalHelp = "Still needed", "The goal minus what you have."
  W.boxDiff.goalTitle, W.boxDiff.goalHelp = "Farm time left", "Still needed, divided by your gold per hour: this run's once it's 10 minutes old, otherwise your average over saved runs. Assumes you don't spend gold along the way."
  -- a thin progress bar along the bottom of the Still needed box
  W.goalBar = CreateFrame("StatusBar", nil, W.boxSmart)
  W.goalBar:SetPoint("BOTTOMLEFT", 1, 1); W.goalBar:SetPoint("BOTTOMRIGHT", -1, 1)
  W.goalBar:SetHeight(3)
  W.goalBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  W.goalBar:SetStatusBarColor(1, 0.82, 0, 0.9)
  W.goalBar:SetMinMaxValues(0, 100)
  W.goalBar:Hide()
  placeBoxes()

  W.tabs = {}
  W.tabs.loot = UI.Button(frame, 110, 26, "Loot", function() tab = "loot"; ns.Refresh(true) end)
  W.tabs.loot:SetPoint("TOPLEFT", 12, -168)
  W.tabs.bags = UI.Button(frame, 110, 26, "My bags", function() tab = "bags"; ns.Refresh(true) end)
  W.tabs.bags:SetPoint("LEFT", W.tabs.loot, "RIGHT", 6, 0)
  tip(W.tabs.bags, "What's in my bags", "Everything you're carrying right now, priced vendor vs. auction house. Updates as your bags change. Quest items and items no vendor will buy are left out.")
  W.tabs.history = UI.Button(frame, 110, 26, "History", function() tab = "history"; ns.Refresh(true) end)
  W.tabs.history:SetPoint("LEFT", W.tabs.bags, "RIGHT", 6, 0)
  W.tabs.goal = UI.Button(frame, 110, 26, "Goal", function() tab = "goal"; ns.Refresh(true) end)
  W.tabs.goal:SetPoint("LEFT", W.tabs.history, "RIGHT", 6, 0)
  tip(W.tabs.goal, "Saving up", "Pick what you're saving for (mount, dual spec, epic mount or your own amount) and see how much farming is left, zone by zone.")

  W.miniCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  W.miniCheck:SetSize(24, 24)
  W.miniCheck.text = label(W.miniCheck, "Mini tracker while recording", "GameFontHighlightSmall")
  W.miniCheck.text:SetPoint("RIGHT", W.miniCheck, "LEFT", -2, 0)
  W.miniCheck.text:SetJustifyH("RIGHT")
  W.miniCheck:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -169)
  W.miniCheck:SetChecked(ns.settings().mini)
  W.miniCheck:SetScript("OnClick", function(self) ns.settings().mini = self:GetChecked() and true or false; ns.Refresh(false) end)
  tip(W.miniCheck, "Mini tracker", "While recording, a small bar with the timer and running totals stays on screen when this window is closed. Click it to open this window.")

  -- the list, on a dark well with the column names on top
  local well = UI.Panel(frame, C.well)
  well:SetPoint("TOPLEFT", 12, -TOP_LIST); well:SetPoint("BOTTOMRIGHT", -12, 44)
  W.header = CreateFrame("Frame", nil, frame)
  W.header:SetHeight(ROW_H)
  W.header:SetPoint("TOPLEFT", 20, -(TOP_LIST + 2))
  W.header:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
  W.headerLeft = label(W.header, "")
  W.headerCells = {}
  for i = 1, MAX_CELLS do W.headerCells[i] = label(W.header, "") end
  -- a clickable area over each column name; clicking sorts by that column
  local function headerButton(fs)
    local b = CreateFrame("Button", nil, W.header)
    b:SetPoint("TOPLEFT", fs, "TOPLEFT", -4, 5)
    b:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 4, -5)
    local h = b:CreateTexture(nil, "HIGHLIGHT")
    h:SetAllPoints(); h:SetColorTexture(1, 0.82, 0, 0.08)
    b:SetScript("OnClick", function(self) if self.key then setSort(self.key) end end)
    b:SetScript("OnEnter", function(self)
      if not self.key then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine("Sort by " .. (self.title or ""))
      GameTooltip:AddLine("Click again to flip the order.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
  end
  W.headerLeftBtn = headerButton(W.headerLeft)
  W.checkAll = CreateFrame("CheckButton", nil, W.header, "UICheckButtonTemplate")
  W.checkAll:SetSize(22, 22)
  W.checkAll:SetPoint("LEFT", W.header, "LEFT", 2, 0)
  W.checkAll:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    for _, id in ipairs(self.ids or {}) do ns.setVendorPick(id, on) end
    ns.Refresh(false)
  end)
  W.checkAll:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self:GetChecked() and "Untick everything" or "Tick everything")
    GameTooltip:AddLine("Ticks or clears every item in this list for Vendor items.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  W.checkAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
  W.checkAll:Hide()
  W.headerBtns = {}
  for i = 1, MAX_CELLS do W.headerBtns[i] = headerButton(W.headerCells[i]) end
  local hl = frame:CreateTexture(nil, "ARTWORK")
  hl:SetColorTexture(1, 0.82, 0, 0.25); hl:SetHeight(1)
  hl:SetPoint("TOPLEFT", well, "TOPLEFT", 6, -24); hl:SetPoint("TOPRIGHT", well, "TOPRIGHT", -6, -24)
  W.hl = hl

  local scroll = CreateFrame("ScrollFrame", "TopRamenFarmScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -(TOP_LIST + 28))
  scroll:SetPoint("BOTTOMRIGHT", -40, 50)
  W.scroll = scroll
  W.content = CreateFrame("Frame", nil, scroll)
  W.content:SetSize(frame:GetWidth() - 60, 1)
  scroll:SetScrollChild(W.content)

  W.empty = label(frame, "", "GameFontHighlight")
  W.empty:SetPoint("TOP", well, "TOP", 0, -60)
  W.empty:SetJustifyH("CENTER")

  -- Goal tab settings, at the top of the well
  local p = CreateFrame("Frame", nil, frame)
  p:SetPoint("TOPLEFT", well, "TOPLEFT", 8, -4)
  p:SetPoint("RIGHT", well, "RIGHT", -8, 0)
  p:SetHeight(GOAL_H - 6)
  p:Hide()
  W.goal = p
  local sep = p:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(1, 0.82, 0, 0.15); sep:SetHeight(1)
  sep:SetPoint("BOTTOMLEFT", 0, 0); sep:SetPoint("BOTTOMRIGHT", 0, 0)

  local saving = label(p, HX.muted .. "Saving for|r", "GameFontHighlight")
  saving:SetPoint("TOPLEFT", 4, -10)
  W.goalChecks = {}
  local prev = saving
  local function goalCheck(key, title, text)
    local c = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("LEFT", prev, "RIGHT", prev == saving and 8 or 14, 0)
    c.text = label(c, "", "GameFontHighlight")
    c.text:SetPoint("LEFT", c, "RIGHT", 1, 0)
    c:SetScript("OnClick", function(self) ns.goal()[key] = self:GetChecked() and true or false; ns.Refresh(false) end)
    tip(c, title, text)
    prev = c.text
    return c
  end
  for _, def in ipairs(ns.GOALS) do
    W.goalChecks[def.key] = goalCheck(def.key, def.label, function()
      local full = ns.money(def.cost, false, true)
      local off = def.rep and (" " .. ns.money(math.floor(def.cost * ns.REP_DISCOUNT), false, true) .. " when you're Honored.") or ""
      return def.help .. " " .. full .. "." .. off .. " Already have it? It's left out of the total."
    end)
  end
  W.goalCustomCheck = goalCheck("useCustom", "Your own goal", "Add any amount of gold you want to save up, on top of anything else ticked.")
  W.goalCustomCheck.text:SetText(HX.text .. "Other|r")
  local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  eb:SetSize(64, 20)
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetMaxLetters(6)
  eb:SetPoint("LEFT", W.goalCustomCheck.text, "RIGHT", 12, 0)
  local function saveCustom(self)
    local g = ns.goal()
    local n = tonumber(self:GetText()) or 0
    if n ~= (g.custom or 0) then
      g.custom = n
      g.useCustom = n > 0
    end
    ns.Refresh(false)
  end
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEditFocusLost", saveCustom)
  eb:SetScript("OnEscapePressed", function(self)
    local c = ns.goal().custom or 0
    self:SetText(c > 0 and tostring(c) or "")
    self:ClearFocus()
  end)
  W.goalCustom = eb
  local gl = label(p, HX.gold .. "g|r", "GameFontHighlight")
  gl:SetPoint("LEFT", eb, "RIGHT", 4, 0)

  W.goalHonored = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  W.goalHonored:SetSize(24, 24)
  W.goalHonored:SetPoint("TOPLEFT", 0, -32)
  W.goalHonored:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  W.goalHonored.text = label(W.goalHonored, "", "GameFontHighlight")
  W.goalHonored.text:SetPoint("LEFT", W.goalHonored, "RIGHT", 1, 0)
  W.goalHonored:SetScript("OnClick", function(self, button)
    if button == "RightButton" then ns.goal().honored = nil
    else ns.goal().honored = self:GetChecked() and true or false end
    ns.Refresh(false)
  end)
  tip(W.goalHonored, "Honored discount", "Honored with your home city takes 10% off the mount and epic mount. It's ticked for you when the addon sees you're Honored. Click to set it yourself; right-click to go back to automatic.")

  local count = label(p, HX.muted .. "Count toward it|r", "GameFontHighlight")
  count:SetPoint("TOPLEFT", 4, -68)
  W.goalCount = {}
  prev = count
  for _, o in ipairs({
    { "gold", "Gold on hand", 116, "Only the gold you're carrying counts. Farm time uses your vendor value per hour." },
    { "vendor", "+ bags, vendored", 140, "Your gold plus your bags sold to a vendor. Farm time uses your vendor value per hour." },
    { "smart", "+ bags, sold smart", 150, "Your gold plus your bags sold smart (auction house where it pays more). Farm time uses your sell-smart value per hour." },
  }) do
    local key = o[1]
    local b = UI.Button(p, o[3], 22, o[2], function() ns.goal().count = key; ns.goalBagsDirty(); ns.Refresh(false) end)
    b:SetPoint("LEFT", prev, "RIGHT", prev == count and 10 or 6, 0)
    tip(b, o[2], o[4])
    W.goalCount[key] = b
    prev = b
  end

  -- footer
  W.back = UI.Button(frame, 150, 24, "Back to current", function() viewIndex = nil; ns.Refresh(true) end)
  W.back:SetPoint("BOTTOMLEFT", 12, 12)
  W.clearHist = UI.Button(frame, 130, 24, "Clear history", function()
    if not StaticPopupDialogs.TOPRAMENFARM_CLEAR then
      StaticPopupDialogs.TOPRAMENFARM_CLEAR = {
        text = "Delete every saved Top Ramen Farm session for this character?",
        button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = function() wipe(ns.char().history); viewIndex = nil; ns.Refresh(true) end,
        timeout = 0, whileDead = true, hideOnEscape = true,
      }
    end
    StaticPopup_Show("TOPRAMENFARM_CLEAR")
  end)
  W.clearHist:SetPoint("BOTTOMLEFT", 12, 12)
  W.vendor = UI.Button(frame, 170, 24, "Vendor items", function() if ns.VendorPrompt then ns.VendorPrompt() end end)
  W.vendor:SetPoint("BOTTOMLEFT", 12, 12)
  if W.vendor.SetMotionScriptsWhileDisabled then W.vendor:SetMotionScriptsWhileDisabled(true) end
  W.vendor:HookScript("OnEnter", function(self) if ns.VendorTooltip then ns.VendorTooltip(self) end end)
  W.vendor:HookScript("OnLeave", function() GameTooltip:Hide() end)
  W.vendor:Hide()
  W.prices = label(frame, "")
  W.prices:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 19)
  W.prices:SetPoint("LEFT", frame, "BOTTOMLEFT", 170, 0)
  W.prices:SetJustifyH("RIGHT")
  W.prices:SetWordWrap(false)

  frame:SetScript("OnSizeChanged", function()
    placeBoxes()
    W.content:SetWidth(math.max(100, (W.scroll:GetWidth() or (frame:GetWidth() - 60))))
    ns.Refresh(true)
  end)
  frame:SetScript("OnShow", function()
    W.miniCheck:SetChecked(ns.settings().mini)
    W.content:SetWidth(math.max(100, (W.scroll:GetWidth() or (frame:GetWidth() - 60))))
    ns.Refresh(true)
  end)
  frame:SetScript("OnHide", function() updateMini() end)
end

local function buildMini()
  mini = CreateFrame("Button", "TopRamenFarmMini", UIParent, "BackdropTemplate")
  UI.Skin(mini, C.bg, C.trim, 1, 0.92)
  mini:SetSize(240, 40)
  mini:SetFrameStrata("MEDIUM")
  mini:SetClampedToScreen(true)
  mini:SetMovable(true)
  mini:EnableMouse(true)
  mini:RegisterForDrag("LeftButton")
  mini:SetScript("OnDragStart", mini.StartMoving)
  mini:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self, ns.db().mini) end)
  local m = ns.db().mini
  if m.point then mini:SetPoint(m.point, UIParent, m.rel or m.point, m.x or 0, m.y or 0)
  else mini:SetPoint("TOP", UIParent, "TOP", 0, -120) end
  mini.top = label(mini, "", "GameFontHighlightSmall")
  mini.top:SetPoint("TOPLEFT", 10, -7)
  mini.bottom = label(mini, "", "GameFontHighlightSmall")
  mini.bottom:SetPoint("BOTTOMLEFT", 10, 7)
  mini:SetScript("OnClick", function() ns.ToggleWindow() end)
  tip(mini, "Top Ramen Farm", "Recording your loot. Click to open the farm tracker; drag to move. /trfarm mini turns this bar off.", "ANCHOR_BOTTOM")
  mini:Hide()
end

function ns.BagsChanged()
  if ns.goalBagsDirty then ns.goalBagsDirty() end
  if frame and frame:IsShown() and (tab == "bags" or tab == "goal") then ns.Refresh(true) end
end

function ns.ShowTab(name)
  if not frame then build() end
  tab = name
  if frame:IsShown() then ns.Refresh(true) else frame:Show() end
end

function ns.ToggleWindow()
  if not frame then build() end
  if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- a 1-second tick keeps the timers moving while recording
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  buildMini()
  updateMini()
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function()
      if not ns.isRunning() then return end
      updateMini()
      if frame and frame:IsShown() then updateStatus(); updateBoxes() end
    end)
  end
end)
