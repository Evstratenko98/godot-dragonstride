# Authoritative action stream protocol

`WorldActionStream` is the only top-level orchestrator allowed to start player and
turn-lifecycle mutations. In multiplayer the host owns the FIFO and assigns every
accepted action a monotonically increasing `sequence_id`. Singleplayer executes the
same records and executors without an alternate gameplay path.

## Record and lifecycle

An external request is identified by `(requester_steam_id, request_id)`. The host
rejects malformed, duplicate, and over-capacity requests before acceptance. The
external queue holds at most 100 records; internal lifecycle continuations do not
consume this allowance.

`NetworkActionChannel` transports only lifecycle metadata:

- accepted or rejected to the requester;
- started, completed, or cancelled to participants;
- the action-boundary snapshot used by a joining client.

The stable record fields are `request_id`, `sequence_id`,
`requester_steam_id`, `actor_entity_id`, `action_type`, and `turn_epoch`.
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
client completion or canonical position update. NPC movement and attacks during the
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

## Late join

A joining client requests a stream snapshot after its runtime is configured and
buffers live messages until receipt. At the next action boundary the host sends
entity cells/vitality, object state, inventories, turn state, round-scoped spell
usage, and `next_sequence_id`. Events older than that boundary are discarded; newer
buffered events are then presented in order.

This protocol is intentionally incompatible with builds made before the `Actions`
channel and sequenced profile payloads were introduced.
