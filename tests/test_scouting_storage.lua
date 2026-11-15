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
assert(#db.scouting.Players.a.At == 4) -- unchanged liveness only
assert(db.scouting.Players.a.LastSeen == 3)
db.scouting_ack = 2
s = New(db)
local p = s.players.a
assert(#p.At == 1 and p.At[1] == 4 and p.Levels[1] == 60 and p.Guilds[1] == 'G' and p.Party[1] == false)
assert(db.minimapHidden and db.other == 42 and db.scouting_ack == 2)
-- Non-monotonic timestamps and interior deltas.
s:Observe('a', 'A', 61, 'H', false, 1)
s:Observe('a', 'A', 61, 'H', true, 5)
s = New(db)
assert(s.players.a.Levels[2] == 61 and s.players.a.Guilds[2] == 'H')
for _, enabled in ipairs({false, 1, 'true'}) do
 db.sidekick_enabled = enabled
 assert(not s:Observe('b', 'B', 1, '', false, 8))
end
db.sidekick_enabled = true
-- Malformed data and unknown versions are not touched, even by acknowledgement.
local broken = { Version = 99, Players = {} }
assert(New({scouting = broken}).blocked and broken.Version == 99)
local bad = { Name = 'B', LastSeen = 1, At = {1}, Levels = {'_'}, Guilds = {false}, Party = {true} }
assert(New({scouting = {Players = {b = bad}}, scouting_ack = 100}).blocked)
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
print('scouting storage tests passed')
