local _, addon = ...
local Storage = {}
addon.ScoutingStorage = Storage
local CAPACITY, AGE = 1000, 86400
local fields = { "Levels", "Guilds", "Party" }
local function timestamp(v)
	return type(v) == "number" and v >= 0 and v < math.huge and v == math.floor(v)
end
-- Shared mutation marker for collectors. Timestamps are wall-clock seconds,
-- not sequence numbers: multiple writes in one second can have the same value.
function Storage.TouchCollections(db, at)
	if at == nil and type(time) == "function" then
		local ok, value = pcall(time)
		if ok then at = value end
	end
	if type(issecretvalue) == "function" and issecretvalue(at) then return end
	if timestamp(at) then db.collections.last_updated = at end
end
local function dense(a)
	if type(a) ~= "table" then return nil end
	local count = 0
	for k in pairs(a) do
		if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then return nil end
		count = count + 1
	end
	for i = 1, count do if a[i] == nil then return nil end end
	return count
end
local function metadataString(v) return type(v) == "string" and v ~= "" end
local function metadataGender(v) return v == 1 or v == 2 or v == 3 end
local function valid(p)
	if type(p) ~= "table" or type(p.Name) ~= "string" or p.Name == "" or not timestamp(p.LastSeen) then return false end
	if p.LastGrouped ~= nil and not timestamp(p.LastGrouped) then return false end
	if p.Realm ~= nil and not metadataString(p.Realm) then return false end
	if p.Race ~= nil and not metadataString(p.Race) then return false end
	if p.Gender ~= nil and not metadataGender(p.Gender) then return false end
	local n = dense(p.At)
	if not n then return false end
	for _, f in ipairs(fields) do if dense(p[f]) ~= n then return false end end
	for i = 1, n do
		if not timestamp(p.At[i]) then return false end
		for _, f in ipairs(fields) do
			local v = p[f][i]
			if v == "_" then
				if i == 1 then return false end
			elseif f == "Levels" then
				if v ~= false and (not timestamp(v) or v == 0) then return false end
			elseif f == "Guilds" then
				if v ~= false and type(v) ~= "string" then return false end
			elseif type(v) ~= "boolean" then return false end
		end
	end
	return true
end
local function compact(p, keep)
	local out = { At = {}, Levels = {}, Guilds = {}, Party = {} }
	local decoded, previous = {}, {}
	for i, at in ipairs(p.At) do
		for _, f in ipairs(fields) do if p[f][i] ~= "_" then decoded[f] = p[f][i] end end
		if keep(at) then
			local n = #out.At + 1
			out.At[n] = at
			for _, f in ipairs(fields) do
				out[f][n] = n > 1 and previous[f] == decoded[f] and "_" or decoded[f]
				previous[f] = decoded[f]
			end
		end
	end
	local changed = #out.At ~= #p.At
	for i, at in ipairs(out.At) do
		if p.At[i] ~= at then changed = true end
		for _, f in ipairs(fields) do if p[f][i] ~= out[f][i] then changed = true end end
	end
	if changed then p.At, p.Levels, p.Guilds, p.Party = out.At, out.Levels, out.Guilds, out.Party end
	return changed
end
local function last(p)
	local values = {}
	for i = 1, #p.At do
		for _, f in ipairs(fields) do if p[f][i] ~= "_" then values[f] = p[f][i] end end
	end
	return values
end
local methods = {}
function Storage.New(db, report)
	local self = setmetatable({ db = db, slots = {}, lookup = {}, insert = 1, gc = 1, current = {}, latest = {} }, { __index = methods })
	local function reject()
		self.blocked = true
		if report then report("Scouting data unsupported or malformed; preserved without changes.") end
		return self
	end
	if type(db) ~= "table" then return reject() end
	-- Sidekick captures and clears the whole container while WoW is closed.
	-- Each collector owns only its entry; preserve unknown sibling collections.
	if db.collections == nil then db.collections = {} end
	if type(db.collections) ~= "table" then return reject() end
	if db.collections.scouting == nil then
		db.collections.scouting = { Version = 1, Players = {} }
		Storage.TouchCollections(db)
	end
	local s = db.collections.scouting
	if type(s) ~= "table" or (s.Version ~= nil and s.Version ~= 1) or type(s.Players) ~= "table" then return reject() end
	local keys = {}
	for guid, p in pairs(s.Players) do
		if type(guid) ~= "string" or guid == "" or not valid(p) then return reject() end
		keys[#keys + 1] = guid
	end
	-- Refuse an oversized imported store rather than destroy unacknowledged data.
	if #keys > CAPACITY then return reject() end
	table.sort(keys)
	self.players = s.Players
	for i, guid in ipairs(keys) do self.slots[i], self.lookup[guid] = guid, i end
	return self
end
function methods:Enabled() return not self.blocked and self.db.sidekick_enabled == true end
function methods:SetCurrent(current) self.current = current end
function methods:Remove(guid, at)
	local slot = self.lookup[guid]
	if slot then
		self.slots[slot], self.lookup[guid], self.players[guid] = nil, nil, nil
		self.insert = slot
		self.latest[guid] = nil
		Storage.TouchCollections(self.db, at)
	end
end
function methods:Slot(grouped, now)
	local low, former
	for offset = 0, CAPACITY - 1 do
		local i = (self.insert + offset - 1) % CAPACITY + 1
		local guid = self.slots[i]
		if not guid then return i end
		if grouped and not self.current[guid] then
			local p = self.players[guid]
			if not p.LastGrouped or now - p.LastGrouped > AGE then low = low or i else former = former or i end
		end
	end
	return low or former
end
function methods:Observe(guid, name, level, guild, grouped, now, force, metadata)
	if not self:Enabled() or not timestamp(now) or type(guid) ~= "string" or guid == "" or type(name) ~= "string" or name == "" or type(grouped) ~= "boolean" then return false end
	if level ~= false and (not timestamp(level) or level == 0) then return false end
	if guild ~= false and (type(guild) ~= "string" or guild == "_") then return false end
	local p = self.players[guid]
	if not p then
		local slot = self:Slot(grouped, now)
		if not slot then return false end
		if self.slots[slot] then self:Remove(self.slots[slot], now) end
		p = { Name = name, At = {}, Levels = {}, Guilds = {}, Party = {} }
		self.players[guid], self.slots[slot], self.lookup[guid] = p, guid, slot
		self.insert = slot % CAPACITY + 1
		for offset = 1, CAPACITY do
			local nextSlot = (slot + offset - 1) % CAPACITY + 1
			if not self.slots[nextSlot] then self.insert = nextSlot; break end
		end
	end
	local edited = p.Name ~= name or p.LastSeen ~= now or (grouped and p.LastGrouped ~= now)
	p.Name, p.LastSeen = name, now
	-- Optional player scalars are not observation history. Failed or unknown
	-- lookups must not erase a previously available identity value.
	if metadata then
		if metadataString(metadata.realm) then edited = edited or p.Realm ~= metadata.realm; p.Realm = metadata.realm end
		if metadataString(metadata.race) then edited = edited or p.Race ~= metadata.race; p.Race = metadata.race end
		if metadataGender(metadata.gender) and (metadata.gender ~= 1 or p.Gender == nil) then edited = edited or p.Gender ~= metadata.gender; p.Gender = metadata.gender end
	end
	if grouped then p.LastGrouped = now end
	local before = self.latest[guid] or last(p)
	-- Unavailable lookups must not erase previously observed enrichment.
		if level == false and before.Levels ~= nil then level = before.Levels end
		if guild == false and before.Guilds ~= nil then guild = before.Guilds end
		local values = { Levels = level, Guilds = guild, Party = grouped }
	local changed = force or #p.At == 0
	for _, f in ipairs(fields) do if before[f] ~= values[f] then changed = true end end
	if changed then
		local n = #p.At + 1
		p.At[n] = now
		for _, f in ipairs(fields) do p[f][n] = n > 1 and before[f] == values[f] and "_" or values[f] end
	end
	self.latest[guid] = values
	if edited or changed then Storage.TouchCollections(self.db, now) end
	return true
end
function methods:Leave(guid, now)
	local p = not self.blocked and self.players[guid]
	if p then
		local v = self.latest[guid] or last(p)
		self:Observe(guid, p.Name, v.Levels or false, v.Guilds or false, false, now, false)
	end
end
function methods:Collect(now, budget, refresh)
	if self.blocked or not timestamp(now) then return end
	for _ = 1, math.min(budget, CAPACITY) do
		local slot = self.gc
		self.gc = slot % CAPACITY + 1
		local guid = self.slots[slot]
		if guid then
			local p = self.players[guid]
			local observed = self:Enabled() and refresh and refresh(guid)
			if observed then self:Observe(guid, observed.name, observed.level, observed.guild, observed.grouped, now, false, observed) end
			if not self.current[guid] and now - p.LastSeen > AGE then
				self:Remove(guid, now)
			else
				if compact(p, function(at) return now - at <= AGE end) then Storage.TouchCollections(self.db, now) end
				self.latest[guid] = nil
				if #p.At == 0 then
					if observed then self:Observe(guid, observed.name, observed.level, observed.guild, observed.grouped, now, true, observed)
					elseif not self.current[guid] then self:Remove(guid, now) end
				end
			end
		end
	end
end
