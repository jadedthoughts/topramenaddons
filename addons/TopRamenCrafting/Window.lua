-- Top Ramen Crafting: the planner window. /topramencraft opens it.

local _, ns = ...
local P = ns.Planner

local WIDTH, HEIGHT = 780, 660          -- default size; the window can be resized from its corner
local MIN_W, MIN_H, MAX_W, MAX_H = 780, 500, 1600, 1100 -- wide enough for 5 boxes in the top row
local BOX_W, BOX_STEP = 144, 150 -- profession / AH Database boxes
local ROW_H = 20
local GOLD, DIM, GOOD, BAD, WARN = "|cffe0b04a", "|cffa89a85", "|cff6fcf7a", "|cffe0705a", "|cffe6b84f"
local DIFF_COLOR = { optimal = "|cffff8040", medium = "|cffffff00", easy = "|cff40c040", trivial = "|cff808080" }
local NO_WINDOW = { Skinning = true, Herbalism = true, Fishing = true }
local WINDOW_NAME = { Mining = "Smelting" }
local SKILL_LINE = {
  Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202, Leatherworking = 165,
  Tailoring = 197, Mining = 186, ["First Aid"] = 129, Cooking = 185, Jewelcrafting = 755, Inscription = 773,
}
local ICON = {
  Alchemy = "Trade_Alchemy", Blacksmithing = "Trade_BlackSmithing", Enchanting = "Trade_Engraving",
  Engineering = "Trade_Engineering", Leatherworking = "Trade_LeatherWorking", Tailoring = "Trade_Tailoring",
  Mining = "Spell_Fire_FlameBlades", ["First Aid"] = "Spell_Holy_SealOfSacrifice", Cooking = "INV_Misc_Food_15",
  Jewelcrafting = "INV_Misc_Gem_01", Inscription = "INV_Inscription_Tradeskill01",
}
local MODES = { "vendor", "best", "ah" }
local MODE_TEXT = { vendor = "Sell to: vendor", best = "Sell to: best price", ah = "Sell to: auction house" }
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local WAITING = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t"
local NOT_READY = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"

-- does this profession need its window opened before the plan can be trusted?
local function needsOpen(p, skill)
  if not p then return true, "not read yet" end
  if p.needsOpen then return true, "open to update" end
  if skill and (p.scannedRank or 0) < skill.rank then return true, "skill went up" end
  return false
end

local frame, W = nil, {}
local tab = "plan"

---------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------
local function settings()
  local db = ns.db()
  db.settings = db.settings or {}
  local s = db.settings
  if s.mode == nil then s.mode = "vendor" end
  if s.points == nil then s.points = 10 end
  if s.maxAge == nil then s.maxAge = 3 end
  if s.ownedFree == nil then s.ownedFree = true end
  if s.makeReagents == nil then s.makeReagents = true end
  if s.bestChance == nil or not s.bestChanceDefaulted then s.bestChance = true; s.bestChanceDefaulted = true end -- on by default
  return s
end

local function coins(c)
  c = math.floor(math.abs(c) + 0.5)
  if c == 0 then return "0|cffc27c3ac|r" end
  local g, s, cc = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local out = {}
  if g > 0 then out[#out + 1] = "|cffffd100" .. g .. "g|r" end
  if s > 0 or g > 0 then out[#out + 1] = "|cffc7c7cf" .. s .. "s|r" end
  out[#out + 1] = "|cffc27c3a" .. cc .. "c|r"
  return table.concat(out, " ")
end

local function money(c, signed)
  if c == nil then return DIM .. "?|r" end
  local r = math.floor(c + 0.5)
  if signed then
    if r < 0 then return BAD .. "-|r" .. coins(r) end
    if r > 0 then return GOOD .. "+|r" .. coins(r) end
  end
  return (r < 0 and "-" or "") .. coins(r)
end

local function itemText(id)
  local it = ns.itemData(id)
  if not it then return DIM .. "item " .. id .. "|r" end
  local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.quality]
  return ((q and q.hex) or "|cffffffff") .. it.name .. "|r"
end

local function whereText(w)
  if w == "vendor" then return "|cff9fd3ffVendor|r" end
  if w == "ah" then return GOLD .. "Auction house|r" end
  if w == "craft" then return GOOD .. "Craft it|r" end
  return BAD .. "No price|r"
end

local function sortedRecipes(p)
  local list = {}
  for _, r in pairs(p and p.recipes or {}) do list[#list + 1] = r end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

local function currentSkills()
  local out = {}
  for _, s in ipairs(ns.readSkills()) do out[s.name] = s end
  return out
end

local function craftingProfessions()
  local list = {}
  for _, s in ipairs(ns.readSkills()) do
    if not NO_WINDOW[s.name] and not ns.IGNORED_PROFESSIONS[s.name] then list[#list + 1] = s end
  end
  return list
end

---------------------------------------------------------------------------
-- opening a profession window
---------------------------------------------------------------------------
local function skillLineFor(name)
  local T = C_TradeSkillUI
  if T and T.GetAllProfessionTradeSkillLines and T.GetProfessionInfoBySkillLineID then
    local ok, lines = pcall(T.GetAllProfessionTradeSkillLines)
    if ok and type(lines) == "table" then
      for _, id in ipairs(lines) do
        local ok2, info = pcall(T.GetProfessionInfoBySkillLineID, id)
        if ok2 and info and (info.professionName == name or info.parentProfessionName == name) then
          return info.parentProfessionID or id
        end
      end
    end
  end
  return SKILL_LINE[name]
end

local function openProfession(name)
  local T = C_TradeSkillUI
  local id = skillLineFor(name)
  if T and T.OpenTradeSkill and id then
    local ok, res = pcall(T.OpenTradeSkill, id)
    if ok and res ~= false then return end
  end
  ns.say("Couldn't open " .. (WINDOW_NAME[name] or name) .. " from here. Open it from your spellbook; the planner picks it up either way.")
end

---------------------------------------------------------------------------
-- widgets
---------------------------------------------------------------------------
local function label(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  return fs
end

local function button(parent, text, w, h, onClick)
  return ns.UI.Button(parent, w, h or 22, text, onClick)
end

local function checkbox(parent, text, onClick)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  local l = label(c, text, "GameFontHighlightSmall")
  l:SetPoint("LEFT", c, "RIGHT", 2, 0)
  c:SetScript("OnClick", onClick)
  return c
end

-- a box you can type a whole number into; onSet(number) runs on Enter or when you click away
local function numberBox(parent, width, onSet)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width or 32, 18)
  e:SetAutoFocus(false)
  e:SetNumeric(true)
  e:SetMaxLetters(3)
  e:SetJustifyH("CENTER")
  local function apply(self)
    local v = tonumber(self:GetText())
    if v then onSet(v) end
    self:ClearFocus()
    ns.RefreshWindow()
  end
  e:SetScript("OnEnterPressed", apply)
  e:SetScript("OnEditFocusLost", function(self) local v = tonumber(self:GetText()); if v then onSet(v) end; ns.RefreshWindow() end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ns.RefreshWindow() end)
  -- don't overwrite what you're typing when the window refreshes
  e.SetValue = function(self, v) if not self:HasFocus() then self:SetText(tostring(v)) end end
  return e
end

-- "title [-] [ n ] [+]": the buttons step by 1, or type a number in the box
local function stepper(parent, title, onChange, onSet)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(190, 22)
  local t = label(box, title)
  t:SetPoint("LEFT", 0, 0)
  local minus = button(box, "-", 22, 20, function() onChange(-1) end)
  minus:SetPoint("LEFT", t, "RIGHT", 6, 0)
  local value = numberBox(box, 34, onSet)
  value:SetPoint("LEFT", minus, "RIGHT", 8, 0)
  local plus = button(box, "+", 22, 20, function() onChange(1) end)
  plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
  box.value = value
  return box
end

-- columns as fractions of the list width: { {start, width, justify}, ... }
local LAYOUT = {
  plan = { { 0, .34, "LEFT" }, { .35, .07, "RIGHT" }, { .43, .07, "RIGHT" }, { .51, .15, "RIGHT" }, { .67, .16, "RIGHT" }, { .84, .16, "RIGHT" } },
  money = { { 0, .38, "LEFT" }, { .39, .15, "RIGHT" }, { .55, .17, "RIGHT" }, { .73, .13, "RIGHT" } },
  shop = { { 0, .30, "LEFT" }, { .31, .07, "RIGHT" }, { .39, .08, "RIGHT" }, { .48, .07, "RIGHT" }, { .57, .17, "LEFT" }, { .75, .25, "RIGHT" } },
  guild = { { 0, .34, "LEFT" }, { .35, .20, "LEFT" }, { .56, .13, "RIGHT" }, { .70, .11, "RIGHT" }, { .84, .16, "LEFT" } },
  flips = { { 0, .36, "LEFT" }, { .37, .12, "RIGHT" }, { .50, .15, "RIGHT" }, { .66, .15, "RIGHT" }, { .82, .18, "RIGHT" } },
}
local OPEN_W = 70 -- the Open button on guild rows
local MAKE_W = 96 -- the "- n +" controls on money-maker rows
local CHECK_W = 24 -- the pick checkbox on plan and money-maker rows

local function listWidth()
  return math.max(MIN_W, (frame and frame:GetWidth()) or WIDTH) - 64
end

-- pixel position and width of a column; money-maker columns leave room for the + / - controls
local function colPos(name, col)
  local left = (name == "plan" or name == "money" or name == "flips") and CHECK_W or 0
  local w = listWidth() - left - (name == "money" and MAKE_W or 0) - ((name == "guild" or name == "flips") and OPEN_W or 0)
  return 4 + left + col[1] * w, col[2] * w
end
local HEADERS = {
  plan = { "Recipe", "Crafts", "Points", "Materials", "Sells for", "Net" },
  money = { "Recipe", "Materials", "Sells for", "Profit each" },
  shop = { "Material", "Need", "Have", "Buy", "Where", "Total" },
  guild = { "Guildmate", "Profession", "Skill", "Recipes", "Link" },
  flips = { "Item", "Cheap units", "AH price", "Vendor pays", "Profit" },
}

-- craft time as text: 3s, 1.5s, 4m 05s, 1h 02m
local function dur(sec)
  if not sec then return "?" end
  if sec < 10 and sec ~= math.floor(sec) then return ("%.1fs"):format(sec) end
  sec = math.floor(sec + 0.5)
  if sec < 60 then return sec .. "s" end
  if sec < 3600 then return ("%dm %02ds"):format(math.floor(sec / 60), sec % 60) end
  return ("%dh %02dm"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end
-- total crafting time for a list of { recipe, n }; also how many recipes have no time recorded yet
local function craftTime(list)
  local total, unknown = 0, 0
  for _, x in ipairs(list or {}) do
    if x.recipe.cast then total = total + x.recipe.cast * x.n else unknown = unknown + 1 end
  end
  return total, unknown
end

local rows = {}
local function getRow(i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, W.content)
  row:SetHeight(ROW_H)
  row:SetPoint("RIGHT", W.content, "RIGHT", 0, 0)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints()
  row.stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
  row.cols = {}
  for c = 1, 6 do row.cols[c] = label(row, "", "GameFontHighlightSmall") end
  row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.check:SetSize(20, 20)
  row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.check:SetScript("OnClick", function(self)
    local r = self:GetParent()
    if r.OnCheck then r.OnCheck(self:GetChecked() and true or false) end
  end)
  row.minus = button(row, "-", 20, 16, function(self) self:GetParent():OnStep(-1) end)
  row.qty = numberBox(row, 30, function(v) local r = row; if r.OnSet then r.OnSet(v) end end)
  row.plus = button(row, "+", 20, 16, function(self) self:GetParent():OnStep(1) end)
  row.open = button(row, "Open", 60, 18, function(self) local r = self:GetParent(); if r.OnOpen then r.OnOpen() end end)
  row.open:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.open:Hide()
  row:SetScript("OnEnter", function(self)
    if not self.itemID or self.itemID == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) else GameTooltip:SetHyperlink("item:" .. self.itemID) end
    if self.extra and #self.extra > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Used for:", 0.88, 0.69, 0.29)
      for _, l in ipairs(self.extra) do GameTooltip:AddLine(l, 1, 1, 1) end
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", function(self) if self.OnRowClick then self.OnRowClick() end end)
  rows[i] = row
  return row
end

local function setRow(i, layoutName, values, itemID, step, extra, check)
  local row = getRow(i)
  row.extra = extra
  row.open:Hide(); row.OnOpen = nil; row.OnRowClick = nil
  if check then
    row.check:SetChecked(check.checked)
    row.OnCheck = check.fn
    row.check:Show()
  else
    row.OnCheck = nil
    row.check:Hide()
  end
  local layout = layoutName and LAYOUT[layoutName]
  for c = 1, 6 do
    local fs, col = row.cols[c], layout and layout[c]
    if col and values[c] then
      local x, w = colPos(layoutName, col)
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", row, "LEFT", x, 0)
      fs:SetWidth(w)
      fs:SetJustifyH(col[3])
      fs:SetText(values[c])
      fs:Show()
    else
      fs:Hide()
    end
  end
  if not layout then -- full-width line
    local fs = row.cols[1]
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", 4, 0)
    fs:SetWidth(listWidth() - 8)
    fs:SetJustifyH("LEFT")
    fs:SetText(values[1] or "")
    fs:Show()
  end
  row.itemID = itemID
  row.OnStep = step and step.fn or nil
  if step then
    row.minus:ClearAllPoints(); row.minus:SetPoint("LEFT", row, "LEFT", listWidth() - MAKE_W + 8, 0); row.minus:Show()
    row.qty:ClearAllPoints(); row.qty:SetPoint("LEFT", row.minus, "RIGHT", 6, 0)
    row.qty:SetValue(step.value); row.qty:Show()
    row.plus:ClearAllPoints(); row.plus:SetPoint("LEFT", row.qty, "RIGHT", 2, 0); row.plus:Show()
    row.OnSet = step.set
  else
    row.minus:Hide(); row.qty:Hide(); row.plus:Hide(); row.OnSet = nil
  end
  row:Show()
end

---------------------------------------------------------------------------
-- rendering
---------------------------------------------------------------------------
local profButtons = {}

local function selectedProfession(c)
  local profs = craftingProfessions()
  local sel = c.selected
  local valid = false
  for _, s in ipairs(profs) do if s.name == sel then valid = true end end
  if not valid then
    sel = nil
    for _, s in ipairs(profs) do if c.professions[s.name] then sel = s.name; break end end
    sel = sel or (profs[1] and profs[1].name)
    c.selected = sel
  end
  return sel
end

-- which crafts are ticked for the shopping list: picks.plan[recipe] / picks.money[recipe] = true
local function picks(c, prof)
  c.picks = c.picks or {}
  c.picks[prof] = c.picks[prof] or { plan = {}, money = {} }
  return c.picks[prof]
end

local function makeQty(c, prof)
  c.makeQty = c.makeQty or {}
  c.makeQty[prof] = c.makeQty[prof] or {}
  return c.makeQty[prof]
end

local function renderButtons(c, skills, sel)
  local profs = craftingProfessions()
  for i, s in ipairs(profs) do
    local b = profButtons[i]
    if not b then
      b = CreateFrame("Button", nil, frame, "BackdropTemplate")
      b:SetSize(BOX_W, 42)
      ns.UI.Skin(b, ns.UI.C.row, ns.UI.C.line)
      b.iconBorder = ns.UI.Frame(b, ns.UI.C.track, ns.UI.C.trim, 1)
      b.iconBorder:SetSize(34, 34)
      b.iconBorder:SetPoint("LEFT", 4, 0)
      b.icon = b.iconBorder:CreateTexture(nil, "ARTWORK")
      b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
      b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      b.hl = { Show = function() b:SetBackdropColor(1, 0.82, 0, 0.08); b:SetBackdropBorderColor(1, 0.82, 0, 0.6) end,
               Hide = function() local c = ns.UI.C; b:SetBackdropColor(c.row[1], c.row[2], c.row[3], 1); b:SetBackdropBorderColor(c.line[1], c.line[2], c.line[3], 1) end }
      b.text = label(b, "", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", b.iconBorder, "RIGHT", 6, 0)
      b.text:SetWidth(BOX_W - 48)
      b:SetScript("OnClick", function(self)
        local cd = ns.charData()
        cd.selected = self.prof
        openProfession(self.prof)
        ns.RefreshWindow()
      end)
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(WINDOW_NAME[self.prof] or self.prof)
        GameTooltip:AddLine("Click to open it and read its recipes. A red X means its recipes need reading again before the plan is reliable.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      profButtons[i] = b
    end
    b.prof = s.name
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + (i - 1) * BOX_STEP, -(ns.UI.HEAD_H + 12))
    b.icon:SetTexture("Interface\\Icons\\" .. (ICON[s.name] or "INV_Misc_QuestionMark"))
    local p = c.professions[s.name]
    local stale, why = needsOpen(p, s)
    local mark = stale and (NOT_READY .. BAD .. " " .. why .. "|r") or READY
    b.text:SetText((s.name == sel and GOLD or "") .. (WINDOW_NAME[s.name] or s.name) .. "|r\n" .. s.rank .. "/" .. s.max .. "  " .. mark)
    if s.name == sel then b.hl:Show() else b.hl:Hide() end
    b:Show()
  end
  for i = #profs + 1, #profButtons do profButtons[i]:Hide() end
  if #profs == 0 then W.noProf:Show() else W.noProf:Hide() end

  -- the AH Database box: when prices were last scanned, and how fresh that is
  local box = W.ahBox
  if not box then
    box = CreateFrame("Button", nil, frame, "BackdropTemplate")
    box:SetSize(BOX_W, 42)
    ns.UI.Skin(box, ns.UI.C.row, ns.UI.C.line)
    box.iconBorder = ns.UI.Frame(box, ns.UI.C.track, ns.UI.C.trim, 1)
    box.iconBorder:SetSize(34, 34)
    box.iconBorder:SetPoint("LEFT", 4, 0)
    box.icon = box.iconBorder:CreateTexture(nil, "ARTWORK")
    box.icon:SetPoint("TOPLEFT", 1, -1); box.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    box.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    box.text = label(box, "", "GameFontHighlightSmall")
    box.text:SetPoint("LEFT", box.iconBorder, "RIGHT", 6, 0)
    box.text:SetWidth(BOX_W - 48)
    box:SetScript("OnClick", function()
      if not ns.Prices.isAHOpen() then ns.say("open the auction house, then click AH Database (or Full scan) to scan prices."); return end
      if ns.Prices.fullScanWait() > 0 then ns.Prices.quickScan() else ns.Prices.fullScan() end
    end)
    box:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine("AH Database")
      GameTooltip:AddLine("Green check: scanned in the last 15 minutes. Yellow ?: up to a day old. Red X: older than a day, or never scanned.", 1, 1, 1, true)
      GameTooltip:AddLine("At the auction house, click to scan: a full scan, or a quick scan while the full scan is on its 15-minute cooldown.", 1, 1, 1, true)
      local line = ns.Prices.statusText()
      if line then GameTooltip:AddLine(line, 0.7, 0.7, 0.7, true) end
      GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
      local v = ns.Prices.progress()
      if v then
        self.bar:SetWidth(math.max(1, ((self:GetWidth() or BOX_W) - 2) * v))
        self.bar:Show()
        self.pct:SetText(math.floor(v * 100) .. "%")
        self.pct:Show()
        self.text:SetAlpha(0.35)
      elseif self.bar:IsShown() then
        self.bar:Hide(); self.pct:Hide(); self.text:SetAlpha(1)
      end
    end)
    W.ahBox = box
  end
  box:ClearAllPoints()
  box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -(ns.UI.HEAD_H + 12)) -- always at the far right
  local state, age = ns.Prices.freshness()
  local t = ns.Prices.lastScanAt()
  local when = "never scanned"
  if t then
    -- 12-hour time today ("3:57 PM"); with the date when it's from another day ("Nov 15 3:57 PM")
    local clock = date("%I:%M %p", t):gsub("^0", "")
    when = (date("%x", t) == date("%x")) and clock or (date("%b %d ", t):gsub(" 0", " ") .. clock)
  end
  local mark = state == "ok" and READY or state == "aging" and WAITING or NOT_READY
  local color = state == "ok" and GOOD or state == "aging" and WARN or BAD
  if ns.Prices.isScanning() then when = "scanning..." ; mark = WAITING; color = WARN end
  box.text:SetText("AH Database\n" .. color .. when .. "|r  " .. mark)
  box:Show()
end

local function freshness(pl, recipes, p, skill)
  local ids = {}
  for _, r in ipairs(recipes) do
    for _, rg in ipairs(r.reagents) do ids[rg.id] = true end
    if (r.out or 0) > 0 then ids[r.out] = true end
  end
  local fresh, aging, old, none, total = 0, 0, 0, 0, 0
  for id in pairs(ids) do
    total = total + 1
    local it = pl:get(id)
    if not it then none = none + 1
    elseif not it.ah then if not it.vbuy then none = none + 1 end
    elseif it.age == nil or it.age > pl.s.maxAge then old = old + 1
    elseif it.age <= 1 then fresh = fresh + 1
    else aging = aging + 1 end
  end
  local parts = {}
  local scanLine = ns.Prices and ns.Prices.statusText()
  if scanLine then parts[#parts + 1] = DIM .. scanLine .. "|r"
  elseif not ns.auctionator() then parts[#parts + 1] = BAD .. "No auction prices yet: open the auction house and click Full scan.|r" end
  local stale, why = needsOpen(p, skill)
  if p and stale then
    parts[#parts + 1] = BAD .. "Recipe colors may be out of date (" .. why .. ", last read at skill " .. (p.scannedRank or 0) ..
      "). Click " .. (WINDOW_NAME[p.name] or p.name or "the profession button") .. " above to open it and update the plan.|r"
  end
  local priceLine = "AH prices: " .. fresh .. " fresh, " .. aging .. " a few days old, " .. old .. " too old, " .. none .. " none"
  if old + none > total * 0.3 then parts[#parts + 1] = BAD .. priceLine .. ". Click Full scan at the auction house.|r"
  elseif old + aging + none > 0 then parts[#parts + 1] = WARN .. priceLine .. ".|r"
  else parts[#parts + 1] = GOOD .. priceLine .. ".|r" end
  return table.concat(parts, "\n")
end

---------------------------------------------------------------------------
-- Guild tab: who has which profession, what they can make, and their saved profession links
---------------------------------------------------------------------------
local askedGuild = false -- read the guild list once per session when the tab is first opened

local function nameKey(n) return ((n or ""):gsub("%-.*$", "")):lower() end

-- who's online right now, from the guild roster (falls back to the saved list)
local function rosterOnline()
  local on = {}
  if not (GetNumGuildMembers and GetGuildRosterInfo) then return on end
  for i = 1, (GetNumGuildMembers() or 0) do
    local ok, name, _, _, _, _, _, _, _, online = pcall(GetGuildRosterInfo, i)
    if ok and name then on[nameKey(Ambiguate and Ambiguate(name, "short") or name)] = online and true or false end
  end
  return on
end

local function shortDate(t)
  if not t then return "" end
  return (date("%b %d", t):gsub(" 0", " "))
end

local function renderGuild(n)
  local db = ns.db()
  local dir = db.guildDir
  local known, links = db.guild or {}, db.links or {}
  local function line(text) n = n + 1; setRow(n, nil, { text }) end

  if not dir and not askedGuild and IsInGuild and IsInGuild() and ns.readGuildDirectory then
    askedGuild = true
    ns.readGuildDirectory(true)
    dir = db.guildDir
  end

  -- everything we know about a person's profession, matched by name without caring about capitals
  local function find(t, who, prof)
    local wk, pk = nameKey(who), (prof or ""):lower()
    for name, profs in pairs(t) do
      if nameKey(name) == wk then
        for p, e in pairs(profs) do if p:lower() == pk then return e, name, p end end
      end
    end
  end
  local online = rosterOnline()
  local guids = ns.knownGUIDs and ns.knownGUIDs() or {}
  local function isOnline(who, fallback)
    local v = online[nameKey(who)]
    if v == nil then return fallback end
    return v
  end

  local function personRow(who, prof, on)
    local rec = find(known, who, prof)
    local link, linkName, linkProf = find(links, who, prof)
    local nameText = (on and GOOD or DIM) .. who .. "|r" .. (on and "" or (DIM .. "  offline|r"))
    local skill = rec and rec.rank and rec.rank > 0 and (rec.rank .. "/" .. tostring(rec.max or "?")) or (DIM .. "-|r")
    local count = rec and tostring(rec.count or 0) or (DIM .. "-|r")
    n = n + 1
    local g = guids[who]
    local otherRealm = g and ns.sameRealm and not ns.sameRealm(g)
    local guid = not link and not otherRealm and ns.canBuildLink and ns.canBuildLink(prof) and g
    setRow(n, "guild", { nameText, prof, skill, count,
      link and (shortDate(link.seen) .. (link.built and (DIM .. " built|r") or "")) or (guid and (DIM .. "can build|r")) or
      (otherRealm and (DIM .. "needs their link|r")) or (DIM .. "no|r") })
    if (link or guid) and on then -- profession windows only open while the person is online
      local r = rows[n]
      r.OnOpen = function()
        if link then
          if SlashCmdList and SlashCmdList.TOPRAMENCRAFT then SlashCmdList.TOPRAMENCRAFT("relink " .. linkName .. " " .. linkProf) end
        else
          ns.openBuiltLink(who, prof)
        end
      end
      r.open:Show()
    end
  end

  local q = W.guildSearch and (W.guildSearch:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
  local people, linkedCount, recordedCount = 0, 0, 0
  for _, profs in pairs(links) do for _ in pairs(profs) do linkedCount = linkedCount + 1 end end
  for _, profs in pairs(known) do for _ in pairs(profs) do recordedCount = recordedCount + 1 end end
  if dir then for _, list in pairs(dir.profs) do people = people + #list end end

  W.fresh:SetText((IsInGuild and IsInGuild()) and "" or (WARN .. "You're not in a guild. Links people send you still show below.|r"))
  W.summary:SetText(("%d profession entries in the guild    %d recipe lists known    %d saved links\n%s"):format(people, recordedCount, linkedCount,
    DIM .. "Click a profession to fold it. Open shows an online guildmate's profession and saves their recipes.|r"))

  -- everyone we know about, grouped by profession: the guild list, then people who linked a profession
  local groups, seen = {}, {}
  if dir then
    local profNames = {}
    for prof in pairs(dir.profs) do profNames[#profNames + 1] = prof end
    table.sort(profNames)
    for _, prof in ipairs(profNames) do
      local list = {}
      for _, m in ipairs(dir.profs[prof]) do
        list[#list + 1] = { who = m.name, prof = prof, on = isOnline(m.name, m.online) }
        seen[nameKey(m.name) .. "|" .. prof:lower()] = true
      end
      groups[#groups + 1] = { key = prof, title = prof, people = list, counts = true }
    end
  end
  local others = {}
  for _, t in ipairs({ known, links }) do
    for who, profs in pairs(t) do
      for prof in pairs(profs) do
        local k = nameKey(who) .. "|" .. prof:lower()
        if not seen[k] then seen[k] = true; others[#others + 1] = { who = who, prof = prof, on = isOnline(who, false) } end
      end
    end
  end
  if #others > 0 then
    groups[#groups + 1] = { key = "_others", title = dir and "Others who linked a profession" or "Profession links you've seen", people = others }
  end
  local function byOnline(a, b)
    if a.on ~= b.on then return a.on end
    if a.who ~= b.who then return a.who < b.who end
    return a.prof < b.prof
  end

  if q ~= "" then
    -- guildmates whose name matches
    local people = {}
    for _, g in ipairs(groups) do
      for _, x in ipairs(g.people) do if x.who:lower():find(q, 1, true) then people[#people + 1] = x end end
    end
    table.sort(people, function(a, b) if a.who ~= b.who then return a.who < b.who end return a.prof < b.prof end)
    if #people > 0 then
      line(GOLD .. "Guildmates matching \"" .. q .. "\"|r")
      for _, x in ipairs(people) do personRow(x.who, x.prof, x.on) end
    end
    -- who can make it: search every recipe list we've recorded
    local byRecipe, names = {}, {}
    for who, profs in pairs(known) do
      for prof, e in pairs(profs) do
        for _, rname in pairs(e.recipes or {}) do
          if rname:lower():find(q, 1, true) then
            if not byRecipe[rname] then byRecipe[rname] = {}; names[#names + 1] = rname end
            table.insert(byRecipe[rname], { who = who, prof = prof })
          end
        end
      end
    end
    table.sort(names)
    if #names == 0 and #people == 0 then
      line(DIM .. "No guildmate or known recipe matches \"" .. q .. "\".|r")
      line(DIM .. "Recipes are searchable once a guildmate's profession has been opened (Open, or a link they send).|r")
    end
    for i, rname in ipairs(names) do
      if i > 60 then line(DIM .. (#names - 60) .. " more recipes match. Type more of the name.|r"); break end
      line(GOLD .. rname .. "|r")
      local list = byRecipe[rname]
      for _, x in ipairs(list) do x.on = isOnline(x.who, false) end
      table.sort(list, byOnline)
      for _, x in ipairs(list) do personRow(x.who, x.prof, x.on) end
    end
    return n
  end

  -- the directory: click a profession to fold or unfold it
  local folded = settings().guildFolded or {}
  settings().guildFolded = folded
  for _, g in ipairs(groups) do
    table.sort(g.people, byOnline)
    local on = 0
    for _, x in ipairs(g.people) do if x.on then on = on + 1 end end
    local closed = folded[g.key]
    line((closed and "|cff8f8f8f[+]|r " or "|cff8f8f8f[-]|r ") .. GOLD .. g.title .. "|r" ..
      DIM .. "   " .. #g.people .. (g.counts and " in the guild, " or " people, ") .. on .. " online|r")
    rows[n].OnRowClick = function() folded[g.key] = (not folded[g.key]) or nil; ns.RefreshWindow() end
    if not closed then
      for _, x in ipairs(g.people) do personRow(x.who, x.prof, x.on) end
    end
  end
  if not dir and #others == 0 then line(DIM .. "Nothing yet. Open the guild list with Refresh guild list, or ask someone to link a profession in chat.|r") end
  return n
end

---------------------------------------------------------------------------
-- Vendor flips: auction listings priced below what a vendor pays for the item
---------------------------------------------------------------------------
local sellCache = {}
local function vendorSell(id)
  local v = sellCache[id]
  if v ~= nil then return v or nil end
  local sell
  if C_Item and C_Item.GetItemInfo then sell = select(11, C_Item.GetItemInfo(id))
  elseif GetItemInfo then sell = select(11, GetItemInfo(id)) end
  if sell == nil then -- not loaded yet: ask the game, and the window refreshes when it arrives
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return nil, true
  end
  sellCache[id] = sell > 0 and sell or false
  return sell > 0 and sell or nil
end

-- reagents: trade goods and reagent items, plus anything a recipe you know uses
local function reagentSet()
  local set = {}
  for _, c in pairs(ns.db().chars or {}) do
    for _, p in pairs(c.professions or {}) do
      for _, r in pairs(p.recipes or {}) do
        for _, rg in ipairs(r.reagents or {}) do set[rg.id] = true end
      end
    end
  end
  return set
end
local function isReagent(id, used)
  if used[id] then return true end
  local classID
  if C_Item and C_Item.GetItemInfoInstant then classID = select(6, C_Item.GetItemInfoInstant(id))
  elseif GetItemInfoInstant then classID = select(6, GetItemInfoInstant(id)) end
  return classID == 5 or classID == 7 -- Reagent, Trade Goods
end

-- show an item on the auction window's own buy screen, quantity filled in where the game allows
function ns.ShowInAH(id, qty)
  local f, a = AuctionHouseFrame, C_AuctionHouse
  if not (f and f:IsShown() and a) then ns.say("open the auction house first."); return false end
  local name = (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
  local opened = pcall(function()
    if AuctionHouseFrameDisplayMode and f.SetDisplayMode then f:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy) end
    f:SelectBrowseResult({ itemKey = a.MakeItemKey(id) })
  end)
  if not opened and f.SearchBar then pcall(function() f.SearchBar:SetSearchText(name); f.SearchBar:StartSearch() end) end
  local function setQty()
    pcall(function()
      local cb = f.CommoditiesBuyFrame
      local bd = cb and (cb.GetBuyDisplay and cb:GetBuyDisplay() or cb.BuyDisplay)
      if bd and bd.SetQuantitySelected and qty then bd:SetQuantitySelected(qty) end
    end)
  end
  if C_Timer then C_Timer.After(0.6, setQty) else setQty() end
  return true
end

-- one item's flip from its scanned price levels: the listings below what a vendor pays
local function flipEntry(id, e)
  local sell, pending = vendorSell(id)
  if pending or not sell then return nil, pending end
  local lv = e.l or { e.p, e.q }
  local units, cost = 0, 0
  for i = 1, #lv - 1, 2 do
    if lv[i] < sell then units = units + lv[i + 1]; cost = cost + lv[i] * lv[i + 1] else break end
  end
  return { id = id, units = units, cost = cost, avg = units > 0 and cost / units or 0, sell = sell,
           profit = sell * units - cost, age = time() - (e.t or 0) }
end

-- ticked vendor flips, priced from the latest prices: { id, units, cost, avg, sell, profit } (units 0 when none are left cheap)
local function flipPicks() local d = ns.db(); d.flipPicks = d.flipPicks or {}; return d.flipPicks end
function ns.FlipShopping()
  local out = {}
  local P = ns.Prices
  for id in pairs(flipPicks()) do
    local p, q, l
    if P then p, _, q, l = P.lookup(id) end
    local x = p and flipEntry(id, { p = p, q = q, l = l })
    out[#out + 1] = x or { id = id, units = 0, cost = 0, avg = 0, sell = 0, profit = 0 }
  end
  table.sort(out, function(a, b) return a.profit > b.profit end)
  return out
end

local function renderFlips(n)
  local P = ns.Prices
  local function line(text) n = n + 1; setRow(n, nil, { text }) end
  if not P or not P.forEach then line(DIM .. "No auction data yet.|r"); return n end
  -- reworking ~6,000 items on every item-info event would stutter: reuse the last result for a second
  local now = GetTime and GetTime() or time()
  local fc = W.flipCache
  local list, waiting, all
  if fc and now - fc.at < 1 then
    list, waiting, all = fc.list, fc.waiting, fc.all
    if waiting > 0 and C_Timer and not fc.again then fc.again = true; C_Timer.After(1.1, ns.RefreshWindow) end
  else
  list, waiting, all = {}, 0, 0
  P.forEach(function(id, e)
    all = all + 1
    local x, pending = flipEntry(id, e)
    if pending then waiting = waiting + 1; return end
    if x and x.units > 0 then list[#list + 1] = x end
  end)
  table.sort(list, function(a, b) return a.profit > b.profit end)
  local used = reagentSet()
  for _, x in ipairs(list) do x.reagent = isReagent(x.id, used) end
  W.flipCache = { at = now, list = list, waiting = waiting, all = all }
  end
  local onlyReagents = settings().flipReagents
  if onlyReagents then
    local f = {}
    for _, x in ipairs(list) do if x.reagent then f[#f + 1] = x end end
    list = f
  end
  local total = 0
  for _, x in ipairs(list) do total = total + x.profit end
  local scanAt = P.lastScanAt and P.lastScanAt()
  W.summary:SetText(("%d %s listed below what a vendor pays    Buy them all and vendor them: %s profit\n%s"):format(#list,
    onlyReagents and "reagents" or "items", money(total, true),
    DIM .. "From your last scan" .. (scanAt and (" (" .. date("%I:%M %p", scanAt):gsub("^0", "") .. ")") or "") ..
    "; cheap listings sell fast, so run a Full scan first. Tick items to add them to the Shopping list.|r"))
  if waiting > 0 then line(DIM .. "Loading vendor prices for " .. waiting .. " more items; the list fills in as they arrive.|r") end
  if all == 0 then line(DIM .. "No auction prices yet. Open the auction house and click Full scan.|r") end
  local ahOpen = P.isAHOpen and P.isAHOpen()
  for i, x in ipairs(list) do
    if i > 150 then line(DIM .. (#list - 150) .. " more with smaller profits.|r"); break end
    n = n + 1
    local picked = flipPicks()
    setRow(n, "flips", { itemText(x.id), tostring(x.units), money(x.avg) .. DIM .. " avg|r", money(x.sell), money(x.profit, true) }, x.id,
      nil, nil, { checked = picked[x.id] and true or false, fn = function(v) picked[x.id] = v or nil; ns.RefreshWindow() end })
    if ahOpen then
      local r = rows[n]
      r.OnOpen = function() if ns.ShowInAH then ns.ShowInAH(x.id, x.units) end end
      r.open:Show()
    end
  end
  if #list == 0 and all > 0 and waiting == 0 then
    line(DIM .. (onlyReagents and "No reagents" or "Nothing") .. " on the auction house is priced below what a vendor pays right now.|r")
  end
  return n
end

local function render()
  if not (frame and frame:IsShown()) then return end
  local c = ns.charData()
  local s = settings()
  local skills = currentSkills()
  local sel = selectedProfession(c)
  renderButtons(c, skills, sel)

  if ns.Prices then
    local open, busy = ns.Prices.isAHOpen(), ns.Prices.isScanning()
    if open and not busy then W.quickScan:Enable() else W.quickScan:Disable() end
    if open and not busy and ns.Prices.fullScanWait() == 0 then W.fullScan:Enable() else W.fullScan:Disable() end
  end
  W.mode:SetText(MODE_TEXT[s.mode])
  W.points.value:SetValue(s.points)
  W.age.value:SetValue(s.maxAge)
  W.owned:SetChecked(s.ownedFree)
  W.make:SetChecked(s.makeReagents)
  W.best:SetChecked(s.bestChance)
  for name, b in pairs(W.tabs) do if name == tab then b:LockHighlight() else b:UnlockHighlight() end end

  local p = sel and c.professions[sel]
  local recipes = sortedRecipes(p)
  local all = {}
  for _, prof in pairs(c.professions) do for _, r in pairs(prof.recipes or {}) do all[#all + 1] = r end end
  local skill = sel and skills[sel]
  local pl = P.new(function(id) return ns.itemData(id) end, recipes, all, s)

  local n = 0
  local function line(text) n = n + 1; setRow(n, nil, { text }) end -- no item, no tooltip

  if tab == "guild" or tab == "flips" then
    W.header:Show()
    local hdr, lay = HEADERS[tab], LAYOUT[tab]
    for i = 1, 6 do
      local fs = W.headerCols[i]
      if lay[i] then
        local x, w = colPos(tab, lay[i])
        fs:ClearAllPoints(); fs:SetPoint("LEFT", W.header, "LEFT", x, 0)
        fs:SetWidth(w); fs:SetJustifyH(lay[i][3]); fs:SetText(DIM .. hdr[i] .. "|r"); fs:Show()
      else fs:Hide() end
    end
    if tab == "flips" then W.headerBuy:Show() else W.headerBuy:Hide() end
    if tab == "guild" then n = renderGuild(n) else W.fresh:SetText(""); n = renderFlips(n) end
  elseif not p then
    W.fresh:SetText(sel and (WARN .. "Click " .. sel .. " above so its recipes are recorded.|r") or "")
    W.summary:SetText("")
    W.header:Hide()
    line(DIM .. "No recipes recorded for this profession yet.|r")
  else
    p.name = sel
    W.fresh:SetText(freshness(pl, recipes, p, skill))
    local rank, cap = skill and skill.rank or p.rank or 0, skill and skill.max or p.max or 0
    local room = math.max(0, cap - rank)
    local points = math.min(s.points, room > 0 and room or s.points)
    local plan = pl:planSkillUps(points, rank)
    local qty = makeQty(c, sel)
    local pick = picks(c, sel)
    local extra = {}
    for _, r in ipairs(recipes) do
      if pick.money[r.name] then extra[#extra + 1] = { recipe = r, n = math.max(1, qty[r.name] or 1) } end
    end

    W.header:Show()
    local hdr, lay = HEADERS[tab], LAYOUT[tab]
    for i = 1, 6 do
      local fs = W.headerCols[i]
      if lay[i] then
        local x, w = colPos(tab, lay[i])
        fs:ClearAllPoints(); fs:SetPoint("LEFT", W.header, "LEFT", x, 0)
        fs:SetWidth(w); fs:SetJustifyH(lay[i][3]); fs:SetText(DIM .. hdr[i] .. "|r"); fs:Show()
      else fs:Hide() end
    end
    if tab == "plan" or tab == "money" then W.headerBuy:Show() else W.headerBuy:Hide() end
    if tab == "money" then
      W.headerCols[5]:ClearAllPoints(); W.headerCols[5]:SetPoint("LEFT", W.header, "LEFT", listWidth() - MAKE_W + 8, 0)
      W.headerCols[5]:SetWidth(MAKE_W - 8); W.headerCols[5]:SetJustifyH("CENTER"); W.headerCols[5]:SetText(DIM .. "Make|r"); W.headerCols[5]:Show()
    end

    if tab == "plan" then
      local sh = pl:shopping(plan.crafts)
      local back = pl:totalPayout(plan.crafts)
      local reach = math.min(cap, math.floor(rank + plan.expected))
      local secs, unk = craftTime(plan.crafts)
      local ps = craftTime(sh.prep)
      W.summary:SetText(("Skill %d to ~%d of %d    Spend %s    Get back %s    Net %s    Crafting %s\n%sUses your own materials worth %s (they'd sell for %s).|r")
        :format(rank, reach, cap, money(sh.cash), money(back), money(back - sh.cash, true), dur(secs + ps) .. (unk > 0 and "+" or ""),
          DIM, money(sh.ownedValue), money(sh.ownedResale)))
      if room == 0 then line(WARN .. "You're at " .. rank .. "/" .. cap .. ". Visit your trainer for the next rank to keep leveling.|r") end
      if plan.expected < points - 1e-9 and room > 0 then
        line(WARN .. ("Only about %.1f of %d points could be planned. The rest need prices (scan the AH) or new recipes from a trainer."):format(plan.expected, points) .. "|r")
      end
      for _, cr in ipairs(plan.crafts) do
        local r = cr.recipe
        local cost = pl:recipeCost(r) * cr.n
        local value, where = pl:payout(r)
        value = value * cr.n
        local y, exact = P.yellowStart(r)
        local note = ""
        note = DIM .. "  " .. dur(r.cast) .. "|r"
        if y and rank < y then note = note .. DIM .. "  orange until " .. (exact and "" or "~") .. y .. "|r"
        elseif r.gray and rank < r.gray then note = note .. DIM .. "  gray at " .. r.gray .. "|r" end
        setRow(n + 1, "plan", {
          (DIFF_COLOR[r.diff] or "") .. r.name .. "|r" .. note, tostring(cr.n), ("%.1f"):format(cr.points or cr.n * (P.CHANCE[r.diff] or 0)),
          money(cost), money(value) .. (where == "ah" and (DIM .. " AH|r") or ""), money(value - cost, true),
        }, r.out, nil, nil, { checked = pick.plan[r.name] and true or false, fn = function(v)
          pick.plan[r.name] = v or nil
          ns.RefreshWindow()
        end })
        n = n + 1
      end
      if #plan.crafts > 0 then line(DIM .. "Tick the crafts you want to buy materials for; they go on the Shopping list.|r") end
      if #plan.crafts == 0 then line(DIM .. "No recipe can give skill points with the prices available.|r") end
      line(DIM .. "Colors change as you level: after crafting, click the profession button again to refresh.|r")

    elseif tab == "money" then
      local list = pl:moneyMakers(qty)
      W.lastMoney = { list = list, qty = qty }
      W.summary:SetText("Profit per craft if you buy every material for the number in Make (more crafts reach pricier listings).\n" ..
        DIM .. "Tick a craft to add it to the shopping list; type how many, or use - and +.   " ..
        (s.mode == "vendor" and "Selling to a vendor." or s.mode == "ah" and "Selling on the auction house (after its 5% cut)." or "Selling wherever pays more.") .. "|r")
      for _, x in ipairs(list) do
        local r = x.recipe
        local limit = ""
        if x.atBest < 2000 and x.atBest < x.upTo then limit = DIM .. "  best price to " .. x.atBest .. ",|r" end
        if x.upTo < 2000 then
          limit = limit .. (x.qty > x.upTo and WARN or DIM) .. "  pays up to " .. x.upTo .. "|r"
        end
        setRow(n + 1, "money", {
          (DIFF_COLOR[r.diff] or "") .. r.name .. "|r" .. DIM .. "  " .. dur(r.cast) .. "|r" .. limit, money(x.cost),
          money(x.value) .. (x.where == "ah" and (DIM .. " AH|r") or ""), money(x.net, true),
        }, r.out, { value = math.max(1, qty[r.name] or 1), fn = function(_, d)
          qty[r.name] = math.max(1, math.min(999, math.max(1, qty[r.name] or 1) + d))
          if d > 0 then pick.money[r.name] = true end
          ns.RefreshWindow()
        end, set = function(v)
          qty[r.name] = math.max(1, math.min(999, v))
          pick.money[r.name] = true -- typing a number means you want it
        end }, nil, { checked = pick.money[r.name] and true or false, fn = function(v)
          pick.money[r.name] = v or nil
          ns.RefreshWindow()
        end })
        n = n + 1
      end
      if #list == 0 then line(DIM .. "Nothing makes money at these prices. Try selling to the best price, or scan the AH for fresher prices.|r") end
      for _, x in ipairs(list) do
        if x.qty > x.upTo then
          if x.total < 0 then
            line(WARN .. ("Making %d %s loses %s overall: only the first %d pay. Set Make to %d or less."):format(x.qty, x.recipe.name,
              money(-x.total), x.upTo, x.upTo) .. "|r")
          else
            line(WARN .. ("Making %d %s earns %s, but each one past %d loses money. Set Make to %d for the most profit."):format(x.qty,
              x.recipe.name, money(x.total), x.upTo, x.upTo) .. "|r")
          end
        end
      end

    else -- shopping
      local crafts, source = {}, {}
      for _, x in ipairs(plan.crafts) do
        if pick.plan[x.recipe.name] then crafts[#crafts + 1] = x; source[#crafts] = "skill-up plan" end
      end
      for _, x in ipairs(extra) do crafts[#crafts + 1] = x; source[#crafts] = "money maker" end
      local sh = pl:shopping(crafts)
      -- which crafts need each material (directly, or through a reagent you'll make first)
      local usedFor = {}
      local function addUse(id, text) usedFor[id] = usedFor[id] or {}; table.insert(usedFor[id], text) end
      for _, x in ipairs(crafts) do
        for _, rg in ipairs(x.recipe.reagents) do addUse(rg.id, (rg.n * x.n) .. " for " .. x.n .. " " .. x.recipe.name) end
      end
      for _, x in ipairs(sh.prep) do
        for _, rg in ipairs(x.recipe.reagents) do addUse(rg.id, (rg.n * x.n) .. " to make " .. x.n .. " " .. x.recipe.name) end
      end
      W.lastShopping = sh
      local flips = ns.FlipShopping()
      local flipCost, flipValue = 0, 0
      for _, f in ipairs(flips) do flipCost = flipCost + f.cost; flipValue = flipValue + f.sell * f.units end
      local ah, vendor = flipCost, 0
      for _, b in ipairs(sh.buy) do
        if b.buy > 0 and b.total then if b.where == "ah" then ah = ah + b.total else vendor = vendor + b.total end end
      end
      W.summary:SetText(("Auction house %s    Vendor %s%s\n%s%d craft(s) and %d vendor flip(s) selected.|r"):format(money(ah), money(vendor),
        sh.unknown > 0 and ("    " .. BAD .. sh.unknown .. " with no price|r") or "", DIM, #crafts, #flips))
      if #crafts == 0 and #flips == 0 then
        line(DIM .. "Nothing selected yet. Tick crafts on the Skill-up plan or Money makers tab, or items on Vendor flips, to build your list.|r")
      end
      if #crafts > 0 then
        line(GOLD .. "This list is for|r")
        for i, x in ipairs(crafts) do
          line("   " .. x.n .. " " .. (DIFF_COLOR[x.recipe.diff] or "") .. x.recipe.name .. "|r" .. DIM .. "  (" .. source[i] .. ")   " ..
            (x.recipe.cast and (dur(x.recipe.cast * x.n) .. (x.n > 1 and (", " .. dur(x.recipe.cast) .. " each") or "")) or "time ?") .. "|r")
        end
      end
      if #sh.prep > 0 then
        line(GOLD .. "Craft these first|r")
        for _, x in ipairs(sh.prep) do
          local it = ns.itemData(x.recipe.out)
          local same = it and it.name == x.recipe.name
          line("   Make " .. x.n .. " " .. itemText(x.recipe.out) .. (same and "" or (DIM .. "  (" .. x.recipe.name .. ")|r")) ..
            DIM .. "   " .. (x.recipe.cast and dur(x.recipe.cast * x.n) or "time ?") .. "|r")
        end
      end
      if #crafts > 0 then line(GOLD .. "Materials|r" .. DIM .. "  (hover one to see what it's for)|r") end
      for _, b in ipairs(sh.buy) do
        local it = pl:get(b.id)
        local haveText = tostring(b.have)
        if it and it.total > it.bags then haveText = haveText .. DIM .. "*|r" end
        setRow(n + 1, "shop", {
          itemText(b.id), tostring(b.need), haveText, b.buy > 0 and (GOLD .. b.buy .. "|r") or (DIM .. "0|r"),
          b.buy > 0 and whereText(b.where) or (DIM .. "have enough|r"), b.buy > 0 and money(b.total) or "",
        }, b.id, nil, usedFor[b.id])
        n = n + 1
        -- auction house items: the price tiers this amount buys from, and how much of it is at a good price
        if b.buy > 0 and b.where == "ah" and b.tiers and #b.tiers > 0 then
          local parts, shownTiers = {}, 0
          for i, t in ipairs(b.tiers) do
            if shownTiers < 4 or i == #b.tiers then
              if shownTiers == 4 and i == #b.tiers and #b.tiers > 5 then
                local units, lo = 0, b.tiers[5][1]
                for k = 5, #b.tiers do units = units + b.tiers[k][2] end
                parts[#parts + 1] = units .. " at " .. coins(lo) .. " to " .. coins(t[1])
              else
                parts[#parts + 1] = t[2] .. " at " .. coins(t[1]) .. (t.vendor and " (vendor)" or "") .. (t.unlisted and (WARN .. " (not listed yet)|r") or "")
              end
              shownTiers = shownTiers + 1
            end
          end
          line("      " .. DIM .. table.concat(parts, "  ·  ") .. "|r")
          if b.rest > 0 then
            local cheapest = b.tiers[1][1]
            line("      " .. WARN .. (b.good > 0
              and ("Good price for " .. b.good .. " (up to " .. coins(math.floor(cheapest * P.GOOD_PRICE)) .. "). The other " .. b.rest ..
                   " average " .. coins(b.restAvg) .. ", so you could buy " .. b.good .. " now and wait for the rest.")
              or ("Prices climb fast: the cheapest is " .. coins(cheapest) .. " but these average " .. coins(b.restAvg) .. ".")) .. "|r")
          end
          if b.short then
            local it2 = pl:get(b.id)
            line("      " .. BAD .. "Only " .. tostring(it2 and it2.listed or "a few") .. " were listed at your last scan.|r")
          end
        end
      end
      if #crafts > 0 and #sh.buy == 0 then line(DIM .. "Nothing to buy.|r") end
      if #flips > 0 then
        line(GOLD .. "Vendor flips|r" .. DIM .. "  (buy on the auction house, sell to a vendor)|r")
        local picked = flipPicks()
        for _, f in ipairs(flips) do
          setRow(n + 1, "shop", {
            itemText(f.id), tostring(f.units), DIM .. "-|r", f.units > 0 and (GOLD .. f.units .. "|r") or (DIM .. "0|r"),
            f.units > 0 and whereText("ah") or (WARN .. "none below vendor price now|r"), f.units > 0 and money(f.cost) or "",
          }, f.id)
          n = n + 1
          if f.units > 0 then
            line("      " .. DIM .. "at most " .. coins(f.sell - 1) .. " each; vendor pays " .. money(f.sell * f.units) .. ", " .. "|r" .. money(f.profit, true))
          end
        end
      end
      if #crafts > 0 or #flips > 0 then
        local total = ah + vendor
        local have = (GetMoney and GetMoney()) or 0
        local left = have - total
        local function totalRow(text, value)
          n = n + 1
          setRow(n, "shop", { text, nil, nil, nil, nil, value })
        end
        line(" ")
        totalRow(GOLD .. "Grand total|r" .. (sh.unknown > 0 and (BAD .. "  (+" .. sh.unknown .. " item(s) with no price)|r") or ""), money(total))
        totalRow("Your gold", money(have))
        totalRow(left >= 0 and (GOOD .. "Left after buying|r") or (BAD .. "Short by|r"), left >= 0 and (GOOD .. money(left) .. "|r") or (BAD .. money(-left) .. "|r"))
        -- what a vendor pays for everything you craft from this list (reagents you make first get used up, not sold)
        local vendorBack = 0
        for _, x in ipairs(crafts) do
          local it = ns.itemData(x.recipe.out)
          if it then vendorBack = vendorBack + (it.sell or 0) * (((x.recipe.min or 1) + (x.recipe.max or x.recipe.min or 1)) / 2) * x.n end
        end
        vendorBack = vendorBack + flipValue
        local after = left + vendorBack
        totalRow("After vending" .. DIM .. "  (vendor pays " .. money(vendorBack) .. ")|r",
          after >= 0 and (GOOD .. money(after) .. "|r") or (BAD .. "-" .. money(-after) .. "|r"))
        local secs, unk = craftTime(crafts)
        local ps, pu = craftTime(sh.prep)
        -- what everything on the list sells for (vendor, AH after its cut, or the better of the two, per your setting),
        -- minus what you spend buying materials
        local sells = pl:totalPayout(crafts) + flipValue
        local profit = sells - total
        local how = s.mode == "vendor" and "vendor" or s.mode == "ah" and "auction house, after its cut" or "best of vendor or auction house"
        totalRow((profit >= 0 and GOOD or BAD) .. "Total profit|r" .. DIM .. "  (sells for " .. money(sells) .. " (" .. how .. ")" ..
          ((sh.ownedValue or 0) > 0 and (", plus your own materials worth " .. money(sh.ownedValue)) or "") .. ")|r",
          (profit >= 0 and (GOOD .. "+" .. money(profit) .. "|r") or (BAD .. "-" .. money(-profit) .. "|r")))
        if #crafts > 0 then totalRow("Crafting time" .. ((unk + pu) > 0 and (DIM .. "  (" .. (unk + pu) .. " recipe(s) without a time: open the profession once)|r") or ""),
          dur(secs + ps)) end
      end
      if #sh.buy > 0 then line(DIM .. "* includes items in your bank.|r") end
    end
  end

  for i = n + 1, #rows do rows[i]:Hide() end
  W.content:SetHeight(math.max(1, n * ROW_H))
  if tab == "shop" then
    W.clearPicks:Show()
    if ns.auctionator() then W.createList:Show() else W.createList:Hide() end
  else
    W.createList:Hide(); W.clearPicks:Hide()
  end
  if tab == "flips" then W.flipReagents:SetChecked(settings().flipReagents and true or false); W.flipReagents:Show() else W.flipReagents:Hide() end
  if tab == "money" then W.maxMake:Show(); W.resetMake:Show(); W.bestMake:Show()
  else W.maxMake:Hide(); W.resetMake:Hide(); W.bestMake:Hide() end
  if tab == "guild" then
    local at = ns.db().guildDir and ns.db().guildDir.at
    local when, mark, color = "never", NOT_READY, BAD
    if at then
      local clock = date("%I:%M %p", at):gsub("^0", "")
      when = (date("%x", at) == date("%x")) and clock or (date("%b %d ", at):gsub(" 0", " ") .. clock)
      local age = time() - at
      if age <= 15 * 60 then mark, color = READY, GOOD elseif age <= 24 * 3600 then mark, color = WAITING, WARN end
    end
    if ns.guildProgress and ns.guildProgress() then when, mark, color = "reading...", WAITING, WARN end
    W.guildRefresh.text:SetText("Refresh guild list    " .. DIM .. "Last:|r " .. color .. when .. "|r  " .. mark)
    W.guildRefresh:Show(); W.guildSearch:Show(); W.guildSearchLabel:Show()
    W.summary:SetPoint("RIGHT", frame, "RIGHT", -250, 0)
  else
    W.guildRefresh:Hide(); W.guildSearch:Hide(); W.guildSearchLabel:Hide()
    W.summary:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
  end
  if ns.RefreshShopPanel then ns.RefreshShopPanel() end
end

-- The same shopping list as the Shopping list tab (ticked crafts, minus what you own), for the AH panel.
-- returns { prof, crafts = { {recipe, n} }, buy = rows from Planner:shopping, planner }
function ns.CurrentShopping()
  local c = ns.charData()
  local s = settings()
  local skills = currentSkills()
  local sel = selectedProfession(c)
  local p = sel and c.professions[sel]
  -- ticked vendor flips: buy only listings below what a vendor pays
  local function withFlips(buy)
    for _, f in ipairs(ns.FlipShopping()) do
      if f.units > 0 then
        buy[#buy + 1] = { id = f.id, where = "ah", buy = f.units, need = f.units, have = 0, price = f.avg, total = f.cost,
                          flip = true, maxPrice = f.sell - 1 }
      end
    end
    return buy
  end
  if not p then return { prof = sel, crafts = {}, buy = withFlips({}) } end
  local recipes = sortedRecipes(p)
  local all = {}
  for _, prof in pairs(c.professions) do for _, r in pairs(prof.recipes or {}) do all[#all + 1] = r end end
  local pl = P.new(function(id) return ns.itemData(id) end, recipes, all, s)
  local skill = skills[sel]
  local rank, cap = skill and skill.rank or p.rank or 0, skill and skill.max or p.max or 0
  local room = math.max(0, cap - rank)
  local plan = pl:planSkillUps(math.min(s.points, room > 0 and room or s.points), rank)
  local pick, qty = picks(c, sel), makeQty(c, sel)
  local crafts = {}
  for _, x in ipairs(plan.crafts) do if pick.plan[x.recipe.name] then crafts[#crafts + 1] = x end end
  for _, r in ipairs(recipes) do
    if pick.money[r.name] then crafts[#crafts + 1] = { recipe = r, n = math.max(1, qty[r.name] or 1) } end
  end
  local sh = pl:shopping(crafts)
  local buy = {}
  for _, b in ipairs(sh.buy) do buy[#buy + 1] = b end
  return { prof = sel, crafts = crafts, buy = withFlips(buy), planner = pl }
end

local pending = false
function ns.RefreshWindow()
  if not (frame and frame:IsShown()) then return end
  if pending then return end
  pending = true
  local run = function() pending = false; local ok, err = pcall(render); if not ok then ns.say("window error: " .. tostring(err)) end end
  if C_Timer then C_Timer.After(0.2, run) else run() end
end
ns.OnDataChanged = ns.RefreshWindow

---------------------------------------------------------------------------
-- building the window
---------------------------------------------------------------------------
local function createShoppingList()
  local c = ns.charData()
  -- the same list as the Shopping list tab: craft materials plus ticked vendor flips
  local sh = ns.CurrentShopping()
  local entries = {}
  for _, b in ipairs(sh.buy or {}) do
    local it = ns.itemData(b.id)
    local name = (it and it.name) or (GetItemInfo and GetItemInfo(b.id))
    if b.buy > 0 and b.where == "ah" and name then entries[#entries + 1] = { name = name, qty = b.buy, maxPrice = b.maxPrice } end
  end
  ns.createShoppingList("Top Ramen: " .. (c.selected or "Crafting"), entries)
end

local function build()
  frame = ns.UI.Window("TopRamenCraftPlanner")
  local saved = ns.db().window or {}
  frame:SetSize(math.max(MIN_W, math.min(MAX_W, saved.w or WIDTH)), math.max(MIN_H, math.min(MAX_H, saved.h or HEIGHT)))
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  else
    if frame.SetMinResize then frame:SetMinResize(MIN_W, MIN_H) end
    if frame.SetMaxResize then frame:SetMaxResize(MAX_W, MAX_H) end
  end
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  ns.ApplyOpacity()
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    local win = ns.db().window or {}
    win.point, win.rel, win.x, win.y = point, rel, x, y
    ns.db().window = win
  end)
  local pos = ns.db().window
  if pos and pos.point then frame:SetPoint(pos.point, UIParent, pos.rel or pos.point, pos.x or 0, pos.y or 0)
  else frame:SetPoint("CENTER") end
  frame:SetScript("OnShow", function() ns.RefreshWindow() end)
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(60, function() if frame:IsShown() then ns.RefreshWindow() end end)
  end
  frame:SetScript("OnSizeChanged", function(self, w, h)
    if W.content then W.content:SetWidth(listWidth()) end
    ns.RefreshWindow()
  end)

  -- drag the bottom-right corner to resize
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -8, 8)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    local win = ns.db().window or {}
    win.w, win.h = frame:GetWidth(), frame:GetHeight()
    local point, _, rel, x, y = frame:GetPoint()
    win.point, win.rel, win.x, win.y = point, rel, x, y
    ns.db().window = win
  end)
  tinsert(UISpecialFrames, "TopRamenCraftPlanner")

  local head = ns.UI.Header(frame, "Crafting planner")
  W.head = head
  local close = head.close

  -- re-read bags, bank, prices and any open profession window right now
  W.refresh = button(head, "Refresh", 84, 28, function()
    if ns.markAllStale then ns.markAllStale() end -- every profession gets a red X ...
    if ns.scanOpen then ns.scanOpen() end      -- ... except one whose window is open right now
    ns.RefreshWindow()
    ns.say("planner refreshed: bags, bank and prices. Open each profession marked with a red X to update its recipes.")
  end)
  W.refresh:SetPoint("RIGHT", close, "LEFT", -4, 0)
  W.refresh:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Refresh")
    GameTooltip:AddLine("Re-reads your bags, bank and prices, and marks every profession with a red X until you open its window again, so its recipes and colors are read fresh. The bank count is from the last time you opened your bank.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  W.refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- our own auction house scans (only work while the auction house is open)
  local function tip(b, title, text)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(title)
      GameTooltip:AddLine(text, 1, 1, 1, true)
      if not (ns.Prices and ns.Prices.isAHOpen()) then GameTooltip:AddLine("Open the auction house to use this.", 1, 0.5, 0.4, true) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  W.quickScan = button(head, "Quick scan", 96, 28, function() ns.Prices.quickScan() end)
  W.quickScan:SetPoint("RIGHT", W.refresh, "LEFT", -6, 0)
  tip(W.quickScan, "Quick scan", "Searches the auction house for just the materials and products your recipes use. No cooldown; takes a little while.")
  W.fullScan = button(head, "Full scan", 90, 28, function() ns.Prices.fullScan() end)
  W.fullScan:SetPoint("RIGHT", W.quickScan, "LEFT", -6, 0)

  tip(W.fullScan, "Full scan", "Reads every listing on the auction house at once and saves the lowest price of each item. The game allows this once every 15 minutes.")

  W.noProf = label(frame, WARN .. "No crafting professions found on this character.|r")
  W.noProf:SetPoint("TOPLEFT", 20, -(ns.UI.HEAD_H + 26))

  W.fresh = label(frame, "")
  W.fresh:SetPoint("TOPLEFT", 20, -118)
  W.fresh:SetPoint("RIGHT", frame, "RIGHT", -20, 0)

  -- settings, on their own panel
  local panel = ns.UI.Panel(frame)
  panel:SetPoint("TOPLEFT", 12, -150); panel:SetPoint("RIGHT", frame, "RIGHT", -12, 0); panel:SetHeight(62)
  local s = settings()
  W.mode = button(frame, MODE_TEXT[s.mode], 170, 22, function()
    local st = settings()
    local i = 1
    for k, m in ipairs(MODES) do if m == st.mode then i = k end end
    st.mode = MODES[i % #MODES + 1]
    ns.RefreshWindow()
  end)
  W.mode:SetPoint("TOPLEFT", 20, -158)
  W.points = stepper(frame, "Points to plan", function(d)
    local st = settings(); st.points = math.max(1, math.min(300, st.points + d)); ns.RefreshWindow()
  end, function(v) settings().points = math.max(1, math.min(300, v)) end)
  W.points:SetPoint("LEFT", W.mode, "RIGHT", 14, 0)
  W.age = stepper(frame, "Max price age (days)", function(d)
    local st = settings(); st.maxAge = math.max(0, math.min(21, st.maxAge + d)); ns.RefreshWindow()
  end, function(v) settings().maxAge = math.max(0, math.min(21, v)) end)
  W.age:SetPoint("LEFT", W.points, "RIGHT", 22, 0)
  W.owned = checkbox(frame, "Use my materials first", function(self) settings().ownedFree = self:GetChecked() and true or false; ns.RefreshWindow() end)
  W.owned:SetPoint("TOPLEFT", 18, -184)
  W.make = checkbox(frame, "Make reagents myself when cheaper", function(self) settings().makeReagents = self:GetChecked() and true or false; ns.RefreshWindow() end)
  W.make:SetPoint("TOPLEFT", 202, -184)
  W.best = checkbox(frame, "Best chance for skill-ups", function(self) settings().bestChance = self:GetChecked() and true or false; ns.RefreshWindow() end)
  W.best:SetPoint("TOPLEFT", 442, -184)
  W.best:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Best chance for skill-ups")
    GameTooltip:AddLine("Always pick the recipe most likely to give a point: orange (guaranteed) when you have one, then the best yellow. Price only decides between equally good chances. Off: balance cost against how many crafts it takes.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  W.best:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- tabs
  W.tabs = {}
  local prev
  for _, t in ipairs({ { "plan", "Skill-up plan" }, { "money", "Money makers" }, { "shop", "Shopping list" }, { "flips", "Vendor flips" }, { "guild", "Guild" } }) do
    local b = button(frame, t[2], 140, 28, function() tab = t[1]; ns.RefreshWindow() end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 14, -222) end
    W.tabs[t[1]] = b
    prev = b
  end

  W.summary = label(frame, "", "GameFontHighlight")
  W.summary:SetPoint("TOPLEFT", 20, -268)
  if W.summary.SetSpacing then W.summary:SetSpacing(5) end -- room between the two summary lines
  W.summary:SetPoint("RIGHT", frame, "RIGHT", -20, 0)

  W.header = CreateFrame("Frame", nil, frame)
  W.header:SetHeight(ROW_H)
  W.header:SetPoint("TOPLEFT", 20, -320)
  W.header:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
  W.headerCols = {}
  for i = 1, 6 do W.headerCols[i] = label(W.header, "", "GameFontHighlightSmall") end
  W.headerBuy = label(W.header, DIM .. "Buy|r", "GameFontHighlightSmall")
  W.headerBuy:SetPoint("LEFT", W.header, "LEFT", 0, 0)

  local scroll = CreateFrame("ScrollFrame", "TopRamenCraftPlannerScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -340)
  scroll:SetPoint("BOTTOMRIGHT", -40, 50)
  -- the list sits on a dark well, with a gold line under the column names
  local well = ns.UI.Panel(frame, ns.UI.C.well)
  well:SetPoint("TOPLEFT", 12, -314); well:SetPoint("BOTTOMRIGHT", -12, 46)
  local hl = frame:CreateTexture(nil, "ARTWORK")
  hl:SetColorTexture(1, 0.82, 0, 0.25); hl:SetHeight(1)
  hl:SetPoint("TOPLEFT", well, "TOPLEFT", 6, -24); hl:SetPoint("TOPRIGHT", well, "TOPRIGHT", -6, -24)
  W.content = CreateFrame("Frame", nil, scroll)
  W.content:SetSize(listWidth(), 1)
  scroll:SetScrollChild(W.content)

  W.createList = button(frame, "Create Auctionator list", 190, 26, createShoppingList)
  W.createList:SetPoint("BOTTOMLEFT", 14, 12)
  W.clearPicks = button(frame, "Clear all selected", 150, 26, function()
    local c = ns.charData()
    if c.selected and c.picks then c.picks[c.selected] = nil end
    ns.db().flipPicks = nil
    ns.RefreshWindow()
  end)
  W.clearPicks:SetPoint("BOTTOMLEFT", 14, 12)
  -- Guild tab: refresh the guild's profession list, and a recipe search
  -- works like the AH Database box: click to read again; shows when it was last read, how fresh, and progress
  do
    local b = CreateFrame("Button", nil, frame, "BackdropTemplate")
    b:SetSize(320, 26)
    ns.UI.Skin(b, ns.UI.C.button, ns.UI.C.trim, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20); b.icon:SetPoint("LEFT", 4, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
    b.text = label(b, "", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetWidth(286)
    b:SetScript("OnClick", function()
      if ns.readGuildDirectory and not ns.readGuildDirectory() then ns.say("couldn't read the guild list (not in a guild, or already reading).") end
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine("Refresh guild list")
      GameTooltip:AddLine("Green check: read in the last 15 minutes. Yellow ?: up to a day old. Red X: older than a day, or never read.", 1, 1, 1, true)
      GameTooltip:AddLine("Click to read every guildmate's professions again (takes a few seconds).", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.bar = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.bar:SetPoint("TOPLEFT", 1, -1); b.bar:SetPoint("BOTTOMLEFT", 1, 1)
    b.bar:SetColorTexture(0.29, 0.87, 0.5, 0.55)
    b.pct = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.pct:SetPoint("CENTER", 0, 0)
    b.pct:SetTextColor(1, 1, 1)
    if b.pct.GetFont then local f, size = b.pct:GetFont(); if f then b.pct:SetFont(f, size or 13, "OUTLINE") end end
    b.bar:Hide(); b.pct:Hide()
    b:SetScript("OnUpdate", function(self, elapsed)
      self.tick = (self.tick or 0) + (elapsed or 0)
      if self.tick < 0.1 then return end
      self.tick = 0
      local v = ns.guildProgress and ns.guildProgress()
      if v then
        self.bar:SetWidth(math.max(1, ((self:GetWidth() or 320) - 2) * v)); self.bar:Show()
        self.pct:SetText(math.floor(v * 100) .. "%"); self.pct:Show()
        self.text:SetAlpha(0.35)
      elseif self.bar:IsShown() then
        self.bar:Hide(); self.pct:Hide(); self.text:SetAlpha(1)
      end
    end)
    b:SetPoint("BOTTOMLEFT", 14, 12)
    W.guildRefresh = b
  end
  W.guildSearch = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  W.guildSearch:SetSize(170, 20)
  W.guildSearch:SetAutoFocus(false)
  W.guildSearch:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -268)
  W.guildSearch:SetScript("OnTextChanged", function() ns.RefreshWindow() end)
  W.guildSearch:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  W.guildSearch:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  W.guildSearch:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Search")
    GameTooltip:AddLine("Type part of a guildmate's name to find them, or part of a recipe or item name to see who can make it.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  W.guildSearch:SetScript("OnLeave", function() GameTooltip:Hide() end)
  W.guildSearchLabel = label(frame, "Name or recipe", "GameFontHighlightSmall")
  W.guildSearchLabel:SetPoint("RIGHT", W.guildSearch, "LEFT", -10, 0)
  W.guildRefresh:Hide(); W.guildSearch:Hide(); W.guildSearchLabel:Hide()
  -- Vendor flips: reagents only
  W.flipReagents = checkbox(frame, "Reagents only", function(self) settings().flipReagents = self:GetChecked() and true or nil; ns.RefreshWindow() end)
  W.flipReagents:SetPoint("BOTTOMLEFT", 14, 13)
  W.flipReagents:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Reagents only")
    GameTooltip:AddLine("Show only trade goods and reagents (cloth, leather, herbs, ore...), plus anything your known recipes use.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  W.flipReagents:SetScript("OnLeave", function() GameTooltip:Hide() end)
  W.flipReagents:Hide()
  -- Money makers: set every recipe's Make to the amount that earns the most
  W.maxMake = button(frame, "Max profit", 120, 26, function()
    local m = W.lastMoney
    if not m then return end
    for _, x in ipairs(m.list) do
      if x.upTo > 0 then m.qty[x.recipe.name] = math.min(999, x.upTo) end
    end
    ns.RefreshWindow()
  end)
  W.resetMake = button(frame, "Reset", 80, 26, function()
    local m = W.lastMoney
    if not m then return end
    for k in pairs(m.qty) do m.qty[k] = nil end -- every Make back to 1
    ns.RefreshWindow()
  end)
  W.resetMake:SetPoint("BOTTOMLEFT", 14, 12)
  W.resetMake:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Reset")
    GameTooltip:AddLine("Sets Make back to 1 for every recipe. Ticks stay as they are.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  W.resetMake:SetScript("OnLeave", function() GameTooltip:Hide() end)
  W.resetMake:Hide()
  W.bestMake = button(frame, "Best price", 110, 26, function()
    local m = W.lastMoney
    if not m then return end
    for _, x in ipairs(m.list) do
      if x.atBest > 0 then m.qty[x.recipe.name] = math.min(999, x.atBest) end
    end
    ns.RefreshWindow()
  end)
  W.bestMake:SetPoint("LEFT", W.resetMake, "RIGHT", 8, 0)
  W.bestMake:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Best price")
    GameTooltip:AddLine("Sets Make for every recipe to the most you can make while Profit each stays at its best: only materials at the price the first craft pays (at most 999). Ticks stay as they are.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  W.bestMake:SetScript("OnLeave", function() GameTooltip:Hide() end)
  W.bestMake:Hide()
  W.maxMake:SetPoint("LEFT", W.bestMake, "RIGHT", 8, 0)
  W.maxMake:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Max profit")
    GameTooltip:AddLine("Sets Make for every recipe on this list to the number that earns the most: every craft up to where one more would lose money (at most 999). Ticks stay as they are.", 1, 1, 1, true)
    GameTooltip:AddLine("Each recipe is worked out on its own; if two use the same material, buying both pushes its price up further.", 1, 0.82, 0, true)
    GameTooltip:Show()
  end)
  W.maxMake:SetScript("OnLeave", function() GameTooltip:Hide() end)
  W.maxMake:Hide()
  -- Auctionator's list, only if Auctionator is installed
  W.createList:ClearAllPoints()
  W.createList:SetPoint("LEFT", W.clearPicks, "RIGHT", 8, 0)
end

-- background opacity, 0.3 - 1.0 (saved). The profession window is roughly 0.92.
function ns.ApplyOpacity()
  if not frame then return end
  local a = settings().opacity or 0.92
  local c = ns.UI.C
  frame:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], a)
  frame:SetBackdropBorderColor(c.trim[1], c.trim[2], c.trim[3], 1)
end

function ns.SetOpacity(pct)
  pct = tonumber(pct)
  if not pct then
    ns.say("background opacity is " .. math.floor((settings().opacity or 0.92) * 100 + 0.5) .. "%. Change it with /trc opacity 30-100.")
    return
  end
  settings().opacity = math.max(0.3, math.min(1, pct / 100))
  ns.ApplyOpacity()
  ns.say("background opacity set to " .. math.floor(settings().opacity * 100 + 0.5) .. "%.")
end

function ns.ToggleWindow()
  if not frame then
    build()
    frame:Hide() -- new frames start out shown; hide it so the toggle below opens it on the first /trc
  end
  if frame:IsShown() then frame:Hide() else frame:Show() end
end

function ns.ResetWindow()
  ns.db().window = nil
  if frame then frame:ClearAllPoints(); frame:SetPoint("CENTER"); frame:SetSize(WIDTH, HEIGHT) end
  ns.say("planner window moved back to the center at its default size.")
end

-- keep the window current while it's open
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_MONEY", "CHAT_MSG_SKILL", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED", "AUCTION_HOUSE_CLOSED", "MERCHANT_CLOSED", "BANKFRAME_CLOSED", "GUILD_ROSTER_UPDATE" }) do
  pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function() ns.RefreshWindow() end)
