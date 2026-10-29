# 2026-10-29 — a chart shows its news (row 216, slice 0279)

**What it is.** The owner (row 216): every chart record kept, and a point on the chart for every
happening, with a press that says what caused it — "real time, news-like". This slice is
docs/NEWS_AND_MARKERS.md's **N3** (the markers read + the client dots), COMPOSED out of what the
writers already feed — the design's `public.world_news` table is NOT built: `public.events` (0004,
append-only, with payloads) IS the news log, so a marker is an EVENT ROW read through one mapping.
No second event log, no duplicated marker registry, no writer hunks, no knob, no switch, no second
clock. Both sides land together: migration `20260818000279_a_chart_shows_its_news.sql` + the client.

**The marker→event mapping** (the design's §2.2 kinds whose writers exist today), held in
`public.news_kinds(kind, importance, scope, min_total)`:

| Event kind (writer) | Design kind | Imp / scope | Anti-spam |
|---|---|---|---|
| `ECONOMY_SWITCH` (0240/0268) | UPDATE ("Update: Economy …") | 3 / world | every one |
| `SOLD` (cmd.do_sell) | BIG_SALE | 2 / port+good+company | total ≥ **250,000** (the design's constant, fixed — NOT a knob; N4 re-cuts it to `news_big_trade`) |
| `BOUGHT` (cmd.do_buy) | BIG_BUY | 2 / port+good+company | same |
| `NPC_REFOUNDED` (0097's upkeep crossing) | MERCHANT_BROKE ("{company} is broke") | 2 / company | the writer's own cooldown + weekly cap |

Design kinds whose writers do not exist yet — NEW_HARBOUR, RELATIONS, WANTS, PRICE_SPIKE, RESTOCK,
PIRATES, the E-slices' gifts — produce NO markers until their slices land (N4/N5/N6). Said in the
header, not hidden.

**The read** `world.news_marks(p_chart, p_port, p_good, p_from, p_to)` — stable, security definer,
authenticated only, one new client entry point (a hunk on `client_rpc_entry_points`, inserted at the
head of the reads, the 0104 trick). Returns ≤ 300 rows (newest kept): id, at, kind, importance,
scope, port_id, good_id, company_id, detail (the template's words as SERVED values). The design's
§3.1 chart table is the read's WHERE. A trade's PORT comes from the ledger's 0277 point columns
(rows written before 0277 carry no port and stand on no city chart — they still read); the GOOD is
matched by the payload's served name (unique in the seed; a duplicate resolves to the lowest code);
the COMPANY is the event's player_id. Rides the partial index `events_news_at (created_at desc)
where kind in (the four)`. Marks sit on the SAME wall-clock axis the charts already draw.

**The client.** `newsMarksModel.ts` (pure geometry: dot r = 3 on the plot's floor line, 24 px hit
target, 12 px cluster with a count and the highest importance, accent for imp 3 / ink-muted for
1–2) — both chart models stay separate and never see a mark; each gained one field, `window`, the
marks map their instants with. `NewsCard.tsx`: the press → a portal card (FIXED, out of flow by
construction — a press selects, it never re-flows anything): the headline from
`src/lib/i18n/dict/news.ts` templates filled with the served detail + `properName` (the client
computes no figure), ago via the axis's own `agoLabel` + the UTC minute, up to 5 cluster items
newest first, "+N more", and an "Open city" link where the caller has navigation (the map's goTo;
the company link waits for the merchant sheet). Marks are re-read with the chart's window
(`useNewsMarks`), never per second — the design's §3.2 rule; the live feed is N2's slice. Mounted
on: the price chart (COMMAND good page, the quay's trade tray, the map's price tray), Stats →
Overview (world money, sold, bought), City purse, Merchants (earned day).

**Words.** One dict file (`news`), EN+KO, the design's own templates; `tests/newsMarks.spec.ts`
proves the fill in both languages and the geometry in Node; `i18n.keys.spec.ts` holds the parity.

**The probe plan (in the self-assert, rolled back; counts ONLY its own rows — it applies on prod).**
A probe house founded at Lisbon; a REAL small trade through `cmd.do_buy` (proves the writers still
write, the 250,000 threshold bites, and 0277's trigger fills the ledger port); the big-trade
markers planted through the ONE authorities for events and money — `public.emit_event` +
`public.credit` with the writer's own payload shape (a probe barca cannot hold a 250,000 trade;
the chain's probe idiom, 0216/0224); a `ECONOMY_SWITCH` world row; a `NPC_REFOUNDED` row; an
UNMAPPED `VOYAGE_REPORT` (anti-proof: never a marker); an OLD row — a backdated switch event,
inserted (the append-only law's permitted half; the fixed probe id) — read with INCLUSIVE bounds
at its own instant. Asserts: each chart serves exactly its design set (price = the port's trades +
the world rows; city = the same; world = the switch rows only; merchants = switch + refound;
another port's chart carries the world rows but none of the probe's trades); every served mark
maps to one mapped event row and the unmapped event serves nothing; UPDATE and DELETE on events
refused; the stats family + the money/event authorities byte for byte (kept-md5); entry points +1
with the new row granted to authenticated only; the walls at 0; 6 timed reads printed in the
receipt; the probe rolled back leaving 0 rows.

**PROD CHECKS (before the push; read-only, one statement per file).**
1. `select count(*) from pg_attribute where attrelid='public.ledger'::regclass and attname in ('port_id','fleet_id','voyage_id') and not attisdropped;` → 3 (0277 applied).
2. `select kind, count(*), min(created_at), max(created_at) from public.events where kind in ('ECONOMY_SWITCH','SOLD','BOUGHT','NPC_REFOUNDED') group by kind order by kind;`
3. Old rows the read must serve: `select count(*) from public.events where kind in ('ECONOMY_SWITCH','SOLD','BOUGHT','NPC_REFOUNDED') and created_at < now() - interval '72 hours';`
4. `select count(*) from public.client_rpc_entry_points();` (the before-count; after = +1).
5. The hunk's pre-image lines occur exactly once in the live body:
   `select (length(def) - length(replace(def, '      -- the reads (world)' || E'\n      (''world''::text, ''snapshot''::text,      ''''::text),', ''))) / length('      -- the reads (world)' || E'\n      (''world''::text, ''snapshot''::text,      ''''::text),') from (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r','') as def) x;` → 1.
6. `select count(*) from public.events where kind='SOLD' and coalesce((payload->>'total')::numeric,0) >= 250000 and created_at >= now() - interval '7 days';` (how many big-trade markers the newest 300 can hold; the price spike / restock / pirates kinds are NOT in the mapping yet — their writers have not landed).

**AFTER THE DEPLOY** (30-minute window; a read does not alter live play, so the after-check is the
client's look plus one timed read): `select count(*) from public.client_rpc_entry_points();` = before
+ 1; one timed `select count(*) from world.news_marks('world', null, null, now() - interval '7 days', now());`
(expect the economy-switch history as imp-3 markers, < 5 ms); one `world.news_marks('price', …)`
window on a busy port. On the client: Stats → Overview shows the switch dots on the three charts;
press → the card in EN and KO (Language switch); the price chart's dots on a port with a ≥ 250,000
sale; a press never moves anything on the page; the series lines are unchanged.

**FORWARD ROLLBACK** (one file, in number order, if the markers must come off before N4):
reverse the entry-points hunk (new → old, the same occurs-once discipline); `drop function
world.news_marks(text, uuid, uuid, timestamptz, timestamptz); drop table public.news_kinds; drop
index public.events_news_at;` — the client's `marks` props default to null, so the client keeps
working untouched (downgrade-safe by construction).

**What is NOT proven** (the migration header says it too): a ≥ 250,000 trade through the real
`cmd` verbs (no probe hold fits one); marks do not update every second while a chart is open
(window-driven reads — the live feed with `news_head` is N2); pre-0277 trade markers carry no port
and stand on no city chart; player company names in markers are public (the design's (D)).

**Chain note.** 0273–0278 land before this file. If any of them hunks
`client_rpc_entry_points`, re-slice this hunk's pre-image against the then-live body before the run
(the occurs-once assert fails loud). `world.game_day` / `world.week_of` (0275's authority) are
untouched — kept-md5 proves it.
