local addon, frames = {}, {}
function CreateFrame()
 local f = {}
 function f:RegisterEvent() end
 function f:SetScript(k,v) self[k] = v end
 frames[#frames+1] = f; return f
end
local units = {target='near', mouseover='other', player='self'}
local grouped = false
function time() return 100000 end
function IsInRaid() return false end
function GetNumSubgroupMembers() return grouped and 1 or 0 end
function UnitIsPlayer(u) return units[u] ~= nil end
function UnitGUID(u) return units[u] end
function UnitName(u) return units[u], 'Realm' end
function UnitLevel() return 60 end
function GetGuildInfo() return nil end
function UnitInParty(u) return grouped and (units[u] == 'near' or units[u] == 'self') end
function UnitInRaid() return nil end
local forwarded
SlashCmdList = {CHRONICLEFOREVER = function(message) forwarded = message end}
ChronicleCompanionForeverDB = {sidekick_enabled=true, minimapHidden=true, other=10}
for _, file in ipairs({'ScoutingStorage.lua','ScoutingRoster.lua','ScoutingNearby.lua'}) do assert(loadfile(file))('test', addon) end
for _, f in ipairs(frames) do f.OnEvent(f, 'ADDON_LOADED', 'test') end
local r, n, db = addon.ScoutingRoster, addon.ScoutingNearby, ChronicleCompanionForeverDB
assert(db.scouting_nearby_enabled == false)
n:Observe('target'); assert(not r.store.players.near)
SlashCmdList.CHRONICLEFOREVER(' SCOUT ')
assert(db.scouting_nearby_enabled and r.store.players.near.Party[1] == false)
assert(r.store.players.near.LastGrouped == nil)
-- Promote the same nearby entry when it joins.
grouped, units.party1 = true, 'near'
r:Reconcile()
assert(r.store.players.near.Party[2] == true and r.store.players.near.LastGrouped == 100000)
n:Observe('target'); assert(#r.store.players.near.At == 2)
-- Nearby never evicts, even stale players.
for i = 1, 997 do r.store:Observe('fill'..i, 'P', 1, '', false, 1) end
units.target = 'overflow'; n:Observe('target'); assert(not r.store.players.overflow)
-- Existing observations still update in the full buffer.
units.target = 'other'; n:Observe('target'); assert(r.store.players.other.LastSeen == 100000)
frames[2].OnEvent(frames[2], 'NAME_PLATE_UNIT_ADDED', 'nameplate1') -- unresolved
units.nameplate1 = 'other'
frames[2].OnEvent(frames[2], 'NAME_PLATE_UNIT_ADDED', 'nameplate1')
assert(n.byGUID.other == 'nameplate1')
frames[2].OnEvent(frames[2], 'NAME_PLATE_UNIT_REMOVED', 'nameplate1')
assert(not n.byGUID.other)
-- Secret identity and membership results must not reach storage or tracking.
local secret = 'secret-value'
function issecretvalue(value) return value == secret end
local originalGUID = UnitGUID
units.nameplate2 = 'secret-player'
UnitGUID = function(u) if u == 'nameplate2' then return secret end; return originalGUID(u) end
frames[2].OnEvent(frames[2], 'NAME_PLATE_UNIT_ADDED', 'nameplate2')
assert(not n.byUnit.nameplate2 and not r.store.players[secret])
UnitGUID = originalGUID
for _, api in ipairs({'UnitInParty', 'UnitInRaid'}) do
 local original = _G[api]
 _G[api] = function() return secret end
 n:Observe('target')
 assert(not n.byGUID.other and not n.byUnit.target, api .. ' secret must prevent observation')
 _G[api] = original
end
n:Observe('target'); assert(n.byGUID.other == 'target')
-- Optional APIs missing or throwing cannot invent observations.
UnitInParty = nil
n:Observe('target'); assert(not n.byGUID.other)
UnitInParty = function() error('unavailable') end
n:Observe('target'); assert(not n.byGUID.other)
SlashCmdList.CHRONICLEFOREVER('scout')
assert(not db.scouting_nearby_enabled and r.store.players.near)
db.scouting_nearby_enabled = true; db.sidekick_enabled = 'true'
n:Observe('target'); assert(not n.byGUID.other)
assert(db.minimapHidden and db.other == 10)
SlashCmdList.CHRONICLEFOREVER('minimap')
assert(forwarded == 'minimap', 'existing commands must still reach the minimap router')
assert(SLASH_CHRONICLESCOUTING1 == nil and SlashCmdList.CHRONICLESCOUTING == nil)
print('scouting nearby tests passed')
