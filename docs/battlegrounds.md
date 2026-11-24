# Battleground evidence collection (Version 1)

This is **SavedVariables collection, not combat logging**. It runs only while
`ChronicleCompanionForeverDB.sidekick_enabled == true` (literal boolean). It does
not call `LoggingCombat`, change logging CVars, affect the minimap logging light,
or write `WoWCombatLog.txt`. Arenas and non-battleground instances are excluded
from this collector. The existing combat logger still excludes battlegrounds.

## Compatibility and evidence contract

**None of these APIs/events have been verified on live WoW Forever.** This is a
best-effort implementation of conventional WoW interfaces, not a claim of complete
Forever objective coverage. Event registration and API calls are protected;
missing, throwing, secret, or unsupported values are skipped. Without usable
`IsInInstance()` and `time()` there is no recording. Collection starts only after
an observed `IsInInstance()` result of `true, "pvp"`.

The event sources are `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`,
`UPDATE_BATTLEFIELD_STATUS`, `UPDATE_BATTLEFIELD_SCORE`, `UPDATE_WORLD_STATES`, and
`CHAT_MSG_BG_SYSTEM_ALLIANCE`, `CHAT_MSG_BG_SYSTEM_HORDE`,
`CHAT_MSG_BG_SYSTEM_NEUTRAL`. On each delivered event, the collector checks current
presence, captures available evidence, and checks `GetBattlefieldWinner()`.
It does not poll, request scoreboards, or collect player scoreboard statistics.

This is **not all possible battleground traffic**. Candidate additional channels
not captured are `RAID_BOSS_EMOTE`, `RAID_BOSS_WHISPER`,
`CHAT_MSG_RAID_BOSS_EMOTE`, `CHAT_MSG_RAID_BOSS_WHISPER`,
`CHAT_MSG_MONSTER_YELL`, `CHAT_MSG_MONSTER_SAY`, `CHAT_MSG_MONSTER_EMOTE`,
`CHAT_MSG_MONSTER_WHISPER`, and generic `CHAT_MSG_SYSTEM`. Some client versions or
battleground scripts may deliver objective/NPC messages on such channels, but
Forever delivery has not been established. They also carry non-objective noise.
Live traces are needed to decide which to include, their argument shapes and any
cross-channel duplicate identity. Player chat, combat-log events, scores, map
POIs, unit auras, and match statistics are not captured. Only the three BG-system
channels above have their first message argument retained; sender, language,
channel metadata, and further chat arguments are not persisted.

Recognized structure currently means the **event envelope** (announcement source,
world-state snapshot, observed lifecycle, completion code), not localized message
classification. All admitted BG-system announcements are raw fallback, including
repeated or unrecognized text. There is no objective-text dictionary or semantic
compression; snapshot deduplication is the only evidence compression. A future
verified locale/client-specific classifier should retain raw evidence and avoid
claiming universal flag/base coverage from these channels alone.

- **Announcements:** the first chat argument is retained verbatim with its exact
  channel/event name. Localized text is **not parsed** into asserted flag pickup,
  capture, return, base assault, defense, ownership, actor, or faction semantics.
  Such actions are evidence only where the client announces or displays them.
  Identical announcements are retained: without a reliable message ID they may
  represent distinct actions.
- **World states:** ordered snapshots of `GetNumWorldStateUI()` rows and the first
  eight positional returns of `GetWorldStateUIInfo(index)`. These conventionally
  represent uiType, state, text, icon, dynamicIcon, tooltip, dynamicTooltip, and
  extendedUI; their actual meanings/types on Forever are unverified. Values are
  raw booleans, finite numbers, or strings; nil positions become `false` (nil and
  actual false are intentionally indistinguishable). Row order/index is UI order,
  **not a stable objective ID**. Consumers must not interpret arbitrary row/text
  changes as authoritative objective transitions. Identical consecutive available
  snapshots are suppressed within a segment. An unavailable snapshot is skipped,
  not replaced by an empty one; a successful count of zero is an empty snapshot.
- **Completion:** `GetBattlefieldWinner()` values 0, 1, or 2 are retained once per
  segment as raw winner codes. Conventional clients use Horde/Alliance/tie codes,
  but that mapping is not asserted here. No completion is inferred from chat,
  leaving, elapsed time, or a missing winner. Completion does not stop collecting
  subsequent evidence until an observed exit.

## Persisted schema

```lua
ChronicleCompanionForeverDB.collections.battlegrounds = {
    Version = 1,
    Events = {
        { At = 1700000000, Kind = "observed_enter", Segment = 1,
          Source = "PLAYER_ENTERING_WORLD" },
        { At = 1700000000, Kind = "world_states", Segment = 1,
          Rows = { { 1, 1, "localized UI text", false, false, false, false, false } } },
        { At = 1700000001, Kind = "announcement", Segment = 1,
          Source = "CHAT_MSG_BG_SYSTEM_NEUTRAL", Text = "localized announcement" },
        { At = 1700000300, Kind = "completion_observed", Segment = 1, Winner = 0 },
        { At = 1700000310, Kind = "observed_leave", Segment = 1 },
    },
    -- Stopped = "capacity" -- only set when a storage limit prevents append
}
```

`At` is observed wall-clock `time()` in integer seconds, **not the match start,
objective occurrence time, or match duration**. Events array order is observation
order; equal or backwards timestamps are possible. `Segment` references the
array index of its `observed_enter`. Segments are observation windows, not match
identifiers. Entry `Source` identifies the event that first exposed presence.

Reload/login starts a new segment on the next observation in a battleground;
it never merges into an old segment or fabricates an end for it. Disabling
Sidekick, once noticed on an event, discards only in-memory continuity; reenabling
starts a new segment. No data is mutated while disabled. Missed exits, reconnects,
disabled intervals, or direct transitions between battlegrounds without an
observed non-pvp state cannot be reconstructed or reliably distinguished. Repeated
world/zone events while continuously in pvp do not create extra entries. Missing
exit/completion events remain missing in storage.

Only this collection entry is owned by the collector. Sibling collections are
preserved. Mutations use `ScoutingStorage.TouchCollections` for the shared
`collections.last_updated` wall-clock marker (including creation and a capacity
stop); no-op/disabled observations do not touch it. No collection is created
merely for logging in outside a battleground.

## Limits and preservation

- At most **512 events** and **262,144 units of storage weight** across all pending
  segments. Weight counts string bytes and eight units per number/boolean,
  including table keys, recursively. It bounds payload growth, not exact Lua heap
  use or serialized file size.
- Each announcement must be at most **4,096 bytes**. Larger/secret/non-string
  messages are skipped, not truncated into misleading evidence.
- A snapshot must have at most **32 rows**, eight fields per row, and at most
  **256 bytes per string field**. Invalid, oversized, or partly unavailable
  snapshots are skipped as a whole. Consequently this is not a lossless stream.
- When the next valid event would exceed the event/weight budget, the collector
  sets `Stopped = "capacity"`, warns once per load (if a chat frame is available),
  and stops appending even across reloads. It **never evicts pending history**.
  Capacity can prevent recording a later exit/completion. There is no automatic
  age-based deletion, ring buffer, or destructive recovery.
- Malformed/oversized existing data, unknown versions, and unknown fields in the
  owned schema block recording with a warning and are preserved unchanged.
  Unknown sibling collections do not block recording.

Chronicle Sidekick should capture and clear `collections` **while WoW is closed**,
then the next load can create fresh storage. The addon does not implement upload,
acknowledgment, or a live-clear protocol. Do not delete pending data to recover
space unless it has been captured or intentionally discarded by its owner.

## Regression validation

Run `nix shell nixpkgs#lua -c sh -c 'for test in tests/test_*.lua; do lua "$test" || exit; done'`
(or use an installed Lua). Deterministic mock tests cover opt-in, preserved siblings,
raw messages, snapshot changes, duplicate world events, completion, observed exits,
reload segmentation, missing/throwing/secret APIs, malformed schemas, both storage
limits, and offline draining. These tests do not verify the live client's API
availability, positional world-state contract, event delivery, or winner timing.
