local addon = {}
local clock = 100
function time() return clock end
assert(loadfile('ScoutingStorage.lua'))('test', addon)
local Storage = addon.ScoutingStorage
local db = {sidekick_enabled=true}
local s = Storage.New(db)
assert(db.collections.last_updated == 100, 'initialization is a persisted change')
clock = 101
s = Storage.New(db)
assert(db.collections.last_updated == 100, 'loading unchanged data is not a mutation')
assert(s:Observe('a', 'A', 60, '', true, 102))
assert(db.collections.last_updated == 102)
s:Observe('a', 'A', 60, '', true, 103)
assert(db.collections.last_updated == 103 and #s.players.a.At == 1, 'liveness-only edits count')
s:Observe('a', 'Renamed', 61, 'Guild', true, 104)
assert(db.collections.last_updated == 104 and #s.players.a.At == 2)
s:Leave('a', 105)
assert(db.collections.last_updated == 105 and s.players.a.Party[3] == false)
-- A sibling collector can use the same marker; no-op scouting must not overwrite it.
db.collections.battlegrounds = {Version=1}
Storage.TouchCollections(db, 200)
s:Observe('a', 'Renamed', 61, 'Guild', false, 105)
s:Leave('missing', 201)
s:Remove('missing', 202)
s:SetCurrent({a=true})
s.gc = 1; s:Collect(203, 1)
assert(db.collections.last_updated == 200, 'no-op observations and GC must not touch the marker')
assert(not s:Observe('bad', 'Bad', 0, '', false, 204))
db.sidekick_enabled = false
assert(not s:Observe('a', 'Changed', 61, '', false, 205))
assert(db.collections.last_updated == 200, 'rejected writes do not touch the marker')
-- Retention pruning and removals are persisted changes, even with recording off.
s.gc = 1; s:Collect(86506, 1)
assert(db.collections.last_updated == 86506 and #s.players.a.At == 0)
s:SetCurrent({})
s.gc = 1; s:Collect(86507, 1)
assert(db.collections.last_updated == 86507 and not s.players.a)
assert(db.collections.battlegrounds.Version == 1)
db.sidekick_enabled = true
s:Observe('b', 'B', 1, '', false, 86508)
clock = 86509; s:Remove('b')
assert(db.collections.last_updated == clock, 'explicit removal defaults to the game clock')
-- A rejected schema cannot change existing metadata or its data.
local broken = {collections={last_updated=7, scouting={Version=99, Players={}}}}
assert(Storage.New(broken).blocked and broken.collections.last_updated == 7)
-- Sidekick clearing the container gives the next load a fresh timestamp.
db.collections = {}
clock = 90000
s = Storage.New(db)
assert(db.collections.last_updated == 90000 and next(s.players) == nil)
-- Unavailable or secret clocks must never leak invalid metadata into SavedVariables.
local originalTime = time
for _, invalid in ipairs({false, 'invalid', -1}) do
 Storage.TouchCollections(db, invalid)
 assert(db.collections.last_updated == 90000)
end
function issecretvalue(value) return value == 'secret' end
function time() return 'secret' end
Storage.TouchCollections(db)
assert(db.collections.last_updated == 90000)
function time() error('unavailable') end
Storage.TouchCollections(db)
assert(db.collections.last_updated == 90000)
time = originalTime
print('collection timestamp tests passed')
