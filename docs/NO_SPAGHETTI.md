# NO SPAGHETTI — the standing law

> The owner, 2026-08-22: *"most of all, sort out your code so that it is well tidy and organized.
> No spaghetti. And for the future as well, design and organize code so that it does not create
> spaghetti."*

`docs/SECTIONS.md` answers **where does this belong?**. This file answers the other half:
**how do I add something without making a second one of it?**

It is not advice. Most of what is written here is checked off disk by
`tests/duplication.spec.ts` and `tests/sections.spec.ts`, and every rule that is *not* checked says
so out loud, so nobody mistakes a paragraph for a guard.

---

## 0. Why a law, and not a preference

This project keeps finding **the same defect**. Not similar defects — the same one, wearing
different clothes. The ledger, all measured, all cited:

| the thing | how many of it | where it is written down |
|---|---:|---|
| *"is this group on a sortie?"* (predecessor project) | **7 copies**, 5 functions, 4 shapes, 3 key sets | `docs/CORE_REUSE.md:1479` |
| *"is this fleet docked?"* (predecessor project) | **11 copies**, 3 inside one function body | `docs/CORE_REUSE.md:1480` |
| the chip recipe | **12 hand-written copies** across Command, Market, Fleets | `src/components/ui/buttonStyles.ts:31-35` |
| the text field | **4 hand-written recipes**, differing in border, focus ring, padding, touch height | `src/components/ui/Input.tsx:5-8` |
| *"how much fits in this hull?"* | **7 implementations** — 4 server, 3 client — **and one of the client copies was already wrong** | `supabase/migrations/20260818000017_a_quartermaster_stows_the_hold_and_a_purser_shaves_the_spread.sql:18-31` |
| *"is this order legal?"* | a second authority, 838 lines, deleted | `src/features/command/README.md:66` |
| the price | a second authority, deleted | `src/features/market/marketRows.ts:4-10` |
| *"what is the maximum I can buy?"* | 2 copies killed in D10, **a third found alive in D11g** | `docs/DEV_LOG.md:397-409` |

Read the fifth row again. Seven answers to one question, and **the seventh had silently drifted** —
`MarketScreen` forgot the stores and had been wrong since the day it was written. Nobody
introduced a bug; somebody added a term to one copy. That is the whole disease in one line:
**duplication does not fail when it is written. It fails when one copy is edited.**

The cost, in the owner's own words, quoted in the predecessor's migration `0349:8-9`:

> *"Everything is messed up when we make or change one thing, spaghetti. What is the point of
> having law and rules?"*

---

## 1. One authority per concept

**A concept has exactly one place that DECIDES it. Everything else asks.**

The hard part is never spotting a copy — it is telling a legitimate **second caller** from an
illegitimate **second author**. Three questions, in order. Any single *yes* makes it an author.

1. **Does it re-derive, rather than read?** If the code recomputes a value that something else
   already computes — from the same inputs, by the same arithmetic — it is an author, however
   short the arithmetic is. `Math.max(0, ship.hold - used)` is nine characters of author.
2. **Would a rule change have to be made here too?** Post a quartermaster who adds +10% stowage.
   If this line must be edited for the game to stay correct, this line owns part of the rule.
   Seven places had to be edited; that is how the count was taken.
3. **Can it disagree?** If two sites can print different answers to one question for the same
   world, they are two authorities — even if they agree today. *Especially* if they agree today,
   because nobody will check them again.

A **caller** does none of that. It names the authority and uses the answer:
`public.fleet_free_hold(fleet)`, `buttonClasses('chip')`, `fleetHoldFree(fleet)`,
`world.market(port).buy`. There is no ceiling on callers. Ten screens calling one function is not
duplication; it is the function working.

### The threshold, and it is not negotiable

Carried from `docs/CORE_REUSE.md:1491-1492`:

> **Written a second time → it becomes a function. Found a third time → stop the feature and fold
> it, the same turn.**

Not "file a task". Not "note it in the dev log". The same turn, before the feature it was found
in ships. `docs/DEV_LOG.md:127-131` records the alternative honestly: composing PORT introduced two
duplications *within ten minutes of writing down the rule that forbade them* — and they were
deleted immediately, which is why they cost ten minutes instead of a migration.

### Say the word

When you find N copies of one rule, **write "spaghetti"** in the first sentence of the finding.
Not "entanglement", not "a design tension", not "the cost of the current shape". A softened verdict
lets the mess survive another session. A comment claiming the fork is deliberate is not evidence
that it isn't spaghetti — it is a copy with an alibi. `0305`'s header names that exact tell:

> *"One comment even reads 'the mover/brake guard VERBATIM', recording the copy as if that made it
> safe. **A rule with seven authors has no author.**"* — `docs/CORE_REUSE.md:1483-1484`

---

## 2. A shared thing is neither screen's

The moment two screens want the same thing, **it stops belonging to the screen that wrote it
first.** It does not get borrowed, wrapped, re-exported or imported sideways — it moves.

`docs/SECTIONS.md:54-58` records the clearest tell this repo has produced: `market/handOff.ts` was
written as an adapter whose stated reason to exist was that *"commandDraft.ts is owned by the CMD
tab"*. **An adapter that exists only to survive a boundary is proof the boundary is in the wrong
place.**

### Where it goes — ask what KIND of thing it is, not who needs it

| the thing is… | it goes to | entrance | test |
|---|---|---|---|
| a **rule of the game** — a fact about a fleet, an order, a price, a voyage | `src/domain/<name>/` | `index.ts` | can it be computed with no React, no screen, no store? |
| **machinery** with no opinion about the game — rpc, db, formatting, geometry | `src/lib/<name>/` | `index.ts` | would it be equally at home in a different game? |
| **how something LOOKS or is operated** — a recipe, a control, a layout | `src/components/ui/` | `index.ts` | is it a shape on screen rather than a fact about the world? |
| **a decision** — anything that changes the world or judges legality | **the server.** A new migration. | — | if the client could compute it, the client could lie about it |
| **the world in memory** — the served payload, the loading and failure gate | `src/live/` | — | is it the one copy of what the server last said? |

Two of those rows are load-bearing and get argued about, so they are settled here:

* **A "rule of the game" that decides anything is not a domain module, it is a migration.**
  `src/domain/*` may only *read what a payload already says* (`docs/SECTIONS.md:39-41`). The
  moment client maths chooses an outcome, there are two authorities and the client's is the one
  that can be edited by a player. `validate.ts` was 838 lines of exactly this, and deleting it —
  not reconciling it — was the fix (`src/features/command/README.md:66`).
* **A recipe is design-system property even if only one screen uses it today.** The chip was
  hand-written twelve times because the first copy was "just this one screen".

### The trap this rule sets, and the only way out of it

A boundary that forbids borrowing does not remove the need to share — it converts it into a
**silent copy**, and that is worse, because a copy has no import for a spec to see. There are two
of those in the tree right now and they are the worked example:

* `PortPicker` exists twice — `features/command/ArgPickers.tsx:111` (exported) and
  `features/market/MarketScreen.tsx:592` (not). MARKET could not import COMMAND's, correctly, so
  it wrote its own. **A picker is not COMMAND's; it is a control.** It belongs in
  `src/components/ui/`, and then there is one.
* `num()` and `str()` — "read a field out of a jsonb payload safely" — exist twice,
  `features/command/PreviewPanel.tsx:131,138` and `features/ledger/LedgerScreen.tsx:357,363`,
  **and they have already drifted**: LEDGER's `num` accepts a numeric that arrived as a string
  (*"jsonb numerics can arrive as a JSON number or as a string, depending on the transport"*) and
  COMMAND's does not. Same question, two answers, one of them wrong on some transports. That is
  machinery, so it belongs in `src/lib/`.

So when the boundary bites, the answer is never "copy it" and never "import sideways". It is
**promote it**, in the same turn, using the table above.

### The three moves that are NOT a fix

* **A wrapper.** See §6.
* **A re-export.** `features/a` exporting `features/b`'s function keeps one owner and adds one
  more name for it. The import graph is checked (`tests/sections.spec.ts`), so this fails anyway.
* **A "shared" folder inside a screen.** `features/command/shared/` is a section wearing a
  disguise. Sections live in `src/domain/`, and they have entrances.

---

## 3. Superseding vs re-cutting a deployed migration

**A migration that has run anywhere is history. It is never edited.** Not to fix a typo in a
comment, not to tidy, not to "correct" a rule. `supabase/migrations/README.md:43-48`.

The reason is not tidiness. `schema_migrations` keys on the version, so a *recorded* migration is
never re-applied: an edit to a deployed file changes what a fresh chain builds and changes
**nothing** on the live server. The two diverge silently, and the file on disk stops being a record
of what production actually runs. `docs/SECTIONS.md:78-82` states the consequence for this repo:
re-cutting `0001–0012` would desync the live project and destroy every player's world to gain a
filing improvement.

### The sanctioned path

**A change to a rule goes in a NEW migration that `create or replace`s the function.** That is not
a workaround for the no-edit rule — it is a better record than an edit would be:

* the chain still replays in order, and the old file **still proves its own claims** when it does
  (`docs/DEV_LOG.md:28-31`);
* the new file states, in its header, what it supersedes and why, so the change has a date, a
  reason and an author;
* `pg_get_functiondef` on the live server matches the LAST definition, which is the one in the
  newest file — one place to look.

Four things a superseding migration must do, all of which `0017` does and all of which have been
skipped at least once in the predecessor project:

1. **Name what it supersedes, with `file:line`.** `tests/duplication.spec.ts` enforces the weaker
   half of this: a migration that re-creates a function an earlier migration created must say
   **"supersede"** in its header. It cannot check that the sentence is true; a reviewer can.
2. **Move everything that must move together, in one file.** `0017:50-55` is the standing example:
   `cmd.do_buy` checked room with `fleet_free_hold` and then placed cargo with `fleet_load`'s
   **own private copy of the same arithmetic**. Wire a bonus into the check and not the placement
   and the player pays for tuns that never land. Both were composed onto one authority in one
   slice, *"or neither would have"*.
3. **Prove the no-op.** If the new rule is inert with no new data (no officer posted, no skill
   studied), the migration re-computes the old definition inline and demands equality. Prose
   saying "this changes nothing" is not evidence (`0017:145-149`).
4. **Say what it deliberately does NOT touch.** `0017:57-64` refuses to let the quartermaster
   reach `voyage.ship_speed`, because speed has one owner — the navigator of `0015` — *"and this
   file does not open a second door to it."*

### When `create or replace` is not enough

Changing a function's **arity** makes an overload, not a replacement, and the old calls then fail
with *"function is not unique"*. Drop and recreate — and **re-issue the grants**, because a
dropped function takes its ACL with it (`0017:83-87`).

### And the mirror rule for the client

`src/lib/db/chain.ts` fingerprints the chain, so editing any migration rebuilds every local
player's database. That is survivable (`docs/DEV_LOG.md:383-387`); a divergence between the file
and production is not.

---

## 4. The self-assert discipline

Every migration proves itself in the transaction that applies it, and `tests/duplication.spec.ts`
checks the shape of every file in the chain: a `do $$ … $$` block, a
`'<NNNN> self-assert FAIL: …'` exception, and a closing
`raise notice '<NNNN> … self-assert ok: …'` receipt. Seventeen of seventeen pass today.

What the spec **cannot** check, and you therefore must:

* **Assert the property, not the statement you just ran.** Count the rows back. Recompute the
  profit. Re-read the flag. `select 1` proves nothing
  (`supabase/migrations/README.md:141-142`).
* **Every assert must be able to fail.** An assert over an empty set passes vacuously and is
  *worse* than no assert, because it reports safety it never checked — the predecessor shipped one
  and it cost a broken production deploy (`supabase/migrations/README.md:143-147`,
  `docs/CORE_REUSE.md:1443-1451`). If a check can only run against rows that may not exist, assert
  the row count first.
* **Carry a positive control, and make it prove the AMOUNT.** `0014:243-244`: *"Trade once, and
  require fame to move BY THE DEFINED AMOUNT — not merely to be non-zero. A weight read from the
  wrong knob would still be non-zero."*
* **Never let a probe pick its subject by lottery.** This has now happened **twice**, in two
  different migrations, and both are written up in the files themselves:
  * `0010:227-238` — the drift assert read ONE row before and after a tick and required it to
    change. `numeric(6,4)` rounds a small OU step to nothing, so it had roughly a **1-in-1,150**
    chance of failing a correct boot. Measured and repointed: 14,967 of 14,980 rows move, and the
    assert now demands 90% and prints the count.
  * `0014:248-258` — *"THIS PICK WAS A LOTTERY, AND IT LOST."* `where pg.stock > 50 limit 1` with
    **no `order by`**, so which good the probe bought depended on heap order, which varies because
    the seed writes rows keyed by `gen_random_uuid()`. It passed twice and failed on the third run
    on an unchanged chain.
  * The fix in both cases is the same and is the rule: **a probe is deterministic and satisfies
    its own preconditions.** `order by` something stable, pick a subject the world will actually
    let you use, and assert that the subject exists before asserting anything about it.
* **A proof never asserts an ambient default it does not own.** Set the precondition yourself
  in-transaction, or follow the game. Growing the world from 12 ports to 214 set off every
  seed-shaped assertion in the chain at once — `= 144 rows`, `"188 nm, 1.6 days"`, *buy sal at
  Lisboa* — and they were rewritten to compute counts from the tables and to **find their own
  subject** (`docs/HISTORY.md:193-196`).
* **Read the answer.** `0014:272-273`: `perform` discarded the result of an order, so a refusal
  arrived as the silent *"no ducats moved"* failure instead of as its own reason.

**Why an unordered `limit 1` is not machine-checked:** it cannot be. There are eight of them in the
chain today and most are legitimate — *"the player's only fleet"* is one row by construction, and
no static rule can tell that from `0014`'s lottery. This one is on the reviewer. When you write
`limit 1` in a `do $$` block, either add an `order by` or write the sentence explaining why the set
has exactly one member.

---

## 5. Delete, don't adapt

**A wrapper around a duplicate is not a fix. It is a third thing.**

When a new model replaces an old one, **the deletion of the old is part of the same change** — not
a follow-up, not a task, not "once it's proven". A feature that ships while its predecessor stays
live is spaghetti by construction, and the predecessor project's own note for this is blunt:
*"never two systems side-by-side behind a flag… replace, then delete the old entirely (code + SQL)
in the same effort."*

This repo has done it correctly enough times to make it the norm rather than an aspiration:

* `validate.ts` — 838 lines — **deleted**, not adapted, when `cmd.preview()` made it a second
  authority (`src/features/command/README.md:66`).
* `features/market/prices.ts` — **deleted**, not reconciled. `src/lib/db/README.md:282` wrote the
  instruction before the work: *"delete that path rather than reconciling two price authorities."*
* The MAX-quantity copy found alive in D11g — *"the fix deletes the copy rather than correcting
  it"* (`docs/DEV_LOG.md:405`).
* `TradedRow`'s `block` prop — *"Two renderings of one fact; this was the copy to delete."*
  (`docs/DEV_LOG.md:305`)
* A new `GamePanel` beside `Card` was **rejected** for being two authorities for "what a panel
  is"; `Card` was changed instead (`docs/DEV_LOG.md:260-264`).

And the counter-example, so the shape is recognisable: `market/handOff.ts` was an adapter written
*to survive a boundary*. It survives today only because the boundary moved and it stopped being a
border crossing — it is now a named intent, not a bridge (`docs/SECTIONS.md:54-58`).

**The test:** if you are writing something whose job is to make two versions of one thing coexist,
you are not fixing the duplication. Stop, and delete one of them.

---

## 6. When a number may live in a test

A test that hard-codes a number is asserting a **world**, not a property. Most of the time that is
a bug: it fails on a correct system the day the world legitimately changes, and it was never
testing what its name claimed.

**Derive it, or find it.** Compute counts from the tables. Ask the world for the best trade a
starter can afford and play whatever it is. Assert `days = nm / knots / 24` rather than
`"188 nm, 1.6 days"`. `docs/HISTORY.md:193-196` is the pass where the whole chain was converted.

**A literal number is allowed in exactly three cases**, and each one carries a duty:

1. **It is a measurement, and the comment says where it was measured.** `tests/map.voyage.spec.ts:232`
   — *"MEASURED in the browser and then pinned here"*. A number in a comment that was never
   rendered is not a measurement; that mistake has its own entry
   (`docs/CORE_REUSE.md:1518-1527`), and its rule is: **if a number gates a decision, a proof
   produces it.**
2. **It is a deliberate inventory that must not change by accident** — the chain's last migration
   (`tests/db.chain.spec.ts:33-34`), the RPC catalogue's allow-list
   (`tests/rpc.surface.spec.ts:423-425`). These exist *precisely so that* adding one is an edit
   somebody made on purpose.
3. **It is a law of the interface**, not a fact about content — 44px of reach, 390px of phone.

### The "moved deliberately" convention

When a pin legitimately changes, **move it in the same change that made it change, and say so in
a dated comment on the line above**:

```ts
// Moved deliberately with 0013-0016 (the record, the house, the roster and the school).
const LAST = '20260818000017_a_quartermaster_stows_the_hold_and_a_purser_shaves_the_spread.sql'
```
```ts
// Pin moved deliberately 2026-08-22: the DEFAULT is now `panel`, because that is what a Card's …
```

`docs/DEV_LOG.md:90-92` shows the entry that goes with it: *"Three test pins moved deliberately"*,
naming each. A pin that moves without a sentence is a test being edited until it goes green, which
is the failure this convention exists to make visible.

**Never weaken to green.** Deleting an assertion, or loosening it to "any outcome", throws away the
coverage. Every legitimate repoint in this repo's history kept or *strengthened* the property.

---

## 7. What is enforced, and what is not

Guards are only worth having if they can fail, so **every guard in this repo was broken on purpose
and watched go red before it was trusted** (`docs/SECTIONS.md:8-9`). A check that has never failed
is decoration. There is a recorded case of one that passed the bug it was written for
(`docs/HISTORY.md:124-126`).

| enforced by | what it refuses |
|---|---|
| `tests/sections.spec.ts` | a screen importing another screen · a domain section reaching up or sideways · a section with no entrance · reaching past an entrance · `lib`/`components` importing anything above them · the design system imported file-by-file instead of through `index.ts` · **`src/chart` reaching up into a screen, the shell, the store or `live/`, and anything reaching past `src/chart`'s entrance** |
| `tests/duplication.spec.ts` | a raw Tailwind palette literal · a class recipe hand-written twice · a screen re-declaring a name the design system or a domain section already exports · two modules exporting one name · a migration with no self-assert receipt · a migration re-creating an existing function without declaring a supersede |
| `tests/db.chain.spec.ts` | a chain that is out of order, CRLF, duplicate-versioned, or has silently gained a migration |
| `npm run db:check-versions` + CI | two migrations sharing a version (a silent no-op deploy) |
| `npm run db:apply` / `db:proof` | every self-assert in the chain, against real Postgres, before a push |

**Not enforced, and therefore yours:** whether an assert is vacuous · whether a `limit 1` is a
lottery · whether a superseding header tells the truth · whether the thing you just wrote already
exists under a different name · whether a number in a test was actually measured · whether the old
path was deleted.

### Why "the same NAME in two files" is not a check

It nearly is. Measured on 2026-08-22 there are exactly **five** module-level names declared in more
than one file, and four of them are real duplication — `statusTone`
(`features/command/OrderQueue.tsx:166`, `features/fleets/FleetsScreen.tsx:499`: byte-identical
bodies, two authorities for what colour a fleet status is), `PortPicker`, `num` and `str` (§2).
The fifth is `TONE`, a private lookup table inside seven different primitives, each mapping a
*different* set of tones. Those are one word, not one concept.

A rule cannot tell those apart, so the rule is not written. What IS written is the half that can
be: **two modules never EXPORT the same name** (`tests/duplication.spec.ts`), and no screen
re-declares a name a section owns. The rest is question 1 of the checklist.

### Seams this repo has, named rather than tidied

* **`src/features/*` imports `src/app/shellState`** (`FleetsScreen`, `LedgerScreen`, `MapScreen`,
  `AuthPage`) while `src/app` renders the screens — a folder-level cycle. The state is not the
  shell's; it is app-wide UI state, and it belongs in a section of its own. Not enforced, because
  the rule would be red the day it was written, and a red guard gates nothing.
* **The eyebrow recipe** (`font-mono text-xs tracking-wider uppercase text-ink-faint mb-0.5`) is
  written twice inside the design system — `Card.tsx` and `PageHeader.tsx` — while
  `SectionLabel` exists. `tests/duplication.spec.ts` treats `src/components/**` as one authority
  and so does not count it; it is a real duplication and it is written here so it is not lost.

**The four open duplications named above — `statusTone`, `PortPicker`, `num`, `str` — are not
seams. They are debt, they are listed so they cannot be lost, and the standing instruction is
§1: fold them.** This list is a claim about 2026-08-22, not evidence; re-derive it before you use
it (`docs/CORE_REUSE.md:1589-1595`).

---

## 7B. THE FORWARD HALF — plan the shape BEFORE you write it

Added 2026-08-23, in the owner's own words: *"no spaghetti - separate independant codes, with plans
for future - meaning future codes must not also be made spaghetti, which means it has to be planned
precisely and correctly."*

Everything above this section is **reactive**: it says what to do once two authorities already
exist. That is necessary and it is not enough. Every duplication this repository has torn out was
cheap to prevent and expensive to remove — seven copies of "how much fits in this hull", four
spellings of "where does her next order happen", two `PortPicker`s, `num`/`str` written three times.
**None of them were written by someone being careless. They were written by someone who did not
decide where the concept lived before they needed it.**

So this section is the counterpart to §8: §8 runs before you FINISH; this one runs before you START.

### The four questions, before the first line of a new thing

1. **What CONCEPT am I adding, in one noun phrase?** Not "a panel for X" — the concept. If you
   cannot name it in one phrase you are adding more than one thing, and they will end up tangled
   with each other. Split them first.

2. **Where does it live, and WHY there?** §2 already gives the test: ask what KIND of thing it is,
   never who needs it first. Write the answer in the file's header. A file whose header cannot say
   why it is in that directory is a file that gets copied into a second directory later.

3. **Who is the SECOND caller going to be?** Answer it now, even though it does not exist yet. Most
   spaghetti in this repo is a thing built for one screen that a second screen then needed:
   `PortPicker`, the chart, `routesByGood`. **If a second caller is plausible, put it where both can
   reach it TODAY** — the cost is a directory choice, and the cost of getting it wrong is a silent
   copy no import check can see (§2's trap). If a second caller is genuinely implausible, say so in
   the header, so the next person knows it was considered rather than missed.

4. **What would make this the WRONG shape, and how would anyone find out?** Name the failure and,
   where it can be, make it a guard. A rule nobody can watch break is a rule that will be broken
   quietly. That is why `duplication.spec.ts`, `sections.spec.ts` and the chart's three entrance
   rules exist, and why every one of them was watched going red before it was trusted.

### What must be planned on paper before it is built

Some shapes cannot be retrofitted cheaply. These require the decision to be WRITTEN — in the
section's own header, or in a doc — before the code exists:

* **A new section or layer** (`src/chart/`, `src/domain/trade/`): what may import it, what it may
  import, and where its single entrance is. `docs/SECTIONS.md` and `tests/sections.spec.ts` must
  gain the rule in the same change, or the boundary is a comment rather than a boundary.
* **A new server contract**: what the payload carries **and what it deliberately does not**, with
  the reason. 0025's board carries a name, a nation, a standing and the fames it is computed from
  because everything else is actionable against another player — that sentence had to exist before
  the SQL did.
* **Anything with two callers on day one.** Two callers is not a coincidence; it is the definition
  of a shared authority. Decide its home before writing either caller.
* **A new word a player reads.** `categoryLabel`, `portNameOf` and `nationNameOf` all exist because
  a code-to-name translation was hand-written first and folded later — one of them seven times, with
  one copy already drifted. Any new code the player must never see needs its one reading NOW.

### The rule that keeps this rule alive

**A plan that lives only in a turn is not a plan.** It is gone at the next context compaction, and
this project has already lost instructions that way. The decision goes in the file's own header,
where whoever next touches the code will read it, or into `docs/SECTIONS.md` where a test can
enforce it. §8's checklist then verifies it was honoured.

If work is handed to a subagent, **the plan is part of the brief**. An agent told "build X" will
build X somewhere. An agent told "build X, it lives HERE, and its second caller will be Y" builds it
where it belongs. Every carve-out in this repo that went well, went well for that reason.

---

## 7C. A RULE IS ABSOLUTE, OR IT IS NOT A RULE

Added 2026-08-23, the owner: *"i want everything to be perfect, meaning that something that does not
to be conditional must not be conditional."*

**The failure this prevents, which actually happened.** `deploy-pages.yml` said, in effect: *if the
cloud credentials are present, publish the online game; otherwise publish the local one.* Both
branches compile, lint, boot and play. So for weeks the published site was a browser-local world
with no account and no server — a house that dies when its owner clears their storage — while every
check downstream stayed green, because nothing downstream can tell the two artefacts apart. **The
only place the difference was knowable was the branch itself, and that is exactly where it was
being swallowed.**

The rule is not "avoid conditionals". Conditionals are how software works. The rule is:

> **A conditional may choose between two ACCEPTABLE outcomes. It may never choose between an
> acceptable outcome and an unacceptable one.** When the alternative is unacceptable, the branch is
> not a choice — it is a failure that has been dressed up as a choice, and it must throw, refuse or
> fail the build instead.

### How to tell which one you are writing

Ask: **if the `else` branch runs, is anyone harmed, misled, or given the wrong artefact?**

* *"If no fleet is selected, ask which"* — a real choice. Both outcomes are fine.
* *"If the catalogue has no name for this code, show the code"* — a real choice. A code is at least
  true, and `portNameOf`'s header says so in as many words.
* *"If the credentials are missing, publish the offline build"* — **not a choice.** One outcome is
  the product and the other is a different product wearing its name. Fail.
* *"If the migration cannot apply, carry on"* — **not a choice.** `src/lib/db/chain.ts` already gets
  this right: it THROWS on a duplicate version rather than booting a world with a rule missing.

### The three shapes to hunt

1. **The silent fallback.** `A ?? B` where B is not merely a lesser A but a different thing. Ask
   what B being wrong would look like from the outside. If the answer is "exactly like success",
   it must be an error.
2. **The swallowed failure.** A `catch` that logs and continues, a `.catch(() => {})`, an
   `-ErrorAction SilentlyContinue`. The refusal contract exists so failures CROSS the boundary as
   refusals; a swallowed one leaves every screen on "Opening the world…" for ever, which this repo
   has already shipped once.
3. **The optional guard.** A check that only runs when something else is configured. `world.buffs()`
   was, for a while, the ONLY thing winding the fair calendar — so fairs existed if and only if a
   player opened one tab. 0028 fixed the mechanism; the shape is the lesson. **A world rule that
   depends on a screen being looked at is not a world rule.**

### And the mirror: do not make ABSOLUTE what is genuinely conditional

Over-applying this is its own defect. A fallback that keeps a truthful, lesser answer on screen is
correct and must not be turned into a crash: an unresolvable port code, a market read that failed
while the prices around it are still true, a chart that has not loaded yet. §7B's fourth question
applies — name what going wrong would look like, and let that decide which shape you are writing.

**The test either way:** a conditional whose branches are both acceptable needs no defence. One
whose `else` is unacceptable needs to stop being a conditional.

---

## 8. The checklist — run this before you finish anything

Ten questions. They take two minutes and every one of them has caught something real in this
repository.

1. **Did I write a rule that already exists?** `grep` for the *concept*, not for the name you
   chose. Seven answers to "how much fits in this hull" used seven different spellings.
2. **Is anything I added the SECOND place that decides something?** If yes: fold it now, in this
   turn, and delete the copy.
3. **If a rule changed tomorrow, how many files would I have to edit?** More than one is the
   answer this file exists to prevent.
4. **Did I delete what my change replaced** — code, SQL, proof, doc sentence — in the same change?
   `docs/DEV_LOG.md:65-68` is the standard: a screen's sentence became false, so it was deleted,
   and three docs that repeated it were corrected in the same pass.
5. **Did I write an adapter?** If its reason to exist is that something is "owned" by another
   part, the boundary is wrong. Move the thing; do not bridge to it.
6. **Did I edit a migration that has run?** Never. New file, `create or replace`, header names what
   it supersedes.
7. **Can my new assert fail?** Break it on purpose. Watch it go red. Put it back. If you did not
   do this, you do not know whether you added a guard or a decoration.
8. **Does my probe pick its subject deterministically, and did I set my own precondition?**
9. **Is every number I pinned a measurement, an inventory, or a law of the interface** — and does
   the comment say which?
10. **Did I run the guards?** `npx playwright test tests/sections.spec.ts tests/duplication.spec.ts`
    for structure, `npm run db:apply && npm run db:proof` for the chain, `npm run typecheck` and
    `npm run lint` for the rest. A green report you did not read is a claim, not evidence.

---

## 9. The one-line version

**If a fact can be read two ways, that duality IS the spaghetti. Pick one, derive or delete the
other — in the turn that created it.**

And its forward half, which is §7B in one line:

**Decide where a concept lives BEFORE you need it twice — because by the time you need it twice, the
copy already exists.**

And §7C in one line:

**If the `else` branch is unacceptable, it is not a branch — it is a failure you agreed to hide.**
