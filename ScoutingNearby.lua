local ADDON_NAME, addon = ...
local frame = CreateFrame("Frame")
local roster = addon.ScoutingRoster
local nearby = { byGUID = {}, byUnit = {} }
addon.ScoutingNearby = nearby
function nearby:Enabled()
	return roster.store and roster.store:Enabled() and roster.store.db.scouting_nearby_enabled == true
end
function nearby:Forget(unit)
	local guid = self.byUnit[unit]
	if guid and self.byGUID[guid] == unit then self.byGUID[guid] = nil end
	self.byUnit[unit] = nil
end
function nearby:Read(unit)
	if not self:Enabled() then return nil end
	local o = roster:Read(unit)
	if not o then return nil end
	-- A complete roster and available membership APIs are required to assert
	-- out-of-group membership. Never infer membership from persisted history.
	if type(UnitInParty) ~= "function" or type(UnitInRaid) ~= "function" then return nil end
	local partyOK, party = pcall(UnitInParty, unit)
	local raidOK, raid = pcall(UnitInRaid, unit)
	if not partyOK or not raidOK then return nil end
	-- Secret membership is unknown, not evidence that a unit is ungrouped.
	if type(issecretvalue) == "function" and (issecretvalue(party) or issecretvalue(raid)) then return nil end
	local grouped = (party ~= nil and party ~= false) or (raid ~= nil and raid ~= false)
	if grouped ~= (roster.members[o.guid] == true) then return nil end
	if not grouped and not roster.complete then return nil end
	o.grouped = grouped
	return o
end
function nearby:Observe(unit)
	self:Forget(unit)
	local o = self:Read(unit)
	if not o then return end
	-- Nearby admission always uses free space, even if a group unit is seen
	-- before the roster has admitted it. The roster owns group admission.
	if not roster.store.players[o.guid] and not roster.store:Slot(false, roster.Call("time")) then return end
	if roster.store:Observe(o.guid, o.name, o.level, o.guild, o.grouped, roster.Call("time"), false, o) then
		local old = self.byGUID[o.guid]
		if old then self.byUnit[old] = nil end
		self.byGUID[o.guid], self.byUnit[unit] = unit, o.guid
	end
end
local originalRefresh = roster.Refresh
function roster:Refresh(guid)
	local grouped = originalRefresh(self, guid)
	if grouped then return grouped end
	local unit = nearby.byGUID[guid]
	local o = unit and nearby:Read(unit)
	if o and o.guid == guid then return o end
	if unit then nearby:Forget(unit) end
end
function nearby:Toggle()
	local db = ChronicleCompanionForeverDB
	if type(db) ~= "table" then return end
	db.scouting_nearby_enabled = db.scouting_nearby_enabled ~= true
	self.byGUID, self.byUnit = {}, {}
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("Chronicle: nearby scouting " .. (db.scouting_nearby_enabled and "on" or "off") .. ". Recording also requires Sidekick opt-in.")
	end
	if self:Enabled() then self:Observe("target"); self:Observe("mouseover") end
end
-- Extend the existing /clog and /chronicle router without changing minimap behavior.
local previousCommand = SlashCmdList.CHRONICLEFOREVER
SlashCmdList.CHRONICLEFOREVER = function(message)
	if (message or ""):lower():match("^%s*scout%s*$") then nearby:Toggle()
	elseif previousCommand then previousCommand(message) end
end
frame:RegisterEvent("ADDON_LOADED")
for _, event in ipairs({"PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED"}) do
	pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, unit)
	if event == "ADDON_LOADED" then
		if unit == ADDON_NAME and type(ChronicleCompanionForeverDB) == "table" and ChronicleCompanionForeverDB.scouting_nearby_enabled == nil then
			ChronicleCompanionForeverDB.scouting_nearby_enabled = false
		end
	elseif event == "PLAYER_TARGET_CHANGED" then nearby:Observe("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then nearby:Observe("mouseover")
	elseif type(unit) == "string" and unit:match("^nameplate%d+$") then
		if event == "NAME_PLATE_UNIT_REMOVED" then nearby:Forget(unit) else nearby:Observe(unit) end
	end
end)
