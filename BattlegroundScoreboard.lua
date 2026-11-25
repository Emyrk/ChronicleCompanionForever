local _, addon = ...
local board = { generation = 0, baseline = {}, support = {} }
addon.BattlegroundScoreboard = board
local MAX_PROBES, MAX_BYTES, MAX_ROWS, MAX_STATS = 4000, 16777216, 120, 32
local MAX_COUNT = 9007199254740991
-- Never export these objects: original secret scalars and API row references are
-- retained only in this module closure, never in addon state or SavedVariables.
local retained, capturedProbe = {}, nil
local retentionFields = {'damageDone', 'healingDone'}
local function secrecy(v)
    if type(issecretvalue) ~= 'function' then return 'unavailable' end
    local ok, result = pcall(issecretvalue, v)
    if not ok then return 'unavailable' end
    if result == true then return 'secret' end
    if result == false then return 'public' end
    return 'unavailable'
end
local function retentionValue(v)
    local result = {Secrecy=secrecy(v)}
    -- No coercion, comparison, formatting or serialization before literal false.
    if result.Secrecy == 'public' and type(v) == 'number' and v == v and math.abs(v) < math.huge then result.Value = v end
    return result
end
local function retainedField(row, field)
    if secrecy(row) ~= 'public' or type(row) ~= 'table' then return nil, 'unavailable' end
    local ok, v = pcall(function() return row[field] end)
    if not ok then return nil, 'unavailable' end
    return v, 'ok'
end
local fields = { 'name', 'guid', 'killingBlows', 'honorableKills', 'deaths', 'honorGained',
    'faction', 'raceName', 'gender', 'className', 'classToken', 'damageDone', 'healingDone',
    'rating', 'ratingChange', 'prematchMMR', 'mmrChange', 'postmatchMMR', 'talentSpec',
    'honorLevel', 'roleAssigned' }
local statFields = { 'pvpStatID', 'pvpStatValue', 'orderIndex', 'name', 'tooltip', 'iconName' }
local probeFields = { Source=true, Fields=true, Changes=true, Unidentified=true, At=true, Monotonic=true, Request=true, Count=true, Omitted=true, Filter=true, RequestAt=true, Retention=true }
local counters = { Polls=true, Dropped=true, Hidden=true, Unidentified=true, Unavailable=true,
    Truncated=true, APIErrors=true, MissingAPIs=true, TimerFailures=true, TimedSamples=true, TotalMicros=true, MaxMicros=true, Requests=true, RetentionChecks=true, RetentionPublic=true }
local function secret(v)
    if type(issecretvalue) ~= 'function' then return false end
    local ok, result = pcall(issecretvalue, v)
    return not ok or result ~= false
end
local function finite(v)
    return not secret(v) and type(v) == 'number' and v == v and math.abs(v) < math.huge
end
local function weight(v, depth)
    if depth > 12 or secret(v) then return nil end
    if type(v) == 'string' then return #v end
    if type(v) == 'number' then return finite(v) and 8 or nil end
    if type(v) == 'boolean' then return 8 end
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
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
function board:Touch()
    if self.batching then self.dirty = true; return end
    if self.db and self.db.sidekick_enabled == true then pcall(addon.ScoutingStorage.TouchCollections, self.db) end
end
local function profile()
    if type(debugprofilestop) ~= 'function' then return end
    local ok, v = pcall(debugprofilestop)
    if ok and finite(v) then return v end
end
function board:Count(key)
    if not self.store then return end
    local old = self.store.Counts[key] or 0
    if old < MAX_COUNT then self.store.Counts[key] = old + 1; self:Touch() end
end
function board:Availability(item, path)
    if self.probe and path then
        local status = self.probe.Fields[path] or {}
        self.probe.Fields[path] = status
        status[item.Type] = (status[item.Type] or 0) + 1
    end
    return item
end
function board:Scalar(v, path)
    local item
    if secret(v) then item = {Type='secret'}; self:Count('Hidden')
    elseif v == nil then item = {Type='nil'}
    elseif type(v) == 'string' then
        item = {Type='string', Value=v:sub(1, 512)}
        if #v > 512 then item.Type, item.Bytes = 'truncated', #v; self:Count('Truncated') end
    elseif type(v) == 'boolean' or finite(v) then item = {Type=type(v), Value=v}
    else item = {Type='unsupported', LuaType=type(v)}; self:Count('Unavailable') end
    return self:Availability(item, path)
end
function board:Field(row, key, path)
    -- Only fixed known keys are accessed, never iterate API-returned table keys.
    if secret(row) then return self:Scalar(row, path) end
    if type(row) ~= 'table' then return self:Availability({Type='unavailable'}, path) end
    local ok, result = pcall(function() return row[key] end)
    if not ok then self:Count('APIErrors'); return self:Availability({Type='unavailable', Reason='access-error'}, path) end
    return self:Scalar(result, path)
end
local function resolve(name)
    local namespace, key = name:match('^([^.]+)%.(.+)$')
    local v = _G[namespace or name]
    if secret(v) then return nil end
    if namespace then
        if type(v) ~= 'table' then return nil end
        local ok, result = pcall(function() return v[key] end)
        if not ok or secret(result) then return nil end
        return result
    end
    return v
end
function board:API(name, ...)
    local fn = resolve(name)
    if type(fn) ~= 'function' then
        if self.support[name] ~= 'missing' then self:Count('MissingAPIs') end
        self.support[name] = 'missing'; return nil, 'missing'
    end
    local ok, a, b = pcall(fn, ...)
    if not ok then self.support[name] = 'error'; self:Count('APIErrors'); return nil, 'error' end
    self.support[name] = 'ok'
    return a, 'ok', b
end
function board:Present()
    local db = ChronicleCompanionForeverDB
    if type(db) ~= 'table' or db.sidekick_enabled ~= true then return false end
    local fn = resolve('IsInInstance')
    if type(fn) ~= 'function' then self.support.IsInInstance = 'missing'; return false end
    local ok, a, b = pcall(fn)
    self.support.IsInInstance = ok and 'ok' or 'error'
    return ok and not secret(a) and not secret(b) and a == true and b == 'pvp'
end
function board:Open(db)
    if self.db == db and self.container == db.collections then return self.store end
    self.db, self.container, self.store, self.lastStore, self.baseline = db, db.collections, nil, nil, {}
    if db.collections ~= nil and type(db.collections) ~= 'table' then self.blocked = 'malformed collections'; return end
    local s = db.collections and db.collections.battlegroundScoreboard
    if s ~= nil then
        local valid = type(s) == 'table' and s.Version == 1 and type(s.Probes) == 'table' and type(s.Counts) == 'table'
        local size = valid and weight(s, 0)
        if valid then
            for k in pairs(s) do if k ~= 'Version' and k ~= 'Probes' and k ~= 'Counts' and k ~= 'Bytes' then valid = false end end
            for k, v in pairs(s.Counts) do
                if not counters[k] or not finite(v) or v < 0 or v > MAX_COUNT or v % 1 ~= 0 then valid = false end
            end
            local n = 0
            for k, probe in pairs(s.Probes) do
                n = n + 1
                if not finite(k) or k < 1 or k % 1 ~= 0 or k > #s.Probes or type(probe) ~= 'table' then valid = false
                else
                    if type(probe.Source) ~= 'string' then valid = false end
                    for field in pairs(probe) do if not probeFields[field] then valid = false end end
                end
            end
            if n ~= #s.Probes or n > MAX_PROBES or not finite(s.Bytes) or s.Bytes < 0 then valid = false end
        end
        if not valid or not size then self.blocked = 'unsupported/malformed scoreboard preserved'; return end
        local bytes = weight(s.Probes, 0)
        if s.Bytes ~= bytes then s.Bytes = bytes; self:Touch() end
    else
        db.collections = db.collections or {}
        s = {Version=1, Probes={}, Counts={}, Bytes=0}
        db.collections.battlegroundScoreboard = s
        self:Touch()
    end
    self.store, self.lastStore, self.container, self.blocked = s, s, db.collections, nil
    return s
end
function board:Append(probe)
    local s, bytes = self.store, weight(probe, 0)
    if not bytes or #s.Probes >= MAX_PROBES or s.Bytes + bytes + 8 > MAX_BYTES - 4096 then
        self:Count('Dropped')
        if not self.warned and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage('Chronicle BG scoreboard capacity reached; probes dropped. /clog bgstatus')
            self.warned = true
        end
        return false
    end
    s.Probes[#s.Probes+1], s.Bytes = probe, s.Bytes + bytes + 8
    self:Touch()
    return true
end
function board:Stats(row)
    local ok, stats = pcall(function() return row.stats end)
    if not ok then self:Count('APIErrors'); return {Type='unavailable', Reason='access-error'} end
    if secret(stats) or type(stats) ~= 'table' then return self:Scalar(stats, 'stats') end
    local result = {Type='stats', Values={}}
    local lengthOK, n = pcall(function() return #stats end)
    if not lengthOK or not finite(n) or n < 0 or n % 1 ~= 0 then return {Type='unavailable', Reason='length'} end
    result.Count = n
    if n > MAX_STATS then self:Count('Truncated'); result.Omitted = n - MAX_STATS end
    for i = 1, math.min(n, MAX_STATS) do
        local readOK, stat = pcall(function() return stats[i] end)
        if not readOK then result.Values[i] = {Type='unavailable', Reason='access-error'}; self:Count('APIErrors')
        elseif secret(stat) or type(stat) ~= 'table' then result.Values[i] = self:Scalar(stat, 'stats.row')
        else
            local values = {}
            for _, field in ipairs(statFields) do values[field] = self:Field(stat, field, 'stats.' .. field) end
            result.Values[i] = {Type='row', Fields=values}
        end
    end
    return result
end
function board:Retain(row, key, probe)
    if self.completed or #retained >= 3 or capturedProbe == probe then return end
    local copied, initial, anySecret = {}, {}, false
    for _, field in ipairs(retentionFields) do
        local v, status = retainedField(row, field)
        local state = status == 'ok' and secrecy(v) or 'unavailable'
        copied[field], initial[field] = v, state
        if state == 'secret' then anySecret = true end
    end
    -- Only samples actually observed secret during the active observation window
    -- participate. Missing/throwing checkers cannot accidentally admit values.
    if not anySecret then return end
    retained[#retained+1] = {ID=#retained+1, CapturedAt=probe.At, Key=key,
        Copied=copied, Initial=initial, Row=row}
    capturedProbe = probe
end
function board:CheckRetention(stage, at, fresh)
    if #retained == 0 then return nil end
    local output = {Stage=stage, CheckedAt=at, Samples={}}
    for _, sample in ipairs(retained) do
        local saved = {ID=sample.ID, CapturedAt=sample.CapturedAt, Initial=sample.Initial,
            Copied={}, RetainedTable={}, Fresh={}, FreshCorrelation='unavailable'}
        local current = fresh and fresh[sample.Key]
        if current then saved.FreshCorrelation = 'readable-identity' end
        for _, field in ipairs(retentionFields) do
            saved.Copied[field] = retentionValue(sample.Copied[field])
            local v, status = retainedField(sample.Row, field)
            saved.RetainedTable[field] = status == 'ok' and retentionValue(v) or {Secrecy='unavailable'}
            v, status = retainedField(current, field)
            saved.Fresh[field] = status == 'ok' and retentionValue(v) or {Secrecy='unavailable'}
            if sample.Initial[field] == 'secret' and saved.Copied[field].Secrecy == 'public' then self:Count('RetentionPublic') end
        end
        output.Samples[#output.Samples+1] = saved
    end
    self:Count('RetentionChecks')
    return output
end
function board:RetentionOnly(stage)
    if not self.store or #retained == 0 then return end
    self.batching = true
    local at, status = self:API('time')
    local timestamp = status == 'ok' and self:Scalar(at) or {Type=status}
    local result = self:CheckRetention(stage, timestamp)
    self:Append({Source='retention', At=timestamp, Retention=result})
    self.batching = false
    if self.dirty then self.dirty = false; self:Touch() end
end
function board:Poll(source)
    if self.busy then return end
    self.busy, self.batching = true, true
    local start = profile()
    local probe = {Source=source, Fields={}, Changes={}, Unidentified={}}
    self.probe = probe
    self:Count('Polls')
    local at, atStatus = self:API('time')
    local mono, monoStatus = self:API('GetTime')
    probe.At, probe.Monotonic = atStatus == 'ok' and self:Scalar(at) or {Type=atStatus}, monoStatus == 'ok' and self:Scalar(mono) or {Type=monoStatus}
    self.lastPoll = finite(mono) and mono or nil
    -- Refresh only at admitted cadence; synchronous score events cannot recurse.
    -- Completion retries read cached rows; never increase refresh request cadence.
    local requestDue = not self.requested or (finite(mono) and self.lastRequest and mono - self.lastRequest >= 30)
    probe.Request = 'throttled'
    if requestDue then
        self.requested, self.lastRequest = true, finite(mono) and mono or nil
        if type(resolve('RequestBattlefieldScoreData')) == 'function' then self:Count('Requests') end
        local _, requestStatus = self:API('RequestBattlefieldScoreData')
        probe.Request, probe.RequestAt = requestStatus, probe.Monotonic
    end
    local filter, filterStatus = self:API('GetBattlefieldScoreFaction')
    probe.Filter = filterStatus == 'ok' and self:Scalar(filter) or {Type=filterStatus}
    local n, status = self:API('GetNumBattlefieldScores')
    probe.Count = status == 'ok' and self:Scalar(n) or {Type=status}
    local updates, seen, fresh = {}, {}, {}
    if status == 'ok' and finite(n) and n >= 0 and n % 1 == 0 then
        if n > MAX_ROWS then probe.Omitted = n - MAX_ROWS; self:Count('Truncated') end
        for i = 1, math.min(n, MAX_ROWS) do
            local row, rowStatus = self:API('C_PvP.GetScoreInfo', i)
            if rowStatus ~= 'ok' or secret(row) or type(row) ~= 'table' then
                probe.Unidentified[#probe.Unidentified+1] = {Index=i, Row=rowStatus == 'ok' and self:Scalar(row, 'row') or self:Availability({Type=rowStatus}, 'row')}
                self:Count('Unidentified')
            else
                local current = {}
                for _, field in ipairs(fields) do current[field] = self:Field(row, field, field) end
                current.stats = self:Stats(row)
                local id, kind
                for _, field in ipairs({'guid', 'name'}) do
                    if current[field].Type == 'string' and current[field].Value ~= '' then id, kind = current[field].Value, field; break end
                end
                local key = id and (kind .. ':' .. id)
                if key and seen[key] then
                    -- Even the first row is ambiguous when a fallback identity repeats.
                    updates[key], fresh[key] = nil, nil
                    for j = #probe.Changes, 1, -1 do
                        local change = probe.Changes[j]
                        if change.IdentityKind == kind and change.Identity == id then table.remove(probe.Changes, j) end
                    end
                end
                if not key or seen[key] then
                    probe.Unidentified[#probe.Unidentified+1] = {Index=i, Row={Type='unavailable', Reason=key and 'duplicate-identity' or 'identity'}}
                    self:Count('Unidentified')
                else
                    seen[key] = true
                    fresh[key] = row
                    local previous, changed = self.baseline[key], {}
                    for field, v in pairs(current) do if not previous or not same(v, previous[field]) then changed[field] = v end end
                    if next(changed) then
                        probe.Changes[#probe.Changes+1] = {Identity=id, IdentityKind=kind, Baseline=previous == nil, Fields=changed}
                        updates[key] = current
                    end
                end
            end
        end
    else self:Count('Unavailable') end
    -- Capture only after duplicate identities have been removed from the fresh map.
    for key, row in pairs(fresh) do self:Retain(row, key, probe) end
    probe.Retention = self:CheckRetention(source, probe.At, fresh)
    -- Atomic probe+diff append: rejected writes must not advance replay baselines.
    if self:Append(probe) then for key, row in pairs(updates) do self.baseline[key] = row end end
    local finish = start and profile()
    if finish and finish >= start then
        local micros = math.min(MAX_COUNT, math.floor((finish - start) * 1000))
        self:Count('TimedSamples')
        self.store.Counts.TotalMicros = math.min(MAX_COUNT, (self.store.Counts.TotalMicros or 0) + micros)
        self.store.Counts.MaxMicros = math.max(self.store.Counts.MaxMicros or 0, micros)
        self.dirty = true
    end
    self.probe, self.busy, self.batching = nil, false, false
    if self.dirty then self.dirty = false; self:Touch() end
end
function board:Stop()
    retained, capturedProbe = {}, nil
    self.generation = self.generation + 1
    if self.timer then pcall(function() self.timer:Cancel() end) end
    self.timer, self.active, self.baseline, self.lastPoll, self.completed, self.retries = nil, false, {}, nil, false, 0
    self.store, self.db, self.container = nil, nil, nil
end
function board:Schedule(delay)
    if self.timer then pcall(function() self.timer:Cancel() end) end
    self.generation = self.generation + 1
    local generation = self.generation
    local fn = resolve('C_Timer.NewTimer')
    if type(fn) ~= 'function' then self.support.Timer = 'missing'; self:Count('TimerFailures'); self.timer = nil; return end
    local ok, timer = pcall(fn, delay, function()
        if generation ~= self.generation then return end
        self.timer = nil
        self:Observe('timer', true)
    end)
    if not ok or secret(timer) or timer == nil then
        self.support.Timer = 'error'; self:Count('TimerFailures'); self.timer = nil
    else self.timer, self.support.Timer = timer, 'ok' end
end
function board:Observe(source, due)
    if source == 'PLAYER_LEAVING_WORLD' then self:Stop(); return end
    if self.busy then return end
    -- Clear the store before support probes so disabled/late callbacks cannot mutate it.
    local db = ChronicleCompanionForeverDB
    if type(db) ~= 'table' or db.sidekick_enabled ~= true then self:Stop(); return end
    if source == 'UPDATE_BATTLEFIELD_SCORE' and self.active and self.timer then return end
    if not self:Present() then self:Stop(); return end
    if source == 'PLAYER_REGEN_ENABLED' then self:RetentionOnly('combat_exit'); return end
    if not self:Open(db) then
        if not self.blockWarned and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage('Chronicle BG scoreboard: ' .. (self.blocked or 'unavailable') .. '; recording paused.')
            self.blockWarned = true
        end
        self:Stop(); return
    end
    local entered = not self.active
    if entered then self.active, self.baseline, self.completed, self.retries = true, {}, false, 0 end
    local winner, winnerStatus = self:API('GetBattlefieldWinner')
    local completion = not self.completed and (source == 'PVP_MATCH_COMPLETE' or (winnerStatus == 'ok' and finite(winner) and (winner == 0 or winner == 1 or winner == 2)))
    if completion then self.completed, self.retries = true, 3 end
    local now = self:API('GetTime')
    local elapsed = finite(now) and self.lastPoll and now - self.lastPoll >= 30
    if entered or due or completion or (source == 'UPDATE_BATTLEFIELD_SCORE' and elapsed) then
        self:Poll(completion and 'completion' or source)
        if due and self.retries > 0 and not completion then self.retries = self.retries - 1 end
        self:Schedule(self.retries > 0 and 5 or 30)
    elseif not self.timer then self:Schedule(self.retries > 0 and 5 or 30) end
end
function board:Status()
    local s = self.store or self.lastStore
    local lines = {('Scoreboard: %s; cadence=30s; probes=%d/%d weight=%d/%d'):format(
        self.blocked or (self.active and 'active' or 'inactive'), s and #s.Probes or 0, MAX_PROBES, s and s.Bytes or 0, MAX_BYTES) }
    if s then
        local parts = {}
        for _, key in ipairs({'Polls','Dropped','Hidden','Unidentified','Unavailable','Truncated','APIErrors','MissingAPIs','TimerFailures','TimedSamples','TotalMicros','MaxMicros','Requests','RetentionChecks','RetentionPublic'}) do parts[#parts+1] = key .. '=' .. (s.Counts[key] or 0) end
        lines[#lines+1] = table.concat(parts, ' ')
    end
    for _, name in ipairs({'IsInInstance','GetNumBattlefieldScores','C_PvP.GetScoreInfo','GetBattlefieldScoreFaction','RequestBattlefieldScoreData','C_Timer.NewTimer'}) do
        lines[#lines+1] = name .. ': ' .. (self.support[name] or (type(resolve(name)) == 'function' and 'available (not probed)' or 'missing'))
    end
    lines[#lines+1] = 'Secret retention experiment: in-memory samples=' .. #retained .. '/3 (cleared on exit/disable/reload)'
    if self.support.Timer then lines[#lines+1] = 'Scoreboard timer: ' .. self.support.Timer end
    for _, line in ipairs(lines) do if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end end
    return lines
end
local frame = CreateFrame('Frame')
for _, event in ipairs({'PLAYER_ENTERING_WORLD','PLAYER_LEAVING_WORLD','ZONE_CHANGED_NEW_AREA','UPDATE_BATTLEFIELD_STATUS','UPDATE_BATTLEFIELD_SCORE','PVP_MATCH_COMPLETE','PLAYER_REGEN_ENABLED'}) do
    if addon.BattlegroundDiagnostics then addon.BattlegroundDiagnostics:Register(frame, event) else pcall(frame.RegisterEvent, frame, event) end
end
frame:SetScript('OnEvent', function(_, event) board:Observe(event) end)
