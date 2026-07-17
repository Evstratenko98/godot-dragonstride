# Authoritative action stream protocol

`WorldActionStream` is the only top-level orchestrator allowed to start player and
turn-lifecycle mutations. In multiplayer the host owns the FIFO and assigns every
accepted action a monotonically increasing `sequence_id`. Singleplayer executes the
same records and executors without an alternate gameplay path.

## Record and lifecycle

An external request is identified by `(match_id, requester_steam_id, request_id)`.
The host rejects malformed, duplicate, stale-turn, rate-limited, and over-capacity
requests before acceptance. The external queue holds at most 64 records and the
combined internal queue is capped at 256 records. Per Steam ID, the token bucket
accepts 8 intents per second with a burst of 12, while the deduplication window keeps
the latest 256 accepted request IDs.

An actor may have at most one pending external gameplay action in total, counting
both the currently executing record and queued records. Any second external action
for the same actor is rejected with `actor_busy`.

`NetworkActionChannel` transports lifecycle metadata and the bounded snapshot stream:

- accepted or rejected to the requester;
- started, completed, or cancelled to participants;
- the action-boundary snapshot used for initial synchronization and one-shot resync.

Every lifecycle record carries `protocol_version`, `match_id`, and `sequence_id`.
The stable action fields are `request_id`, `sequence_id`, `match_id`,
`requester_steam_id`, `actor_entity_id`, `action_type`, and `turn_revision`.
Gameplay payload travels through the matching character, combat, spell, or inventory
channel on reliable transfer channel 1. A client joins lifecycle metadata and payload
by `sequence_id` before presenting the action.

## Execution and presentation

The host validates gameplay immediately before execution. A record that became
invalid still consumes its sequence and is broadcast as cancelled with a stable
reason. Only one authoritative action mutates the world at a time. The next host
action starts after the previous host presentation completes.

Clients present records in exact sequence order. A client waits for both its local
presentation and the authoritative completed/cancelled lifecycle message. Client
presentation latency never blocks the host. Movement and attack presentations use a
two-second grace watchdog; meteor presentation has a four-second total watchdog.
Unapplied timed-out actions are cancelled with `presentation_timeout`; an action whose
gameplay result was already applied only has its presentation forced to finish.

Player movement sends direction only. The host determines `from_cell`, validates and
reserves `target_cell`, commits the cell at Tween completion, and never accepts a
client completion or canonical position update. Both authoritative and remote player
movement start the walk presentation and update facing from the accepted direction.
NPC movement and attacks during the
composite world turn carry the world action's parent sequence plus a local
subsequence.

## Turns and modes

Free mode is the explicit `free` state. It has no player lifecycle records or
movement/attack/interaction limits, but uses the same FIFO. Turn mode uses internal
`PLAYER_TURN_STARTED`, `WORLD_TURN_STARTED`, and `WORLD_TURN_ENDED` records. The world
turn owns the stream while NPC behaviours run in parallel. Player intents and spell
casts are rejected during that composite action.

`END_PLAYER_TURN` is accepted only while the stream is idle. Its executor atomically
queues the next player-start or world-start continuation before later external
requests can enter behind it. Turn mode changes are host-only `SET_TURN_MODE` system
records. `BLOCKING_EVENT` is reserved for future cutscenes and disallows spell intents.

Spell slots are reserved when a cast is accepted and are consumed when the cast
successfully starts. Reservations are released on cancellation. In turn mode usage is
cleared only on a new full round; free mode has no round usage limit. Entity targets
are resolved again at execution and cancel if missing or dead, while cell targets keep
their accepted cell.

Every change of the allowed action author advances the monotonic `turn_revision`.
Move, attack, interaction, spell cast, inventory use, and end turn intents must carry
the current `match_id` and `turn_revision`. In turn mode, spell cast and inventory use
are accepted only from the active player; inventory move and delete remain available
for organization outside the player's turn.

## Resynchronization boundary

Late join and reconnect are intentionally rejected by the first-iteration match
protocol. An accepted client must finish initial synchronization before it reports
`player_world_ready`. A running client enters one bounded resync cycle when an
expected lifecycle/profile message is missing, a future sequence exceeds the window,
or an auxiliary buffer reaches its limit. Gameplay input remains disabled during
that cycle.

Snapshot requests contain `(match_id, sync_id, expected_sequence_id)`. The host sends
snapshots only between actions; during an action it returns `sync_pending`. A complete
snapshot contains the frozen roster hash, turn revision, inventories and their
revisions, spell usage, entity vitality/cells, object and AI state, dynamic spawns,
removal records, world-turn generation, and the next `boundary_sequence_id`.

The client validates the complete snapshot before mutation and applies registry cell
changes through the atomic batch API. Events below the committed boundary are
discarded. A runtime resync that cannot complete within 35 seconds ends only that
client session; the host match continues and the player becomes disconnected.

Snapshots use schema version 1 and are serialized into at most 16 reliable chunks of
48 KiB, with a total limit of 512 KiB. Chunks are correlated by `sync_id` and are
committed only after the SHA-256 checksum matches. Initial synchronization retries
every 500 ms for up to 8 seconds.

## Bounded delivery

The remote future window is 64 sequence IDs, with at most 64 sequence buckets, 32
profile messages per sequence, and 256 deferred profile messages in total. Stale
messages below `next_remote_sequence_id` are discarded immediately. A missing
sequence/profile payload is watched for two seconds; a missing terminal lifecycle is
watched for five seconds.

All action, turn, combat, inventory, entity, NPC, spawn, snapshot-request, and removal
buffers are cleared with the session. The protocol exposes aggregated local counters
for buffered records, resync attempts/results, stale packets, buffer rejections, and
watchdog activations; these diagnostics are never sent over the network.

## Disconnect and asynchronous generations

The frozen roster is not changed when a client disconnects. Its character stays
visible, registered, targetable, and cell-occupying, but cannot act. Queued external
actions are cancelled with `actor_disconnected`; a started action reaches exactly one
authoritative terminal. Future turns for that player are skipped.

Each world turn advances `world_turn_generation`. NPC completion callbacks are
accepted only when their `(entity_id, generation)` token matches the current pending
entry. Per-NPC behavior has an eight-second watchdog, the whole world turn remains
bounded by 32 seconds, and one NPC may buffer at most eight remote sub-actions.

## Inventory and spell transactions

Inventory intents carry `expected_inventory_revision`; the host validates it both at
acceptance and immediately before execution. A successful add/move/delete/use
increments the revision once. Failed operations restore the previous inventory, and
item-use rollback also restores the typed effect state. `stale_inventory` returns a
fresh authoritative snapshot to the owner.

Meteor casts are correlated by `cast_id`. A cancelled queued/pre-impact cast releases
its reservation and use slot. Impact damage is applied once; a later presentation
timeout cannot roll it back or apply it again.

## Protocol compatibility and limits

The current network protocol version is 2. It is advertised in lobby data, filtered
in lobby discovery, checked in `prepare_match`, transport identity registration, and
snapshots. Builds with another version are rejected before world loading.

Identifiers and display names are limited to 64 characters, roster size to four,
normal intent payloads to 8 KiB, world-record collections to 512, and snapshots to
512 KiB. Every channel validates `match_id`, sender identity, types, bounded values,
and safe reason codes before emitting a domain signal or changing replication state.

This protocol is intentionally incompatible with builds made before the `Actions`
channel and protocol version 2.
