# The command language, as built

`DESIGN.md` §F is the specification. This file records only the places where the document is
**genuinely silent or internally inconsistent**, and what was chosen instead. Nothing here overrides
§F; where §F says something, §F won.

Everything below is a decision that a future reader could otherwise mistake for an accident.

---

## 1. Twenty-seven verbs, not twenty-six

§F.1's EBNF lists **27** verbs. §E.1's ASCII verb pad shows **21** (it is a wireframe, and it ran out
of room). The EBNF is the grammar, so `grammar.ts` implements the EBNF's 27 and the pad renders all
of them — the eight V0 verbs live, the other nineteen struck through and unpressable.

## 2. A real verb outside V0 raises `E_RANK_LOCKED`, not `E_PARSE`

§K.1 ships eight verbs. `SPLIT`, `INVEST`, `EXPLORE` and the rest are real orders in a game the
player will eventually play, so calling them a parse error would be a lie about the language.
`E_PARSE` means "that is not an order this game understands"; these are orders this game understands
and has not yet opened. `E_RANK_LOCKED` — "not open to you in this version" — is the closest code in
§F.5's closed list, and the sentence names the eight that are.

## 3. `E_CREW_POOL` needs a threshold, and §F.2 does not give one

§F.2's `HIRE` precondition is *"port crew pool ≥ count **or** pay the urgent premium"* — which, read
literally, never refuses anything, yet `E_CREW_POOL` exists in §F.5's list. The choice:

- up to the pool → the ordinary rate;
- between the pool and **twice** the pool → ×2.5 "urgent recruitment", and the check line **warns**;
- beyond twice the pool → `E_CREW_POOL`: the town has not got the men, at any price.

## 4. `BUY`/`SELL` for a fleet at sea is checked against its DESTINATION

§F.2: an order "executes immediately if the fleet is docked; otherwise queued and executed on
arrival — which is the whole point of the queue: *sell the cloves when you get to Amsterdam*." So a
`BUY` on a sailing fleet is **not** `E_NOT_DOCKED`. The market checked is the last port on its
voyage path, and the check line says so and warns that the price will have moved.

`PROVISION`, `HIRE` and `REPAIR` do require `DOCKED` (§F.2 states the precondition and does not
describe queuing them), and `SAIL` accepts `DOCKED` **or** `ANCHORED` (§F.2's `ANCHOR` explicitly
"keeps the fleet available for an immediate `SAIL`").

## 5. Which fleet a fleet-less order belongs to

`BUY sal 60` names no fleet, and §F.1 makes the `FOR <fleet>` clause optional. The missing fleet is
supplied by the **CMD tab's selection**, held in `commandDraft.ts` beside the draft string. That is
what makes a one-line order complete on a phone, and it is why MARKET and PORT set the selection at
the same moment they set the text.

## 6. Codes the V0 static check does not raise

Listed so that "absent" is never mistaken for "forgotten". All are real; each arrives with the
system that owns it.

| Code | Why not at V0 |
|---|---|
| `E_PORT_CLOSED` | Ice closure is a V1 season effect (§B.4). No V0 port can close. |
| `E_LANGUAGE` | Language levels arrive with V1's wider world. |
| `E_STALE` | A version mismatch is a server fact. There is no second device yet. |
| `E_NO_ROUTE` | Raised by the code, but unreachable in the V0 fixture: all 12 ports are connected by the 22 authored legs, so no destination is unreachable. It exists for the moment a leg is removed. |
| `E_MIN_INVEST` … `E_NO_ACADEMY` | Investment, shipbuilding, exploration and officers are all "Not in V0" (§K.1); their verbs are refused wholesale by rule 2 above. |

The codes that **are** raised are asserted, one test each, in `tests/commandGrammar.spec.ts`, and the
closing test pins the set so a new one cannot appear untested.

## 7. `CANCEL` with no index addresses the head of the queue

§F.3's table describes `CANCEL <fleet> [<index>]` but not what an omitted index means. It addresses
the head — the order that is running or about to — because that is the one a player in a hurry
means. The check line always names the order it would remove, in full, before anything happens.

## 8. Where the shared machinery lives

Three modules are imported across feature folders rather than duplicated. Stated here because a
cross-feature import should be a decision, not a habit:

| Module | Owner | Used by |
|---|---|---|
| `features/command/geo.ts` | routing is a `SAIL` concern | fleets (leg progress), market (neighbour radius) |
| `features/fleets/fleetMath.ts` | speed, endurance, hold, progress | command (validation), port, ledger |
| `features/market/prices.ts` | §G.1 price formation | command (cost and limit checks), port |

`features/command/worldModel.ts` assembles them into the one read model every screen shares, and
`fixtures/useWorld.ts` is the only place that model is built from a snapshot and the shell's clock.

## 9. Reach law

`CORE_REUSE.md` §1.5: **"An action may never live inside a region that can scroll or clip it."**

No screen in this domain gives any container a `max-h` or an `overflow` — the page's own scroll is
the only scroll, which is the one the law permits. The single exception is the `Table` primitive's
horizontal scroll box, which is that primitive's stated rule; the tap target in every table is the
**first** column, so it is reachable without scrolling the table at all.

This has been rendered and measured, not argued: at 390×844 in Chromium, all five screens report
`document.documentElement.scrollWidth === clientWidth === 390` and no console errors.

## 10. What is not wired

There is no server, and the screens say so where it matters. `Issue` on the CMD tab does not send
anything: it records the exact string that *would* go to `cmd.issue(fleet_id, raw_text,
expected_version)` and prints it under "Issued this session". The fixture queue does not change. A
button that pretends to have done something is worse than one that admits it has not.
