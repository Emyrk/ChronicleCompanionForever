local _, addon = ...
local d = { registrations = {}, failures = {} }
addon.BattlegroundDiagnostics = d
local MAX_EVENTS, MAX_BYTES, MAX_ARGS, MAX_STRING = 20000, 16777216, 64, 8192
local MAX_COUNT = 9007199254740991
local countFields = { Dropped=true, Skipped=true, Truncated=true, APIErrors=true, MissingAPIs=true, LegacyDropped=true }
local recordFields = { Source=true, WallTime=true, Monotonic=true, Presence=true,
    Registration=true, Metadata=true, Args=true, Observations=true, WorldCount=true,
    WorldRows=true, QueueSlots=true, Queues=true, QueueFallback=true }
local unpackValues = unpack or table.unpack
local function pack(...) return { n = select('#', ...), ... } end
local function secret(v)
    if type(issecretvalue) ~= 'function' then return false end
    local ok, value = pcall(issecretvalue, v)
    return not ok or value ~= false
end
local function weight(v, depth)
    if depth > 12 then return nil end
    if type(v) == 'string' then return #v end
    if type(v) == 'boolean' then return 8 end
    if type(v) == 'number' and v == v and math.abs(v) < math.huge then return 8 end
    if type(v) ~= 'table' then return nil end
    local total = 0
    for k, value in pairs(v) do
        local a, b = weight(k, depth + 1), weight(value, depth + 1)
        if not a or not b then return nil end
        total = total + a + b
        if total > MAX_BYTES then return nil end
    end
    return total
end
function d:Count(key, n)
    if self.store and countFields[key] then
        local before = self.store.Counts[key] or 0
        local after = math.min(MAX_COUNT, before + (n or 1))
        if after ~= before then
            self.store.Counts[key] = after
            -- Counters can change even when no event is admitted (outside BG).
            pcall(addon.ScoutingStorage.TouchCollections, self.db)
        end
    end
end
function d:Raw(...)
    local args = pack(...)
    local out = { n = args.n, Values = {} }
    if args.n > MAX_ARGS then self:Count('Truncated'); out.Omitted = args.n - MAX_ARGS end
    for i = 1, math.min(args.n, MAX_ARGS) do
        local v, item = args[i], {}
        if secret(v) then item.Type = 'secret'; self:Count('Skipped')
        elseif v == nil then item.Type = 'nil'
        elseif type(v) == 'string' then
            item.Type, item.Value = 'string', v:sub(1, MAX_STRING)
            if #v > MAX_STRING then item.Bytes = #v; self:Count('Truncated') end
        elseif type(v) == 'boolean' or (type(v) == 'number' and v == v and math.abs(v) < math.huge) then
            item.Type, item.Value = type(v), v
        else item.Type = 'unsupported'; item.LuaType = type(v); self:Count('Skipped') end
        out.Values[i] = item
    end
    return out
end
local function resolve(name)
    local namespace, field = name:match('^([^.]+)%.(.+)$')
    if namespace then return type(_G[namespace]) == 'table' and _G[namespace][field] end
    return _G[name]
end
function d:API(name, ...)
    local fn = resolve(name)
    local observation = { API = name, Args = self:Raw(...) }
    if type(fn) ~= 'function' then
        observation.Status = 'missing'; self:Count('MissingAPIs'); self.failures[name] = 'missing'
        return observation
    end
    local results = pack(pcall(fn, ...))
    if not results[1] then
        observation.Status, observation.Error = 'error', self:Raw(results[2])
        self:Count('APIErrors'); self.failures[name] = 'error'
    else observation.Status, observation.Returns = 'ok', self:Raw(unpackValues(results, 2, results.n)) end
    return observation
end
local function value(observation, index)
    local v = observation.Returns and observation.Returns.Values[index]
    return v and v.Value
end
function d:Block(reason)
    self.blocked = reason
    if not self.blockWarned and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage('Chronicle BG diagnostics: ' .. reason .. '; recording paused. /clog bgstatus')
        self.blockWarned = true
    end
end
function d:Open(db)
    if type(db) ~= 'table' or db.sidekick_enabled ~= true then self.store, self.db, self.container = nil, nil, nil; return end
    if self.db == db and self.container == db.collections then return self.store end
    self.db, self.container, self.store = db, db.collections, nil
    self.started, self.capacity = false, false
    if db.collections ~= nil and type(db.collections) ~= 'table' then self:Block('malformed collections'); return end
    local s = db.collections and db.collections.battlegroundDiagnostics
    if s ~= nil then
        local valid = type(s) == 'table' and s.Version == 1 and type(s.Events) == 'table' and type(s.Counts) == 'table'
        local size = valid and weight(s, 0)
        if valid then
            for k in pairs(s) do if k ~= 'Version' and k ~= 'Events' and k ~= 'Counts' and k ~= 'Bytes' then valid = false end end
            for k, v in pairs(s.Counts) do if not countFields[k] or type(v) ~= 'number' or v ~= v or v < 0 or v > MAX_COUNT or v % 1 ~= 0 then valid = false end end
            local n = 0
            for k in pairs(s.Events) do
                n = n + 1
                if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 or k > #s.Events then valid = false end
            end
            for _, record in ipairs(s.Events) do
                if type(record) ~= 'table' or type(record.Source) ~= 'string' then valid = false; break end
                for key in pairs(record) do if not recordFields[key] then valid = false end end
            end
            if n ~= #s.Events or n > MAX_EVENTS or type(s.Bytes) ~= 'number' or s.Bytes < 0 then valid = false end
        end
        if not valid or not size then self:Block('unsupported/malformed diagnostics preserved'); return end
        -- Recompute rather than trusting a persisted budget counter.
        local bytes = weight(s.Events, 0)
        if s.Bytes ~= bytes then
            s.Bytes = bytes
            pcall(addon.ScoutingStorage.TouchCollections, db)
        end
    else
        db.collections = db.collections or {}
        s = { Version = 1, Events = {}, Counts = {}, Bytes = 0 }
        db.collections.battlegroundDiagnostics = s
        -- Marker failure must not discard otherwise usable raw evidence.
        pcall(addon.ScoutingStorage.TouchCollections, db)
    end
    self.store, self.container, self.blocked = s, db.collections, nil
    return s
end
function d:Append(record)
    local s = self.store
    if not s then return end
    local bytes = weight(record, 0)
    if not bytes or #s.Events >= MAX_EVENTS or s.Bytes + bytes + 8 > MAX_BYTES - 4096 then
        self:Count('Dropped')
        self.capacity = true
        if not self.warned and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage('Chronicle BG diagnostics: capacity reached; evidence dropped. /clog bgstatus')
            self.warned = true
        end
    else
        s.Events[#s.Events + 1] = record
        s.Bytes = s.Bytes + bytes + 8
    end
    local ok = pcall(addon.ScoutingStorage.TouchCollections, self.db)
    if not ok then self:Count("APIErrors"); self.failures.TouchCollections = "error" end
end
function d:Register(frame, event)
    local ok, result = pcall(frame.RegisterEvent, frame, event)
    self.registrations[#self.registrations + 1] = { Event = event, OK = ok and result ~= false,
        Result = self:Raw(result) }
end
function d:Observe(event, ...)
    local db = ChronicleCompanionForeverDB
    -- Preserve a blocked legacy store too: it may be a future schema owned elsewhere.
    if type(db) ~= 'table' or db.sidekick_enabled ~= true then self.store, self.db, self.container = nil, nil, nil; return end
    if not self:Open(db) then return end
    local instance = self:API('IsInInstance')
    local inBG = value(instance, 1) == true and value(instance, 2) == 'pvp'
    -- Announcement args are never retained outside an observed battleground.
    if (self.announcements[event] or event == 'PLAYER_TARGET_CHANGED' or event == 'UPDATE_MOUSEOVER_UNIT') and not inBG then return end
    local record = { Source = event, WallTime = self:API('time'), Monotonic = self:API('GetTime'), Presence = instance }
    if not self.started then
        record.Registration = self.registrations
        record.Metadata = { self:API('GetBuildInfo'), self:API('GetLocale'), self:API('UnitGUID', 'player'), self:API('UnitName', 'player') }
        self.started = true
    end
    if inBG then
        record.Args = self:Raw(...)
        record.Observations = { self:API('GetInstanceInfo'), self:API('GetBattlefieldWinner'),
            self:API('C_PvP.GetActiveMatchState'), self:API('C_PvP.GetActiveMatchDuration'),
            self:API('UnitGUID', 'player'), self:API('UnitGUID', 'target'), self:API('UnitGUID', 'mouseover') }
        local count = self:API('GetNumWorldStateUI')
        record.WorldCount, record.WorldRows = count, {}
        local n = value(count, 1)
        if type(n) == 'number' and n >= 0 and n % 1 == 0 then
            for i = 1, math.min(n, 64) do record.WorldRows[i] = self:API('GetWorldStateUIInfo', i) end
            if n > 64 then self:Count('Truncated') end
        else self:Count('Skipped') end
        local slots = self:API('GetMaxBattlefieldID')
        record.QueueSlots, record.Queues = slots, {}
        n = value(slots, 1)
        if type(n) ~= 'number' or n < 0 or n % 1 ~= 0 then n = 3; record.QueueFallback = true end
        if n > 16 then self:Count('Truncated') end
        for i = 1, math.min(n, 16) do record.Queues[i] = self:API('GetBattlefieldStatus', i) end
    end
    self:Append(record)
end
function d:Status()
    local db = ChronicleCompanionForeverDB
    local enabled = type(db) == 'table' and db.sidekick_enabled == true
    local legacyBlocked = enabled and type(db.collections) == 'table' and db.collections.battlegrounds ~= nil
        and addon.Battlegrounds and not addon.Battlegrounds:Store(db)
    local s = enabled and not legacyBlocked and self:Open(db)
    local lines = { 'Chronicle BG: Sidekick gate=' .. tostring(enabled) .. '; diagnostics=' .. (not enabled and 'disabled' or (legacyBlocked and 'legacy data preserved; paused') or self.blocked or 'automatic') }
    lines[#lines + 1] = ('Diagnostics events=%d/%d weight=%d/%d (not file bytes)'):format(s and #s.Events or 0, MAX_EVENTS, s and s.Bytes or 0, MAX_BYTES)
    if s then
        local counts = {}
        for _, k in ipairs({'Dropped','Skipped','Truncated','APIErrors','MissingAPIs','LegacyDropped'}) do counts[#counts+1] = k .. '=' .. (s.Counts[k] or 0) end
        lines[#lines+1] = table.concat(counts, ' ')
    end
    local legacy = type(db) == 'table' and type(db.collections) == 'table' and db.collections.battlegrounds
    lines[#lines+1] = 'Legacy collector: ' .. (addon.Battlegrounds and addon.Battlegrounds.warned and 'warning (see chat; data preserved)' or 'no warning observed')
    if type(legacy) == 'table' and type(legacy.Events) == 'table' then
        lines[#lines+1] = 'Legacy events=' .. #legacy.Events .. '/20000; weight cap=8388608; stopped=' .. tostring(legacy.Stopped)
    end
    for _, r in ipairs(self.registrations) do if not r.OK then lines[#lines+1] = 'Event registration failed: ' .. r.Event end end
    -- Read-only probes: status works before initialization and outside BG.
    for _, name in ipairs({'IsInInstance','time','GetTime','GetInstanceInfo','GetBattlefieldStatus','GetNumWorldStateUI','GetWorldStateUIInfo','GetBattlefieldWinner','C_PvP.GetActiveMatchState','C_PvP.GetActiveMatchDuration'}) do
        if type(resolve(name)) ~= 'function' then lines[#lines+1] = 'API missing: ' .. name
        elseif self.failures[name] then lines[#lines+1] = 'API observed failure: ' .. name .. ' (' .. self.failures[name] .. ')' end
    end
    for _, line in ipairs(lines) do if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end end
    if addon.BattlegroundScoreboard then addon.BattlegroundScoreboard:Status() end
    return lines
end
d.announcements = {}
for _, name in ipairs({'CHAT_MSG_BG_SYSTEM_ALLIANCE','CHAT_MSG_BG_SYSTEM_HORDE','CHAT_MSG_BG_SYSTEM_NEUTRAL',
    'RAID_BOSS_EMOTE','RAID_BOSS_WHISPER','CHAT_MSG_RAID_BOSS_EMOTE','CHAT_MSG_RAID_BOSS_WHISPER',
    'CHAT_MSG_MONSTER_SAY','CHAT_MSG_MONSTER_YELL','CHAT_MSG_MONSTER_EMOTE','CHAT_MSG_MONSTER_WHISPER','CHAT_MSG_SYSTEM'}) do d.announcements[name] = true end
if SlashCmdList then
    local previous = SlashCmdList.CHRONICLEFOREVER
    SlashCmdList.CHRONICLEFOREVER = function(message)
        if (message or ''):lower():match('^%s*bgstatus%s*$') then d:Status()
        elseif previous then previous(message) end
    end
end
