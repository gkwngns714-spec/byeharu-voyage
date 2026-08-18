# byeharu-voyage — Dev Log

Running record of **requests**, **decisions**, **work done**, **bugs**, and **fixes**.
Newest entries at the top. Dates are absolute (YYYY-MM-DD).

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

### Work dispatched today

Three foundation agents, on disjoint file domains:

| # | Agent | Writes |
|---|-------|--------|
| 1 | Core reuse audit of `byeharu` | `docs/CORE_REUSE.md` |
| 2 | Real-world port / region / goods dataset | `data/*.json`, `docs/WORLD_DATA.md` |
| 3 | Game design, grounded in Uncharted Waters Origin research | `docs/DESIGN.md`, `docs/DESIGN_RESEARCH.md` |
