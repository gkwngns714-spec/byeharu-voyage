# byeharu-voyage — Dev Log

Running record of **requests**, **decisions**, **work done**, **bugs**, and **fixes**.
Newest entries at the top. Dates are absolute (YYYY-MM-DD).

---

## 2026-08-18 — D8: a blind local gate, and then an assert that could never pass

Two failures, one after the other, and the second is the more interesting one.

### Round 1 — the local gate was blind

CI's `disposable-chain` job — the one that boots a real Supabase in Docker — failed applying
migration **0001**, on 0001's own self-assert, three runs running (`8d1956e`, `27bcb58`, `0836c31`):

```
ERROR: 0001 self-assert FAIL: 16 default ACL entr(ies) would grant a client role a
       write/execute on future objects (SQLSTATE P0001)
```

`npm run db:apply` and `npm run db:proof` were **green on this machine** the whole time, because
`scripts/db/apply-chain.mjs` boots a **bare PGlite**: no `anon`, no `authenticated`, and **no
`ALTER DEFAULT PRIVILEGES` entries of any kind**. 0001's lockdown had nothing to revoke and its
assert had nothing to find. It passed **vacuously** — and so did every other grant / default-ACL /
role-dependent assert in the chain. A green run over an empty starting state is not a proof.

Fix: **`scripts/db/supabase-preamble.sql`**, a **test fixture, never a migration**, applied by
`apply-chain.mjs` before 0001. It creates the Supabase roles and installs the default privileges a
real project ships, **under a grantor that is not the role applying the chain** — which is the
entire mechanism. It lives in `scripts/`, so the Supabase CLI (which only reads
`supabase/migrations/`) cannot deploy it. The harness refuses to run without it, and refuses to run
if it stops printing its own receipt. With it in place, the unfixed 0001 failed locally with CI's
message character for character.

### Round 2 — the assert was over-broad, and unsatisfiable on the real thing

The first fix made 0001 revoke the defaults of **every grantor `pg_default_acl` names**. CI then
failed with the message that fix was written to produce (run `32122434872`):

```
ERROR: 0001: cannot clear the default privileges held by grantor supabase_admin in schema public
       (object type S). The role applying this migration is postgres, which is not a member of
       supabase_admin, so ALTER DEFAULT PRIVILEGES FOR ROLE is refused.
```

So the grantor was `supabase_admin` and **the revoke is genuinely impossible from the migration
role.** The assert as written could never pass on a real Supabase project.

**The assert was wrong.** Stated plainly, and argued before changing, because that is the rule.
The governing fact — verified by running it, not by reasoning about it:

> **A `pg_default_acl` row applies ONLY to objects created by its own grantor.**

Measured on PostgreSQL 18.3 with all 16 entries in place and 0001 §5a applied:

```
create table public.t_by_postgres        ->  owner postgres        relacl = null            (no client privilege)
create table public.t_by_supabase_admin  ->  owner supabase_admin  anon + authenticated get
                                             INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, SELECT
```

Same split for sequences and functions. `supabase_admin`'s defaults cannot reach an object this
game owns. The assert was demanding control over something the migration cannot control **and**
that does not threaten it — a permanently blocked deploy, which is really just sustained pressure
to delete the check.

**0001 restructured to assert what it can actually guarantee:**

* **(d)** — default ACLs **owned by the role applying the chain** are clean. Kept and narrowed to
  this; these are the ones that decide every object the chain creates. Real protection, unchanged
  in force.
* **(d2)** — foreign grantors' defaults are a permanent **`NOTICE` on every apply**, naming the
  grantor and object types. Never swallowed, never fatal.
* **(i) — NEW, and it is what pays for the narrowing.** Every table, sequence, view and function in
  all four schemas is **owned by the role applying the chain**, so none can have inherited a foreign
  grantor's defaults. That turns (d2)'s un-revokable entries from an unprovable claim into an
  irrelevant one, which is the honest position. Positive control: the same authority
  (`public.objects_not_owned_by()`) asked about a role that owns nothing must return rows — a
  control that needs no privileges, which matters because the migration role on Supabase is not a
  superuser and cannot manufacture a violation to test with.
* Proof 03 gained an **eighth marker**, `GRANT_LOCKDOWN_CHAIN_OWNS_EVERYTHING`, so the ownership law
  is checked at **end of chain** — and CI re-runs proof 03 against the disposable Supabase, which is
  the only place it meets the platform's real roles. The workflow also re-checks both claims with
  raw catalogue queries, independent of the chain's own authorities.

**§5b deliberately does not even attempt the foreign revoke.** It would succeed here (the harness
runs as a superuser) and fail there, putting the cheap gate and CI back on different code paths —
the original defect of this whole episode.

Nothing is deployed anywhere, so **0001 was amended in place; no 0011 patch.** Forward-only starts
when the chain goes live.

**A defect found by firing the error paths instead of trusting them.** Both new failure branches
were run deliberately on PGlite. The first raised `operator is not unique: text || "char"` instead
of its own message — `pg_default_acl.defaclobjtype` is `"char"` and needs an explicit `::text`. An
error path that has never been fired is not known to work.

### What this actually taught, which is subtler than round 1

Round 1's lesson was the obvious one: *CI catches a class of defect the local gate cannot see.*
Round 2's is sharper and worth more:

> **A local gate that models a hostile starting state can produce an assert that is unsatisfiable
> on the real thing.** The preamble was right to exist — without it the defect was invisible. Its
> first assert was wrong, because "reproduce the hostile state" is not the same as "reproduce what
> the migration role is *permitted to do about it*". PGlite runs as a superuser; Supabase's
> `postgres` is not one and is not a member of `supabase_admin`. A fixture that models the
> environment but not the **authority** will happily let you write a check that passes locally and
> can never pass in production.

The general rule this leaves behind: **assert the thing you own, and prove the thing you don't own
cannot reach you.** Not: assert that the platform is shaped the way you would have shaped it.

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
