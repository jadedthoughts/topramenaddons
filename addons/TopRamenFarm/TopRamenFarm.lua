-- Top Ramen Farm: press Start, go farm, and it records everything you loot (items and coin)
-- and tallies what the haul is worth: sold to a vendor vs. sold smart (auction house when it pays more).
-- Toggle it off and the session goes into your history.
--
-- Prices: vendor price comes from the game. Auction prices come from Top Ramen Crafting's own
-- auction house scans if you have it, otherwise from Auctionator, whichever is fresher.

local ADDON, ns = ...

ns.VERSION = "0.1.0"
ns.AH_CUT = 0.95        -- the auction house keeps 5% of a sale
local HISTORY_MAX = 50  -- sessions kept per character

---------------------------------------------------------------------------
-- saved data
---------------------------------------------------------------------------
local db
local function ensureDB()
  TopRamenFarmDB = TopRamenFarmDB or {}
  db = TopRamenFarmDB
  db.chars = db.chars or {}
  db.settings = db.settings or {}
  db.window = db.window or {}
  db.mini = db.mini or {}
  if db.settings.mini == nil then db.settings.mini = true end -- mini tracker while recording
  if db.settings.opacity == nil then db.settings.opacity = 0.92 end
end
function ns.db() if not db then ensureDB() end return db end
function ns.settings() return ns.db().settings end

local function charKey()
  return (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
end
function ns.char()
  local d = ns.db()
  local k = charKey()
  d.chars[k] = d.chars[k] or {}
  d.chars[k].history = d.chars[k].history or {}
  return d.chars[k]
end

function ns.say(msg) print("|cffffd100Top Ramen Farm:|r " .. tostring(msg)) end
local function refresh(full) if ns.Refresh then ns.Refresh(full) end end

---------------------------------------------------------------------------
-- money text
---------------------------------------------------------------------------
function ns.coins(c, short)
  c = math.floor(math.abs(c or 0) + 0.5)
  if c == 0 then return "0|cffc27c3ac|r" end
  local g, s, cc = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local out = {}
  if g > 0 then out[#out + 1] = "|cffffd100" .. g .. "g|r" end
  if (s > 0 or g > 0) and not (short and g >= 100) then out[#out + 1] = "|cffc7c7cf" .. s .. "s|r" end
  if not (short and g > 0) then out[#out + 1] = "|cffc27c3a" .. cc .. "c|r" end
  return table.concat(out, " ")
end
function ns.money(c, signed, short)
  if c == nil then return "|cff8f877a?|r" end
  local r = math.floor(c + 0.5)
  if signed and r > 0 then return "|cff4ade80+|r" .. ns.coins(r, short) end
  if r < 0 then return "|cfff87171-|r" .. ns.coins(r, short) end
  return ns.coins(r, short)
end
function ns.clock(sec)
  sec = math.floor(sec or 0)
  local h, m, s = math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%d:%02d", m, s)
end
-- copper per hour, or nil for the first minute (too noisy to mean anything)
function ns.perHour(c, sec)
  if not c or not sec or sec < 60 then return nil end
  return c * 3600 / sec
end

---------------------------------------------------------------------------
-- prices
---------------------------------------------------------------------------
local pending = {} -- item ids we've asked the game about
-- WoW Forever only has the modern C_Item versions; fall back to the old globals elsewhere
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local RequestItem = (C_Item and C_Item.RequestLoadItemDataByID) or function() end

-- Top Ramen Crafting's own scans: TopRamenCraftDB.ah["Realm-Faction"].items[id] = { p = copper, t = time }
local function trcPrice(id)
  local d = TopRamenCraftDB
  if type(d) ~= "table" or type(d.ah) ~= "table" then return nil end
  local _, faction = UnitFactionGroup("player")
  local r = d.ah[((GetRealmName and GetRealmName()) or "?") .. "-" .. (faction or "")]
  local e = r and r.items and r.items[id]
  if type(e) == "table" and e.p and e.p > 0 then
    return e.p, math.floor((time() - (e.t or 0)) / 86400), "Top Ramen Crafting"
  end
end

local function auctionatorPrice(id)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not api or not api.GetAuctionPriceByItemID then return nil end
  local ok, p = pcall(api.GetAuctionPriceByItemID, ADDON, id)
  if not ok or type(p) ~= "number" or p <= 0 then return nil end
  local age
  if api.GetAuctionAgeByItemID then
    local ok2, a = pcall(api.GetAuctionAgeByItemID, ADDON, id)
    if ok2 and type(a) == "number" then age = a end
  end
  return p, age, "Auctionator"
end

-- the freshest auction price we know: copper each, age in days (may be nil), source name
function ns.ahPrice(id)
  local p1, a1, s1 = trcPrice(id)
  local p2, a2, s2 = auctionatorPrice(id)
  if p1 and p2 then
    if (a2 or 99) < (a1 or 99) then return p2, a2, s2 end
    return p1, a1, s1
  end
  if p1 then return p1, a1, s1 end
  return p2, a2, s2
end

function ns.priceSources()
  local list = {}
  if type(TopRamenCraftDB) == "table" and type(TopRamenCraftDB.ah) == "table" then list[#list + 1] = "Top Ramen Crafting" end
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if api and api.GetAuctionPriceByItemID then list[#list + 1] = "Auctionator" end
  return list
end

-- everything we know about pricing one item. Returns nil while the game is still loading the item.
--   { name, link, icon, quality, vendor (each), ah (raw each), ahNet (each after the 5% cut),
--     age, src, canAH, best (each), sellTo = "vendor" | "ah" | "none" }
function ns.itemValue(id, bound)
  local name, link, quality, _, _, _, _, _, _, icon, sell, classID, _, bind = GetInfo(id)
  if not name then
    if not pending[id] then
      pending[id] = true
      pcall(RequestItem, id)
    end
    return nil
  end
  local v = { name = name, link = link, icon = icon, quality = quality, vendor = sell or 0, classID = classID, bind = bind }
  v.quest = classID == 12 or bind == 4
  -- poor (grey) items, soulbound items and quest items can't go on the auction house
  v.bound = bound or bind == 1
  v.canAH = quality ~= 0 and not v.bound and not v.quest
  if v.canAH then
    v.ah, v.age, v.src = ns.ahPrice(id)
    if v.ah then v.ahNet = math.floor(v.ah * ns.AH_CUT) end
  end
  if v.ahNet and v.ahNet > v.vendor then v.best, v.sellTo = v.ahNet, "ah"
  elseif v.vendor > 0 then v.best, v.sellTo = v.vendor, "vendor"
  else v.best, v.sellTo = 0, "none" end
  return v
end

-- totals for a session at today's prices:
--   money (coin looted), vendor (coin + all items to a vendor), smart (coin + each item where it pays most),
--   count (items looted), kinds, loading (items the game hasn't sent yet), ahWins (kinds better on the AH)
function ns.totals(s)
  local t = { money = s and s.money or 0, vendor = 0, smart = 0, count = 0, kinds = 0, loading = 0, ahWins = 0 }
  t.vendor, t.smart = t.money, t.money
  for key, it in pairs(s and s.items or {}) do
    local n = it.n or 0
    t.count, t.kinds = t.count + n, t.kinds + 1
    local v = ns.itemValue(it.id or key, it.bound)
    if v then
      t.vendor = t.vendor + v.vendor * n
      t.smart = t.smart + v.best * n
      if v.sellTo == "ah" then t.ahWins = t.ahWins + 1 end
    else
      t.loading = t.loading + 1
    end
  end
  return t
end

---------------------------------------------------------------------------
-- sessions
---------------------------------------------------------------------------
function ns.session() return ns.char().session end
function ns.isRunning() local s = ns.session(); return s and s.running or false end

function ns.elapsed(s)
  s = s or ns.session()
  if not s then return 0 end
  local e = s.elapsed or 0
  if s.running and s.segStart then e = e + math.max(0, time() - s.segStart) end
  return e
end

local function noteZone(s)
  local z = GetRealZoneText and GetRealZoneText() or ""
  if not s or z == "" then return end
  s.zoneOrder = s.zoneOrder or {}
  for _, have in ipairs(s.zoneOrder) do if have == z then return end end
  s.zoneOrder[#s.zoneOrder + 1] = z
end

function ns.zonesText(s, max)
  local z = s and s.zoneOrder or {}
  if #z == 0 then return "" end
  max = max or 3
  if #z <= max then return table.concat(z, ", ") end
  local first = {}
  for i = 1, max do first[i] = z[i] end
  return table.concat(first, ", ") .. " +" .. (#z - max)
end

function ns.start()
  local c = ns.char()
  if c.session and c.session.running then return end
  c.session = { running = true, startedAt = time(), segStart = time(), elapsed = 0, money = 0, items = {}, order = {}, zoneOrder = {} }
  noteZone(c.session)
  ns.say("recording your loot. Type /trfarm stop (or press Stop farming) when you're done.")
  refresh(true)
end

function ns.stop()
  local c = ns.char()
  local s = c.session
  if not s or not s.running then return end
  s.elapsed = ns.elapsed(s)
  s.segStart, s.running, s.endedAt = nil, false, time()
  local t = ns.totals(s)
  -- what it was worth at the prices of the day you farmed it
  s.snap = { money = t.money, vendor = t.vendor, smart = t.smart, count = t.count }
  c.session = nil
  if t.count > 0 or t.money > 0 then
    table.insert(c.history, 1, s)
    while #c.history > HISTORY_MAX do table.remove(c.history) end
    ns.say(string.format("stopped after %s. Vendor everything: %s. Sell smart: %s.",
      ns.clock(s.elapsed), ns.coins(t.vendor), ns.coins(t.smart)))
  else
    ns.say("stopped. Nothing was looted, so the session wasn't saved.")
  end
  refresh(true)
end

function ns.toggle() if ns.isRunning() then ns.stop() else ns.start() end end

function ns.deleteHistory(i)
  local h = ns.char().history
  if h[i] then table.remove(h, i) end
  refresh(true)
end

---------------------------------------------------------------------------
-- reading the loot messages
---------------------------------------------------------------------------
-- turn a game format string ("You receive loot: %sx%d.") into a Lua pattern
local function toPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("%%%d%$s", "%%s"):gsub("%%%d%$d", "%%d")
  p = p:gsub("%%s", "\001"):gsub("%%d", "\002")
  p = p:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
  return "^" .. p
end
ns.toPattern = toPattern

local LOOT_MULTI = toPattern(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.")
local LOOT_ONE = toPattern(LOOT_ITEM_SELF or "You receive loot: %s.")
local function amountPattern(fmt, word)
  local p = toPattern(fmt)
  if p then return (p:gsub("^%^", "")) end
  return "(%d+) " .. word
end
local GOLD_P = amountPattern(GOLD_AMOUNT, "Gold")
local SILVER_P = amountPattern(SILVER_AMOUNT, "Silver")
local COPPER_P = amountPattern(COPPER_AMOUNT, "Copper")

-- "You receive loot: [Linen Cloth]x3." -> link, 3
function ns.parseLoot(msg)
  if type(msg) ~= "string" then return nil end
  local link, n = msg:match(LOOT_MULTI)
  if not link then link = msg:match(LOOT_ONE); n = 1 end
  if not link then return nil end
  local id = tonumber(link:match("item:(%d+)"))
  if not id then return nil end
  return id, tonumber(n) or 1, link
end

-- "You loot 1 Gold, 2 Silver, 30 Copper" / "Your share of the loot is ..." -> copper
function ns.parseMoney(msg)
  if type(msg) ~= "string" then return 0 end
  local g = tonumber(msg:match(GOLD_P)) or 0
  local s = tonumber(msg:match(SILVER_P)) or 0
  local c = tonumber(msg:match(COPPER_P)) or 0
  local total = g * 10000 + s * 100 + c
  if total == 0 then -- English fallback in case the client words it differently
    local l = msg:lower()
    total = (tonumber(l:match("(%d+) gold")) or 0) * 10000 + (tonumber(l:match("(%d+) silver")) or 0) * 100 + (tonumber(l:match("(%d+) copper")) or 0)
  end
  return total
end

function ns.addItem(id, n, link)
  local s = ns.session()
  if not s or not s.running then return end
  s.items = s.items or {}
  local it = s.items[id]
  if not it then
    it = { n = 0 }
    s.items[id] = it
    s.order = s.order or {}
    s.order[#s.order + 1] = id
  end
  it.n = it.n + (n or 1)
  it.link = it.link or link
  it.last = time()
  refresh(true)
end

function ns.addMoney(c)
  local s = ns.session()
  if not s or not s.running or not c or c <= 0 then return end
  s.money = (s.money or 0) + c
  refresh(true)
end

---------------------------------------------------------------------------
-- what's in my bags: a session-shaped snapshot of everything sellable in your bags right now
---------------------------------------------------------------------------
local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local function slotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local i = C_Container.GetContainerItemInfo(bag, slot)
    if not i then return nil end
    return i.itemID, i.stackCount, i.hyperlink, i.isBound, i.hasNoValue
  elseif GetContainerItemInfo then
    local _, count, _, _, _, _, link, _, noValue, id, isBound = GetContainerItemInfo(bag, slot)
    if not link then return nil end
    return id or tonumber(link:match("item:(%d+)")), count, link, isBound, noValue
  end
end
local function isQuestSlot(bag, slot)
  if C_Container and C_Container.GetContainerItemQuestInfo then
    local ok, q = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    if ok and type(q) == "table" then return q.isQuestItem or (q.questID ~= nil) end
  end
  return false
end

-- returns { items = { [key] = { id, n, link, bound } }, money = 0, scannedAt, skipped, loading }
-- Left out: quest items and anything a vendor won't buy. Items still loading stay in until we know.
function ns.scanBags()
  local snap = { items = {}, money = 0, scannedAt = time(), skipped = 0, loading = 0 }
  if not NumSlots then return snap end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (NumSlots(bag) or 0) do
      local id, count, link, bound, noValue = slotInfo(bag, slot)
      if id then
        local v = ns.itemValue(id, bound)
        local skip = noValue or isQuestSlot(bag, slot) or (v and (v.quest or v.vendor <= 0))
        if skip then
          snap.skipped = snap.skipped + (count or 1)
        else
          if not v then snap.loading = snap.loading + 1 end
          local key = bound and (id .. ":b") or id
          local it = snap.items[key]
          if not it then it = { id = id, n = 0, link = link, bound = bound or nil }; snap.items[key] = it end
          it.n = it.n + (count or 1)
        end
      end
    end
  end
  return snap
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("CHAT_MSG_LOOT")
ev:RegisterEvent("CHAT_MSG_MONEY")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")

local infoQueued = false
ev:SetScript("OnEvent", function(_, event, a1)
  if event == "ADDON_LOADED" then
    if a1 == ADDON then ensureDB() end
  elseif event == "PLAYER_LOGIN" then
    ensureDB()
    local s = ns.session()
    if s and s.running then
      -- time logged out doesn't count; carry on recording
      s.segStart = time()
      ns.say("still recording your farm session (" .. ns.clock(ns.elapsed(s)) .. " so far). /trfarm to see it.")
    end
    refresh(true)
  elseif event == "PLAYER_LOGOUT" then
    local s = ns.session()
    if s and s.running then
      s.elapsed = ns.elapsed(s)
      s.segStart = nil
    end
  elseif event == "CHAT_MSG_LOOT" then
    if not ns.isRunning() then return end
    local id, n, link = ns.parseLoot(a1)
    if id then ns.addItem(id, n, link) end
  elseif event == "CHAT_MSG_MONEY" then
    if not ns.isRunning() then return end
    ns.addMoney(ns.parseMoney(a1))
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    if ns.isRunning() then noteZone(ns.session()); refresh(false) end
  elseif event == "BAG_UPDATE_DELAYED" then
    if ns.BagsChanged then ns.BagsChanged() end
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if a1 then pending[a1] = nil end
    if not infoQueued then
      infoQueued = true
      local function go() infoQueued = false; refresh(true) end
      if C_Timer then C_Timer.After(0.3, go) else go() end
    end
  end
end)

---------------------------------------------------------------------------
-- slash commands: /trfarm (or /topramenfarm)
---------------------------------------------------------------------------
SLASH_TOPRAMENFARM1 = "/trfarm"
SLASH_TOPRAMENFARM2 = "/topramenfarm"
SlashCmdList.TOPRAMENFARM = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd = msg:match("^(%S+)") or ""
  if cmd == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif cmd == "bags" then
    if ns.ShowTab then ns.ShowTab("bags") end
  elseif cmd == "start" then ns.start()
  elseif cmd == "stop" then ns.stop()
  elseif cmd == "toggle" then ns.toggle()
  elseif cmd == "mini" then
    local st = ns.settings()
    st.mini = not st.mini
    ns.say("mini tracker while recording: " .. (st.mini and "on" or "off") .. ".")
    refresh(false)
  elseif cmd == "opacity" then
    if ns.SetOpacity then ns.SetOpacity(msg:match("opacity%s+(%d+)")) end
  else
    ns.say("/trfarm opens the window. /trfarm bags opens the My bags tab. /trfarm start, /trfarm stop, /trfarm toggle, /trfarm mini (mini tracker on/off), /trfarm opacity 30-100.")
  end
end
