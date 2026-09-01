# WORK PLAN — how DESIGN_V1 gets built, across many sessions, without spaghetti

**Written 2026-09-01.** `docs/DESIGN_V1.md` is the design and every decision in it is answered.
This is the *procedure*: what a session does, what it must never do, and what it leaves behind so
the next session can pick up cold.

The enemy is not difficulty. It is **a session that forgets**. Context is compacted, sessions end,
and a rule read at the start is a rule broken at the end. Everything below exists to make the work
survive that.

---

## 1. THE RULE THAT DECIDES EVERYTHING ELSE

> **One slice per session. One concept per slice. The slice lands or it is reverted.**

A slice is not "a feature". It is **one concept, both sides of its contract, and its proof**. If a
slice would leave the server serving something no screen reads, or a screen reading something the
server does not serve, it is two slices or it is one bigger one — never a half.

This is why the queue in §4 is ordered and not a menu.

---

## 2. HOW A SESSION STARTS — every time, no exceptions

1. **`git pull`.** Then read, in this order:
   - `docs/OWNER_REQUESTS.md` — the owner's own words, all of them. This is the highest authority.
   - `docs/DESIGN_V1.md` — the design. Nothing is invented that this does not already say.
   - `docs/WORK_PLAN.md` — this file. §4 says which slice is next.
   - `docs/DEV_LOG.md`'s top entry — what the last session actually did.
2. **Read the deploy state from the target, not from prose.** `supabase migration list --linked`.
   Every doc in this repo has been wrong about the head at some point; the database has not.
3. **Take the next unstarted slice from §4.** Not a later one because it looks easier.

---

## 3. HOW A SLICE IS BUILT

### 3.1 Before a line of code — the §7B questions

`docs/NO_SPAGHETTI.md` §7B, answered **in the slice's PR description**, before writing:

1. **What is the concept, in one noun phrase?**
2. **Where does it live, and why there?** Server or client, which table, which module.
3. **Who is the second caller?** If there will be one, it decides the answer to (2) now, not later.
4. **What would make this wrong?** The thing that, if true, means this design fails.

A slice that cannot answer (3) is the slice most likely to become spaghetti, because the second
caller arrives after the shape is fixed.

### 3.2 The build

- **Its own worktree, its own branch.** `git worktree add ../bv-<slice> -b osn-<slice> main`.
  Never two writing slices in one clone.
- **Compose, never copy.** Before writing a fold, grep for it. This game already has one cargo
  mover, one money mover, one refusal renderer, one grammar, one trade fold. A second of any of
  them is the defect.
- **Migrations are a linear chain.** Take the next free number *at the moment of writing*, and if
  another slice merges first, **regenerate against the new chain** — never textually merge two
  migrations. The number is claimed by the merge, not by the intention.
- **Every migration proves itself in its own transaction**, with a positive control that has been
  watched to go red. `supabase/migrations/README.md` is the law.
- **LF only.** This Windows checkout writes CRLF and the chain guard refuses it.

### 3.3 The gates, in order

1. `npx tsc -b` and `npx eslint src` — locally, before pushing.
2. `npm run db:apply` — if the slice has a migration. Read the self-assert receipt.
3. Push. **CI is the gate that matters**: build, pglite-gate, disposable-chain, acceptance.
4. **Never merge past a red you have not read.** Three times in one day the red was a timeout or a
   dice roll, not a defect — and once it was a genuine latent bug. Read the log every time.

### 3.4 Landing

- Merge, then **deploy the migration by hand**: `supabase db push --linked`. Nothing does this
  automatically, and eight migrations once sat unapplied while the site looked updated.
- **Verify on the target.** `supabase migration list --linked`, then drive the real game in a
  browser. An agent's report and a green tick are claims; the running game is proof.
- Say the deploy state plainly: **built / merged / LIVE**, and which.

---

## 4. THE QUEUE

Stage 1 is serial because each slice settles a concept the later ones need. Stage 2 may run in
parallel **only** once stage 1 is merged, because only then do the shared concepts have one answer.

### Stage 1 — foundations, one session each, in this order

| # | slice | concept it settles | why it must be first |
|---|---|---|---|
| 1 | **Taxonomy** | what a good's category *is* | Captain specialisations and the whole catalogue rest on it |
| 2 | **Catalogue + 1–3 rule** | how many goods exist, and where | 430 goods, strict distribution, demand needs the spread |
| 3 | **Demand** | where a good is *wanted* | The market slice and the price band both read it |
| 4 | **Buildings** | what a building *is* | Storage, workstation, 건조소 and Inn all hang off it |
| 5 | **Items** | what a player *owns N of* | 건조소 and captain promotion both spend them |
| 6 | **Levels** | what playing *earns* | Captain promotion spends them |

### Stage 2 — parallel, disjoint file domains, one worktree each

Storage · Workstation · 건조소 · Inn · Market simplification · Ship stats and fittings ·
Regions and the map split

### Stage 3 — last, because they consume stage 2

Crafting recipes · Captain ranks, roles and cabins · Homesickness

---

## 5. WHAT A SESSION LEAVES BEHIND

A session that ends without these has not finished, however much code it wrote.

1. **`docs/OWNER_REQUESTS.md`** — every instruction the owner gave, in their words, the moment it
   was given. A row leaves OPEN only when built **and driven in the running game**.
2. **`docs/DEV_LOG.md`** — one entry: what landed, what it measured, what it deliberately did not
   do, and what went wrong on the way. The mistakes are the valuable part; they are what stops the
   next session repeating them.
3. **This file's §4** — tick the slice, so the next session knows where the queue is.
4. **The deploy state**, stated: which migration is live, and whether the client matches it.

---

## 6. THE THINGS THAT HAVE ALREADY GONE WRONG, SO THEY DO NOT AGAIN

Each of these cost a real session.

- **A doc said the head was X and the database said Y.** Read the target.
- **Green on PGlite and green on CI still is not production** — both boot empty, production does
  not. A migration that *writes* a precondition must be idempotent.
- **A red that was a clock.** Two CI timeouts and one cancelled job read as failures. Read the log.
- **A red that was dice.** Migration 0047's probe sailed under real weather and failed on a hazard
  roll, randomly, per database. Pin the world before asserting on it.
- **A ledger row that was wrong.** Row 56 claimed a capability was "reachable only from Command"
  when it was reachable from nowhere. A row asserted without checking is worse than no row.
- **A conflict that stopped CI silently.** A PR with a merge conflict never ran its checks at all,
  for five days, and looked merely "pending".
- **A blanket `git add -A` committed conflict markers** into the ledger. Check the file, not the
  push.

---

## 7. WHAT IS NEVER DONE WITHOUT ASKING

- Anything that spends the owner's ducats or moves their real fleet in the live game.
- Merging past a red that has not been read and understood.
- Building something `DESIGN_V1.md` does not say, or does not say yet. If the design is silent, the
  answer is a question to the owner, not an invention.
