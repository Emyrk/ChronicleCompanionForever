# Experimental battleground evidence and diagnostics

**No API or event behavior here has been live-verified on WoW Forever.** This PR
collects raw evidence to decide future API contracts, schema and classification.
There is no localized objective classifier and no asserted globally unique match ID.

Collection and diagnostics run automatically only when
`ChronicleCompanionForeverDB.sidekick_enabled == true` (literal boolean). There is
no second diagnostic opt-in. The addon does not enable Sidekick for you. Disabled
observations/status do not mutate SavedVariables. This is **not combat logging**:
no `LoggingCombat`/CVar/minimap-light changes and no `WoWCombatLog.txt` output.
The existing combat logger continues to exclude battlegrounds.

## One-match capture checklist

1. Arrange Sidekick enablement using your existing setup; verify `/clog bgstatus`
   says `Sidekick gate=true; diagnostics=automatic` before queueing. The command
   works outside BG and before initialization, shows counts/caps, registration
   failures, missing APIs and previously observed API failures; it never clears data.
   When enabled it may initialize diagnostic storage. Missing optional APIs are
   expected, not evidence that the remaining collector is broken.
2. Play a battleground normally. Run `/clog bgstatus` inside and after the match;
   retain screenshots/text of any warnings. Target a recognizable BG NPC (and/or
   mouse over it) to capture raw GUID candidates. If possible, have another enabled
   player in the **same match** target the **same NPC** and collect their artifact
   too. Note approximate real time, map, locale, character, result and NPC identity.
3. **Exit WoW completely** to flush SavedVariables. Do not rely on copying the file
   while playing or on `/reload` as a safe offline capture window.
4. **Before Sidekick clears collections**, copy the complete
   `WTF/Account/<ACCOUNT>/SavedVariables/ChronicleCompanionForever.lua` (relative to
   the actual Forever client installation) to a safe artifact location. Retain the
   original file unedited; `.bak` is optional and may describe an older session.
   Alternatively retain Sidekick's full-container capture artifact and verify it
   includes both paths below. Coordinate/temporarily pause external clearing if
   necessary; this addon has no upload acknowledgment or live-clear protocol.
5. Share the artifact(s), capture notes and status output for analysis. The file
   includes player names/GUIDs, NPC/message text and other addon collections;
   handle it as potentially identifying data. Sidekick may capture and clear the
   **whole `collections` container only while WoW is closed**. Never discard the
   sole copy of pending evidence. Restarting after an offline clear creates fresh
   storage; there is no automatic eviction.

Exact persisted paths (both included by existing full-container Sidekick capture):

- `ChronicleCompanionForeverDB.collections.battlegrounds`
- `ChronicleCompanionForeverDB.collections.battlegroundDiagnostics`

Other collection siblings, including scouting and unknown entries, are preserved.
Malformed containers/unsupported owned schemas are preserved rather than reset.
The `collections.last_updated` marker uses observed wall time when available.
Missing time does not prevent diagnostic evidence, but prevents legacy events.

## Diagnostic evidence (`battlegroundDiagnostics.Version = 1`)

Top-level fields are `Version`, `Events`, `Bytes` and `Counts`. Records retain
`Source`, raw `WallTime` (`time()`), `Monotonic` (`GetTime()`) and `Presence`
(`IsInInstance()`). First observation per addon load/container includes registration
success/failure and raw `GetBuildInfo`, `GetLocale`, `UnitGUID("player")`,
`UnitName("player")`. Time values are observation evidence, not event occurrence
or match-start times; monotonic clocks are client-local, not cross-player clocks.

Only an observed `IsInInstance() == true, "pvp"` admits announcement arguments or
BG snapshots. Arena and outside-BG announcements are not saved. Lifecycle/status
API observations can be saved outside BG to diagnose unsupported clients.
No player-chat channels, combat-log streams, or scoreboard statistics are registered.

Candidate announcements are recorded **without semantic interpretation**:

- `CHAT_MSG_BG_SYSTEM_ALLIANCE`, `CHAT_MSG_BG_SYSTEM_HORDE`, `CHAT_MSG_BG_SYSTEM_NEUTRAL`
- `RAID_BOSS_EMOTE`, `RAID_BOSS_WHISPER`, `CHAT_MSG_RAID_BOSS_EMOTE`, `CHAT_MSG_RAID_BOSS_WHISPER`
- `CHAT_MSG_MONSTER_SAY`, `CHAT_MSG_MONSTER_YELL`, `CHAT_MSG_MONSTER_EMOTE`, `CHAT_MSG_MONSTER_WHISPER`
- `CHAT_MSG_SYSTEM`

Other triggers are `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`,
`UPDATE_WORLD_STATES`, `UPDATE_BATTLEFIELD_STATUS`, `UPDATE_BATTLEFIELD_SCORE`,
`PLAYER_TARGET_CHANGED` and `UPDATE_MOUSEOVER_UNIT`. Target/mouseover triggers
only store diagnostic records in BG. No timer, tight polling, or scoreboard
requests are used. Every admitted BG event includes snapshots so a message can be
interpreted alongside contemporaneous API evidence, including unchanged states:

- All raw `GetInstanceInfo()` returns: name, type and conventional eighth return
  map/instance ID are candidates, **not a unique match identifier**.
- `GetBattlefieldWinner()`, including nil and unconventional values.
- Optional `C_PvP.GetActiveMatchState()` / `GetActiveMatchDuration()`.
- `GetNumWorldStateUI()` and up to 64 `GetWorldStateUIInfo(index)` raw rows.
- `GetMaxBattlefieldID()` and `GetBattlefieldStatus(slot)` for up to 16 slots;
  fallback to three conventional slots when the count is unavailable/invalid.
- Raw `UnitGUID("player")`, `UnitGUID("target")`, `UnitGUID("mouseover")` samples.
  Samples can include players or NPCs and are not interpreted/deduplicated as
  instance identifiers. No enumeration of nearby units is attempted.

### Instance identity investigation

`GetBattlefieldStatus` return meanings differ between client versions. The
[Classic API documentation](https://warcraft.wiki.gg/wiki/API_GetBattlefieldStatus/Classic)
labels its third return a displayed instance number (e.g. Warsong Gulch 13), while
other versions label it team size. **All returns are retained without assigning
that position a meaning.** Neither a map ID, displayed server instance number,
nor a GUID component is proven globally unique. Compare same-match multi-player
artifacts and later different-match artifacts before choosing identity semantics.
A single run can discover candidate evidence but cannot prove global uniqueness.

### Raw value representation and support failures

API envelopes contain `API`, positional `Args`, and `Status = "ok"`, `"missing"`
or `"error"`; successful `Returns` and failed `Error` use the same representation.
A raw argument list is `{ n = original_count, Values = { ... }, Omitted = ... }`.
Each position is a tagged table: `Type = "nil"`, `"string"`, `"number"`,
`"boolean"`, `"secret"` or `"unsupported"`; admitted primitives have `Value`.
Thus nil and false remain distinct, including trailing nil returns. Unsupported
values retain `LuaType`, never unsafe object serialization/string conversion.
Secret values (or a throwing secret-value guard) are redacted before comparison.
Strings over 8,192 bytes retain a prefix and original `Bytes`; argument/return
positions beyond 64 are omitted with an explicit count. API failures are protected
and retain safe raw error evidence. Optional APIs may be entirely absent.

### Bounds and counters

Diagnostics retain at most **20,000 records** and **16,777,216 storage-weight
units**, reserving 4,096 units for bookkeeping. `Bytes` is recursive key/value
weight, not serialized file size or Lua heap usage. Counters are bounded numbers:
`Dropped` (record capacity), `Skipped` (unsupported/secret values or unusable
world count), `Truncated` (oversized values/rows/slots), `APIErrors`, `MissingAPIs`,
and `LegacyDropped` (legacy event capacity). These count observations, not distinct
API names; they can continue increasing when record storage is full. Raw records
are never evicted. Capacity warns once per load and `/clog bgstatus` summarizes
counts/caps. A long/noisy match or existing backlog can still exhaust storage;
this is not a lossless guarantee. Registration failures are retained separately
in the first record and reported by status.

## Legacy structured evidence (`battlegrounds.Version = 1`)

Existing schema is unchanged: `Events` contains `observed_enter` (with `Source`),
`announcement` (`Source`, `Text`, only BG-system channels), `world_states` (`Rows`),
`completion_observed` (`Winner` 0/1/2), and `observed_leave`. Every event has `At`
(integer wall seconds) and `Segment` (index of observed entry, **not match ID**).
Reload/re-enable starts another observation window. No actual start/end, faction
winner mapping, or objective actions are inferred. World rows retain the first
eight returns, replacing nil with false, deduplicate identical snapshots, and
require at most 32 rows and 256-byte strings. Legacy announcement strings above
4,096 bytes are skipped; diagnostics retain safer richer raw evidence separately.

Legacy capacity is now **20,000 events / 8,388,608 weight units**, rather than 512
small events. Capacity sets `Stopped = "capacity"`, warns, and never evicts history.
Malformed/unknown legacy stores pause the collector without changing them or their
siblings. Missed exits, disabled intervals and continuous pvp-to-pvp transitions
cannot be reliably reconstructed by the legacy segment logic; raw instance
observations are provided for investigation, not speculative merging.

## Regression validation

Run `nix shell nixpkgs#lua -c sh -c 'for test in tests/test_*.lua; do lua "$test" || exit; done'`.
Tests use deterministic clocks/APIs, not live servers: gating, raw nil/false and
secret/unsupported values, API/registration failures, optional identity APIs,
command routing, caps/counters, and preserved collections. Passing tests does not
establish live Forever API support, event delivery, winner timing or global IDs.
