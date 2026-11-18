local addon = {}
assert(loadfile('ScoutingStorage.lua'))('test', addon)
local New = addon.ScoutingStorage.New
local db = { sidekick_enabled = true, minimapHidden = true, other = 42 }
local s = New(db)
assert(s:Observe('a', 'A', false, false, true, 1))
s:Observe('a', 'A', 60, '', true, 2)
s:Observe('a', 'A', 60, '', false, 2)
s:Observe('a', 'A', 60, 'G', false, 4)
s:Observe('a', 'A', 60, 'G', false, 3)
assert(#db.collections.scouting.Players.a.At == 4) -- unchanged liveness only
assert(db.collections.scouting.Players.a.LastSeen == 3)
-- Age-based compaction materializes the first retained row.
s = New(db)
s:Collect(86403, 1)
local p = s.players.a
assert(#p.At == 1 and p.At[1] == 4 and p.Levels[1] == 60 and p.Guilds[1] == 'G' and p.Party[1] == false)
assert(db.minimapHidden and db.other == 42)
-- Non-monotonic timestamps and interior deltas.
s:Observe('a', 'A', 61, 'H', false, 1)
s:Observe('a', 'A', 61, 'H', true, 5)
s = New(db)
s:Collect(86403, 1)
assert(s.players.a.Levels[2] == 61 and s.players.a.Guilds[2] == 'H')
for _, enabled in ipairs({false, 1, 'true'}) do
 db.sidekick_enabled = enabled
 assert(not s:Observe('b', 'B', 1, '', false, 8))
end
db.sidekick_enabled = true
-- Malformed data and unknown versions are not touched.
local broken = { Version = 99, Players = {} }
assert(New({collections = {scouting = broken}}).blocked and broken.Version == 99)
local bad = { Name = 'B', LastSeen = 1, At = {1}, Levels = {'_'}, Guilds = {false}, Party = {true} }
assert(New({collections = {scouting = {Players = {b = bad}}}}).blocked)
assert(bad.At[1] == 1 and bad.Levels[1] == '_')
-- Capacity, group protection, expired grouping priority and nearby no-eviction.
s = New({sidekick_enabled = true})
for i = 1, 1000 do assert(s:Observe(tostring(i), 'P', 1, '', false, 100000)) end
assert(not s:Observe('overflow', 'P', 1, '', false, 100001))
s:SetCurrent({['1'] = true})
s.players['2'].LastGrouped = 100000
s.players['3'].LastGrouped = 1
s.insert = 1
assert(s:Observe('group', 'P', 1, '', true, 100001))
assert(s.players['1'] and s.players['2'] and not s.players['3'])
local all = {}; for guid in pairs(s.players) do all[guid] = true end
s:SetCurrent(all)
assert(not s:Observe('full', 'P', 1, '', true, 100002))
-- Incremental GC advances despite holes and gives insertion the freed slot.
s:SetCurrent({})
s.gc = 999
s:Collect(200000, 2)
assert(s.gc == 1 and s.slots[999] == nil and s.slots[1000] == nil and s.insert == 1000)
-- A fresh observation restores a baseline; stale absent data never gets retimestamped.
s = New({sidekick_enabled = true})
s:Observe('a', 'A', 1, false, true, 1)
s:SetCurrent({a = true})
s:Collect(90000, 1, function() return {name='A', level=1, guild=false, grouped=true} end)
assert(s.players.a.At[1] == 90000 and s.players.a.Levels[1] == 1 and s.players.a.Guilds[1] == false)
s.gc = 1; s:SetCurrent({}); s:Collect(180000, 1)
assert(not s.players.a)
-- Unknown lookups preserve enrichment; GC protects unresolved current members.
s = New({sidekick_enabled = true})
s:Observe('a', 'A', 25, 'Guild', true, 1)
s:SetCurrent({a=true})
s:Observe('a', 'A', false, false, true, 2)
assert(#s.players.a.At == 1 and s.players.a.Guilds[1] == 'Guild')
s:Collect(90000, 1, function() return nil end)
assert(s.players.a and #s.players.a.At == 0)
s:Observe('a', 'A', 26, '', true, 90001)
assert(s.players.a.At[1] == 90001 and s.players.a.Levels[1] == 26)
assert(s.players.a.Guilds[1] == '')
-- GC cursor wraps through holes; exact age boundary retains data.
s = New({sidekick_enabled = true})
s:Observe('a', 'A', 1, '', false, 10)
s.gc = 1000; s:Collect(86410, 2)
assert(s.gc == 2 and s.players.a and s.players.a.At[1] == 10)
s.gc = 1; s:Collect(86411, 1); assert(not s.players.a and s.gc == 2)
-- Recent former-party fallback is used only when every other slot is protected.
s = New({sidekick_enabled = true})
local protected = {}
for i = 1, 1000 do
 local id = tostring(i)
 s:Observe(id, 'P', 1, '', true, 100000)
 protected[id] = i ~= 500
end
s:SetCurrent(protected)
s:Observe('500', 'P', 1, '', false, 100001)
assert(s.players['500'].LastGrouped == 100000)
assert(s:Observe('new', 'P', 1, '', true, 100002) and not s.players['500'])
-- Sparse arrays and malformed containers are preserved, not reset.
local sparseDB = {sidekick_enabled=true}
s = New(sparseDB); s:Observe('a', 'A', false, false, false, 1)
s = New(sparseDB); assert(s.players.a.At[1] == 1)
local sparse = s.players.a; sparse.At[3] = 3
assert(New(sparseDB).blocked and sparse.At[3] == 3)
for _, malformed in ipairs({false, 'invalid', 42}) do
 local invalid = {collections = malformed}
 assert(New(invalid).blocked and invalid.collections == malformed)
 local invalidEntry = {collections = {scouting = malformed}}
 assert(New(invalidEntry).blocked and invalidEntry.collections.scouting == malformed)
end
-- Collectors preserve unknown sibling collections and persistent settings.
local future = {Version=99, Events={{At=100, Kind='future-event'}}}
local shared = {sidekick_enabled=true, scouting_nearby_enabled=true, minimapHidden=true,
 other=42, collections={battlegrounds=future}}
s = New(shared)
assert(s:Observe('a', 'A', 60, '', false, 100))
s:Collect(100000, 1)
assert(shared.collections.battlegrounds == future and future.Events[1].At == 100)
assert(shared.collections.scouting.Players == s.players and shared.scouting == nil)
-- Simulate Sidekick's durable capture and clear while WoW is closed, then load.
s:Observe('a', 'A', 60, '', false, 100001)
local captured = shared.collections
shared.collections = {}
s = New(shared)
assert(next(s.players) == nil and shared.collections.scouting.Version == 1)
assert(captured.scouting.Players.a and captured.battlegrounds == future)
assert(shared.sidekick_enabled and shared.scouting_nearby_enabled and shared.minimapHidden and shared.other == 42)
assert(s:Observe('b', 'B', 60, '', true, 100002))
assert(shared.collections.scouting.Players.b and not shared.collections.scouting.Players.a)
-- Missing containers also initialize safely with recording disabled.
shared.collections, shared.sidekick_enabled = nil, false
s = New(shared)
assert(not s.blocked and not s:Enabled() and next(shared.collections.scouting.Players) == nil)
assert(not s:Observe('c', 'C', 60, '', true, 100003))
print('scouting storage tests passed')
