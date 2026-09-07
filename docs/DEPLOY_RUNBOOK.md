# DEPLOY RUNBOOK — putting the chain on production without breaking it

**Written 2026-09-06 with migration 0078.** Everything here is about one thing: nothing in this
repo deploys the database, so a deploy is a person running commands, and the commands have an order.

---

## 0. The one sentence

> **Pages deploys itself on merge. The database does not.** A current site is not evidence of a
> current database, and it never has been.

`.github/workflows/` holds `build`, `acceptance`, `migrations-apply-proof` and `deploy-pages`.
There is **no deploy-migrations job** and there is deliberately no `environment:` on the proof jobs,
so CI cannot reach a hosted project even by accident. Eight migrations once sat unapplied while the
site looked perfectly up to date.

---

## 1. Find out where production actually is

Read it from the target. Every doc in this repo has been wrong about the head at some point; the
database has not.

```
supabase login
supabase migration list --linked
```

The right-hand column is what is applied. Compare it with `ls supabase/migrations/`. **Do not
believe prose about this, including this file.**

---

## 2. Stop the clock BEFORE you push

```sql
select public.unwind_the_clock();
```

Run it in the Supabase SQL editor. It answers how many jobs were running.

**Why this is not optional on a database with rows in it.** `pg_cron` is running
`tick_market_drift` every drift slot, and that tick writes `public.port_goods`. A migration that
re-derives the same table is a second writer, and the two take their locks in opposite orders. That
is not a theory — the apply-proof has died on it twice:

```
ERROR: deadlock detected (SQLSTATE 40P01)
At statement: 15
-- ── 6. THE MARKET FOLLOWS THE WORLD: port_goods re-derived for every (harbour, good) pair
```

(runs `33691161924` on `main` and `33695216552` on a branch, both 2026-09-02, inside migration 0041)

A deadlock in CI costs a re-run. **A deadlock during `db push` aborts the push part-way through the
chain**, which leaves production on a migration nobody chose.

Four migrations currently unpushed write the tick's own tables: **0062**, **0065**, **0066**
(`port_goods`) and **0071** (`price_history`).

**Stopping the clock does not break the game.** `docs/DEV_LOG.md` and migration 0010's header both
say why: the ticks are an optimisation for leaderboard freshness, not a correctness requirement.
Every read settles the fleets it reports (0009), so with the clock stopped the only thing that goes
stale is a fleet nobody is looking at.

---

## 3. Push

```
supabase db push --linked
```

Watch it. If it stops, **read the error before re-running** — that is the whole reason step 2
exists, and re-running past an unread red is how the one red that matters gets waved through.

---

## 4. Start the clock again

```sql
select public.wind_the_clock();
```

It answers what it started. The cadence is derived from `drift_slot_seconds` every time, so it
cannot fall out of step with the knob.

**No migration does this for you, and that is deliberate.** A migration that started the clock would
be the very defect 0078 was written to remove: it would be a thing that starts a tick in the middle
of an apply, for every migration that ever lands after it. So the chain leaves the clock **defined
and stopped**, and a person starts it.

---

## 5. Verify on the target, not on a green tick

```
supabase migration list --linked
```

then **open the game and drive it**. An agent's report and a green check are claims; the running
game is proof. `docs/OWNER_REQUESTS.md` rule 2 exists for this: a row leaves OPEN only when the
thing has been driven.

---

## A fresh database

A database built from scratch — a new project, or CI's disposable stack — ends with its clock
**defined and stopped**, because no migration starts it. Run step 4 once and it is running.

That is a real cost and it is the deliberate trade: the alternative is an apply that deadlocks at
random. It is loud rather than silent — 0012 prints it on every apply, and 0078 prints it again.

---

## What is never done here

* Nothing in this repo pushes to a hosted project automatically, and nothing should.
* Never merge past a red that has not been read. Three times in one day the red was a timeout or a
  dice roll — and once it was a genuine latent bug.
* Never edit a migration that is already applied to production, except for the assert-only case
  argued in `docs/NO_SPAGHETTI.md` §3. 0012 was edited under exactly that rule: it has already run
  on production and will never run there again, so the edit changes nothing there, and what it
  fixes is a from-scratch apply — which is the only thing CI proves.
