-- Top Ramen Gear: the Dungeons tab of the /trg window
-- Pick a dungeon: lists every drop and quest reward there that's an upgrade for you,
-- best first, with the boss or quest it comes from. Loot lists come live from DungeonJournal.
local _, ns = ...

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local RequestItem = (C_Item and C_Item.RequestLoadItemDataByID) or function() end

local ROWH = 56
local scroll, content, makeCellFn, layout
-- this session's filters; they start from the defaults chosen in Settings
local session = {}
local function within() if session.within == nil then session.within = ns.db.dgWithinDefault and true or false end return session.within end
local function showAll() if session.showAll == nil then session.showAll = ns.db.dgShowAllDefault and true or false end return session.showAll end
local function mineOnly() if session.mine == nil then session.mine = ns.db.dgMineDefault ~= false end return session.mine end

-- can this character get it? DungeonJournal marks quests with faction ("Alliance" / "Horde" / "Both")
-- and classOnly ("PALADIN"...), and a few bosses with factionOnly (e.g. friendly to the Alliance)
local function forMe(faction, classOnly)
  local myFaction = UnitFactionGroup and UnitFactionGroup("player")
  if faction and faction ~= "Both" and myFaction and faction ~= myFaction then return false end
  if classOnly then
    local myClass = ns.PlayerClass()
    if type(classOnly) == "table" then
      local ok = false
      for _, c in pairs(classOnly) do if c == myClass then ok = true end end
      if not ok then return false end
    elseif myClass and classOnly ~= myClass then return false end
  end
  return true
end
local function levels() return ns.db.dgWithinLevels or 5 end
local page, rowsUI, ddLabel = nil, {}, nil

---------------------------------------------------------------------------
-- reading a dungeon's loot from DungeonJournal
---------------------------------------------------------------------------
local function journal() return ns.FindJournal and ns.FindJournal() end

function ns.DungeonList()
  local fdj = journal()
  if not fdj then return {} end
  local out = {}
  local order = fdj.ORDER
  if type(order) ~= "table" then order = {}; for n in pairs(fdj.DB) do order[#order + 1] = n end; table.sort(order) end
  for _, name in ipairs(order) do
    local d = fdj.DB[name]
    if type(d) == "table" and (d.bosses or d.quests) then out[#out + 1] = { name = name, level = d.level } end
  end
  return out
end

-- every item in a dungeon: { id, source }
-- every item that drops or is a quest reward here. With "Only what I can get" on, sources this
-- character can't use (other faction, other class) are skipped; hidden counts how many items that drops.
local function dungeonItems(name)
  local fdj = journal()
  local d = fdj and fdj.DB[name]
  if type(d) ~= "table" then return {}, 0 end
  local out, seen, skipped = {}, {}, {}
  local mine = mineOnly()
  local function add(id, src)
    id = tonumber(id)
    if id and id > 0 and not seen[id] then seen[id] = true; out[#out + 1] = { id = id, src = src } end
  end
  for _, b in ipairs(d.bosses or {}) do
    if type(b) == "table" and not b.recipeTab and mine and not forMe(b.factionOnly) then
      for _, x in ipairs(b.loot or {}) do if type(x) == "table" and x[1] then skipped[x[1]] = true end end
    elseif type(b) == "table" and not b.recipeTab then
      local src = b.trash and "Trash drop" or b.name
      for _, x in ipairs(b.loot or {}) do if type(x) == "table" then add(x[1], src) end end
      if fdj.GetBossSharedLoot then
        local ok, shared = pcall(fdj.GetBossSharedLoot, name, b)
        if ok and type(shared) == "table" then
          for _, x in ipairs(shared) do if type(x) == "table" then add(x[1], src) end end
        end
      end
    end
  end
  for _, q in ipairs(d.quests or {}) do
    if type(q) == "table" then
      local ok = not mine or forMe(q.faction, q.classOnly)
      for _, list in ipairs({ q.rewardItems or {}, q.additionalRewardItems or {} }) do
        for _, x in ipairs(list) do
          if type(x) == "table" then
            if ok then add(x[1], "Quest: " .. (q.name or "?")) elseif x[1] then skipped[x[1]] = true end
          end
        end
      end
    end
  end
  -- an item you CAN get from another source isn't counted as hidden
  local hidden = 0
  for id in pairs(skipped) do if not seen[tonumber(id)] then hidden = hidden + 1 end end
  return out, hidden
end

-- the dungeon's upgrades for you, best first
function ns.DungeonHunt(name, mode)
  local lvl = ns.Level() or 60
  local list, loading, druidItems = {}, 0, 0
  ns.MarkGearDirty()
  local items, hidden = dungeonItems(name)
  ns.dungeonHidden = hidden
  for _, e in ipairs(items) do
    local _, link = GetInfo(e.id)
    if not link then
      loading = loading + 1; RequestItem(e.id)
    else
      local it = ns.ItemStats(link)
      if it and (not within() or (it.rl or 0) <= lvl + levels()) then
        druidItems = druidItems + 1
        local g1, why = ns.Gain(it, mode, 1)
        if g1 and (g1 > 0.05 or showAll()) then
          list[#list + 1] = {
            it = it, src = e.src, g1 = g1, why = why,
            g3 = mode == "bear" and (ns.Gain(it, mode, 3)) or nil,
            later = (it.rl or 0) > lvl,
          }
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.g1 > b.g1 end)
  return list, loading, druidItems
end

---------------------------------------------------------------------------
-- the page (look: see UI.lua)
---------------------------------------------------------------------------
local UI = ns.UI
local C, HX = UI.C, UI.HEX
local HEAD_H = 58
local SLOTNAME = { head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back", chest = "Chest", wrist = "Wrist",
  hands = "Hands", waist = "Waist", legs = "Legs", feet = "Feet", finger = "Ring", trinket = "Trinket",
  weapon2h = "Two-hand", weapon1h = "One-hand", offhand = "Off-hand", relic = "Relic",
  ranged = "Ranged", offweapon = "Off-hand weapon", shield = "Shield" }
local cards, specs, heads = {}, nil, {}

local function fmt(d)
  if not d or math.abs(d) < 0.05 then return HX.dim .. "±0|r" end
  return (d > 0 and HX.green or HX.red) .. string.format("%+.1f", d) .. "|r"
end

local function dungeonLabel(name)
  for _, d in ipairs(ns.DungeonList()) do
    if d.name == name then return d.level and (name .. "  (" .. d.level .. ")") or name end
  end
  return name
end

-- sorting the list: ns.db.dgSort = { key = "gain" | "src" | "lvl" | "item", desc = true/false }
local function itemName(e) return ((e.it.link or ""):match("%[(.-)%]") or ""):lower() end
local function srcName(e) return (e.src or ""):gsub("^Quest: ", ""):lower() end
function ns.SortDungeonList(list)
  local sort = ns.db.dgSort or { key = "gain", desc = true }
  local key, desc = sort.key, sort.desc
  local function value(e)
    if key == "item" then return itemName(e)
    elseif key == "src" then return srcName(e)
    elseif key == "lvl" then return e.it.rl or 0
    else return e.g1 or 0 end
  end
  table.sort(list, function(a, b)
    local va, vb = value(a), value(b)
    if va ~= vb then
      if desc then return va > vb else return va < vb end
    end
    -- ties: biggest gain first, then by name
    if (a.g1 or 0) ~= (b.g1 or 0) then return (a.g1 or 0) > (b.g1 or 0) end
    return itemName(a) < itemName(b)
  end)
end

-- the heading you're sorting by is gold, with an arrow for the direction
function ns.UpdateSortHeads()
  local sort = ns.db and ns.db.dgSort or { key = "gain", desc = true }
  for k, h in pairs(heads) do
    if h.text then
      local on = (k == sort.key)
      local arrow = on and (sort.desc and " |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:-3|t" or " |TInterface\\Buttons\\Arrow-Up-Up:12:12:0:3|t") or ""
      h.text:SetText(h.title .. arrow)
      local c = on and C.gold or C.muted
      h.text:SetTextColor(c[1], c[2], c[3])
    end
  end
end

local function footer(t) local f = page and page:GetParent(); if f and f.footer then f.footer:SetText(t) end end
local function setCards(a, b, c)
  cards[1].value:SetText(a); cards[2].value:SetText(b); cards[3].value:SetText(c)
end
local function hideRows() for _, r in ipairs(rowsUI) do r:Hide() end end

-- "Boss" / "Quest" / "Trash" and the name, from a source label
local function source(src)
  local q = src:match("^Quest: (.*)$")
  if q then return "Quest", q end
  if src == "Trash drop" then return "Trash", "Trash mobs" end
  return "Boss", src
end
local TAGCOL = { Boss = { { 0.23, 0.11, 0.11 }, { 0.99, 0.65, 0.65 } }, Quest = { { 0.11, 0.16, 0.23 }, { 0.58, 0.77, 0.99 } },
                 Trash = { { 0.16, 0.16, 0.16 }, { 0.75, 0.75, 0.75 } } }

function ns.RenderDungeons()
  if not page or not page:IsShown() then return end
  local mode = ns.CurrentMode()
  if specs then specs:Update(mode) end
  local f = page:GetParent()
  if f and f.who then f.who:SetText(UI.WhoAmI()) end
  if not journal() then
    hideRows(); setCards("–", "–", "–")
    footer(HX.red .. "The DungeonJournal addon isn't loaded. Install or enable it to use this tab.|r")
    return
  end
  local name = ns.db.dungeon
  if ddLabel then ddLabel(name and dungeonLabel(name) or "Pick a dungeon…") end
  if not name then
    hideRows(); setCards("–", "–", "–")
    footer("Pick a dungeon above to see what's worth hunting there.")
    return
  end
  local ok, list, loading, count = pcall(ns.DungeonHunt, name, mode)
  if not ok then footer(HX.red .. "Error: " .. tostring(list) .. "|r"); return end
  ns.SortDungeonList(list)
  ns.UpdateSortHeads()
  for i = #rowsUI + 1, #list do ns.NewDungeonRow(i) end
  if layout then layout() end
  content:SetHeight(math.max(1, #list * ROWH))
  local maxG = 0.1
  local bestE
  for _, e in ipairs(list) do
    if e.g1 > maxG then maxG = e.g1 end
    if e.g1 > 0.05 and (not bestE or e.g1 > bestE.g1) then bestE = e end
  end
  for i, r in ipairs(rowsUI) do
    local e = list[i]
    if e then
      r:Show()
      local top = (e == bestE) -- the gold star follows the best drop, whatever the order
      ns.SetCell(r.item, { e.it }, { glow = top, star = top })
      local _, _, _, _, _, _, sub = GetInfo(e.it.link)
      r.item.sub:SetText((SLOTNAME[e.it.s] or "") .. (sub and sub ~= "" and (" · " .. sub) or ""))
      ns.RowStyle(r, top and "gold" or nil)
      local kind, from = source(e.src)
      r.tag.text:SetText(kind:upper())
      local tc = TAGCOL[kind]
      r.tag:SetBackdropColor(tc[1][1], tc[1][2], tc[1][3], 1)
      r.tag.text:SetTextColor(tc[2][1], tc[2][2], tc[2][3])
      r.tag:SetWidth((r.tag.text:GetStringWidth() or 30) + 12)
      r.src:SetText(from)
      local t = fmt(e.g1)
      if mode == "bear" and ns.db.showBear3 then t = t .. HX.dim .. " · 3t |r" .. fmt(e.g3) end
      r.gain:SetText(t)
      r.bar:SetValue(e.g1 > 0 and e.g1 / maxG or 0)
      r.lvl:SetText(e.later and (HX.red .. e.it.rl .. "|r") or (e.it.rl and e.it.rl > 0 and tostring(e.it.rl) or "–"))
    else
      r:Hide()
    end
  end
  -- the summary cards
  local ups, best, bosses, quests = 0, nil, {}, {}
  for _, e in ipairs(list) do
    if e.g1 > 0.05 then
      ups = ups + 1
      if not best or e.g1 > best then best = e.g1 end
      local kind, from = source(e.src)
      if kind == "Quest" then quests[from] = true else bosses[from] = true end
    end
  end
  local nb, nq = 0, 0
  for _ in pairs(bosses) do nb = nb + 1 end
  for _ in pairs(quests) do nq = nq + 1 end
  local where = {}
  if nb > 0 then where[#where + 1] = nb .. (nb == 1 and " boss" or " bosses") end
  if nq > 0 then where[#where + 1] = nq .. (nq == 1 and " quest" or " quests") end
  setCards((ups > 0 and HX.green or HX.text) .. ups .. "|r", best and (HX.gold .. string.format("%+.1f", best) .. "|r") or (HX.dim .. "–|r"),
    #where > 0 and table.concat(where, " · ") or (HX.dim .. "–|r"))
  local msg
  if ups == 0 then
    msg = count > 0 and ("Nothing in " .. name .. " beats what you're wearing for " .. ns.ModeName(mode) .. ".")
      or "Nothing here you can use."
  else
    msg = "Loot lists from DungeonJournal · hover any item for its tooltip"
    if #list > 8 then msg = msg .. " · scroll for more" end
  end
  if mineOnly() and (ns.dungeonHidden or 0) > 0 then
    msg = msg .. HX.dim .. "  ·  " .. ns.dungeonHidden .. " item(s) hidden: other faction or class only|r"
  end
  if loading > 0 then msg = msg .. HX.dim .. "  ·  loading " .. loading .. " item(s) from the server…|r" end
  footer(msg)
end

-- the dungeon picker: the game's dropdown menu if it exists, otherwise < > buttons
local function buildPicker(p, x, y)
  local lab = UI.Text(p, "GameFontHighlightSmall", C.muted)
  lab:SetPoint("TOPLEFT", x, y)
  lab:SetText("Dungeon")
  local function pick(name) ns.db.dungeon = name; ns.RenderDungeons() end

  if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo then
    local ok, dd = pcall(CreateFrame, "Frame", "TopRamenGearDungeonDropDown", p, "UIDropDownMenuTemplate")
    if ok and dd then
      dd:SetPoint("LEFT", lab, "RIGHT", -8, -2)
      UIDropDownMenu_SetWidth(dd, 210)
      UIDropDownMenu_Initialize(dd, function(_, level)
        for _, d in ipairs(ns.DungeonList()) do
          local info = UIDropDownMenu_CreateInfo()
          info.text = d.level and (d.name .. "  (" .. d.level .. ")") or d.name
          info.checked = (ns.db.dungeon == d.name)
          info.func = function() pick(d.name); CloseDropDownMenus() end
          UIDropDownMenu_AddButton(info, level)
        end
      end)
      ddLabel = function(t) UIDropDownMenu_SetText(dd, t) end
      return
    end
  end
  -- fallback: previous / next buttons
  local text = UI.Text(p, "GameFontNormal", C.gold)
  text:SetPoint("LEFT", lab, "RIGHT", 40, 0)
  text:SetWidth(200)
  local function step(dir)
    local list, idx = ns.DungeonList(), 0
    for i, d in ipairs(list) do if d.name == ns.db.dungeon then idx = i end end
    idx = idx + dir
    if idx < 1 then idx = #list elseif idx > #list then idx = 1 end
    if list[idx] then pick(list[idx].name) end
  end
  local prev = UI.Button(p, 26, 26, "<", function() step(-1) end)
  prev:SetPoint("LEFT", lab, "RIGHT", 8, 0)
  local nxt = UI.Button(p, 26, 26, ">", function() step(1) end)
  nxt:SetPoint("LEFT", text, "RIGHT", 4, 0)
  ddLabel = function(t) text:SetText(t) end
end

-- one list row (rows are made as the list grows)
function ns.NewDungeonRow(i)
  local r = UI.Frame(content, C.row)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROWH)
  r:SetSize(600, ROWH - 4)
  r.item = makeCellFn(r, 8, 296, 36, true)
  r.tag = UI.Frame(r, C.row)
  r.tag:SetHeight(18)
  r.tag.text = UI.Text(r.tag, "GameFontHighlightSmall", nil, 9)
  r.tag.text:SetPoint("CENTER"); r.tag.text:SetJustifyH("CENTER")
  r.src = UI.Text(r, "GameFontHighlight", C.text)
  r.src:SetWordWrap(false)
  r.bar = UI.Bar(r, 56)
  r.gain = UI.Text(r, "GameFontHighlight")
  r.lvl = UI.Text(r, "GameFontHighlight", C.muted)
  r:Hide()
  rowsUI[i] = r
end

-- the column layout that follows the window width
local function makeLayout(p)
  layout = function()
    local w = scroll:GetWidth()
    if not w or w < 100 then return end
    content:SetWidth(w)
    local itemW = math.floor(w * 0.38)
    local srcX, gainX, lvlX = itemW + 16, w - 230, w - 44
    for _, r in ipairs(rowsUI) do
      r:SetWidth(w)
      ns.PlaceCell(r.item, 8, itemW)
      r.tag:ClearAllPoints(); r.tag:SetPoint("LEFT", srcX, 0)
      r.src:ClearAllPoints(); r.src:SetPoint("LEFT", r.tag, "RIGHT", 8, 0); r.src:SetPoint("RIGHT", r, "LEFT", gainX - 10, 0)
      r.bar:ClearAllPoints(); r.bar:SetPoint("LEFT", gainX, 0)
      r.gain:ClearAllPoints(); r.gain:SetPoint("LEFT", r.bar, "RIGHT", 8, 0)
      r.lvl:ClearAllPoints(); r.lvl:SetPoint("LEFT", lvlX, 0)
    end
    local function at(h, x) h:ClearAllPoints(); h:SetPoint("TOPLEFT", 16 + x, -(HEAD_H + 140)) end
    at(heads.item, 8); at(heads.src, srcX); at(heads.gain, gainX); at(heads.lvl, lvlX)
    -- the cards share the width left of the filters
    local cw = math.floor((p:GetWidth() - 32 - 220 - 2 * 10) / 3)
    for n, c in ipairs(cards) do
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", 16 + (n - 1) * (cw + 10), -(HEAD_H + 72)); c:SetWidth(cw)
    end
  end
  return layout
end

local function filter(p, text, y, onClick)
  local c = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  c:SetSize(22, 22)
  c:SetPoint("TOPRIGHT", -196, y)
  local t = c.text or c.Text or c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t:ClearAllPoints(); t:SetPoint("LEFT", c, "RIGHT", 2, 0); t:SetFontObject("GameFontHighlightSmall")
  t:SetText(text)
  c:SetScript("OnClick", onClick)
  return c, t
end

function ns.BuildDungeons(p, W, makeCell, specSwitcher)
  page = p
  specs = specSwitcher
  makeCellFn = makeCell
  buildPicker(p, 16 + (specs and specs:GetWidth() or 380) + 18, -(HEAD_H + 30))

  -- summary cards
  for n, label in ipairs({ "UPGRADES HERE", "BEST SINGLE DROP", "WHERE FROM" }) do
    local c = UI.Frame(p, C.row, C.line)
    c:SetHeight(56)
    c.label = UI.Text(c, "GameFontHighlightSmall", C.muted, 10)
    c.label:SetPoint("TOPLEFT", 12, -9); c.label:SetText(label)
    c.value = UI.Text(c, "GameFontNormalLarge", C.text)
    c.value:SetPoint("BOTTOMLEFT", 12, 9); c.value:SetPoint("RIGHT", -8, 0); c.value:SetWordWrap(false)
    c.value:SetText("–")
    cards[n] = c
  end

  local mine = filter(p, "Only what I can get", -(HEAD_H + 70), function(self) session.mine = self:GetChecked() and true or false; ns.RenderDungeons() end)
  mine:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Only what I can get", 1, 0.82, 0)
    GameTooltip:AddLine("Hides quest rewards for the other faction or another class, and bosses only the other faction can fight.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  mine:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local win, wt = filter(p, "", -(HEAD_H + 92), function(self) session.within = self:GetChecked() and true or false; ns.RenderDungeons() end)
  local all = filter(p, "Show non-upgrades", -(HEAD_H + 114), function(self) session.showAll = self:GetChecked() and true or false; ns.RenderDungeons() end)
  p:SetScript("OnShow", function()
    all:SetChecked(showAll())
    mine:SetChecked(mineOnly())
    win:SetChecked(within())
    wt:SetText("Usable within " .. levels() .. " levels")
    ns.RenderDungeons()
  end)

  -- column headings: click one to sort by it, click again to reverse
  for _, k in ipairs({ { "item", "ITEM" }, { "src", "FROM" }, { "gain", "GAIN" }, { "lvl", "LVL" } }) do
    local h = CreateFrame("Button", nil, p)
    h:SetSize(70, 18)
    h.text = UI.Text(h, "GameFontHighlightSmall", C.muted, 10)
    h.text:SetPoint("LEFT")
    h.key, h.title = k[1], k[2]
    h:SetScript("OnClick", function(self)
      local cur = ns.db.dgSort or { key = "gain", desc = true }
      if cur.key == self.key then
        ns.db.dgSort = { key = self.key, desc = not cur.desc }
      else
        -- gain starts biggest-first; names, sources and levels start A-Z / lowest-first
        ns.db.dgSort = { key = self.key, desc = (self.key == "gain") }
      end
      ns.RenderDungeons()
    end)
    h:SetScript("OnEnter", function(self)
      self.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText("Sort by " .. self.title:lower(), 1, 1, 1)
      GameTooltip:AddLine("Click again to reverse the order.", 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide(); ns.UpdateSortHeads() end)
    heads[k[1]] = h
  end
  ns.UpdateSortHeads()

  scroll, content = ns.MakeScroll(p, "TopRamenGearDungeonScroll", -(HEAD_H + 158))
  return makeLayout(p)
end
