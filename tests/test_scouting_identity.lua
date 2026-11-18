local addon, frames = {}, {}
function CreateFrame()
 local f = {}
 function f:RegisterEvent() end
 function f:SetScript(k, v) self[k] = v end
 frames[#frames + 1] = f
 return f
end
local clock, grouped = 100000, true
local units = {player='self', party1='friend', target='near'}
local secret = {}
function issecretvalue(v) return rawequal(v, secret) end
function time() return clock end
function IsInRaid() return false end
function GetNumSubgroupMembers() return grouped and 1 or 0 end
function UnitIsPlayer(u) return units[u] ~= nil end
function UnitGUID(u) return units[u] end
function UnitName(u) return u == 'player' and 'Mr' or units[u], 'Chronicle' end
function UnitIsUnit(u, v) return units[u] == units[v] end
function GetRealmName() return 'CAMWOW US2 Realm 1 PvE' end
function UnitLevel() return 60 end
function GetGuildInfo() return 'Guild' end
function UnitInParty(u) return grouped and (units[u] == 'self' or units[u] == 'friend') end
function UnitInRaid() return nil end
local realms = {self='', friend='CAMWOWUS2Realm5PvE', near='NearRealm'}
local guidRaces = {self='Scourge', friend='Orc', near='Troll'}
local unitRace, sex = 'Scourge', 2
function UnitRace() return 'Localized race', unitRace end
function UnitSex() return sex end
function GetPlayerInfoByGUID(guid)
 return 'Warrior', 'WARRIOR', 'Localized race', guidRaces[guid], 3, 'Mr Chronicle', realms[guid], 999
end
SlashCmdList = {}
ChronicleCompanionForeverDB = {sidekick_enabled=true, scouting_nearby_enabled=true, minimapHidden=true}
for _, file in ipairs({'ScoutingStorage.lua', 'ScoutingRoster.lua', 'ScoutingNearby.lua'}) do assert(loadfile(file))('test', addon) end
for _, f in ipairs(frames) do f.OnEvent(f, 'ADDON_LOADED', 'test') end
local r, n = addon.ScoutingRoster, addon.ScoutingNearby
local players = r.store.players
assert(players.self.Name == 'Mr-Chronicle') -- no unrelated Name format change
assert(players.self.Realm == 'CAMWOW US2 Realm 1 PvE')
assert(players.friend.Realm == 'CAMWOWUS2Realm5PvE')
assert(players.self.Race == 'Scourge' and players.self.Gender == 2)
assert(players.self.Levels[1] == 60) -- GUID position 8 is never a level
assert(players.friend.Race == 'Scourge') -- prefer UnitRace token
-- Scalar changes do not append history, and unavailable metadata preserves it.
local rows = #players.friend.At
unitRace, sex = nil, 3
r:Reconcile()
assert(players.friend.Race == 'Orc' and players.friend.Gender == 3 and #players.friend.At == rows)
realms.friend, guidRaces.friend, sex = '', nil, 1
r:Reconcile()
assert(players.friend.Realm == 'CAMWOWUS2Realm5PvE' and players.friend.Race == 'Orc' and players.friend.Gender == 3)
assert(#players.friend.At == rows)
-- A remote empty realm does not inherit the local realm or UnitName return 2.
units.target = 'empty'
realms.empty = ''
n:Observe('target')
assert(players.empty and players.empty.Realm == nil and players.empty.Race == nil and players.empty.Gender == 1)
-- Nearby collection and its GC refresh carry the same metadata scalars.
units.target, unitRace, sex = 'near', 'Troll', 2
n:Observe('target')
assert(players.near.Realm == 'NearRealm' and players.near.Race == 'Troll' and players.near.Gender == 2)
realms.near, unitRace, sex = 'UpdatedRealm', 'Orc', 3
r.store.gc = r.store.lookup.near
r.store:Collect(clock, 1, function(guid) return r:Refresh(guid) end)
assert(players.near.Realm == 'UpdatedRealm' and players.near.Race == 'Orc' and players.near.Gender == 3 and #players.near.At == 1)
-- Group GC refresh propagates metadata too.
realms.friend = 'GroupRefreshRealm'
r.store.gc = r.store.lookup.friend
r.store:Collect(clock, 1, function(guid) return r:Refresh(guid) end)
assert(players.friend.Realm == 'GroupRefreshRealm' and #players.friend.At == rows)
-- Exceptions and secret return values never enter stored metadata.
local guidAPI, raceAPI, sexAPI = GetPlayerInfoByGUID, UnitRace, UnitSex
GetPlayerInfoByGUID = function() error('unavailable') end
UnitRace = function() error('unavailable') end
UnitSex = function() error('unavailable') end
r:Reconcile()
assert(players.friend.Realm == 'GroupRefreshRealm' and players.friend.Race == 'Orc' and players.friend.Gender == 3)
GetPlayerInfoByGUID = function() return nil, nil, nil, secret, nil, nil, secret end
UnitRace = function() return 'Race', secret end
UnitSex = function() return secret end
r:Reconcile()
assert(players.friend.Realm == 'GroupRefreshRealm' and players.friend.Race == 'Orc' and players.friend.Gender == 3)
units.target = 'secret-new'
n:Observe('target')
assert(players['secret-new'].Realm == nil and players['secret-new'].Race == nil and players['secret-new'].Gender == nil)
-- Every consumed GUID position is guarded, including realm (7). Position 8
-- is deliberately ignored, even when secret, as it has no known semantics.
for position = 1, 7 do
 GetPlayerInfoByGUID = function()
  local values = {'Warrior','WARRIOR','Orc','Orc',2,'Name','Remote'}
  values[position] = secret
  return unpack(values)
 end
 local o = r:Read('party1')
 assert(o.realm == nil and o.race == nil and o.gender == nil)
end
GetPlayerInfoByGUID = function() return 'Warrior','WARRIOR','Orc','Orc',2,'Name','Remote',secret end
assert(r:Read('party1').realm == 'Remote')
-- Local fallback uses confirmed identity, not the token's spelling. Secret
-- local realm and identity results cannot be compared or persisted.
GetPlayerInfoByGUID = function() return nil end
GetRealmName = function() return secret end
assert(r:Read('player').realm == nil)
GetRealmName = function() return 'Local' end
local sameUnit, getGUID = UnitIsUnit, UnitGUID
UnitIsUnit = function() return secret end
UnitGUID = function(u) if u == 'player' then return secret end; return getGUID(u) end
assert(r:Read('party1').realm == nil)
UnitIsUnit, UnitGUID = sameUnit, getGUID
GetPlayerInfoByGUID, UnitRace, UnitSex = guidAPI, raceAPI, sexAPI
-- Missing optional functions are equivalent to unavailable metadata.
GetPlayerInfoByGUID, UnitRace, UnitSex = nil, nil, nil
assert(r:Read('party1').realm == nil and r:Read('party1').race == nil and r:Read('party1').gender == nil)
-- Optional fields accept old records, retain known values across reload and
-- compaction, and reject malformed imported scalars without rewriting them.
local New = addon.ScoutingStorage.New
local db = {sidekick_enabled=true, minimapHidden=true}
local s = New(db)
s:Observe('old', 'Old', 60, '', false, 1)
assert(not New(db).blocked and s.players.old.Realm == nil)
s:Observe('old', 'Old', 60, '', false, 2, false, {realm='Realm', race='Scourge', gender=2})
assert(#s.players.old.At == 1 and not New(db).blocked)
s:Observe('old', 'Old', 60, '', false, 3, false, {realm='', race='', gender=1})
assert(s.players.old.Realm == 'Realm' and s.players.old.Race == 'Scourge' and s.players.old.Gender == 2)
s.gc = 1
s:Collect(90000, 1, function() return {name='Old', level=60, guild='', grouped=false} end)
assert(s.players.old.Realm == 'Realm' and s.players.old.Race == 'Scourge' and s.players.old.Gender == 2)
assert(#s.players.old.At == 1 and s.players.old.At[1] == 90000)
for _, field in ipairs({'Realm', 'Race', 'Gender'}) do
 local saved = s.players.old[field]
 s.players.old[field] = {}
 assert(New(db).blocked and type(s.players.old[field]) == 'table')
 s.players.old[field] = saved
end
assert(db.minimapHidden)
print('scouting identity tests passed')
