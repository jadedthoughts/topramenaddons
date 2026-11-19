-- Top Ramen Crafting: records your professions and recipes and reads prices, for the planner window.
--
--   /trc (or /topramencraft)   open the planner window (see Window.lua)
--   /trc export                text snapshot of your recipes and prices, for troubleshooting or sharing
--
-- Recipes are recorded automatically every time you open a profession window. Prices come from
-- Auctionator's public API. Read-only: it never buys, sells, crafts or moves anything.

local ADDON, ns = ...
ADDON = ADDON or "TopRamenCrafting"
ns = ns or {}
local FORMAT = "1"
local GOLD = "|cffe0b04a"

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local RequestItem = (C_Item and C_Item.RequestLoadItemDataByID) or function() end
local CountItem = (C_Item and C_Item.GetItemCount) or GetItemCount

local db, charKey

local function say(msg) print(GOLD .. "Top Ramen:|r " .. msg) end

local function clean(s)
  if not s then return "" end
  s = tostring(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
  s = s:gsub("|", "/"):gsub("[%^~;\r\n\t]", " ")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function idFromLink(link)
  return link and tonumber(link:match("item:(%d+)")) or nil
end

local function charData()
  db.chars = db.chars or {}
  local c = db.chars[charKey]
  if not c then
    c = { professions = {} }
    db.chars[charKey] = c
  end
  c.professions = c.professions or {}
  return c
end

---------------------------------------------------------------------------
-- Profession skill levels (read from the skills list, no window needed)
---------------------------------------------------------------------------
local PROF_HEADERS = {
  ["Professions"] = true, ["Secondary Skills"] = true,
}
if TRADE_SKILLS then PROF_HEADERS[TRADE_SKILLS] = true end
if SECONDARY_SKILLS then PROF_HEADERS[SECONDARY_SKILLS] = true end

local function readSkills()
  local out = {}
  if GetNumSkillLines and GetSkillLineInfo then
    local header
    for i = 1, (GetNumSkillLines() or 0) do
      local name, isHeader, _, rank, _, modifier, maxRank = GetSkillLineInfo(i)
      if isHeader then
        header = name
      elseif name and header and PROF_HEADERS[header] then
        out[#out + 1] = { name = clean(name), rank = rank or 0, bonus = modifier or 0, max = maxRank or 0 }
      end
    end
  end
  if #out == 0 and GetProfessions and GetProfessionInfo then
    for _, idx in ipairs({ GetProfessions() }) do
      if idx then
        local name, _, rank, maxRank, _, _, _, modifier = GetProfessionInfo(idx)
        if name then out[#out + 1] = { name = clean(name), rank = rank or 0, bonus = modifier or 0, max = maxRank or 0 } end
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Recipe recording (runs whenever a profession window opens or changes)
---------------------------------------------------------------------------
local IGNORED_PROFESSIONS = { Fishing = true }

local function storeProfession(prof, rank, maxRank, recipes, missing)
  if not prof or prof == "" or prof == "UNKNOWN" or IGNORED_PROFESSIONS[prof] then return end
  local c = charData()
  local p = c.professions[prof] or { recipes = {} }
  c.professions[prof] = p
  p.recipes = p.recipes or {}
  local t = time()
  local n = 0
  for name, r in pairs(recipes) do
    r.seen = t
    -- remember the colors seen at each skill, so we learn where this recipe turns yellow:
    -- orangeMax = highest skill it was still orange, yellowMin = lowest skill it wasn't
    local prev = p.recipes[name]
    r.orangeMax, r.yellowMin = prev and prev.orangeMax, prev and prev.yellowMin
    if rank and rank > 0 then
      if r.diff == "optimal" then r.orangeMax = math.max(r.orangeMax or 0, rank)
      elseif r.diff == "medium" or r.diff == "easy" or r.diff == "trivial" then r.yellowMin = math.min(r.yellowMin or 9999, rank) end
    end
    r.gray = r.gray or (prev and prev.gray)
    p.recipes[name] = r -- merge: recipes hidden by a filter or collapsed header are kept from earlier scans
    n = n + 1
  end
  if n == 0 then return end
  p.rank, p.max = rank or 0, maxRank or 0
  p.scannedAt, p.scannedRank = t, rank or 0
  p.incomplete = (missing or 0) > 0
  p.needsOpen = nil -- just read from its open window
  if ns.OnDataChanged then ns.OnDataChanged() end
end

-- Modern professions window (C_TradeSkillUI), which WoW Forever uses
local DIFF_NAMES = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

local function modernProfession()
  local T = C_TradeSkillUI
  local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
  local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
  local name = (base and base.professionName ~= "" and base.professionName) or (child and (child.parentProfessionName or child.professionName))
  local src = (child and (child.maxSkillLevel or 0) > 0) and child or base
  if not src then return name, 0, 0 end
  return name, (src.skillLevel or 0) + 0, src.maxSkillLevel or 0
end

local function isBasicSlot(slot)
  if slot.required ~= nil then return slot.required end
  local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
  return slot.reagentType == nil or slot.reagentType == basic
end

-- Which profession (and skill, if the game says) a window shows, when it isn't your own.
-- Tries several sources because Forever leaves the usual ones empty for linked windows.
local PROFESSION_BY_LINE = { [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering",
  [165] = "Leatherworking", [197] = "Tailoring", [186] = "Mining", [182] = "Herbalism", [393] = "Skinning",
  [129] = "First Aid", [185] = "Cooking", [356] = "Fishing", [755] = "Jewelcrafting", [773] = "Inscription" }
local function otherProfession(sampleRecipeID)
  local T = C_TradeSkillUI
  local found = {}
  local name, rank, maxRank
  local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
  if base and base.professionName and base.professionName ~= "" then
    name, rank, maxRank = base.professionName, base.skillLevel, base.maxSkillLevel; found[#found + 1] = "base"
  end
  local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
  if child and (child.professionName or "") ~= "" then
    name = name or child.parentProfessionName or child.professionName
    if (child.skillLevel or 0) > 0 then rank, maxRank = child.skillLevel, child.maxSkillLevel end
    found[#found + 1] = "child"
  end
  if sampleRecipeID and T.GetTradeSkillLineForRecipe then
    local ok, lineID, lineName, parentID = pcall(T.GetTradeSkillLineForRecipe, sampleRecipeID)
    if ok and (lineID or parentID) then
      name = name or PROFESSION_BY_LINE[parentID or 0] or PROFESSION_BY_LINE[lineID or 0] or lineName
      found[#found + 1] = "recipe line " .. tostring(lineID) .. "/" .. tostring(parentID)
      if T.GetProfessionInfoBySkillLineID then
        for _, id in ipairs({ lineID, parentID }) do
          local ok2, info = pcall(T.GetProfessionInfoBySkillLineID, id)
          if ok2 and info and (info.skillLevel or 0) > 0 and not rank then
            rank, maxRank = info.skillLevel, info.maxSkillLevel; found[#found + 1] = "line info"
          end
        end
      end
    end
  end
  -- the profession window's own skill bar reads per-recipe profession info on newer clients
  if sampleRecipeID and T.GetProfessionInfoByRecipeID and not rank then
    local ok, info = pcall(T.GetProfessionInfoByRecipeID, sampleRecipeID)
    if ok and info then
      name = name or info.parentProfessionName or info.professionName
      if (info.skillLevel or 0) > 0 then rank, maxRank = info.skillLevel, info.maxSkillLevel end
      found[#found + 1] = "recipe info " .. tostring(info.skillLevel) .. "/" .. tostring(info.maxSkillLevel)
    end
  end
  return name, rank, maxRank, table.concat(found, ", ")
end

-- Someone else's profession window (a link from chat): save who knows what.
local lastLinked
local function recordLinked(who)
  local T = C_TradeSkillUI
  local learned, first = {}, nil
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local info = T.GetRecipeInfo(id)
    if info and info.learned and info.name then learned[id] = clean(info.name); first = first or id end
  end
  if not first then return end
  local prof, rank, maxRank = otherProfession(first)
  if not prof or not who then return end
  who = clean(who)
  db.guild = db.guild or {}
  db.guild[who] = db.guild[who] or {}
  local n = 0
  for _ in pairs(learned) do n = n + 1 end
  db.guild[who][clean(prof)] = { recipes = learned, count = n, rank = rank, max = maxRank, seen = time() }
  local key = who .. "|" .. prof .. "|" .. n
  if key ~= lastLinked then
    lastLinked = key
    say("recorded " .. who .. "'s " .. prof .. ": " .. n .. " recipes" .. (rank and rank > 0 and (" (skill " .. rank .. "/" .. tostring(maxRank) .. ")") or "") .. ".")
  end
  if ns.OnDataChanged then ns.OnDataChanged() end
end

-- Profession links seen in chat, saved so they can be opened again later:
-- db.links[who][profession] = { link = "trade:...", text = "Tailoring", seen = time }
local CHAT_EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT" }
local function shortName(sender)
  if Ambiguate then return Ambiguate(sender or "", "short") end
  return (sender or ""):gsub("%-.*$", "")
end
local function saveChatLinks(msg, sender)
  if not (db and msg and msg:find("|Htrade:", 1, true)) then return end
  local who = clean(shortName(sender))
  if who == "" then return end
  db.links = db.links or {}
  for link, text in msg:gmatch("|H(trade:[^|]+)|h%[([^%]]+)%]|h") do
    db.links[who] = db.links[who] or {}
    db.links[who][clean(text)] = { link = link, text = text, seen = time() }
    local spell = tonumber(link:match("^trade:Player%-[^:]+:(%d+):"))
    if spell then db.linkSpell = db.linkSpell or {}; db.linkSpell[clean(text)] = spell end
  end
end

-- open a saved profession link again, the same as clicking it in chat
local function openSavedLink(who, prof)
  local e = db.links and db.links[who] and db.links[who][prof]
  if not e then return false end
  local T = C_TradeSkillUI
  if T and T.CloseTradeSkill then pcall(T.CloseTradeSkill) end
  if ProfessionsFrame and ProfessionsFrame:IsShown() then pcall(HideUIPanel, ProfessionsFrame) end
  local text = "|cffffd000|H" .. e.link .. "|h[" .. e.text .. "]|h|r"
  if SetItemRef then pcall(SetItemRef, e.link, text, "LeftButton") end
  return true
end
ns.openSavedLink = openSavedLink

-- Building a profession link for anyone in the guild. A link is "trade:<character ID>:<profession spell>:<skill line>",
-- e.g. trade:Player-6933-005BBF14:4038:202 (Engineering). The guild roster gives each member's character ID.
local PROF_LINE = { Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202, Leatherworking = 165,
  Tailoring = 197, Mining = 186, ["First Aid"] = 129, Cooking = 185, Jewelcrafting = 755, Inscription = 773 }
-- the profession's spell at each rank (Apprentice, Journeyman, Expert, Artisan)
local PROF_SPELLS = {
  Alchemy = { 2259, 3101, 3464, 11611 }, Blacksmithing = { 2018, 3100, 3538, 9785 }, Enchanting = { 7411, 7412, 7413, 13920 },
  Engineering = { 4036, 4037, 4038, 12656 }, Leatherworking = { 2108, 3104, 3811, 10662 }, Tailoring = { 3908, 3909, 3910, 12180 },
  Mining = { 2575, 2576, 3564, 10248 }, ["First Aid"] = { 3273, 3274, 7924, 10846 }, Cooking = { 2550, 3102, 3413, 18260 },
  Jewelcrafting = { 25229, 25230, 28894, 28895 }, Inscription = { 45357, 45358, 45359, 45360 },
}

-- character IDs by name: from the guild roster, and from links people have sent. db.guids[name] = "Player-..."
local function knownGUIDs()
  db.guids = db.guids or {}
  if GetNumGuildMembers and GetGuildRosterInfo then
    for i = 1, (GetNumGuildMembers() or 0) do
      local v = (function(...) return { n = select("#", ...), ... } end)(pcall(GetGuildRosterInfo, i))
      if v[1] and type(v[2]) == "string" then
        for k = 3, v.n do
          if type(v[k]) == "string" and v[k]:find("^Player%-") then db.guids[clean(shortName(v[2]))] = v[k]; break end
        end
      end
    end
  end
  for who, profs in pairs(db.links or {}) do
    for _, e in pairs(profs) do
      local g = e.link and e.link:match("^trade:(Player%-[^:]+)")
      if g then db.guids[who] = db.guids[who] or g end
    end
  end
  return db.guids
end
ns.knownGUIDs = function() if not db then return {} end; return knownGUIDs() end
ns.canBuildLink = function(prof) return PROF_LINE[prof] ~= nil end
-- built links have only opened for characters whose ID has the same server number as yours (the number after "Player-")
local function myRealmID() return UnitGUID and (UnitGUID("player") or ""):match("^Player%-(%d+)%-") end
local function sameRealm(guid) local r = guid and guid:match("^Player%-(%d+)%-"); return r ~= nil and r == myRealmID() end
ns.sameRealm = sameRealm

-- is this guildmate online right now? (nil when they aren't in the guild roster)
local function isOnlineNow(who)
  if not (GetNumGuildMembers and GetGuildRosterInfo) then return nil end
  for i = 1, (GetNumGuildMembers() or 0) do
    local ok, name, _, _, _, _, _, _, _, online = pcall(GetGuildRosterInfo, i)
    if ok and name and clean(shortName(name)):lower() == who:lower() then return online and true or false end
  end
  return nil
end
local OFFLINE_MSG = " is offline. Profession windows only open while the person is online; their recorded recipes stay on the Guild tab."

-- open anyone's profession by building their link. Tries the rank that worked before for this profession first,
-- then each rank in turn, and saves the one that opens.
local function openBuiltLink(who, prof, verbose)
  local guid = knownGUIDs()[who]
  local line, spells = PROF_LINE[prof], PROF_SPELLS[prof]
  if not guid then say("no character ID for " .. who .. " yet. They need to be in your guild, or link a profession once."); return false end
  if not (line and spells) then say("can't build a " .. prof .. " link."); return false end
  if isOnlineNow(who) == false then say(who .. OFFLINE_MSG); return true end
  if not sameRealm(guid) then
    say(who .. "'s character ID has a different server number (" .. tostring(guid:match("^Player%-(%d+)%-")) .. ", yours is " ..
      tostring(myRealmID()) .. "). Built links haven't opened for those, so their profession opens from a link they send in chat.")
    return false
  end
  db.linkSpell = db.linkSpell or {}
  local order, first = {}, db.linkSpell[prof]
  if first then order[1] = first end
  for _, id in ipairs(spells) do if id ~= first then order[#order + 1] = id end end
  local T, i = C_TradeSkillUI, 0
  local tried = {}
  say("opening " .. who .. "'s " .. prof .. "...")
  local function try()
    i = i + 1
    if i > #order then
      say("couldn't open " .. who .. "'s " .. prof .. ". They may need to be online.")
      say("tried (character ID " .. guid .. "): " .. table.concat(tried, "; "))
      return
    end
    local link = "trade:" .. guid .. ":" .. order[i] .. ":" .. line
    -- close whatever profession window is open, so it can't block this one or be mistaken for it
    if T and T.CloseTradeSkill then pcall(T.CloseTradeSkill) end
    if ProfessionsFrame and ProfessionsFrame:IsShown() then pcall(HideUIPanel, ProfessionsFrame) end
    if TradeSkillFrame and TradeSkillFrame:IsShown() then pcall(HideUIPanel, TradeSkillFrame) end
    local function open()
      if SetItemRef then pcall(SetItemRef, link, "|cffffd000|H" .. link .. "|h[" .. prof .. "]|h|r", "LeftButton") end
    end
    if C_Timer then C_Timer.After(0.5, open) else open() end
    local function check()
      local linked, name = false, nil
      if T and T.IsTradeSkillLinked then linked, name = T.IsTradeSkillLinked() end
      local shown = ProfessionsFrame and ProfessionsFrame:IsShown() or (TradeSkillFrame and TradeSkillFrame:IsShown())
      tried[#tried + 1] = order[i] .. " -> " .. (linked and ("window of " .. tostring(name)) or (shown and "a window, not linked" or "nothing"))
      if verbose then say("  " .. link .. ": " .. tried[#tried]) end
      if linked and name and clean(shortName(name)):lower() == who:lower() then
        db.linkSpell[prof] = order[i]
        db.links = db.links or {}
        db.links[who] = db.links[who] or {}
        db.links[who][prof] = { link = link, text = prof, seen = time(), built = true }
        say("it opened: " .. who .. "'s " .. prof .. " is showing.")
        if ns.OnDataChanged then ns.OnDataChanged() end
      else
        try()
      end
    end
    if C_Timer then C_Timer.After(3, check) else check() end
  end
  try()
  return true
end
ns.openBuiltLink = function(who, prof) return openBuiltLink(who, prof) end
ns._openBuiltLink = openBuiltLink

-- The guild's profession directory (who has which profession, offline members included), saved as
-- db.guildDir = { at = time, profs = { [prof] = { { name, online, class }, ... } } }
local guildReading, guildReadStart = false, nil
local GUILD_READ_SECONDS = 3
local function readGuildDirectory(quiet)
  if guildReading or not (IsInGuild and IsInGuild()) or not (GetNumGuildTradeSkill and GetGuildTradeSkillInfo) then return false end
  guildReading = true
  guildReadStart = GetTime and GetTime() or time()
  if ns.OnDataChanged then ns.OnDataChanged() end
  local G = C_GuildInfo
  local getOff = GetGuildRosterShowOffline or (G and G.GetGuildRosterShowOffline)
  local setOff = SetGuildRosterShowOffline or (G and G.SetGuildRosterShowOffline)
  local wasOffline = getOff and getOff()
  if setOff then pcall(setOff, true) end -- the list follows "show offline members"; turned back after reading
  if G and G.GuildRoster then pcall(G.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
  if QueryGuildRecipes then pcall(QueryGuildRecipes) end
  if not quiet then say("reading the guild's professions...") end
  local function read()
    guildReading = false
    if ExpandGuildTradeSkillHeader then
      local i = 1
      while i <= (GetNumGuildTradeSkill() or 0) and i < 2000 do
        local ok, skillID, collapsed, _, header = pcall(GetGuildTradeSkillInfo, i)
        if ok and header and collapsed then pcall(ExpandGuildTradeSkillHeader, skillID) end
        i = i + 1
      end
    end
    local profs, current, people = {}, nil, 0
    for i = 1, (GetNumGuildTradeSkill() or 0) do
      local ok, _, _, _, header, _, _, _, playerName, _, class, online, _, _, classFile = pcall(GetGuildTradeSkillInfo, i)
      if ok and header then
        current = (not header:find("DNT")) and clean(header) or nil
        if current and IGNORED_PROFESSIONS[current] then current = nil end
        if current then profs[current] = profs[current] or {} end
      elseif ok and playerName and current then
        local list = profs[current]
        list[#list + 1] = { name = clean(playerName), online = online and true or false, class = classFile or class }
        people = people + 1
      end
    end
    if setOff and wasOffline ~= nil then pcall(setOff, wasOffline) end
    if people > 0 then
      db.guildDir = { at = time(), profs = profs }
      if not quiet then say("guild professions read: " .. people .. " entries.") end
    elseif not quiet then
      say("the guild profession list came back empty. Try again in a moment.")
    end
    if ns.OnDataChanged then ns.OnDataChanged() end
  end
  if C_Timer then C_Timer.After(GUILD_READ_SECONDS, read) else read() end
  return true
end
-- 0-1 while the guild list is being read, nil otherwise
ns.guildProgress = function()
  if not guildReading or not guildReadStart then return nil end
  local now = GetTime and GetTime() or time()
  return math.max(0.02, math.min(0.99, (now - guildReadStart) / GUILD_READ_SECONDS))
end

-- how long one craft takes, in seconds (a recipe is a spell; this is its cast time)
local function castSeconds(spellID)
  if not spellID then return nil end
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if ok and type(info) == "table" and info.castTime then return info.castTime / 1000 end
  end
  if GetSpellInfo then
    local ok, _, _, _, ct = pcall(GetSpellInfo, spellID)
    if ok and type(ct) == "number" then return ct / 1000 end
  end
  return nil
end

local function scanModern()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return false end
  if T.IsTradeSkillLinked then
    local linked, who = T.IsTradeSkillLinked()
    if linked then pcall(recordLinked, who); return true end
  end
  if (T.IsTradeSkillGuild and T.IsTradeSkillGuild()) or (T.IsNPCCrafting and T.IsNPCCrafting()) then return true end
  local prof, rank, maxRank = modernProfession()
  if not prof then return true end
  local recipes, missing = {}, 0
  for _, recipeID in ipairs(T.GetAllRecipeIDs() or {}) do
    local info = T.GetRecipeInfo(recipeID)
    if info and info.learned and not info.isDummyRecipe and not info.isRecraft and info.name then
      local schem = T.GetRecipeSchematic and T.GetRecipeSchematic(recipeID, false)
      local r = { name = clean(info.name), diff = DIFF_NAMES[info.relativeDifficulty] or "", out = 0, min = 1, max = 1, reagents = {},
                  gray = (info.maxTrivialLevel or 0) > 0 and info.maxTrivialLevel or nil,
                  cast = castSeconds(recipeID) }
      if schem then
        r.out = schem.outputItemID or 0
        r.min = schem.quantityMin or 1
        r.max = schem.quantityMax or r.min
        for _, slot in ipairs(schem.reagentSlotSchematics or {}) do
          if isBasicSlot(slot) and slot.reagents and slot.reagents[1] then
            local rid = slot.reagents[1].itemID
            if not rid then missing = missing + 1 end
            r.reagents[#r.reagents + 1] = { id = rid or 0, n = slot.quantityRequired or 1, name = "" }
          end
        end
      else
        missing = missing + 1
      end
      recipes[r.name] = r
    end
  end
  storeProfession(clean(prof), rank, maxRank, recipes, missing)
  return true
end

local function scanTradeSkill()
  if scanModern() then return end
  if not (GetTradeSkillLine and GetNumTradeSkills) then return end
  if IsTradeSkillLinked and IsTradeSkillLinked() then return end -- someone else's recipe list
  local prof, rank, maxRank = GetTradeSkillLine()
  local num = GetNumTradeSkills() or 0
  if not prof or num == 0 then return end
  local recipes, missing = {}, 0
  for i = 1, num do
    local name, kind = GetTradeSkillInfo(i)
    if name and kind ~= "header" and kind ~= "subheader" then
      local mn, mx = 1, 1
      if GetTradeSkillNumMade then mn, mx = GetTradeSkillNumMade(i) end
      local r = { name = clean(name), diff = kind or "", out = idFromLink(GetTradeSkillItemLink(i)) or 0,
                  min = mn or 1, max = mx or mn or 1, reagents = {} }
      for j = 1, (GetTradeSkillNumReagents(i) or 0) do
        local rName, _, rCount = GetTradeSkillReagentInfo(i, j)
        local rid = idFromLink(GetTradeSkillReagentItemLink(i, j))
        if not rid then missing = missing + 1 end
        r.reagents[#r.reagents + 1] = { id = rid or 0, n = rCount or 1, name = clean(rName) }
      end
      recipes[r.name] = r
    end
  end
  storeProfession(clean(prof), rank, maxRank, recipes, missing)
end

-- Vanilla-style Enchanting uses the separate "craft" window
local function scanCraft()
  if not (GetCraftDisplaySkillLine and GetNumCrafts) then return end
  local prof, rank, maxRank = GetCraftDisplaySkillLine()
  if not prof then return end -- Beast Training uses this window too; it has no skill line
  local recipes, missing = {}, 0
  for i = 1, (GetNumCrafts() or 0) do
    local name, _, kind = GetCraftInfo(i)
    if name and kind ~= "header" and kind ~= "subheader" then
      local link = GetCraftItemLink and GetCraftItemLink(i)
      local r = { name = clean(name), diff = kind or "", out = idFromLink(link) or 0, min = 1, max = 1, reagents = {} }
      for j = 1, (GetCraftNumReagents(i) or 0) do
        local rName, _, rCount = GetCraftReagentInfo(i, j)
        local rid = idFromLink(GetCraftReagentItemLink(i, j))
        if not rid then missing = missing + 1 end
        r.reagents[#r.reagents + 1] = { id = rid or 0, n = rCount or 1, name = clean(rName) }
      end
      recipes[r.name] = r
    end
  end
  storeProfession(clean(prof), rank, maxRank, recipes, missing)
end

local pending = {}
local function schedule(fn)
  if pending[fn] then return end
  pending[fn] = true
  local run = function() pending[fn] = nil; pcall(fn) end
  if C_Timer then C_Timer.After(0.3, run) else run() end
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
local function auctionator()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

local function apiCall(api, fname, id)
  if not (api and api[fname]) then return nil end
  local ok, v = pcall(api[fname], ADDON, id)
  if ok then return v end
end

-- Trade supplies sold by vendors, at full list price per single item (copper), before any
-- reputation discount. Used when Auctionator hasn't seen a vendor sell the item to you yet;
-- once it has, your own (possibly discounted) price is used instead.
local VENDOR_LIST_PRICE = {
  [2320] = 10,    -- Coarse Thread
  [2321] = 100,   -- Fine Thread
  [4291] = 500,   -- Silken Thread
  [8343] = 2000,  -- Heavy Silken Thread
  [14341] = 5000, -- Rune Thread
  [2880] = 100,   -- Weak Flux
  [3466] = 2000,  -- Strong Flux
  [4289] = 50,    -- Salt
  [2678] = 2,     -- Mild Spices (10c for 5)
  [2692] = 40,    -- Hot Spices
  [3713] = 160,   -- Soothing Spices
  [3371] = 4,     -- Empty Vial (20c for 5)
  [3372] = 40,    -- Leaded Vial (2s for 5)
  [6217] = 124,   -- Copper Rod
  [3857] = 500,   -- Coal
  [4399] = 200,   -- Wooden Stock
  [4400] = 2000,  -- Heavy Stock
  [6529] = 50,    -- Shiny Bauble
  [6532] = 250,   -- Bright Baubles
  [6530] = 100,   -- Nightcrawlers
  [2605] = 100,   -- Green Dye
  [6260] = 50,    -- Blue Dye
  [2604] = 50,    -- Red Dye
  [2324] = 25,    -- Bleach
  [2928] = 20,    -- Dust of Decay
  [2325] = 1000,  -- Black Dye
  [4341] = 500,   -- Yellow Dye
  [4342] = 2500,  -- Purple Dye
  [4340] = 350,   -- Gray Dye
}

-- Everything the planner needs to know about one item, read live. nil if the game hasn't loaded it yet.
-- age: days since Auctionator last saw it (nil = no price, or older than Auctionator keeps).
local function itemData(id, api)
  api = api or auctionator()
  local name, _, quality, _, _, _, _, stack, _, _, sell, _, _, bindType = GetInfo(id)
  if not name then RequestItem(id); return nil end
  -- auction price: our own scan first; Auctionator's only when we haven't seen the item, or saw it longer ago
  local ah = apiCall(api, "GetAuctionPriceByItemID", id)
  local age = ah and apiCall(api, "GetAuctionAgeByItemID", id) or nil
  local listed, levels
  local own, ownAge, ownQty, ownLevels
  if ns.Prices then own, ownAge, ownQty, ownLevels = ns.Prices.lookup(id) end
  if own and (not ah or age == nil or ownAge <= age) then ah, age, listed, levels = own, ownAge, ownQty, ownLevels end
  local bags = CountItem(id) or 0
  return {
    id = id, name = name, quality = quality or 0, sell = sell or 0,
    vbuy = (ns.Prices and ns.Prices.vendorPrice(id)) or apiCall(api, "GetVendorPriceByItemID", id) or VENDOR_LIST_PRICE[id],
    ah = ah, age = age, listed = listed, levels = levels, bags = bags, total = CountItem(id, true) or bags, stack = stack or 1, bind = bindType or 0,
  }
end

local function num(v)
  if v == nil then return "" end
  if v == math.floor(v) then return tostring(v) end
  return string.format("%.2f", v)
end

local function itemLine(id, api)
  local it = itemData(id, api)
  if not it then return nil end
  return "tc_item=" .. table.concat({
    id, clean(it.name), it.quality, it.sell, num(it.vbuy), num(it.ah), it.age or "",
    it.bags, it.total, it.stack, it.bind,
  }, "^"), (it.ah ~= nil or it.vbuy ~= nil), (it.ah ~= nil) and it.age or 0
end

local function buildExport()
  local c = charData()
  local api = auctionator()
  local t = time()
  local lines = {
    "# Top Ramen Crafting export (format " .. FORMAT .. ")",
    "# Snapshot of your recipes, materials and prices",
  }
  local _, faction = UnitFactionGroup("player")
  lines[#lines + 1] = "tc_meta=" .. table.concat({
    FORMAT, clean(UnitName("player")), clean(GetRealmName and GetRealmName() or ""),
    clean(faction or ""), UnitLevel("player") or 0, t, api and 1 or 0,
  }, "^")

  local current = {}
  for _, s in ipairs(readSkills()) do
    current[s.name] = s
    lines[#lines + 1] = "tc_skill=" .. table.concat({ s.name, s.rank, s.bonus, s.max }, "^")
  end

  local items, notes = {}, {}
  for prof, p in pairs(c.professions) do
    local cur = current[prof]
    lines[#lines + 1] = "tc_prof=" .. table.concat({
      prof, cur and cur.rank or p.rank or 0, cur and cur.max or p.max or 0,
      p.scannedAt or 0, p.scannedRank or 0, p.incomplete and 1 or 0,
    }, "^")
    if cur and (p.scannedRank or 0) < cur.rank then
      notes[#notes + 1] = prof .. " recipes were read at skill " .. (p.scannedRank or 0) .. " (now " .. cur.rank ..
        "). Open your " .. prof .. " window to refresh recipe colors, then export again."
    end
    for _, r in pairs(p.recipes or {}) do
      local parts = {}
      for _, rg in ipairs(r.reagents or {}) do
        parts[#parts + 1] = rg.id .. ":" .. rg.n
        if rg.id > 0 then items[rg.id] = true end
      end
      if (r.out or 0) > 0 then items[r.out] = true end
      lines[#lines + 1] = "tc_recipe=" .. table.concat({
        prof, r.name, r.diff or "", r.out or 0, r.min or 1, r.max or 1, table.concat(parts, ","),
      }, "^")
    end
  end
  local NO_RECIPES = { Skinning = true, Herbalism = true, Fishing = true }
  for name in pairs(current) do
    if not c.professions[name] and not NO_RECIPES[name] then
      notes[#notes + 1] = "Open your " .. name .. " window once so its recipes are recorded."
    end
  end

  local missing, priced, oldPrices, count = 0, 0, 0, 0
  for id in pairs(items) do
    local line, hasAH, age = itemLine(id, api)
    if line then
      lines[#lines + 1] = line
      count = count + 1
      if hasAH then priced = priced + 1 end
      if hasAH and (age == nil or age > 1) then oldPrices = oldPrices + 1 end
    else
      missing = missing + 1
    end
  end
  if not api and not (ns.Prices and ns.Prices.statusText()) then
    notes[#notes + 1] = "No auction prices yet: click Full scan in the planner while at the auction house."
  elseif oldPrices > 0 or priced < count then
    notes[#notes + 1] = (count - priced) .. " item(s) have no price at all and " .. oldPrices ..
      " auction price(s) are more than a day old. Click Full scan in the planner at the auction house."
  end
  return table.concat(lines, "\n"), missing, notes
end

---------------------------------------------------------------------------
-- Shopping list import (from the page) -> Auctionator shopping list
---------------------------------------------------------------------------
-- entries: { {name = "Light Leather", qty = 20}, ... }
local function createShoppingList(listName, entries)
  local api = auctionator()
  if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
    say("Auctionator isn't loaded, so the shopping list can't be created.")
    return false
  end
  local terms = {}
  for _, e in ipairs(entries) do
    -- vendor flips carry a price cap, so Auctionator only shows listings that still profit
    local ok, s = pcall(api.ConvertToSearchString, ADDON, { searchString = e.name, isExact = true, quantity = e.qty, maxPrice = e.maxPrice })
    if ok and s then terms[#terms + 1] = s end
  end
  if #terms == 0 then say("There's nothing to buy at the auction house."); return false end
  local ok, err = pcall(api.CreateShoppingList, ADDON, listName, terms)
  if ok then
    say("Created Auctionator shopping list \"" .. listName .. "\" with " .. #terms ..
      " items. At the auction house, open Auctionator's Shopping tab and search the list.")
  else
    say("Couldn't create the shopping list: " .. tostring(err))
  end
  return ok
end


---------------------------------------------------------------------------
-- Window (copy out, or paste in)
---------------------------------------------------------------------------
local frame
local function showWindow(title, text, onAccept)
  if not frame then
    frame = CreateFrame("Frame", "TopRamenCraftFrame", UIParent, "BackdropTemplate")
    frame:SetSize(640, 440)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", 0, -18)

    local scroll = CreateFrame("ScrollFrame", "TopRamenCraftScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 22, -44)
    scroll:SetPoint("BOTTOMRIGHT", -42, 52)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(560)
    edit:SetAutoFocus(true)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(edit)
    frame.edit = edit

    frame.accept = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.accept:SetSize(200, 24)
    frame.accept:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -6, 18)
    frame.accept:SetText("Create Auctionator list")

    frame.close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.close:SetSize(110, 24)
    frame.close:SetText(CLOSE or "Close")
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    tinsert(UISpecialFrames, "TopRamenCraftFrame")
  end
  frame.title:SetText(title)
  frame.edit:SetText(text or "")
  frame.close:ClearAllPoints()
  if onAccept then
    frame.accept:Show()
    frame.accept:SetScript("OnClick", function() onAccept(frame.edit:GetText()); frame:Hide() end)
    frame.close:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 6, 18)
  else
    frame.accept:Hide()
    frame.close:SetPoint("BOTTOM", 0, 18)
  end
  frame:Show()
  frame.edit:SetFocus()
  if text and text ~= "" then frame.edit:HighlightText() end
end

local function runExport(attempt)
  pcall(scanTradeSkill) -- pick up an open profession window right now
  pcall(scanCraft)
  local ok, text, missing, notes = pcall(buildExport)
  if not ok then say("export failed: " .. tostring(text)); return end
  if missing > 0 and attempt < 4 and C_Timer then
    say("loading " .. missing .. " item(s) from the server, one moment...")
    C_Timer.After(2, function() runExport(attempt + 1) end)
    return
  end
  showWindow("Top Ramen crafting snapshot: press Ctrl+C to copy it", text)
  say("crafting snapshot ready. Press Ctrl+C to copy it.")
  for _, n in ipairs(notes) do say(n) end
  if missing > 0 then say(missing .. " item(s) still weren't loaded. Run /topramencraft export again to include them.") end
end

---------------------------------------------------------------------------
-- Events and slash commands
---------------------------------------------------------------------------
local function ensureDB()
  if db then return end
  TopRamenCraftDB = TopRamenCraftDB or {}
  db = TopRamenCraftDB
  charKey = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
  for _, c in pairs(db.chars or {}) do
    for name in pairs(IGNORED_PROFESSIONS) do if c.professions then c.professions[name] = nil end end
  end
end

ns.readGuildDirectory = function(quiet) ensureDB(); return readGuildDirectory(quiet) end

local SCANS = {
  TRADE_SKILL_SHOW = scanTradeSkill, TRADE_SKILL_UPDATE = scanTradeSkill,
  TRADE_SKILL_LIST_UPDATE = scanTradeSkill, TRADE_SKILL_DATA_SOURCE_CHANGED = scanTradeSkill, CRAFT_SHOW = scanCraft, CRAFT_UPDATE = scanCraft,
}
local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "ADDON_LOADED")
pcall(events.RegisterEvent, events, "PLAYER_LOGIN")
for e in pairs(SCANS) do pcall(events.RegisterEvent, events, e) end -- a missing event is skipped, not fatal
for _, e in ipairs(CHAT_EVENTS) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event:find("^CHAT_MSG_") then pcall(saveChatLinks, arg1, arg2); return end
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then ensureDB() end
    return
  end
  if event == "PLAYER_LOGIN" then ensureDB(); return end
  if db and SCANS[event] then schedule(SCANS[event]) end
end)

local function craftCommand(msg)
  ensureDB()
  local cmd = (msg or ""):lower():match("^%s*(%S*)")
  if cmd == "ids" then
    -- /trc ids: group guildmates by the server number in their character ID, with what the game reports for each
    local mine = UnitGUID and UnitGUID("player") or "?"
    local realmID = GetRealmID and GetRealmID()
    say("you: " .. mine .. "; realm " .. tostring(GetRealmName and GetRealmName()) .. " (" .. tostring(GetNormalizedRealmName and GetNormalizedRealmName()) ..
      "), realm ID " .. tostring(realmID))
    local groups, order = {}, {}
    for name, guid in pairs(knownGUIDs()) do
      local num = guid:match("^Player%-(%d+)%-") or "?"
      if not groups[num] then groups[num] = { n = 0, sample = name, guid = guid }; order[#order + 1] = num end
      groups[num].n = groups[num].n + 1
    end
    table.sort(order, function(a, b) return groups[a].n > groups[b].n end)
    for _, num in ipairs(order) do
      local g = groups[num]
      local realm = "?"
      if GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, nm, rn = pcall(GetPlayerInfoByGUID, g.guid)
        if ok and nm and nm ~= "" then realm = (rn == nil or rn == "") and "same realm as you (named)" or tostring(rn)
        elseif ok then realm = "not known yet (the game hasn't loaded this character)" end
      end
      say(("  %s: %d guildmates, e.g. %s; game says: %s"):format(num, g.n, g.sample, realm))
    end
    return true
  elseif cmd == "openlink" then
    -- /trc openlink trade:Player-6933-00376EC7:7413:333 : open any profession link as typed, and report whose window shows
    local link = (msg or ""):match("(trade:[^%s|]+)")
    if not link then say("type /trc openlink trade:Player-<number>-<id>:<spell>:<skill line>"); return true end
    local T = C_TradeSkillUI
    local before
    if T and T.IsTradeSkillLinked then local l, n = T.IsTradeSkillLinked(); before = l and n or nil end
    if T and T.CloseTradeSkill then pcall(T.CloseTradeSkill) end
    if ProfessionsFrame and ProfessionsFrame:IsShown() then pcall(HideUIPanel, ProfessionsFrame) end
    say("opening " .. link .. "...")
    local function open() if SetItemRef then pcall(SetItemRef, link, "|cffffd000|H" .. link .. "|h[Profession]|h|r", "LeftButton") end end
    local function check()
      local linked, name = false, nil
      if T and T.IsTradeSkillLinked then linked, name = T.IsTradeSkillLinked() end
      if linked and name and name ~= before then say("it opened: " .. tostring(name) .. "'s window is showing.")
      elseif linked then say("it didn't open: the window still shows " .. tostring(name) .. "'s profession from before.")
      else say("it didn't open.") end
    end
    if C_Timer then C_Timer.After(0.5, open); C_Timer.After(3.5, check) else open(); check() end
    return true
  elseif cmd == "build" then
    -- /trc build <name> <profession>: build the link from the guild roster even if one is saved, showing each try
    local rest = (msg or ""):match("^%s*%S+%s+(.+)$") or ""
    local who, prof = rest:match("^(.-)%s+(%S+)$")
    if prof and who and who:lower():match("first$") and prof:lower() == "aid" then who, prof = who:sub(1, -7), "First Aid" end
    if not who or who == "" then
      -- no name: list online guildmates on your own realm, with their professions, to test with
      local mine = UnitGUID and (UnitGUID("player") or ""):match("^Player%-(%d+)%-")
      local guids, on = knownGUIDs(), {}
      if GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, (GetNumGuildMembers() or 0) do
          local ok, name, _, _, _, _, _, _, _, online = pcall(GetGuildRosterInfo, i)
          if ok and name and online then on[clean(shortName(name))] = true end
        end
      end
      local profsOf = {}
      for prof, list in pairs((db.guildDir and db.guildDir.profs) or {}) do
        for _, m in ipairs(list) do profsOf[m.name] = profsOf[m.name] or {}; table.insert(profsOf[m.name], prof) end
      end
      local same, other = {}, 0
      for name in pairs(on) do
        local g = guids[name]
        local realm = g and g:match("^Player%-(%d+)%-")
        if profsOf[name] and g ~= (UnitGUID and UnitGUID("player")) then
          if realm == mine then same[#same + 1] = name .. " (" .. table.concat(profsOf[name], ", ") .. ")" else other = other + 1 end
        end
      end
      table.sort(same)
      say("your server number: " .. tostring(mine) .. ". Online guildmates with the same number: " .. (#same > 0 and table.concat(same, "; ") or "none") ..
        ". Online with a different number: " .. other .. ".")
      say("type /trc build <name> <profession>, e.g. /trc build Honkytonk Man Engineering")
      return true
    end
    prof = prof:sub(1, 1):upper() .. prof:sub(2):lower()
    local found
    for name in pairs(knownGUIDs()) do if name:lower() == who:lower() then found = name end end
    if not found then
      for name in pairs(db.guids) do if name:lower():find(who:lower(), 1, true) then found = found and found or name end end
    end
    if not found then say("no character ID for \"" .. who .. "\" in the guild roster."); return true end
    local saved = db.links and db.links[found] and db.links[found][prof]
    say("roster character ID for " .. found .. ": " .. tostring(db.guids[found]) .. (saved and ("; saved link: " .. saved.link) or ""))
    openBuiltLink(found, prof, true)
    return true
  elseif cmd == "relink" then
    -- /trc relink <name> <profession>: reopen a profession link saved from chat
    local rest = (msg or ""):match("^%s*%S+%s+(.+)$") or ""
    local who, prof
    for _, p in ipairs({ "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Mining",
                         "Herbalism", "Skinning", "First Aid", "Cooking", "Fishing", "Jewelcrafting", "Inscription" }) do
      local w = rest:lower():match("^(.-)%s+" .. p:lower():gsub(" ", "%%s+") .. "%s*$")
      if w and w ~= "" then who, prof = rest:sub(1, #w), p end
    end
    if not who then
      -- allow a misspelled profession: compare the last word (or two) with each profession name
      local function dist(x, y)
        local prev = {}
        for j = 0, #y do prev[j] = j end
        for i = 1, #x do
          local cur = { [0] = i }
          for j = 1, #y do cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + ((x:sub(i, i) == y:sub(j, j)) and 0 or 1)) end
          prev = cur
        end
        return prev[#y]
      end
      for _, p in ipairs({ "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Mining",
                           "Herbalism", "Skinning", "First Aid", "Cooking", "Fishing", "Jewelcrafting", "Inscription" }) do
        local words = p:find(" ") and 2 or 1
        local head, tail = rest:match("^(.-)%s+(%S+)%s*$")
        if words == 2 and head then
          local h2, t2 = head:match("^(.-)%s+(%S+)$")
          if h2 then head, tail = h2, t2 .. " " .. tail end
        end
        if head and head ~= "" and tail and dist(tail:lower(), p:lower()) <= 2 then who, prof = head, p end
      end
    end
    if not who then
      local list = {}
      for name, profs in pairs(db.links or {}) do for p in pairs(profs) do list[#list + 1] = name .. " " .. p end end
      table.sort(list)
      say("type /trc relink <name> <profession>. Saved links: " .. (#list > 0 and table.concat(list, ", ") or "none yet"))
      return true
    end
    -- find the saved name: exact (any capitals), then part of a name, then a close spelling, if only one fits
    local function distance(x, y)
      local prev = {}
      for j = 0, #y do prev[j] = j end
      for i = 1, #x do
        local cur = { [0] = i }
        for j = 1, #y do
          cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + ((x:sub(i, i) == y:sub(j, j)) and 0 or 1))
        end
        prev = cur
      end
      return prev[#y]
    end
    local typed, exact, partial, close = who:lower(), nil, {}, {}
    local pool = {}
    for name in pairs(db.links or {}) do pool[name] = true end
    for name in pairs(knownGUIDs()) do pool[name] = true end
    for name in pairs(pool) do
      local n = name:lower()
      if n == typed then exact = name
      elseif n:find(typed, 1, true) then partial[#partial + 1] = name
      elseif distance(n, typed) <= 2 or distance(n:match("^%S+") or n, typed) <= 2 then close[#close + 1] = name end
    end
    if exact then who = exact
    elseif #partial == 1 then who = partial[1]
    elseif #partial == 0 and #close == 1 then who = close[1]
    elseif #partial + #close > 1 then
      local all = {}
      for _, x in ipairs(partial) do all[#all + 1] = x end
      for _, x in ipairs(close) do all[#all + 1] = x end
      say("more than one name fits \"" .. who .. "\": " .. table.concat(all, ", ") .. ". Type more of the name.")
      return true
    end
    local e = db.links and db.links[who] and db.links[who][prof]
    if isOnlineNow(who) == false then say(who .. OFFLINE_MSG); return true end
    if not e then
      if not openBuiltLink(who, prof) then say("no saved " .. prof .. " link from " .. who .. " yet. It's saved the next time they link it in chat.") end
      return true
    end
    say("opening " .. who .. "'s " .. prof .. " link from " .. date("%b %d %I:%M %p", e.seen):gsub(" 0", " ") .. "...")
    local rosterID = knownGUIDs()[who]
    local linkID = e.link:match("^trade:(Player%-[^:]+)")
    say("  saved link: " .. e.link .. (e.built and " (built)" or " (from chat)") ..
      (rosterID and ("; roster character ID: " .. rosterID .. (rosterID == linkID and " (same)" or " (DIFFERENT)")) or ""))
    openSavedLink(who, prof)
    if C_Timer then
      C_Timer.After(3, function()
        local T = C_TradeSkillUI
        local linked, linkedName = false, nil
        if T and T.IsTradeSkillLinked then linked, linkedName = T.IsTradeSkillLinked() end
        if linked and linkedName and clean(shortName(linkedName)):lower() == who:lower() then
          say("it opened: " .. who .. "'s " .. prof .. " is showing.")
        elseif linked then
          say("it didn't open: the window still shows " .. tostring(linkedName) .. "'s profession from before.")
        else
          say("it didn't open. They may need to be online.")
        end
      end)
    end
    return true
  elseif cmd == "linked" then
    -- /trc linked: with someone's linked profession window open, report what the addon can read from it
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs) then say("no profession API."); return true end
    local isLinked, linkedName = false, nil
    if T.IsTradeSkillLinked then isLinked, linkedName = T.IsTradeSkillLinked() end
    local ids = T.GetAllRecipeIDs() or {}
    local learned, sample, first = 0, {}, nil
    for _, id in ipairs(ids) do
      local info = T.GetRecipeInfo(id)
      if info and info.learned then learned = learned + 1; first = first or id; if #sample < 5 then sample[#sample + 1] = info.name end end
    end
    local prof, rank, maxRank, sources = otherProfession(first)
    say("profession found via: " .. (sources ~= "" and sources or "nothing"))
    say("linked window: " .. tostring(isLinked) .. ", whose: " .. tostring(linkedName) ..
      ", guild member window: " .. tostring(T.IsTradeSkillGuildMember and T.IsTradeSkillGuildMember() or false))
    say("profession: " .. tostring(prof) .. " " .. tostring(rank) .. "/" .. tostring(maxRank) ..
      ", recipes listed: " .. #ids .. ", learned: " .. learned)
    if #sample > 0 then say("  e.g. " .. table.concat(sample, ", ")) end
    if not isLinked then say("this looks like your own profession. Click someone's profession link in chat first, then /trc linked.")
    elseif db.guild and linkedName and db.guild[clean(linkedName)] then
      local list = {}
      for p, e in pairs(db.guild[clean(linkedName)]) do list[#list + 1] = p .. " (" .. e.count .. ")" end
      say("saved for " .. linkedName .. ": " .. table.concat(list, ", "))
    end
    return true
  elseif cmd == "ah" then
    -- /trc ah: which auction house system this game uses, and whether a test search works. Read-only.
    local A = C_AuctionHouse
    local legacy = QueryAuctionItems ~= nil and GetAuctionItemInfo ~= nil
    local modern = A ~= nil and A.SendSearchQuery ~= nil
    local legacyOpen = AuctionFrame and AuctionFrame:IsShown()
    local modernOpen = AuctionHouseFrame and AuctionHouseFrame:IsShown()
    say("classic auction house functions: " .. tostring(legacy) .. ", modern ones: " .. tostring(modern))
    say("auction house open: " .. tostring((legacyOpen or modernOpen) and true or false) ..
      " (classic window: " .. tostring(legacyOpen and true or false) .. ", modern window: " .. tostring(modernOpen and true or false) .. ")")
    if legacy then
      local ok, canQuery, canQueryAll = pcall(CanSendAuctionQuery)
      say("classic: can search now: " .. tostring(ok and canQuery) .. ", full scan allowed now: " .. tostring(ok and canQueryAll) ..
        ", buy function: " .. tostring(PlaceAuctionBid ~= nil))
    end
    if modern then
      local names = {}
      for _, k in ipairs({ "ReplicateItems", "GetNumReplicateItems", "SendBrowseQuery", "SendSearchQuery",
                           "GetCommoditySearchResultInfo", "GetItemSearchResultInfo", "StartCommoditiesPurchase", "PlaceBid" }) do
        names[#names + 1] = k .. "=" .. tostring(A[k] ~= nil)
      end
      say("modern: " .. table.concat(names, ", "))
    end
    if not (legacyOpen or modernOpen) then say("open the auction house, then run /trc ah again for a test search."); return true end

    local ITEM, NAME = 2318, "Light Leather"
    local listener = CreateFrame("Frame")
    local function finish(text) listener:UnregisterAllEvents(); listener:SetScript("OnEvent", nil); say(text) end
    if legacyOpen and legacy then
      listener:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
      listener:SetScript("OnEvent", function()
        local batch, total = GetNumAuctionItems("list")
        local cheapest, listings, units = nil, 0, 0
        for i = 1, batch or 0 do
          local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
          if (itemID == ITEM or name == NAME) and (buyout or 0) > 0 and (count or 0) > 0 then
            listings, units = listings + 1, units + count
            local each = buyout / count
            if not cheapest or each < cheapest then cheapest = each end
          end
        end
        finish("test search for " .. NAME .. ": " .. tostring(total) .. " result(s), " .. listings .. " with a buyout on this page, " ..
          units .. " units, cheapest " .. (cheapest and (math.floor(cheapest + 0.5) .. "c each") or "n/a") ..
          ". (item ID from the listing: " .. tostring(select(17, GetAuctionItemInfo("list", 1))) .. ")")
      end)
      local ok, err = pcall(QueryAuctionItems, NAME, nil, nil, 0, false, nil, false, true)
      if not ok then finish("classic search failed: " .. tostring(err)) else say("searching for " .. NAME .. "...") end
    elseif modernOpen and modern then
      for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED" }) do pcall(listener.RegisterEvent, listener, e) end
      listener:SetScript("OnEvent", function(_, e)
        local n = A.GetNumCommoditySearchResults and A.GetNumCommoditySearchResults(ITEM) or 0
        local first = n > 0 and A.GetCommoditySearchResultInfo(ITEM, 1)
        finish("test search for " .. NAME .. " (" .. e .. "): " .. n .. " price level(s), cheapest " ..
          (first and (tostring(first.unitPrice) .. "c each, " .. tostring(first.quantity) .. " available") or "n/a"))
      end)
      local ok, err = pcall(function() A.SendSearchQuery(A.MakeItemKey(ITEM), {}, true) end)
      if not ok then finish("modern search failed: " .. tostring(err)) else say("searching for " .. NAME .. "...") end
    end
    if C_Timer then C_Timer.After(8, function() if listener:GetScript("OnEvent") then finish("no search results after 8 seconds.") end end) end
    return true
  elseif cmd == "guild" then
    local G = C_GuildInfo
    local T = C_TradeSkillUI
    local args = (msg or ""):match("^%s*%S+%s*(.*)$") or ""

    -- /trc guild view <full name> <profession>: open one guildmate's recipe list and see if we can read it.
    -- Names can have spaces, so the profession is matched at the end of the line.
    local SKILL_IDS = { Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202, Leatherworking = 165,
      Tailoring = 197, Mining = 186, Herbalism = 182, Skinning = 393, ["First Aid"] = 129, Cooking = 185, Fishing = 356 }
    local viewArgs = args:match("^view%s+(.+)$")
    if viewArgs then
      local who, prof
      for name in pairs(SKILL_IDS) do
        local w = viewArgs:match("^(.-)%s+" .. name:gsub(" ", "%%s+") .. "%s*$")
        if w and w ~= "" then who, prof = w, name end
        if not w then
          w = viewArgs:lower():match("^(.-)%s+" .. name:lower():gsub(" ", "%%s+") .. "%s*$")
          if w and w ~= "" then who, prof = viewArgs:sub(1, #w), name end
        end
      end
      if not who then say("type /trc guild view <name> <profession>, e.g. /trc guild view Kluya Heiral Tailoring"); return true end
      local skillID = SKILL_IDS[prof]
      local fn = (G and G.GetGuildMemberRecipes) or GetGuildMemberRecipes or (T and T.GetGuildMemberRecipes)
      say("GetGuildMemberRecipes available: " .. tostring(fn ~= nil))
      if not fn then return true end
      -- Use the exact name strings the game's guild profession list gives for this person (name, and
      -- name-with-realm), the way Blizzard's own guild window does; then the name as typed.
      local tries, seen = {}, {}
      local function add(x) if x and x ~= "" and not seen[x] then seen[x] = true; tries[#tries + 1] = x end end
      if GetNumGuildTradeSkill and GetGuildTradeSkillInfo then
        if ExpandGuildTradeSkillHeader then pcall(ExpandGuildTradeSkillHeader, skillID) end
        local wanted = who:lower()
        for i = 1, (GetNumGuildTradeSkill() or 0) do
          local ok, _, _, _, _, _, _, _, playerName, fullName = pcall(GetGuildTradeSkillInfo, i)
          if ok and playerName and (playerName:lower() == wanted or (fullName and fullName:lower():find(wanted, 1, true) == 1)) then
            add(fullName); add(playerName)
            say("found in the guild list as \"" .. tostring(playerName) .. "\" / \"" .. tostring(fullName) .. "\"")
          end
        end
      end
      add(who)
      local first, rest = who:match("^(%S+)%s+(.+)$")
      if first then add(first); add(first .. "-" .. rest:gsub("%s+", "")) end

      -- watch for the profession window opening with their recipes
      local opened = false
      local watch = CreateFrame("Frame")
      for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_LIST_UPDATE" }) do pcall(watch.RegisterEvent, watch, e) end
      watch:SetScript("OnEvent", function(_, e)
        local gm = T and T.IsTradeSkillGuildMember and T.IsTradeSkillGuildMember()
        if gm then opened = true end
      end)
      local attempt
      attempt = function(i)
        local name = tries[i]
        if not name then
          watch:UnregisterAllEvents()
          say("none of those opened " .. who .. "'s " .. prof .. ". Try it by hand: Guild window > Professions > " .. prof ..
            " > click " .. who .. " > View Recipes, and tell me if that works.")
          return
        end
        local ok, err = pcall(fn, name, skillID)
        say("asked for \"" .. name .. "\"'s " .. prof .. ": " .. (ok and "ok" or ("error " .. tostring(err))) .. "...")
        local waited = 0
        local function check2()
          waited = waited + 0.5
          local guildMember = opened or (T and T.IsTradeSkillGuildMember and T.IsTradeSkillGuildMember())
          if not guildMember and waited < 5 then if C_Timer then C_Timer.After(0.5, check2) end; return end
          if not guildMember then attempt(i + 1); return end
          watch:UnregisterAllEvents()
          local ids = T and T.GetAllRecipeIDs and T.GetAllRecipeIDs() or {}
          local learned, sample = 0, {}
          for _, id in ipairs(ids) do
            local info = T.GetRecipeInfo(id)
            if info and info.learned then learned = learned + 1; if #sample < 4 then sample[#sample + 1] = info.name end end
          end
          say("it worked with \"" .. name .. "\": showing a guildmate's recipes, " .. learned .. " learned of " .. #ids .. " listed.")
          if #sample > 0 then say("  e.g. " .. table.concat(sample, ", ")) end
        end
        if C_Timer then C_Timer.After(0.5, check2) else check2() end
      end
      attempt(1)
      return true
    end

    -- /trc guild: what's available, then every profession with its members (headers expanded)
    local function has(name, tbl) return (tbl or _G)[name] ~= nil end
    say("in a guild: " .. tostring(IsInGuild and IsInGuild() or false) .. ", members: " .. tostring(GetNumGuildMembers and GetNumGuildMembers() or 0))
    say("member recipes (GetGuildMemberRecipes): " .. tostring(has("GetGuildMemberRecipes") or (G ~= nil and has("GetGuildMemberRecipes", G))) ..
      ", recipe lookup (QueryGuildMembersForRecipe): " .. tostring(G ~= nil and has("QueryGuildMembersForRecipe", G)) ..
      ", expand headers: " .. tostring(has("ExpandGuildTradeSkillHeader")) ..
      ", addon messages: " .. tostring(C_ChatInfo ~= nil and has("SendAddonMessage", C_ChatInfo)))
    if not (IsInGuild and IsInGuild()) then return true end
    if not GetNumGuildTradeSkill then say("no guild profession list in this version."); return true end
    -- the profession list follows the guild roster's "show offline members" setting: turn it on while we read
    local getOff = GetGuildRosterShowOffline or (G and G.GetGuildRosterShowOffline)
    local setOff = SetGuildRosterShowOffline or (G and G.SetGuildRosterShowOffline)
    local wasOffline = getOff and getOff()
    say("show offline members: was " .. tostring(wasOffline) .. ", can change it: " .. tostring(setOff ~= nil))
    if setOff then pcall(setOff, true) end
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
    if QueryGuildRecipes then pcall(QueryGuildRecipes) end
    say("reading the guild profession list in 3 seconds...")
    local report = function()
      -- expand every profession header so members are listed
      -- (expanding a header inserts its members below it, so re-check the length as we go)
      if ExpandGuildTradeSkillHeader then
        local i = 1
        while i <= (GetNumGuildTradeSkill() or 0) and i < 2000 do
          local ok, skillID, collapsed, _, header = pcall(GetGuildTradeSkillInfo, i)
          if ok and header and collapsed then pcall(ExpandGuildTradeSkillHeader, skillID) end
          i = i + 1
        end
      end
      local n = GetNumGuildTradeSkill() or 0
      -- fields: skillID, collapsed, icon, header, numOnline, numVisible, numPlayers,
      --         playerName, playerNameWithRealm, class, online, zone, skill
      local current, count, listed, totals = nil, 0, {}, ""
      local function flush()
        if current then
          say(current .. " " .. totals .. ": " .. count .. " listed" ..
            (#listed > 0 and (" (" .. table.concat(listed, ", ") .. (count > #listed and ", ..." or "") .. ")") or ""))
        end
      end
      local dumped = false
      for i = 1, n do
        if not dumped then
          local vals = { pcall(GetGuildTradeSkillInfo, i) }
          if vals[1] and vals[9] then -- a member row (has a player name)
            local parts = {}
            for k = 2, #vals do parts[#parts + 1] = (k - 1) .. "=" .. tostring(vals[k]) end
            say("raw member fields: " .. table.concat(parts, ", "))
            dumped = true
          end
        end
        local ok, _, _, _, header, numOnline, numVisible, numPlayers, playerName, _, _, online, _, skill = pcall(GetGuildTradeSkillInfo, i)
        if ok and header and header:find("DNT") then
          flush(); current = nil -- developer test entry
        elseif ok and header then
          flush()
          current, count, listed = header, 0, {}
          totals = "[" .. tostring(numOnline) .. " online, " .. tostring(numVisible) .. " shown, " .. tostring(numPlayers) .. " total]"
        elseif ok and playerName then
          count = count + 1
          if #listed < 3 then listed[#listed + 1] = playerName .. " " .. tostring(skill) .. (online and "" or " (offline)") end
        end
      end
      flush()
      if setOff and wasOffline ~= nil then pcall(setOff, wasOffline) end -- put your setting back
      say("rows: " .. n .. ". Next: /trc guild view <name> <profession> with one of those names.")
    end
    if C_Timer then C_Timer.After(3, report) else report() end
    return true
  elseif cmd == "inspect" then
    -- /trc inspect <recipe name>: print every field the game returns for one recipe (profession window must be open)
    local want = ((msg or ""):match("^%s*%S+%s+(.+)$") or ""):lower()
    local T = C_TradeSkillUI
    if want == "" or not (T and T.GetAllRecipeIDs) then
      say("Open a profession window, then type /trc inspect <recipe name>, e.g. /trc inspect Hillman's Shoulders")
      return true
    end
    local function dump(label, t, depth)
      if type(t) ~= "table" then say(label .. " = " .. tostring(t)); return end
      for k, v in pairs(t) do
        if type(v) == "table" and depth < 2 then dump(label .. "." .. tostring(k), v, depth + 1)
        elseif type(v) ~= "table" then say(label .. "." .. tostring(k) .. " = " .. tostring(v)) end
      end
    end
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
      local info = T.GetRecipeInfo(id)
      if info and info.name and info.name:lower() == want then
        say("recipe " .. id .. ": " .. info.name)
        dump("info", info, 0)
        for _, fn in ipairs({ "GetRecipeSkillLineAbility", "GetRecipeRequirements", "GetRecipeDescription", "GetRecipeExperienceInfo" }) do
          if T[fn] then local ok, v = pcall(T[fn], id); if ok and v ~= nil then dump(fn, v, 0) end end
        end
        local names = {}
        for k in pairs(T) do names[#names + 1] = k end
        table.sort(names)
        say("C_TradeSkillUI functions: " .. table.concat(names, ", "))
        return true
      end
    end
    say("No learned recipe called \"" .. want .. "\" in the open profession window.")
    return true
  elseif cmd == "debug" then
    local T = C_TradeSkillUI
    say("modern API: " .. tostring(T ~= nil) .. ", GetAllRecipeIDs: " .. tostring(T and T.GetAllRecipeIDs ~= nil) ..
      ", classic API: " .. tostring(GetTradeSkillLine ~= nil) .. ", Auctionator: " .. tostring(auctionator() ~= nil) ..
      ", OpenTradeSkill: " .. tostring(T and T.OpenTradeSkill ~= nil))
    if T and T.GetAllRecipeIDs then
      local ok, prof, rank, mx = pcall(modernProfession)
      local ids = T.GetAllRecipeIDs() or {}
      local learned = 0
      for _, id in ipairs(ids) do local i = T.GetRecipeInfo(id); if i and i.learned then learned = learned + 1 end end
      say("open profession: " .. tostring(ok and prof) .. " " .. tostring(rank) .. "/" .. tostring(mx) ..
        ", recipes listed: " .. #ids .. ", learned: " .. learned)
    end
    local n = 0
    for name, p in pairs(charData().professions) do
      local c = 0; for _ in pairs(p.recipes or {}) do c = c + 1 end
      say("recorded: " .. name .. " (" .. c .. " recipes, read at skill " .. tostring(p.scannedRank) .. ")"); n = n + 1
    end
    if n == 0 then say("no professions recorded yet") end
    return true
  elseif cmd == "export" or cmd == "craft" then
    runExport(1)
    return true
  elseif cmd == "opacity" then
    if ns.SetOpacity then ns.SetOpacity((msg or ""):match("opacity%s+(%d+)")) end
    return true
  elseif cmd == "reset" then
    if ns.ResetWindow then ns.ResetWindow() end
    return true
  end
end

SLASH_TOPRAMENCRAFT1 = "/topramencraft"
SLASH_TOPRAMENCRAFT2 = "/trc"
SlashCmdList.TOPRAMENCRAFT = function(msg)
  if craftCommand(msg) then return end
  if ns.ToggleWindow then ns.ToggleWindow() else runExport(1) end
end

-- shared with the planner and the window
ns.ADDON = ADDON
ns.say = say
ns.clean = clean
ns.charData = function() ensureDB(); return charData() end
ns.db = function() ensureDB(); return db end
ns.readSkills = readSkills
ns.itemData = itemData
ns.auctionator = auctionator
ns.createShoppingList = createShoppingList
ns.runExport = function() runExport(1) end
ns.IGNORED_PROFESSIONS = IGNORED_PROFESSIONS
ns.VENDOR_LIST_PRICE = VENDOR_LIST_PRICE
ns.scanOpen = function() pcall(scanTradeSkill); pcall(scanCraft) end
-- mark every recorded profession as needing its window opened again (the Refresh button)
ns.markAllStale = function()
  for _, p in pairs(ns.charData().professions) do p.needsOpen = true end
end
