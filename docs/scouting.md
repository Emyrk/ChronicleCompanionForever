# SavedVariables scouting

Status: implemented in the addon with deterministic mock coverage; live Forever API validation remains required before release. The experimental failed-cast probe is not part of this design or the production feature set.

## Scope and integration

Record player levels, guilds, and party/raid presence as enrichment for combat logs. Talents and battleground events come later, in separate collections rather than extra meanings for these arrays. Do not change automatic combat logging.

`ChronicleCompanionForever.toc` already declares the account-wide `ChronicleCompanionForeverDB`. `MinimapButton.lua` initializes that table at the addon's `ADDON_LOADED` and stores `minimapHidden`. Extend the existing table without replacing valid data or unrelated settings. Initialize scouting only after SavedVariables are available. Recording is enabled only when `sidekick_enabled == true`; missing, false, or other values disable recording. This gate does not control combat logging, incremental retention cleanup, or Sidekick capture-and-clear.

## Storage contract

Collection layout and example Lua representation:

```lua
ChronicleCompanionForeverDB = {
    minimapHidden = false, -- existing setting, preserved
    sidekick_enabled = true,
    scouting_nearby_enabled = false, -- persisted user preference
    collections = {
        scouting = {
            Version = 1,
            Players = {
                ["Player-example-guid"] = {
                    Name = "Example",
                    LastSeen = 1700000020,
                    LastGrouped = 1700000010,
                    At     = {1700000010, 1700000010, 1700000020},
                    Levels = {60,         "_",        "_"},
                    Guilds = {"Guild",    "",         "_"},
                    Party  = {true,       "_",        false},
                },
            },
        },
    },
}
```

`collections` is the shared pending-data container. Each collector owns only its named entry and its schema version; future talents and battleground datasets belong beside `collections.scouting`, not inside its player histories. Preserve unknown sibling collections. Persistent settings stay outside `collections` so Sidekick can capture and clear the entire container without resetting preferences. The addon initializes a missing container and scouting entry on load, but preserves malformed containers without recording into them. No migration from the former top-level scouting layout is provided.

- Key players by GUID, not name. `Name` is the latest observed name-and-realm identity label, not a join key or historical name timeline. Do not create entries without a usable GUID and name.
- `At`, `Levels`, `Guilds`, and `Party` are dense, equal-length arrays. A shared index is one observation. Never use nil for an unknown array value.
- `At` holds Unix timestamps in seconds. Timestamps can collide; array order preserves observation order for each player. There are no session IDs or sequence IDs, and no implied ordering between different players' arrays.
- `Levels` holds observed numeric levels. `Guilds` holds guild names; `""` specifically means known guildless. Proposed unknown marker: `false` for unavailable level or guild information. An API query failure must not become a guildless observation.
- Proposed `Party` encoding: `true` means present in the observer's party or raid; `false` means confirmed not in the observer's group, including nearby-only players and observed departures. This is membership, not the unit-token name or a distinction between party and raid.
- The literal Lua string `"_"` means unchanged from the preceding decoded value in that array. It is never a bare Lua variable. It is allowed in `Levels`, `Guilds`, and `Party`, never in `At`. Emit it only when the value is unchanged. Unknown is a value distinct from unchanged.
- The first row of every player entry must contain explicit level, guild, and membership values, using unknown markers for unavailable level or guild data. Membership is always explicitly in-group or out-of-group; unknown membership produces no row. It must decode without earlier data. Every later row must decode by walking forward from that row.

The collection path is `ChronicleCompanionForeverDB.collections.scouting`. The aligned arrays, GUID keys, identity label, literal unchanged marker, and self-contained retained history are the storage requirements.

## Observation behavior

While enabled, snapshot the current party or raid, then reconcile on roster and world events. A load or reload starts a fresh in-memory observation baseline. Record current players as present, even if an earlier persisted row also says present. Do not interpret that row as proof of a newly observed join time.

Within one loaded addon lifetime, compare successful roster snapshots to detect joins and leaves. Include the local player when grouped. A confirmed transition to solo ends the observed group membership. A party-to-raid transition must not manufacture departures for players who remain present.

Record present/join rows, changed level or guild observations, and observed leave rows. Leave rows retain the last known enrichment, or explicit unknowns if none was known. Avoid redundant rows for unchanged snapshots within the same loaded lifetime. A transient unavailable roster or unresolved unit must not by itself imply a departure.

On reload, login, or logout, do not fabricate leave rows for previously saved players. Saved history is not a live roster. Reconcile the newly observable roster without asserting when an unobserved departure occurred. Events during disabled recording or while the addon is not loaded are unknown.

Exact event subscriptions and refresh opportunities for enrichment are subject to client API validation below. Recording is not limited to the combat logger's instance eligibility.

## Capture and clearing

`ChronicleCompanionForeverDB.collections` is the single capture-and-clear boundary. Sidekick must capture the entire container, including collection types and versions it does not understand. It must not clear the container after capturing only selected entries. There is no timestamp acknowledgement or acknowledgement-based pruning path.

Sidekick writes SavedVariables only while WoW is fully closed. Before rewriting, verify that the SavedVariables snapshot is unchanged and that no WoW process using it has restarted; otherwise defer capture and cleanup. Serialize Sidekick writers for the same file. The supported lifecycle assumes no concurrent WoW writers sharing that SavedVariables file.

After durable capture, replace `collections` with an empty table. On the next load, each collector initializes its missing entry. Do not clear or replace the container while the addon is running: collectors retain runtime references to their data.

Addon retention cleanup remains collection-specific. When scouting removes aged rows, decode their carried-forward values, re-encode retained rows in their original array order, compact all four arrays together, and materialize explicit values in the first retained row of each player. If wall-clock changes make timestamps non-monotonic, preserve decoded values across removed interior rows too. Retained history must remain self-contained even when its first row originally used `"_"`.

## Sidekick and Chronicle ownership

1. Sidekick waits for WoW to close, then captures the combat log and the entire `collections` container together, including unknown collection types. It does not select players or correlate player identities or timestamps with the log.
2. Sidekick durably uploads the pair, or durably archives the pair locally for retry. A queued request or an incomplete archive is not durable capture.
3. After either durable outcome, Sidekick can clear the captured container by setting `collections = {}`, even if upload is pending from the archive. Preserve `sidekick_enabled`, `scouting_nearby_enabled`, and every other field outside `collections`, including `minimapHidden`. Never clear data outside the captured snapshot.
4. Chronicle correlates combat logs with enrichment. Sidekick is transport and retention plumbing, not the correlation engine.

The retry archive must retain the combat log and the complete captured container independently of the cleared SavedVariables. No Sidekick repository code is part of this addon change.

WoW flushes SavedVariables on logout or UI reload. In-memory observations are not a realtime disk stream. Crashes can lose observations since the last flush. Logout or reload does not make external writes safe while the WoW process remains open.

## Capacity, retention, and nearby scouting

Keep at most 1,000 players in a circular buffer. The GUID-keyed persisted mapping above may be indexed by runtime slots and a GUID-to-slot lookup rebuilt on load. Maintain separate insertion and GC cursors. Use explicit slot capacity, never Lua's length operator on a slot table with holes.

`LastSeen` is the Unix time of the latest confirmed observation; `LastGrouped` is the latest confirmed observation in the current party/raid, absent if never observed grouped. Refresh these without appending unchanged metadata rows. Current membership comes from the reconciled roster, not persisted `Party` history.

Admission priority:

1. Current party/raid members are protected from capacity eviction.
2. Former members with `LastGrouped` within 24 hours have priority over nearby-only players.
3. Nearby-only players, including former members whose grouping priority has expired, are first eviction candidates.

A new party member uses free space first. Otherwise scan circularly for a low-priority victim, remembering a former-party fallback. Inspect at most 1,000 slots per search; if all are protected, skip and retry on a later reconciliation. Nearby sightings cannot extend former-party priority by refreshing `LastGrouped`.

Nearby scouting defaults off and persists as `scouting_nearby_enabled`. It records only when both this setting and `sidekick_enabled` are exactly true. It may update existing players or occupy free slots, but must never force eviction, even of stale players. Turning it off stops nearby collection without deleting retained data. A player joining the group gains priority in the existing entry. Nearby means observable through supported unit APIs, not arbitrary enumeration of everyone in range; target, mouseover, and nameplate support require client validation.

Use one incremental GC pass with a periodic, fixed slot budget. For example, 10 slots every 10 seconds is an initial tuning proposal, not a schema guarantee. For each visited player:

- Refresh current-group liveness from confirmed roster observations.
- Evict an absent player when `now - LastSeen > 86400`, regardless of former-party priority.
- Otherwise remove observations older than 24 hours and compact the aligned arrays in one pass, preserving carried-forward values and an explicit first retained row.
- When currently observable players lose their entire history, collect a fresh baseline; never timestamp stale absent-player data as a new observation. Remove empty entries when no fresh baseline is available.

This is one pass that either evicts or compacts, not separate cleanup passes. A slot budget does not bound rows processed within one player; per-player compaction remains a single pass for now. Expired data can remain until its GC visit. GC must keep moving forward even when it frees slots.

When GC frees a slot, point the insertion cursor there. After insertion, advance to the next empty slot; if none exists, use the next slot after insertion, wrapping at capacity. Every search has an explicit capacity bound. Sidekick clearing the captured buffer after logout remains the normal cleanup path; GC covers long sessions and missing uploads.

## Deferred decisions and validation

- Per-player observation-count and byte-size caps remain deferred. The 1,000-player and 24-hour policies above bound player count and history age, not total bytes. GC scheduling budgets remain tuning decisions.
- Validate Forever's actual roster enumeration, GUID/name, level, guild, Unix-time, and event APIs before implementation. Candidate lifecycle events include `ADDON_LOADED`, `PLAYER_ENTERING_WORLD`, and the client's supported roster-change events. This document makes no claim of tested Forever API support.
- Verify how the client distinguishes known guildless from unavailable guild data, handles temporarily unresolved roster members, and exposes reliable group departure. Choose event subscriptions and any bounded retries from that evidence.
- Unknown schema versions or malformed aligned arrays must be preserved without recording into or pruning the affected data; report the unsupported state rather than silently resetting it. Confirm the proposed collection/unknown/membership encodings during storage review. Future talents and battleground collections require their own contracts.

## Proposed implementation stack

1. **Spec:** this document only. No runtime changes or probe promotion.
2. **Storage + tests:** initialization and exact-true gate; aligned arrays and literal unchanged encoding; unknown versus guildless; timestamp collisions; whole-container capture-and-clear lifecycle; unknown sibling collection preservation; age-based compaction; materialized first retained rows; empty-player cleanup; preservation of minimap and unrelated fields.
3. **Roster + tests:** validated API adapter; party/raid snapshots and reconciliation; joins, departures, level/guild changes, unresolved units, party-to-raid transitions, disabled recording, and reload without fabricated leaves. Keep combat logging behavior unchanged. Validate client behavior separately from mocked unit tests.

4. **Nearby + tests:** persisted default-off opt-in; validated observable-unit adapters; free-slot-only admission; existing-player updates and party promotion.

## Implementation and local checks

Storage and roster collection now implement this contract. `collections.scouting.Version = 1`
is written for new stores; unversioned scouting entries are also accepted. An
unknown version, malformed player, or imported store above 1,000 players makes
the entire scouting store read-only with a chat warning. This conservative
policy preserves affected data and avoids partial cleanup. Other addon settings
and combat logging remain independent.

The adapter uses conventional modern roster APIs, with legacy party/raid count
fallbacks when `IsInRaid` is unavailable. Event registration is guarded for
client differences. Remote nil guild results remain unknown (`false`); only a
successful local `IsInGuild() == false` confirms guildlessness. Missing identities
make a roster snapshot incomplete, so it cannot produce departures. A valid
count of zero confirms solo. Name labels require an observed realm or the local
realm API. None of these APIs have been verified on a live Forever client here.

Sidekick must set `ChronicleCompanionForeverDB.sidekick_enabled = true` while WoW
is closed to opt in. The addon never enables that flag itself. Any other value
turns recording off. Incremental GC still runs while recording is disabled,
without collecting fresh observations. GC
visits 10 slots every 10 seconds, with no catch-up loop after stalled frames.

Run deterministic Lua 5.1 mocks from the repository root:

```sh
nix shell nixpkgs#lua5_1 -c sh -c 'for test in tests/test_*.lua; do lua "$test" || exit; done'
```

Mocks verify state transitions and storage invariants, not live client API
availability. Before release, test login/reload, party/raid conversion, remote
unit availability, guild queries, and long-session GC on Forever.

### Nearby opt-in

`/clog scout` (also `/chronicle scout`) toggles the persisted nearby preference, which defaults to off.
It does not enable Sidekick recording. Disabling it stops collection and leaves
history intact. Collection observes target changes, mouseover updates, and
supported nameplate add/remove events. There is no scan of arbitrary players,
combat-log event hook, inspection request, or protected action.

The nearby adapter requires working `UnitInParty` and `UnitInRaid` calls and a
complete roster before asserting out-of-group membership. If membership differs
from the reconciled roster, it skips the sighting until reconciliation. Missing
APIs or identities produce no row. GC can refresh still-observable admitted
nearby units, but validates their current GUID to avoid unit-token reuse. An
unchanged sighting refreshes `LastSeen`, never former-group `LastGrouped`.
Validate target/mouseover/nameplate events and unit membership APIs on Forever;
nameplate support is optional and guarded, not assumed to work on that client.
