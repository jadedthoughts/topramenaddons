-- Top Ramen Gear: the gear window (/trg)
-- One row per slot: what you're wearing, and the best thing you own for it.
-- Gold + star = the best choice. Red = what you're wearing should be swapped.
local _, ns = ...


local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local BagLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local Durability = (C_Container and C_Container.GetContainerItemDurability) or GetContainerItemDurability

---------------------------------------------------------------------------
-- working out the best gear you own
---------------------------------------------------------------------------
local SINGLE = {
  { "head", "Head", 1 }, { "neck", "Neck", 2 }, { "shoulder", "Shoulder", 3 }, { "back", "Back", 15 },
  { "chest", "Chest", 5 }, { "wrist", "Wrist", 9 }, { "hands", "Hands", 10 }, { "waist", "Waist", 6 },
  { "legs", "Legs", 7 }, { "feet", "Feet", 8 },
}
local PAIRS = { { "finger", "Ring", 11, 12 }, { "trinket", "Trinket", 13, 14 } }

-- every Druid item in your bags you can wear now, grouped by slot.
-- Broken items (0 durability) still count (they're fine once repaired) but get a broken-armor mark,
-- and Equip best skips them: the game won't put on a broken item.
local function bagItems()
  local out, lvl, waiting = {}, ns.Level() or 60, false
  ns.brokenInBags, ns.brokenLinks = {}, {}
  for bag = 0, 4 do
    for slot = 1, (NumSlots(bag) or 0) do
      local link = BagLink(bag, slot)
      if link then
        local it = ns.ItemStats(link)
        local cur, max
        if Durability then cur, max = Durability(bag, slot) end
        if it and cur and max and max > 0 and cur <= 0 then
          table.insert(ns.brokenInBags, link)
          ns.brokenLinks[link] = true
        end
        if it then
          if (it.rl or 0) <= lvl then
            out[it.s] = out[it.s] or {}
            table.insert(out[it.s], it)
          end
        elseif not ns.ItemStatsKnownBad or not ns.ItemStatsKnownBad(link) then
          waiting = true
        end
      end
    end
  end
  return out, waiting
end

local function sc(items, mode, base, scen) return ns.Score(items, mode, base, scen) end

function ns.Analyse(mode)
  ns.MarkGearDirty()
  local g = ns.Gear()
  local bags, waiting = bagItems()
  local rows = {}

  -- single slots: the best of what's equipped and what's in your bags
  for _, d in ipairs(SINGLE) do
    local key, label, inv = d[1], d[2], d[3]
    local base = ns.BaseWithout({ [inv] = true })
    local cur = g[inv]
    local curS = cur and sc({ cur }, mode, base, 1) or 0
    local best, bestS = cur, curS
    for _, it in ipairs(bags[key] or {}) do
      local s = sc({ it }, mode, base, 1)
      if s > bestS + 0.05 then best, bestS = it, s end
    end
    rows[#rows + 1] = {
      label = label, cur = { cur }, best = { best }, slots = { inv },
      curS = curS, bestS = bestS,
      curS3 = cur and sc({ cur }, mode, base, 3) or 0, bestS3 = best and sc({ best }, mode, base, 3) or 0,
    }
  end

  -- rings and trinkets: the best pair
  for _, d in ipairs(PAIRS) do
    local key, label, a, b = d[1], d[2], d[3], d[4]
    local base = ns.BaseWithout({ [a] = true, [b] = true })
    local pool = {}
    if g[a] then pool[#pool + 1] = g[a] end
    if g[b] then pool[#pool + 1] = g[b] end
    for _, it in ipairs(bags[key] or {}) do pool[#pool + 1] = it end
    local cur = { g[a], g[b] }
    local curS = sc(cur, mode, base, 1)
    local bp, bpS = cur, curS
    for i = 1, #pool do
      for j = i, #pool do
        local pair = (i == j) and { pool[i] } or { pool[i], pool[j] }
        -- unique items can't be worn twice
        if i == j or pool[i].id ~= pool[j].id then
          local s = sc(pair, mode, base, 1)
          if s > bpS + 0.05 then bp, bpS = pair, s end
        end
      end
    end
    -- keep items that stay in their slot, put the new ones where the old ones leave
    local inBest = {}
    for _, it in pairs(bp) do if it then inBest[it.link] = true end end
    local new = {}
    for _, it in pairs(bp) do if it and not ((g[a] and g[a].link == it.link) or (g[b] and g[b].link == it.link)) then new[#new + 1] = it end end
    for n, inv in ipairs({ a, b }) do
      local c = g[inv]
      local keep = c and inBest[c.link]
      local repl = keep and c or table.remove(new, 1)
      rows[#rows + 1] = {
        label = label .. " " .. n, cur = { c }, best = { repl }, slots = { inv }, pair = true,
        pairGain = bpS - curS, pairGain3 = sc(bp, mode, base, 3) - sc(cur, mode, base, 3),
        curS = 0, bestS = 0, keep = keep or (not c and not repl),
      }
    end
  end

  -- weapon: a two-hander, or a one-hander with an off-hand item
  do
    local base = ns.BaseWithout({ [16] = true, [17] = true })
    local mh, oh = g[16], g[17]
    -- an off-hand weapon counts as off-hand DPS (half-damage hits); held-in-off-hand items are unchanged
    local cur = { mh, ns.AsOffhand(oh) }
    local curS = sc(cur, mode, base, 1)
    local best, bestS = cur, curS
    local twos, ones, offs = {}, {}, { false }
    if mh then (mh.s == "weapon2h" and twos or ones)[#(mh.s == "weapon2h" and twos or ones) + 1] = mh end
    if oh then offs[#offs + 1] = ns.AsOffhand(oh) end
    for _, it in ipairs(bags.weapon2h or {}) do twos[#twos + 1] = it end
    for _, it in ipairs(bags.weapon1h or {}) do ones[#ones + 1] = it end
    for _, it in ipairs(bags.offhand or {}) do offs[#offs + 1] = it end
    for _, it in ipairs(bags.shield or {}) do offs[#offs + 1] = it end
    -- Hunters dual wield: off-hand weapons, and one-handers that can go in either hand
    for _, it in ipairs(bags.offweapon or {}) do offs[#offs + 1] = ns.AsOffhand(it) end
    if ns.ClassSlot("INVTYPE_WEAPONOFFHAND", 2, 7) then
      for _, it in ipairs(ones) do
        if it.loc == "INVTYPE_WEAPON" then offs[#offs + 1] = ns.AsOffhand(it) end
      end
    end
    for _, w in ipairs(twos) do
      local s = sc({ w }, mode, base, 1)
      if s > bestS + 0.05 then best, bestS = { w }, s end
    end
    for _, w in ipairs(ones) do
      for _, o in ipairs(offs) do
        -- (not the same item in both hands)
        if o and (o.offhandOf or o) == w then o = nil end
        local combo = o and { w, o } or { w }
        local s = sc(combo, mode, base, 1)
        if s > bestS + 0.05 then best, bestS = combo, s end
      end
    end
    rows[#rows + 1] = {
      label = "Weapon", cur = cur, best = best, slots = { 16, 17 }, curS = curS, bestS = bestS,
      curS3 = sc(cur, mode, base, 3), bestS3 = sc(best, mode, base, 3),
    }
  end

  -- idol (Druid) or ranged weapon (Hunter): the same slot
  do
    local class = ns.PlayerClass()
    local R = ns.CLASS_RULES[class] or {}
    local LABEL = { DRUID = "Idol", PALADIN = "Libram", SHAMAN = "Totem", PRIEST = "Wand", MAGE = "Wand", WARLOCK = "Wand" }
    local key = R.relic and "relic" or "ranged"
    local label = LABEL[class] or "Ranged"
    local base = ns.BaseWithout({ [18] = true })
    local cur = g[18]
    local curS = cur and sc({ cur }, mode, base, 1) or 0
    local best, bestS = cur, curS
    for _, it in ipairs(bags[key] or {}) do
      local s = sc({ it }, mode, base, 1)
      if s > bestS + 0.05 then best, bestS = it, s end
    end
    rows[#rows + 1] = {
      label = label, cur = { cur }, best = { best }, slots = { 18 }, curS = curS, bestS = bestS,
      curS3 = cur and sc({ cur }, mode, base, 3) or 0, bestS3 = best and sc({ best }, mode, base, 3) or 0,
    }
  end

  -- is the equipped item already the best?
  for _, r in ipairs(rows) do
    if r.pair then
      r.same = r.keep
    else
      local same = true
      for i = 1, math.max(#r.cur, #r.best) do
        local x, y = r.cur[i], r.best[i]
        if (x and x.link) ~= (y and y.link) then same = false end
      end
      r.same = same
    end
  end
  return rows, waiting
end

---------------------------------------------------------------------------
-- "Equip best": put on the winning items from your bags
---------------------------------------------------------------------------
local equipQueue, equipTicker, equipDone = nil, nil, 0

-- the items to put on, in order: { link = ..., inv = slot number, name = ... }
function ns.EquipPlan(mode)
  local rows = ns.Analyse(mode)
  local g = ns.Gear()
  local plan = {}
  for _, r in ipairs(rows) do
    if not r.same and r.slots then
      for i, it in ipairs(r.best) do
        local inv = r.slots[i]
        if it and inv and not (g[inv] and g[inv].link == it.link) then
          if ns.brokenLinks and ns.brokenLinks[it.link] then
            plan.broken = plan.broken or {}
            table.insert(plan.broken, it.link)
          else
            plan[#plan + 1] = { link = it.link, inv = inv }
          end
        end
      end
    end
  end
  return plan
end

-- is the game asking "this item will be soulbound, equip it?"
-- (any of the game's pop-ups whose kind mentions binding: EQUIP_BIND, AUTOEQUIP_BIND, ...)
local function bindPopupOpen()
  for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
    local f = _G["StaticPopup" .. i]
    if f and f:IsShown() and type(f.which) == "string" and f.which:find("BIND") then return true end
  end
  if StaticPopup_FindVisible then
    for _, w in ipairs({ "EQUIP_BIND", "AUTOEQUIP_BIND", "EQUIP_BIND_TRADEABLE", "EQUIP_BIND_REFUNDABLE" }) do
      if StaticPopup_FindVisible(w) then return true end
    end
  end
  return false
end

-- put one item from your bags into an equipment slot: find its exact bag slot (link first,
-- then the same item ID) and move it from there, like dragging it onto your character.
-- C_Item.EquipItemByName is the last resort: it can miss items with a random "of the ..." bonus.
local Pickup = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
local function itemID(link) return tonumber((link or ""):match("item:(%d+)")) end
local function findInBags(link)
  local id, byId = itemID(link), nil
  for bag = 0, 4 do
    for slot = 1, (NumSlots(bag) or 0) do
      local l = BagLink(bag, slot)
      if l == link then return bag, slot end
      if not byId and l and id and itemID(l) == id then byId = { bag, slot } end
    end
  end
  if byId then return byId[1], byId[2] end
end
local function equipOne(link, inv)
  local bag, slot = findInBags(link)
  if bag and Pickup and (EquipCursorItem or PickupInventoryItem) then
    if CursorHasItem and CursorHasItem() then ClearCursor() end
    Pickup(bag, slot)
    if EquipCursorItem then EquipCursorItem(inv) else PickupInventoryItem(inv) end
    if CursorHasItem and CursorHasItem() then ClearCursor() end
    return true
  end
  local byName = (C_Item and C_Item.EquipItemByName) or EquipItemByName
  if byName then byName(itemID(link) or link, inv); return true end
  return false -- not in your bags any more
end

-- while equipping, remember the game's red error text ("You can't equip that yet" and so on)
local lastError
local errWatch = CreateFrame("Frame")
errWatch:SetScript("OnEvent", function(_, _, a, b)
  local msg = type(b) == "string" and b or (type(a) == "string" and a) or nil
  if msg then lastError = msg end
end)

local function finishEquip(msg)
  pcall(errWatch.UnregisterEvent, errWatch, "UI_ERROR_MESSAGE")
  if equipTicker then equipTicker:Cancel() end
  equipTicker, equipQueue = nil, nil
  if msg then print("|cffffd100Top Ramen:|r " .. msg) end
  ns.MarkGearDirty()
  ns.RefreshWindow()
end

function ns.EquipBest(mode)
  mode = mode or ns.CurrentMode()
  if equipQueue then return end
  if InCombatLockdown and InCombatLockdown() then
    print("|cffffd100Top Ramen:|r can't change gear in combat. Try again when combat ends.")
    return
  end
  local plan = ns.EquipPlan(mode)
  local repairNote = plan.broken and (" Repair first: " .. table.concat(plan.broken, ", ") .. " (broken items can't be worn).") or ""
  if #plan == 0 then
    print("|cffffd100Top Ramen:|r " .. (plan.broken and ("nothing to put on yet." .. repairNote) or ("you're already wearing the best you own for " .. ns.ModeName(mode) .. ".")))
    return
  end
  equipQueue, equipDone = plan, 0
  lastError = nil
  pcall(errWatch.RegisterEvent, errWatch, "UI_ERROR_MESSAGE")
  local wanted = {}
  for _, x in ipairs(plan) do wanted[x.link] = true end
  local waited, settle, retried = 0, 0, false
  -- one item at a time; wait while the game asks you to confirm binding an item
  equipTicker = C_Timer.NewTicker(0.35, function()
    if InCombatLockdown and InCombatLockdown() then finishEquip("stopped: you entered combat."); return end
    if bindPopupOpen() then
      waited = waited + 1
      if waited > 170 then finishEquip("stopped: the bind confirmation was left open.") end
      return
    end
    waited = 0
    local nextItem = table.remove(equipQueue, 1)
    if not nextItem then
      -- give the server a moment, then check: anything from the list still in your bags gets one more try
      settle = settle + 1
      if settle < 4 then return end
      settle = 0
      local left = {}
      for _, x in ipairs(ns.EquipPlan(mode)) do if wanted[x.link] then left[#left + 1] = x end end
      if #left > 0 and not retried then
        retried = true
        for _, x in ipairs(left) do equipQueue[#equipQueue + 1] = x end
        return
      end
      local msg = "equipped your best gear for " .. ns.ModeName(mode) .. "." .. repairNote
      if #left > 0 then
        local names = {}
        for _, x in ipairs(left) do names[#names + 1] = x.link end
        msg = msg .. " Couldn't put on: " .. table.concat(names, ", ") ..
          (lastError and (". The game said: \"" .. lastError .. "\"") or " (the game gave no reason)") .. "."
      end
      finishEquip(msg)
      return
    end
    local ok, err = pcall(equipOne, nextItem.link, nextItem.inv)
    if ok and err then equipDone = equipDone + 1
    elseif not ok then finishEquip("couldn't equip " .. nextItem.link .. ": " .. tostring(err)) end
  end)
end

---------------------------------------------------------------------------
-- the window (look: see UI.lua)
---------------------------------------------------------------------------
local UI = ns.UI
local C, HX = UI.C, UI.HEX
local W, H, ROWH = 780, 640, 40
local HEAD_H, FOOT_H = 58, 34
local win, rowsUI = nil, {}

local function fmt(d)
  if not d or math.abs(d) < 0.05 then return HX.dim .. "±0|r" end
  return (d > 0 and HX.green or HX.red) .. string.format("%+.1f", d) .. "|r"
end
ns.FmtGain = fmt

local function itemText(items)
  local parts = {}
  for _, it in ipairs(items) do if it then parts[#parts + 1] = it.link end end
  if #parts == 0 then return HX.dim .. "— empty —|r" end
  return table.concat(parts, HX.dim .. " + |r")
end

-- an item cell: quality-bordered icon, name (the item link), optional second line;
-- shows the item's tooltip on hover, shift-click links it in chat
local function makeCell(parent, x, width, iconSize, twoLine)
  iconSize = iconSize or 28
  local b = CreateFrame("Button", nil, parent)
  b:SetPoint("LEFT", x, 0)
  b:SetSize(width, iconSize + 4)
  b.bg = b:CreateTexture(nil, "BACKGROUND") -- kept for compatibility (tints are on the row now)
  b.bg:SetAllPoints(); b.bg:SetColorTexture(0, 0, 0, 0)
  b.iconFrame = UI.Icon(b, iconSize)
  b.iconFrame:SetPoint("LEFT", 0, 0)
  b.icon = b.iconFrame.tex
  b.text = UI.Text(b, twoLine and "GameFontHighlight" or "GameFontHighlightSmall")
  b.text:SetWordWrap(false)
  if twoLine then
    b.text:SetPoint("TOPLEFT", b.iconFrame, "TOPRIGHT", 8, -2)
    b.sub = UI.Text(b, "GameFontHighlightSmall", C.muted)
    b.sub:SetPoint("BOTTOMLEFT", b.iconFrame, "BOTTOMRIGHT", 8, 2)
    b.sub:SetPoint("RIGHT", -4, 0)
  else
    b.text:SetPoint("LEFT", b.iconFrame, "RIGHT", 8, 0)
  end
  b.text:SetPoint("RIGHT", -4, 0)
  -- a red line through the name: "swap this out"
  b.strike = b:CreateTexture(nil, "OVERLAY")
  b.strike:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.9)
  b.strike:SetHeight(1)
  b.strike:SetPoint("LEFT", b.text, "LEFT", 0, 0)
  b.strike:Hide()
  b:SetScript("OnEnter", function(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.link)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self)
    if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
  end)
  return b
end
ns.MakeCell = makeCell

-- move a cell to a new column position (used when the window is resized)
local function placeCell(cell, x, width)
  cell:ClearAllPoints()
  cell:SetPoint("LEFT", x, 0)
  cell:SetWidth(math.max(40, width))
end
ns.PlaceCell = placeCell

-- a scrolling list area: returns the scroll frame and the frame that holds the rows
function ns.MakeScroll(parent, name, top, bottom)
  local sf = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 16, top)
  sf:SetPoint("BOTTOMRIGHT", -34, bottom or (FOOT_H + 8))
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(sf:GetWidth() > 0 and sf:GetWidth() or 600, 10)
  sf:SetScrollChild(content)
  sf:EnableMouseWheel(true)
  return sf, content
end

-- opts: { border = "red" | nil, glow = bool, strike = bool, star = bool, prefix = text }
local function setCell(cell, items, opts)
  opts = opts or {}
  local first
  for _, it in ipairs(items) do if it then first = it; break end end
  cell.link = first and first.link
  if first then cell.iconFrame:SetItem(GetIcon(first.id), first.q, opts.border, opts.glow) else cell.iconFrame:Hide() end
  local broken = ""
  for _, it in ipairs(items) do
    if it and ns.brokenLinks and ns.brokenLinks[it.link] then broken = ns.UI.BROKEN .. " "; break end
  end
  cell.text:SetText((opts.star and (UI.STAR .. " ") or "") .. broken .. (opts.prefix or "") .. itemText(items))
  if opts.strike and first then
    cell.strike:SetWidth(math.max(1, math.min(cell.text:GetStringWidth() or 0, (cell:GetWidth() or 200) - 40)))
    cell.strike:Show()
  else
    cell.strike:Hide()
  end
end
ns.SetCell = setCell

-- a list row: dark, or gold-trimmed when it's an upgrade
function ns.RowStyle(r, kind)
  if kind == "gold" then
    r:SetBackdropColor(1, 0.82, 0, 0.07); r:SetBackdropBorderColor(1, 0.82, 0, 0.4)
  else
    r:SetBackdropColor(C.row[1], C.row[2], C.row[3], 1); r:SetBackdropBorderColor(0, 0, 0, 0)
  end
end

-- the footer line: which talents and form the scores use
function ns.FooterText(mode, extra)
  local parts = {}
  if ns.db.useTalents == false then
    parts[#parts + 1] = "Talents not included (Settings)"
  else
    local m, names = ns.TalentMods, {}
    for _, t in ipairs((m and m.found) or {}) do names[#names + 1] = t.name .. " " .. tostring(t.rank or "?") .. "/" .. tostring(t.max or "?") end
    if #names > 0 then parts[#parts + 1] = "Talents applied: " .. table.concat(names, ", ")
    elseif m and m.scanned then parts[#parts + 1] = "No talents that change gear"
    else parts[#parts + 1] = "Talents not read yet" end
  end
  if mode == "bear" and ns.BearForm then parts[#parts + 1] = ns.BearForm().name end
  local t = table.concat(parts, " · ")
  if extra then t = t .. "  " .. extra end
  return t
end

local function render()
  if not win or not win:IsShown() or not win.gearPage:IsShown() then return end
  local mode = ns.CurrentMode()
  win.specs:Update(mode)
  win.who:SetText(UI.WhoAmI())
  local gp = win.gearPage
  if not ns.isDruid then
    for _, r in ipairs(rowsUI) do r:Hide() end
    gp.sumValue:SetText(HX.muted .. "Druids and Hunters for now|r")
    win.footer:SetText("Top Ramen scores Druid (all four specs) and Hunter (all three) gear for now. More classes are planned.")
    return
  end
  local ok, rows, waiting = pcall(ns.Analyse, mode)
  if not ok then gp.sumValue:SetText(HX.red .. "Error|r"); win.footer:SetText(HX.red .. tostring(rows) .. "|r"); return end
  -- the biggest gain sets the length of a full bar
  local maxG, upgrades = 0.1, 0
  for _, r in ipairs(rows) do
    if not r.same then
      r.d1 = r.pair and r.pairGain or (r.bestS - r.curS)
      if r.d1 > maxG then maxG = r.d1 end
    end
  end
  -- a ring or trinket swap shows on two rows but counts once
  local pairSeen = {}
  for i, r in ipairs(rows) do
    local ui = rowsUI[i]
    ui:Show()
    ui.label:SetText(r.label)
    local hasCur = (r.cur[1] or r.cur[2]) and true or false
    if r.same then
      setCell(ui.cur, r.cur)
      ui.best:Hide()
      ui.bestNote:SetText(hasCur and (HX.dim .. "best you have|r") or (HX.dim .. "nothing to wear here|r"))
      ns.RowStyle(ui, nil)
      ui.bar:Hide(); ui.gain:SetText("")
    else
      local key = r.label:gsub(" %d$", "")
      if not r.pair or not pairSeen[key] then upgrades = upgrades + 1 end
      if r.pair then pairSeen[key] = true end
      setCell(ui.cur, r.cur, { border = hasCur and "red" or nil, strike = hasCur })
      ui.best:Show()
      setCell(ui.best, r.best, { glow = true, star = true })
      ui.bestNote:SetText("")
      ns.RowStyle(ui, "gold")
      local d3 = r.pair and r.pairGain3 or (r.bestS3 - r.curS3)
      local t = fmt(r.d1)
      if mode == "bear" and ns.db.showBear3 then t = t .. HX.dim .. " · 3t |r" .. fmt(d3) end
      if r.pair then t = t .. HX.dim .. " pair|r" end
      ui.gain:SetText(t)
      ui.bar:Show(); ui.bar:SetValue(r.d1 / maxG)
    end
  end
  for i = #rows + 1, #rowsUI do rowsUI[i]:Hide() end
  gp.equip:SetEnabled(upgrades > 0)
  gp.equip.label:SetText(upgrades > 0 and "Equip best" or "All equipped")
  gp.equip.label:SetTextColor(upgrades > 0 and C.text[1] or C.muted[1], upgrades > 0 and C.text[2] or C.muted[2], upgrades > 0 and C.text[3] or C.muted[3])
  if upgrades == 0 then
    gp.sumLabel:SetText("Your gear for " .. ns.ModeName(mode))
    gp.sumValue:SetText(HX.gold .. "Best you own|r")
  else
    gp.sumLabel:SetText("Upgrades in your bags")
    local g = 0
    local seen = {}
    for _, r in ipairs(rows) do
      if not r.same then
        local key = r.label:gsub(" %d$", "")
        if not (r.pair and seen[key]) then g = g + r.d1 end
        if r.pair then seen[key] = true end
      end
    end
    gp.sumValue:SetText(HX.green .. upgrades .. (upgrades == 1 and " slot" or " slots") .. " · " .. string.format("%+.1f", g) .. "|r")
  end
  local extra = waiting and (HX.dim .. "(some bag items are still loading)|r") or nil
  local shownBroken = false
  for _, r in ipairs(rows) do
    if not r.same then for _, it in ipairs(r.best) do if it and ns.brokenLinks and ns.brokenLinks[it.link] then shownBroken = true end end end
  end
  if shownBroken then
    extra = (extra and (extra .. "  ") or "") .. ns.UI.BROKEN .. HX.red .. " = broken: repair it before you can wear it|r"
  end
  win.footer:SetText(ns.FooterText(mode, extra))
end
local pending = false
ns.RefreshWindow = function()
  if not win or not win:IsShown() or pending then return end
  pending = true
  C_Timer.After(0.3, function() pending = false; render(); if ns.RenderDungeons then ns.RenderDungeons() end; if ns.RenderAH then ns.RenderAH() end end)
end

local function buildHeader(f, showTab)
  local head = UI.Frame(f, C.panel)
  head:SetPoint("TOPLEFT", 2, -2); head:SetPoint("TOPRIGHT", -2, -2); head:SetHeight(HEAD_H)
  local line = head:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1); line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
  -- the TR bowl
  local logo = head:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(UI.MEDIA .. "trBowl")
  logo:SetSize(84, 42)
  logo:SetPoint("LEFT", 8, 0)
  local title = UI.Text(head, "GameFontNormalLarge", C.gold)
  title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 6, -3)
  title:SetText("Top Ramen")
  -- "Gear v1.20.0", the same way as the other Top Ramen windows, then who you are
  local sub = UI.Text(head, "GameFontHighlightSmall", C.muted)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  sub:SetText("Gear")
  local ver = UI.Text(head, "GameFontHighlightSmall", C.muted)
  ver:SetPoint("LEFT", sub, "RIGHT", 6, 0)
  ver:SetAlpha(0.6)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local v = get and get("TopRamenGear", "Version")
  ver:SetText(v and ("v" .. v) or "")
  f.who = UI.Text(head, "GameFontHighlightSmall", C.muted, 10)
  f.who:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -2)
  f.who:SetAlpha(0.8)
  -- close
  local close = CreateFrame("Button", nil, head, "UIPanelCloseButton")
  close:SetPoint("RIGHT", -8, 0)
  close:SetScript("OnClick", function() f:Hide() end)
  -- tabs
  local tabs, x = {}, -48
  for _, t in ipairs({ { "settings", "Settings", 84 }, { "ah", "AH", 52 }, { "dungeons", "Dungeons", 88 }, { "gear", "Gear", 64 } }) do
    local b = UI.Pill(head, t[3], 30, t[2], nil, function() showTab(t[1]) end)
    b:SetPoint("RIGHT", x, 0)
    x = x - t[3] - 4
    tabs[t[1]] = b
  end
  -- the AH tab is greyed out (and can't be clicked) unless the auction house is open
  local ah = tabs.ah
  function ah:SetUsable(on)
    self.usable = on
    if on then self:Enable() else self:Disable() end
    self:SetAlpha(on and 1 or 0.35)
  end
  ah:HookScript("OnEnter", function(self)
    if self.usable then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("AH")
    GameTooltip:AddLine("Talk to an auctioneer to use this tab.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  ah:HookScript("OnLeave", function() GameTooltip:Hide() end)
  ah:SetUsable(ns.AHOpen and ns.AHOpen() or false)
  return tabs
end

local function buildFooter(f)
  local foot = UI.Frame(f, C.panel)
  foot:SetPoint("BOTTOMLEFT", 2, 2); foot:SetPoint("BOTTOMRIGHT", -2, 2); foot:SetHeight(FOOT_H)
  foot:SetFrameLevel(f:GetFrameLevel() + 5)
  local line = foot:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1); line:SetHeight(1)
  line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT")
  local icon = foot:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\FriendsFrame\\InformationIcon")
  icon:SetSize(14, 14); icon:SetPoint("LEFT", 14, 0)
  local t = UI.Text(foot, "GameFontHighlightSmall", C.muted)
  t:SetPoint("LEFT", icon, "RIGHT", 8, 0); t:SetPoint("RIGHT", -28, 0)
  t:SetWordWrap(false)
  f.footer = t
end

local function build()
  local f = CreateFrame("Frame", "TopRamenGearWindow", UIParent, "BackdropTemplate")
  win = f
  UI.Skin(f, C.bg, C.trim, 2, 0.97)
  f:SetSize(W, H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  UI.RegisterWindow(f) -- comes to the front over other Top Ramen windows when opened or clicked
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "TopRamenGearWindow")

  -- pages: Gear, Dungeons, Settings
  local gp = CreateFrame("Frame", nil, f); gp:SetAllPoints(); f.gearPage = gp
  local sp = CreateFrame("Frame", nil, f); sp:SetAllPoints(); sp:Hide(); f.settingsPage = sp
  local dp = CreateFrame("Frame", nil, f); dp:SetAllPoints(); dp:Hide(); f.dungeonPage = dp
  local ap = CreateFrame("Frame", nil, f); ap:SetAllPoints(); ap:Hide(); f.ahPage = ap

  local tabs
  local function showTab(name)
    -- the AH tab only while the auction house is open
    if name == "ah" and not (ns.AHOpen and ns.AHOpen()) then name = "gear" end
    ns.db.windowTab = name
    gp:SetShown(name == "gear"); sp:SetShown(name == "settings"); dp:SetShown(name == "dungeons"); ap:SetShown(name == "ah")
    f.specs:SetShown(name ~= "settings")
    for k, b in pairs(tabs) do b:SetActive(k == name, C.gold) end
    if name == "gear" then render()
    elseif name == "dungeons" then ns.RenderDungeons()
    elseif name == "ah" then ns.RenderAH()
    else ns.RefreshSettings(); f.footer:SetText("Every setting is saved between sessions · /trg help lists the slash commands") end
  end
  f.showTab = showTab
  tabs = buildHeader(f, showTab)
  f.tabs = tabs
  buildFooter(f)

  -- the spec switcher, shared by the Gear and Dungeons tabs
  f.specs = UI.SpecSwitcher(f, function(m)
    ns.db.windowMode = m
    render(); if ns.RenderDungeons then ns.RenderDungeons() end; if ns.RenderAH then ns.RenderAH() end
  end)
  f.specs:SetPoint("TOPLEFT", 16, -(HEAD_H + 12))

  ns.BuildSettings(sp)
  f.dungeonLayout = ns.BuildDungeons(dp, W, makeCell, f.specs)
  f.ahLayout = ns.BuildAH(ap, f.specs)

  -- summary at the top right of the Gear tab
  gp.sumValue = UI.Text(gp, "GameFontNormalLarge")
  gp.sumValue:SetPoint("TOPRIGHT", -18, -(HEAD_H + 30)); gp.sumValue:SetJustifyH("RIGHT")
  gp.sumLabel = UI.Text(gp, "GameFontHighlightSmall", C.muted)
  gp.sumLabel:SetPoint("BOTTOMRIGHT", gp.sumValue, "TOPRIGHT", 0, 3); gp.sumLabel:SetJustifyH("RIGHT")

  -- equip the winners
  gp.equip = UI.Button(gp, 128, 32, "Equip best", function() ns.EquipBest(ns.CurrentMode()) end,
    "Puts on every starred item from your bags for the spec selected above. Items that aren't soulbound yet will ask you to confirm, the same as equipping them yourself. Not in combat.")
  gp.equip:SetPoint("TOPLEFT", 16 + f.specs:GetWidth() + 16, -(HEAD_H + 20))

  -- column headings
  local TOP = HEAD_H + 72
  local heads = {}
  for _, k in ipairs({ { "slot", "SLOT" }, { "cur", "EQUIPPED" }, { "best", "BEST YOU OWN" }, { "gain", "GAIN" } }) do
    local h = UI.Text(gp, "GameFontHighlightSmall", C.muted, 10)
    h:SetText(k[2]); heads[k[1]] = h
  end

  local sf, content = ns.MakeScroll(gp, "TopRamenGearScroll", -(TOP + 18))
  content:SetHeight(16 * ROWH)
  for i = 1, 16 do
    local r = UI.Frame(content, C.row)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROWH)
    r:SetSize(W - 50, ROWH - 4)
    r.label = UI.Text(r, "GameFontHighlightSmall", C.muted)
    r.label:SetPoint("LEFT", 10, 0)
    r.cur = makeCell(r, 86, 274)
    r.best = makeCell(r, 354, 260)
    r.bestNote = UI.Text(r, "GameFontHighlightSmall", C.muted)
    r.bar = UI.Bar(r, 56)
    r.gain = UI.Text(r, "GameFontHighlight")
    r:Hide()
    rowsUI[i] = r
  end

  -- columns stretch with the window: Equipped and Best share the space, Gain sits at the right
  local function layoutGear()
    local w = sf:GetWidth()
    if not w or w < 100 then return end
    content:SetWidth(w)
    local gainW = 190
    local cw = math.floor((w - 86 - gainW) / 2)
    for _, r in ipairs(rowsUI) do
      r:SetWidth(w)
      placeCell(r.cur, 86, cw - 8)
      placeCell(r.best, 86 + cw, cw - 8)
      r.bestNote:ClearAllPoints(); r.bestNote:SetPoint("LEFT", 86 + cw, 0)
      r.bar:ClearAllPoints(); r.bar:SetPoint("LEFT", 86 + 2 * cw, 0)
      r.gain:ClearAllPoints(); r.gain:SetPoint("LEFT", r.bar, "RIGHT", 8, 0)
    end
    local function at(h, x) h:ClearAllPoints(); h:SetPoint("TOPLEFT", 16 + x, -TOP) end
    at(heads.slot, 10); at(heads.cur, 86); at(heads.best, 86 + cw); at(heads.gain, 86 + 2 * cw)
  end
  f.layouts = { layoutGear, f.dungeonLayout, ns.SettingsLayout, f.ahLayout }

  -- resizing: drag the grip in the bottom-right corner
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(720, 420, 1600, 1200)
  elseif f.SetMinResize then f:SetMinResize(720, 420); f:SetMaxResize(1600, 1200) end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -6, 6)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  local function savePlace()
    local p, _, rp, x, y = f:GetPoint()
    ns.db.win = { w = f:GetWidth(), h = f:GetHeight(), p = p, rp = rp, x = x, y = y, v = 2 }
  end
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); savePlace() end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePlace() end)
  f:SetScript("OnSizeChanged", function()
    for _, fn in ipairs(f.layouts) do pcall(fn) end
    ns.RefreshWindow()
  end)
  local saved = ns.db.win
  if saved and saved.w then
    -- the redesigned window is a little bigger: grow an older saved size to fit
    f:SetSize(math.max(saved.v == 2 and 720 or W, saved.w), math.max(saved.v == 2 and 420 or H, saved.h))
    f:ClearAllPoints()
    f:SetPoint(saved.p or "CENTER", UIParent, saved.rp or "CENTER", saved.x or 0, saved.y or 0)
  end

  f:SetScript("OnShow", function()
    for _, fn in ipairs(f.layouts) do pcall(fn) end
    showTab(ns.db.windowTab or "gear")
  end)
  f:RegisterEvent("BAG_UPDATE_DELAYED")
  f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  f:SetScript("OnEvent", function() ns.RefreshWindow() end)
  f:Hide() -- new frames start out shown; keep it hidden until /trg opens it
end

function ns.OpenTab(name)
  if not win then build() end
  ns.db.windowTab = name
  if win:IsShown() then win.showTab(name) else win:Show() end
end
function ns.OpenSettings() ns.OpenTab("settings") end

-- the auction house opened or closed: grey out the AH tab or make it usable (leaving it if you were on it)
function ns.SetAHTab(open)
  if not win or not win.tabs then return end
  win.tabs.ah:SetUsable(open and true or false)
  if not open and ns.db.windowTab == "ah" then
    if win:IsShown() then win.showTab("gear") else ns.db.windowTab = "gear" end
  end
end
function ns.SetFooter(text) if win and win.footer then win.footer:SetText(text) end end

function ns.ToggleWindow()
  if not win then build() end
  if win:IsShown() then win:Hide() else win:Show() end
end
