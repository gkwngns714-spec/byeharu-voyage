# byeharu-voyage — Dev Log

Running record of **requests**, **decisions**, **work done**, **bugs**, and **fixes**.
Newest entries at the top. Dates are absolute (YYYY-MM-DD).

---

## 2026-08-18 — D8: the local gate was blind to Supabase's own default privileges

**The failure.** CI's `disposable-chain` job — the one that boots a real Supabase in Docker and
applies the whole chain — failed applying migration **0001**, on 0001's own self-assert:

```
ERROR: 0001 self-assert FAIL: 16 default ACL entr(ies) would grant a client role a
       write/execute on future objects (SQLSTATE P0001)
```

Three runs in a row (`8d1956e`, `27bcb58`, `0836c31`). `npm run db:apply` and `npm run db:proof`
were **green on this machine** the whole time.

**Root cause, in two halves.**

1. *The revoke was half a revoke.* `ALTER DEFAULT PRIVILEGES ... REVOKE` **without `FOR ROLE` only
   touches the current role's own defaults.** Supabase ships
   `GRANT ALL ON TABLES/SEQUENCES/FUNCTIONS TO anon, authenticated, service_role` in `public`,
   issued by its **own bootstrap role** — not by the role that applies migrations. 0001's revoke
   could not see those entries, so all 16 survived: 12 on tables (`anon` + `authenticated` ×
   INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER), 2 on sequences (UPDATE), 2 on functions
   (EXECUTE). **The assert was correct and caught a real defect.** This is the second time this
   exact shape has bitten: it is what aborted a production deploy in the predecessor project
   (memory note *"Prod grant drift: revoke, don't assert"*), and it is why 0001 exists at all.
2. *The local gate could not see it, and was never able to.* `scripts/db/apply-chain.mjs` boots a
   **bare PGlite**: no `anon`, no `authenticated`, and **no `ALTER DEFAULT PRIVILEGES` entries of
   any kind**. So 0001's lockdown had nothing to revoke and its assert had nothing to find. It
   passed **vacuously** — and so did every other grant / default-ACL / role-dependent assert in
   the chain. A green local run over an empty starting state is not a proof, and this was a whole
   *class* of defect the ten-second gate structurally could not catch.

**The fix, both halves.**

* **0001 §5b** now sweeps the default privileges of **every grantor `pg_default_acl` actually
  names**, not just the current role. It is driven by the catalogue rather than by a guess about
  which roles a given Supabase version uses, and it filters on **the same predicate the assert
  uses**, so the sweep and the law cannot drift apart. It prints the grantors it swept, and if a
  revoke is refused it raises naming the grantor, the current role and the membership required —
  rather than letting the count-only assert fire with no explanation. Nothing is deployed
  anywhere, so **0001 was amended in place; no 0011 patch.** Forward-only starts when the chain
  goes live.
* **`scripts/db/supabase-preamble.sql`** — a new **test fixture, never a migration**, applied by
  `apply-chain.mjs` *before* 0001. It creates the Supabase roles and installs the default
  privileges a real project ships, **under a grantor that is not the role applying the chain** —
  which is the entire mechanism. It lives in `scripts/`, so the Supabase CLI (which only reads
  `supabase/migrations/`) cannot deploy it. `apply-chain.mjs` refuses to run without it and
  refuses to run if it does not print its own receipt.

**The assert was not weakened anywhere.** It was strengthened: its failure message now names the
grantor, schema, object type, grantee and privilege of every surviving entry, because "16 entries"
with no grantor named cost a CI round trip to diagnose.

**Proof the fixture is not decorative** — with the preamble in place and 0001 still unfixed,
`npm run db:apply` fails locally with CI's message, character for character:

```
MIGRATION FAILED: 20260818000001_the_world_is_read_only_to_everyone_but_the_server.sql
  message: 0001 self-assert FAIL: 16 default ACL entr(ies) would grant a client role a write/execute on future objects
  sqlstate: P0001
```

With 0001 fixed, the same command prints:

```
── preamble: scripts/db/supabase-preamble.sql  (test fixture, never deployed)
    supabase-preamble ok: 4 Supabase roles present; 16 assert-visible default ACL entries installed
    under grantor supabase_admin (12 table + 2 sequence + 2 function), reproducing the CI starting state
── 20260818000001_…
    0001: cleared foreign-grantor default privileges with 3 ALTER DEFAULT PRIVILEGES statement(s)
    under grantor(s): supabase_admin
    0001 self-assert ok: lockdown holds …, 0 default-ACL leaks, …
```

**How the 16 was derived, since guessing is what caused this.** CI named the number; the arithmetic
was then reproduced on real PostgreSQL 18.3 (PGlite 0.5.5) by issuing the three
`ALTER DEFAULT PRIVILEGES` statements under a foreign grantor and exploding the result through the
assert's own predicate — 12 + 2 + 2 = 16, on the nose. (PostgreSQL stores no `PUBLIC=X` entry in a
function default ACL created that way, which is why it is 16 and not 17.)

**A defect found by exercising the error paths rather than trusting them.** Both new failure
branches were run deliberately on PGlite (the assert with §5b removed; the sweep run as a role that
is not a member of the grantor). The first raised `operator is not unique: text || "char"` instead
of its own message — `pg_default_acl.defaclobjtype` is `"char"` and needs an explicit `::text`. An
error path that has never been fired is not known to work; this one would have cost another CI
round trip.

**Also changed:** `disposable-chain` now re-checks the default ACLs **from outside** migration 0001
and prints every grantor, so the claim never rests on the migration's own self-assert alone, and a
future failure names whose defaults they were on the first run.

**What is still true and must stay written down:** the PGlite gate is *narrower* than the
disposable-Supabase job, not equal to it. `docs/HANDOFF.md` §2 has been corrected to say so and to
name the class.

---

## 2026-08-18 — DAY ZERO: the pivot, and the founding decisions

**The owner's request, verbatim:**

> "since the combat system, visually and code-wise are not working properly. Therefore i want this
> game to turn into a wording, strategical game, where most of the game played on tabs and commands
> made on a separate tab, and i can follow where my fleets are through map - only visually see where
> it is going and where it is. It is going to be a new game, we will use byeharu core to make a new
> byeharu. This time you will have to make a world map, add real countries, cities, especially
> harbour - sea related cities. It is going to be uncharted island origin (mobile game), similar, but
> will have multiple ships (fleet) to be controlled, invest in cities, rank, etc."

### D1 — A new repository, not a branch of `byeharu`

`byeharu` is a **live multiplayer game** with real players on it and **333 applied migrations**
carrying a space-strategy schema, a spatial-combat engine, and a world editor. Grafting an
age-of-sail trading game onto that chain would be spaghetti by the owner's own law: two games, one
schema, one authority per concept violated on day one.

So: **`byeharu-voyage` is a new repository with a new migration chain that starts at 0001.**
`byeharu` is left running and untouched. What crosses over is the **core** — the stack, the shell,
the auth, and above all the *discipline* (server-authoritative RPCs, self-asserting migrations,
CI apply-proof) — not the schema and not the combat code.

Repo: `https://github.com/gkwngns714-spec/byeharu-voyage` (private).
Local: `C:\Users\디폴리스\byeharu-voyage`.

### D2 — The checkout is LF-only, from the first commit

`byeharu` was bitten by CRLF baking `\r` into sliced SQL so it could never match
`pg_get_functiondef` output, failing production deploys. This repo sets `core.autocrlf=false` and
ships a `.gitattributes` with `* text=auto eol=lf` / `*.sql text eol=lf` **before any SQL exists**,
so that class of bug cannot be born here.

### D3 — Combat is not "fixed later". It is designed out.

The visual combat layer is the thing that failed, visually and in code. This game has **no
battlefield**. Risk at sea (pirates, storms, disease) is a **server-resolved number** reported to
the player as a written after-action report on a log tab. There is no scene to render, so there is
no scene to break.

### D4 — The map is an output device

The map tab shows where fleets are and where they are heading. It **never accepts an order**.
All orders are composed on the Command tab. This is the owner's brief taken literally, and it is
also what makes the game cheap to build and impossible to break with a rendering bug.

### D5 — Database: unblocked, deliberately deferred

Verified on this machine (2026-08-18): the Supabase CLI at
`C:\Users\디폴리스\supabase-cli\supabase.exe` (v2.101.0) **is already authenticated** — it lists the
owner's `byeharu` and `aqua-chronicles` projects. So creating the new project needs no action from
the owner. It is deferred until the first migrations exist, so the project is created against a real
schema rather than an empty one.

There is **no Docker on this machine**, so `supabase start` cannot run locally. As in `byeharu`,
**the real migration chain is proven in GitHub Actions CI**, which does have Docker. That remains
the net.

### D6 — The migration chain runs LOCALLY, on real Postgres, with no Docker

`byeharu`'s single worst handicap is written into its own operating notes: *"SQL migrations can NOT be
run locally — no Docker / Supabase CLI / psql on this machine."* Every SQL mistake there costs a push
and a CI round-trip.

That handicap is **not inherited**. Proven on this machine today, not assumed:

```
VERSION: PostgreSQL 18.3 (PGlite 0.5.5) on wasm32-unknown-linux-gnu
PLPGSQL RESULT: Lisbon->Malacca = 6310.0 nautical miles
RAISE works: unknown port
```

That is a real `plpgsql` function with `SELECT ... INTO`, a `RAISE EXCEPTION`, and haversine maths,
compiled and executed in-process by PGlite — the same package `byeharu` already ships, but used there
only as a parser. So the chain gets proven in **three** places, in this order:

1. **PGlite, locally** — the whole chain applied to real Postgres before a single push. New. Fast.
2. **Disposable Supabase in GitHub Actions** — the apply-proof, exactly as in `byeharu`. Still the net.
3. **Supabase cloud** — production.

Because layer 1 exists, a migration should never reach layer 2 red.

### D7 — Supabase cloud slots are full; production is deferred, development is not

Attempted today, real output:

> `Unexpected error creating project: The following organization members have reached their maximum
> limits for the number of active free projects within organizations where they are an administrator
> or owner: gkwngns714-spec (2 project limit).`

Both free slots are taken by `byeharu` (Singapore) and `aqua-chronicles` (Seoul). A third free project
cannot be created while both are active.

This blocks **nothing** right now: V0 is built and played against layer 1 (PGlite), with the identical
SQL. The cloud project is needed only when the game goes online for other players. When that moment
comes it needs one of: pausing `aqua-chronicles` from the Supabase dashboard (reversible), or upgrading
the `byeharu` org to Pro. That is the owner's call and is not urgent yet — it is recorded here so it is
not a surprise later.

### Work dispatched today

Three foundation agents, on disjoint file domains:

| # | Agent | Writes |
|---|-------|--------|
| 1 | Core reuse audit of `byeharu` | `docs/CORE_REUSE.md` |
| 2 | Real-world port / region / goods dataset | `data/*.json`, `docs/WORLD_DATA.md` |
| 3 | Game design, grounded in Uncharted Waters Origin research | `docs/DESIGN.md`, `docs/DESIGN_RESEARCH.md` |
