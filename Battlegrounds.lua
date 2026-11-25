local _, addon = ...
local frame = CreateFrame("Frame")
local collector = {}
addon.Battlegrounds = collector
local MAX_EVENTS, MAX_BYTES = 20000, 8388608
local unpackValues = unpack or table.unpack
local chats = { CHAT_MSG_BG_SYSTEM_ALLIANCE = true, CHAT_MSG_BG_SYSTEM_HORDE = true, CHAT_MSG_BG_SYSTEM_NEUTRAL = true }
local function isSecret(value)
	if type(issecretvalue) ~= "function" then return false end
	local ok, result = pcall(issecretvalue, value)
	return not ok or result ~= false
end
local function call(name, ...)
	if type(_G[name]) ~= "function" then return nil end
	local result = { pcall(_G[name], ...) }
	if not result[1] then return nil end
	for i = 2, 10 do
		if isSecret(result[i]) then return nil end
	end
	return unpackValues(result, 2, 9)
end
local function integer(v) return type(v) == "number" and v >= 0 and v < math.huge and v == math.floor(v) end
local function dense(a, max)
	if type(a) ~= "table" then return nil end
	local n = 0
	for k in pairs(a) do
		if not integer(k) or k < 1 then return nil end
		n = n + 1
	end
	if n > max then return nil end
	for i = 1, n do if a[i] == nil then return nil end end
	return n
end
-- A deterministic storage weight, not serialized file size. Include field names.
local function weight(v)
	if type(v) == "string" then return #v end
	if type(v) ~= "table" then return 8 end
	local n = 0
	for k, value in pairs(v) do n = n + weight(k) + weight(value) end
	return n
end
local function snapshotValid(rows)
	local n = dense(rows, 32)
	if not n then return false end
	for _, row in ipairs(rows) do
		if dense(row, 8) ~= 8 then return false end
		for _, v in ipairs(row) do
			if type(v) == "string" then if #v > 256 then return false end
			elseif type(v) == "number" then if v ~= v or math.abs(v) == math.huge then return false end
			elseif type(v) ~= "boolean" then return false end
		end
	end
	return true
end
local allowed = { At=true, Kind=true, Segment=true, Source=true, Text=true, Rows=true, Winner=true }
local function eventValid(e, index, events)
	if type(e) ~= "table" then return false end
	for k in pairs(e) do if not allowed[k] then return false end end
	if not integer(e.At) or not integer(e.Segment) or e.Segment < 1 or e.Segment > index then return false end
	if e.Kind == "observed_enter" then
		return e.Segment == index and type(e.Source) == "string" and #e.Source <= 64 and e.Text == nil and e.Rows == nil and e.Winner == nil
	end
	if events[e.Segment].Kind ~= "observed_enter" then return false end
	if e.Kind == "announcement" then return chats[e.Source] == true and type(e.Text) == "string" and #e.Text <= 4096 and e.Rows == nil and e.Winner == nil end
	if e.Source ~= nil or e.Text ~= nil then return false end
	if e.Kind == "world_states" then return e.Winner == nil and snapshotValid(e.Rows) end
	if e.Rows ~= nil then return false end
	if e.Kind == "completion_observed" then return e.Winner == 0 or e.Winner == 1 or e.Winner == 2 end
	return e.Kind == "observed_leave" and e.Winner == nil
end
function collector:Warn(message)
	if not self.warned and DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Chronicle battlegrounds: " .. message) end
	self.warned = true
end
function collector:Store(db)
	if self.db == db and self.container == db.collections then return self.store end
	self.db, self.container, self.store, self.active, self.rows, self.winner = db, db.collections, nil, nil, nil, nil
	if db.collections ~= nil and type(db.collections) ~= "table" then self:Warn("malformed collections preserved."); return end
	local s = db.collections and db.collections.battlegrounds
	local bytes = 0
	if s ~= nil then
		local valid = type(s) == "table" and s.Version == 1 and dense(s.Events, MAX_EVENTS) ~= nil
		if valid then
			for k in pairs(s) do if k ~= "Version" and k ~= "Events" and k ~= "Stopped" then valid = false end end
			if s.Stopped ~= nil and s.Stopped ~= "capacity" then valid = false end
			for i, e in ipairs(s.Events) do if not eventValid(e, i, s.Events) then valid = false; break end end
			if valid then bytes = weight(s.Events); valid = bytes <= MAX_BYTES end
		end
		if not valid then self:Warn("unsupported or malformed data preserved; collection paused."); return end
	else
		db.collections = db.collections or {}
		s = { Version = 1, Events = {} }
		db.collections.battlegrounds = s
		addon.ScoutingStorage.TouchCollections(db)
	end
	self.container, self.store, self.bytes = db.collections, s, bytes
	return s
end
function collector:Append(e, at)
	local s = self.store
	if s.Stopped then if addon.BattlegroundDiagnostics then addon.BattlegroundDiagnostics:Count("LegacyDropped") end; self:Warn("capacity reached; pending history preserved. Sidekick must drain collections while WoW is closed."); return false end
	e.At, e.Segment = at, self.active or (#s.Events + 1)
	local bytes = weight(e) + 8
	if #s.Events >= MAX_EVENTS or self.bytes + bytes > MAX_BYTES then
		s.Stopped = "capacity"
		if addon.BattlegroundDiagnostics then addon.BattlegroundDiagnostics:Count("LegacyDropped") end
		addon.ScoutingStorage.TouchCollections(self.db, at)
		self:Warn("capacity reached; pending history preserved. Sidekick must drain collections while WoW is closed.")
		return false
	end
	s.Events[#s.Events + 1], self.bytes = e, self.bytes + bytes
	addon.ScoutingStorage.TouchCollections(self.db, at)
	return true
end
function collector:Snapshot()
	local n = call("GetNumWorldStateUI")
	if not integer(n) or n > 32 or type(GetWorldStateUIInfo) ~= "function" then return end
	local rows = {}
	for i = 1, n do
		local row = { call("GetWorldStateUIInfo", i) }
		-- First return is uiType; absence means unavailable, not an empty row.
		if row[1] == nil then return end
		for j = 1, 8 do if row[j] == nil then row[j] = false end end
		rows[i] = row
	end
	if snapshotValid(rows) then return rows end
end
local function same(a, b)
	if not a or #a ~= #b then return false end
	for i, row in ipairs(a) do for j = 1, 8 do if row[j] ~= b[i][j] then return false end end end
	return true
end
function collector:Event(event, ...)
	local text = ...
	local db = ChronicleCompanionForeverDB
	if type(db) ~= "table" or db.sidekick_enabled ~= true then
		self.active, self.rows, self.winner = nil, nil, nil
		return
	end
	if addon.BattlegroundDiagnostics then
		-- Validate existing collection before touching any diagnostic sibling.
		if db.collections and (type(db.collections) ~= "table" or db.collections.battlegrounds ~= nil) and not self:Store(db) then return end
		addon.BattlegroundDiagnostics:Observe(event, ...)
	end
	local at = call("time")
	if not integer(at) then return end
	local inside, kind = call("IsInInstance")
	if type(inside) ~= "boolean" or type(kind) ~= "string" then return end
	-- Do not initialize a collection merely for logging in outside a battleground.
	if not self.active and (not inside or kind ~= "pvp") then return end
	if not self:Store(db) then return end
	if not inside or kind ~= "pvp" then
		if self.active then self:Append({ Kind = "observed_leave" }, at) end
		self.active, self.rows, self.winner = nil, nil, nil
		return
	end
	if not self.active then
		local index = #self.store.Events + 1
		if not self:Append({ Kind = "observed_enter", Source = event }, at) then return end
		self.active = index
	end
	if chats[event] and not isSecret(text) and type(text) == "string" and #text <= 4096 then
		self:Append({ Kind = "announcement", Source = event, Text = text }, at)
	end
	local rows = self:Snapshot()
	if rows and not same(self.rows, rows) and self:Append({ Kind = "world_states", Rows = rows }, at) then self.rows = rows end
	local winner = call("GetBattlefieldWinner")
	if (winner == 0 or winner == 1 or winner == 2) and self.winner == nil then
		if self:Append({ Kind = "completion_observed", Winner = winner }, at) then self.winner = winner end
	end
end
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "UPDATE_WORLD_STATES", "UPDATE_BATTLEFIELD_STATUS", "UPDATE_BATTLEFIELD_SCORE", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_NEUTRAL" }) do
	if addon.BattlegroundDiagnostics then addon.BattlegroundDiagnostics:Register(frame, event) else pcall(frame.RegisterEvent, frame, event) end
end
if addon.BattlegroundDiagnostics then
	for event in pairs(addon.BattlegroundDiagnostics.announcements) do
		if not chats[event] then addon.BattlegroundDiagnostics:Register(frame, event) end
	end
end
frame:SetScript("OnEvent", function(_, event, ...) collector:Event(event, ...) end)
