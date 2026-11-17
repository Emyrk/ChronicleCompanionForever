local ADDON_NAME, addon = ...
local frame = CreateFrame("Frame")
local roster = { members = {}, units = {} }
addon.ScoutingRoster = roster
local function call(name, ...)
	if type(_G[name]) ~= "function" then return nil end
	local ok, a, b = pcall(_G[name], ...)
	-- pcall catches API errors, but successful calls can still return secret
	-- values. Never let those reach comparisons, concatenation or table keys.
	if ok then
		if type(issecretvalue) == "function" and (issecretvalue(a) or issecretvalue(b)) then return nil end
		return a, b
	end
end
roster.Call = call
local function now() return call("time") end
local function report(message)
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Chronicle: " .. message) end
end
function roster:Read(unit)
	if call("UnitIsPlayer", unit) ~= true then return nil end
	local guid = call("UnitGUID", unit)
	local name, realm = call("UnitName", unit)
	if type(guid) ~= "string" or guid == "" or type(name) ~= "string" or name == "" or name == "UNKNOWNOBJECT" then return nil end
	if type(realm) ~= "string" or realm == "" then realm = call("GetRealmName") end
	if type(realm) ~= "string" or realm == "" then return nil end
	local level = call("UnitLevel", unit)
	if type(level) ~= "number" or level <= 0 then level = false end
	local guild = call("GetGuildInfo", unit)
	if type(guild) ~= "string" or guild == "_" then guild = false end
	-- Nil GetGuildInfo is ambiguous for remote units. Only IsInGuild for the
	-- local player can confirm guildless without inventing remote knowledge.
	if guild == false and call("UnitIsUnit", unit, "player") == true and call("IsInGuild") == false then guild = "" end
	return { guid = guid, name = name .. "-" .. realm, level = level, guild = guild, unit = unit, grouped = true }
end
local function count(v, max)
	return type(v) == "number" and v >= 0 and v <= max and v == math.floor(v)
end
function roster:Snapshot()
	local raid = call("IsInRaid")
	local n, units = nil, {}
	if raid == true then
		n = call("GetNumGroupMembers")
		if not count(n, 40) or n == 0 then return nil end
		for i = 1, n do units[#units + 1] = "raid" .. i end
	elseif raid == false then
		n = call("GetNumSubgroupMembers")
		if not count(n, 4) then return nil end
		if n > 0 then
			units[1] = "player"
			for i = 1, n do units[#units + 1] = "party" .. i end
		end
	else
		-- Older clients expose separate party and raid counters.
		local r, p = call("GetNumRaidMembers"), call("GetNumPartyMembers")
		if not count(r, 40) or not count(p, 4) then return nil end
		if r > 0 then for i = 1, r do units[#units + 1] = "raid" .. i end
		elseif p > 0 then
			units[1] = "player"
			for i = 1, p do units[#units + 1] = "party" .. i end
		end
	end
	local members, complete = {}, true
	for _, unit in ipairs(units) do
		local observation = self:Read(unit)
		if observation then members[observation.guid] = observation else complete = false end
	end
	return members, complete
end
function roster:Reconcile()
	local store = self.store
	if not store then return end
	if not store:Enabled() then
		self.members, self.units, self.complete = {}, {}, false
		store:SetCurrent({})
		return
	end
	local snapshot, complete = self:Snapshot()
	if not snapshot then self.complete = false; return end
	local current = {}
	if not complete then for guid in pairs(self.members) do current[guid] = true end end
	for guid in pairs(snapshot) do current[guid] = true end
	store:SetCurrent(current) -- protect the entire roster before admissions
	local at = now()
	if complete then
		for guid in pairs(self.members) do if not current[guid] then store:Leave(guid, at); self.units[guid] = nil end end
	end
	for guid, o in pairs(snapshot) do
		store:Observe(guid, o.name, o.level, o.guild, true, at, not self.members[guid])
		self.units[guid] = o.unit
	end
	self.members, self.complete = current, complete
end
function roster:Refresh(guid)
	local unit = self.units[guid]
	local o = unit and self:Read(unit)
	if o and o.guid == guid and self.members[guid] then return o end
end
function roster:Load()
	if type(ChronicleCompanionForeverDB) ~= "table" then return end
	self.store = addon.ScoutingStorage.New(ChronicleCompanionForeverDB, report)
	self:Reconcile()
end
frame:RegisterEvent("ADDON_LOADED")
-- RegisterEvent can reject an event absent on older clients. Unsupported
-- events remain an on-client validation item, not a reason to break logging.
for _, event in ipairs({"PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "UNIT_LEVEL", "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "PLAYER_GUILD_UPDATE", "UNIT_GUILD_UPDATE"}) do
	pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name == ADDON_NAME then roster:Load() end
	else roster:Reconcile() end
end)
local elapsed = 0
frame:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 10 then return end
	elapsed = 0 -- do not catch up with unbounded work after a stalled frame
	if roster.store then
		if not roster.store:Enabled() then roster:Reconcile() end
		roster.store:Collect(now(), 10, function(guid) return roster:Refresh(guid) end)
	end
end)
