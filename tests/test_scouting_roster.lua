local addon, frames = {}, {}
function CreateFrame()
 local f = {events={}}
 function f:RegisterEvent(e) self.events[e] = true end
 function f:SetScript(s, cb) self[s] = cb end
 frames[#frames+1] = f; return f
end
local clock, raid, size = 100, false, 1
local units = {player='self', party1='friend'}
function time() return clock end
function IsInRaid() return raid end
function GetNumSubgroupMembers() return size end
function GetNumGroupMembers() return size end
function UnitIsPlayer(u) return units[u] ~= nil end
function UnitGUID(u) return units[u] end
function UnitName(u) return units[u], '' end
function GetRealmName() return 'Realm' end
function UnitLevel() return 60 end
function GetGuildInfo() return nil end
function UnitIsUnit(u,v) return units[u] == units[v] end
function IsInGuild() return false end
ChronicleCompanionForeverDB = {sidekick_enabled=true, minimapHidden=true}
assert(loadfile('ScoutingStorage.lua'))('test', addon)
assert(loadfile('ScoutingRoster.lua'))('test', addon)
local f, r = frames[1], addon.ScoutingRoster
f.OnEvent(f, 'ADDON_LOADED', 'other'); assert(not r.store)
f.OnEvent(f, 'ADDON_LOADED', 'test')
local p = r.store.players
assert(p.self.Name == 'self-Realm' and p.self.Guilds[1] == '')
assert(p.friend.Guilds[1] == false and p.friend.Party[1] == true)
clock = 101; r:Reconcile(); assert(#p.friend.At == 1 and p.friend.LastSeen == 101)
units.party1 = nil; r:Reconcile(); assert(r.members.friend and #p.friend.At == 1)
-- Party to raid is a membership-preserving transition.
raid, size, units.raid1, units.raid2 = true, 2, 'self', 'friend'
r:Reconcile(); assert(#p.friend.At == 1)
-- Confirmed solo produces leaves, not a reload.
raid, size = false, 0
r:Reconcile(); assert(p.friend.Party[2] == false)
size, units.party1 = 1, 'friend'
r:Reconcile(); assert(p.friend.Party[3] == true)
ChronicleCompanionForeverDB.sidekick_enabled = false
r:Reconcile(); size = 0
ChronicleCompanionForeverDB.sidekick_enabled = true
r:Reconcile(); assert(#p.friend.At == 3) -- disabled gap is unknown
-- Reload baseline adds a present observation but never a synthetic leave.
size = 1
assert(loadfile('ScoutingRoster.lua'))('test', addon)
r = addon.ScoutingRoster; r:Load()
assert(#p.friend.At == 4 and p.friend.Party[4] == '_')
clock = 90000
frames[2].OnUpdate(frames[2], 10)
assert(p.friend.At[1] == clock and p.friend.Party[1] == true)
assert(ChronicleCompanionForeverDB.minimapHidden)
-- Missing APIs do not throw or manufacture a departure.
GetNumSubgroupMembers = nil
r:Reconcile(); assert(r.members.friend)
print('scouting roster tests passed')
