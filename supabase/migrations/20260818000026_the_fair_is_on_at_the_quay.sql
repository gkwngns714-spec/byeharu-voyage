-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0026 — THE FAIR IS ON AT THE QUAY
--        BUFFS: a timed modifier table, read at the point of use — and the first thing it modifies
--        is the port's own cut, through the ONE function that already publishes it.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHERE THIS WAS ALREADY DECIDED TO LIVE ─────────────────────────────────────────────────────
-- docs/SECTIONS.md, "Where the sections that do not exist yet will go":
--
--   | buffs | its own migration: a timed modifier table, applied where it is read | must not be
--                                                                                  summed into a
--                                                                                  stored total
--                                                                                  anywhere |
--
-- Both halves are obeyed literally. `public.active_buffs` is a table of rows with a `starts_at`
-- and an `ends_at` — a row that has not begun and a row that has expired both contribute exactly
-- nothing, which is asserted in both directions below. And NOTHING anywhere stores a folded total:
-- `public.buff_multiplier()` is computed on every read, and the self-assert sweeps the catalogue
-- for a buff-shaped column on `ports`, `players`, `fleets` or `ships` and fails if one exists.
--
-- ── A BUFF THAT CHANGES NOTHING IS DECORATION ──────────────────────────────────────────────────
-- 0015 and 0016 both shipped a catalogue that no rule read, and both had to carry a `takes_effect`
-- flag so a card could admit it. That is not repeated here: ONE kind is authored and that kind is
-- READ, by `world.spread()`, on every price the game quotes.
--
-- ── WHY THE PORT'S CUT, AND NOT SPEED, HOLD OR THE DAILY CAP ───────────────────────────────────
-- A timed modifier can only live where the number it modifies is READ AT THE POINT OF USE. Three
-- candidates were examined against the chain as it actually is:
--
--   speed      REJECTED, and this is the interesting one. `voyage.depart` FREEZES the fleet's
--              speed into `voyages.speed_profile` (0006:62, "v_fleet per leg is FROZEN at
--              departure"). A weather buff wired to speed would therefore be SUMMED INTO A STORED
--              TOTAL the moment a fleet sailed — the precise thing SECTIONS.md forbids — and a
--              fair that ended mid-voyage would still be pushing the hull along. The freeze is
--              load-bearing (it is what makes offline settlement byte-identical, proof 01), so the
--              buff moved rather than the freeze.
--   hold       REJECTED. `public.ship_hold_capacity` is read at the point of use, so it would have
--              worked — but a fair that makes a hull bigger for four days is nonsense the player
--              would have to be told to ignore.
--   the cap    REJECTED HERE, DELIBERATELY. `world.daily_cap_remaining` is read at the point of
--              use and a fair lifting it is good sense — but 0016 recorded that the ACCOUNTING
--              skill "attaches in world.daily_cap_remaining", and that wiring lands in 0027. Two
--              new terms arriving in one function from two migrations on the same day is how a
--              composition goes unproven. The cap gets exactly one new reader, in 0027.
--
--   THE CUT    TAKEN. DESIGN G.1 splits a price into a WORLD half and a PORT half:
--
--                  ask = mid x (1 + tax + spread/2)     bid = mid x (1 - spread/2) x (1 - tax)
--
--              `mid` is what the thing is WORTH and 0022 forbade any negotiation from touching it.
--              `spread` is THE PORT'S CUT — and a fair is a fact about the port, publicly, for
--              everybody standing on that quay. It is read at the point of use on every quote and
--              stored nowhere.
--
-- ── WHY world.spread() AND NOT world.spread_effective() ────────────────────────────────────────
-- 0022 minted `world.spread_effective(port, good, fleet)` as THE spread a given HOUSE executes at
-- — her purser, her bargain — and left `world.spread(port)` as the port's PUBLISHED figure. That
-- boundary is exactly right and this file keeps it:
--
--   * a fair is PUBLIC. Every house on the quay gets it, nobody negotiates for it, and
--     `world.market()` prints it on the port card. It therefore belongs in the PUBLISHED number.
--   * putting it in `spread_effective` instead would have made `world.market()` print an ask that
--     no trade charges — 0022's decision 3 named that as the defect to avoid ("what world.market()
--     shows is still what a trade charges"), and it is why HAGGLING hardens the odds and not the
--     price.
--
-- And because `world.spread_effective` computes `v_pub := world.spread(p_port)` as its first line
-- (0022:317), EVERY executed trade reaches the fair through the single authority that already owns
-- "what does this house execute at". THIS FILE DOES NOT TOUCH `world.spread_effective`, `world.
-- quote`, `cmd.do_buy` or `cmd.do_sell`. One line changes, in one function, and the purser, the
-- bargain, the floor and the cap all keep composing exactly as 0022 and 0024 proved they do —
-- which is asserted below on a real fleet carrying both, rather than argued.
--
-- 0017:67 REJECTED "making world.spread(port) player-aware" and that rejection still stands: this
-- file does not make it player-aware. It takes the same one argument, returns one number, and that
-- number is the same for every captain in the harbour.
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ──────────────────────────────────────────────────────────────
--   0005:292-305  world.spread(port) — the port's cut as a pure function of dev_commerce, with no
--                 notion of a calendar. Superseded below; identical when no fair is running, proven
--                 against a captured pre-image of real quotes rather than claimed.
--   0018/0022     public.client_rpc_entry_points() — one row added for the new read.
--
-- ── THE CALENDAR IS DATA, NOT CODE ─────────────────────────────────────────────────────────────
-- `public.buff_kinds` carries everything about a fair: what it is worth, how long it lasts, how
-- often it comes round and how likely a given port is to hold one. Adding a second kind of buff is
-- a row, not a function — the game-development rule this project keeps ("a new ship / module /
-- captain must be ROWS, not code"). Nothing here reads a `festival_*` knob, because a magnitude in
-- a knob AND a magnitude on the row would be two authorities for one number.
--
-- The draw is `voyage.rng` (0006:127), the chain's ONE randomness: a fair at a port in a season is
-- a pure function of (port_id, season, stream, world secret) and of nothing else — in particular
-- not of `now()`. So the calendar is the same on every replay, the tick is idempotent by
-- construction, and the self-assert can REDERIVE which ports drew a fair and require the table to
-- agree, in BOTH directions.
--
-- ── WHO WINDS IT ───────────────────────────────────────────────────────────────────────────────
-- ONE writer, `public.tick_buff_calendar()`, reached two ways and no more:
--   * pg_cron, where the platform has it — 0012's shape, and reported honestly where it does not.
--   * `world.buffs()`, which settles before it answers. That is this chain's own idiom, not a new
--     one (0009: "the read IS the catch-up"), and it is what stops the fair being a feature that
--     only exists on platforms with a scheduler. PGlite has none.
-- Both call the same function. There is no second definition of when a fair happens.
--
-- ── WHAT IT IS WORTH, MEASURED RATHER THAN REASONED ────────────────────────────────────────────
-- Measured by the self-assert on the world as seeded, and printed in its receipt. The arithmetic:
-- a house pays half the spread on the ask and half on the bid, so over a round trip a fair at BOTH
-- ends is worth `magnitude x spread` of the stake. At the shipped 30 per cent and this world's
-- average published spread of ~0.0384 that is ~1.15 per cent of stake — about a tenth of a median
-- voyage, and less than a fully-worked bargain (0024: 2.88 per cent). It is deliberately smaller
-- than haggling: a fair is luck and a bargain is a decision, and the decision must pay more.
--
-- HOW OFTEN: `chance_per_season` 0.12 over a 30 game-day season, running 4 game-days. So a given
-- port is holding a fair on about 1.6 per cent of port-days, and with 214 ports roughly three or
-- four quays in the world have one on at any moment. It is a thing you notice and sail for, not a
-- thing you plan around.
--
-- ── THE BALANCE THE PROOFS PIN DOES NOT MOVE, AND HERE IS EXACTLY WHY ──────────────────────────
-- `scripts/db/proofs/04` and `05` measure a world in which `public.active_buffs` is EMPTY: nothing
-- in those files calls `world.buffs()` or the tick, and PGlite has no pg_cron, so no fair is ever
-- wound during a proof run. `BALANCE_MEDIAN_IN_BAND` therefore measures exactly what it measured
-- before this file, which is the correct thing for it to measure — it is the band for the ORDINARY
-- economy. On a live Supabase project the cron will wind the calendar and roughly 1.6 per cent of
-- port-days will price ~1.15 per cent of stake better over a round trip. That is a real movement
-- and it is STATED here rather than absorbed.
--
-- ── GRANTS: THIS FILE GRANTS. IT REVOKES NOTHING. ──────────────────────────────────────────────
-- ONE new client entry point takes `grant execute ... to authenticated`: `world.buffs(uuid)`. NO
-- table grant is issued — both new tables have RLS on, no policy and no privilege for any client
-- role, so the read is the only door, exactly as 0025 shaped `public.standings`. `public.
-- buff_multiplier` and `public.tick_buff_calendar` are revoked from every client role;
-- `tick_buff_calendar` is granted to `service_role` because cron calls it. `supabase db push`
-- connects through the pooler as `postgres.<ref>` and cannot do this on these schemas: apply
-- through the Management API as `postgres`, as 0018, 0022 and 0025 were.
--
-- Depends ONLY on: 0001 (world_config, wc_*, client_write_grants), 0002 (ports), 0005 (world.spread,
--                  world.game_day, game_day_seconds), 0006 (voyage.rng), 0012 (tick_cron_expression),
--                  0018/0022/0025 (client_rpc_entry_points).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- THE PRE-IMAGE. Real quotes on real (port, good) pairs, taken through the CURRENT world.spread
-- before a line of it moves, so "the ordinary economy did not change" is a comparison and not a
-- sentence. Scaffolding for one assert; dropped at the foot of this file.
create temporary table quote_before_0026 as
  select pg.port_id, pg.good_id, s.side, s.qty,
         q.units, q.total, q.avg_price, q.end_stock,
         world.spread(pg.port_id) as published_spread
    from (select port_id, good_id from public.port_goods order by port_id, good_id limit 40) pg
   cross join (values ('buy'::text, 10::numeric), ('buy', 130), ('sell', 25)) as s(side, qty)
   cross join lateral world.quote(pg.port_id, pg.good_id, s.qty, s.side) q;

-- ── 1. THE TWO KNOBS, AND ONLY TWO ─────────────────────────────────────────────────────────────
-- Everything else about a buff is on its row in public.buff_kinds. A magnitude in a knob AND a
-- magnitude on the row would be two authorities for one number.
insert into public.world_config (key, value, description) values
  ('buff_bonus_cap_pct', to_jsonb(50),
   'The most any one subject may gain from all the buffs of one effect running on it at once, as a percentage. The officer cap''s twin (officer_bonus_cap_pct, 0015): a cap is what stops "additive within an effect" being unbounded, and it is a knob so balancing it is a config change.'),
  ('buff_history_seasons', to_jsonb(2),
   'How many past calendar seasons of expired buffs are kept before they are pruned. The table is a working set, not an archive; an unpruned one grows by (ports x chance) rows every season for ever.')
on conflict (key) do nothing;

-- ── 2. WHAT A BUFF IS — AUTHORED WORLD DATA ────────────────────────────────────────────────────
create table if not exists public.buff_kinds (
  code               text primary key
                     check (code = upper(code) and length(code) between 2 and 24),
  name               text not null,
  subject_kind       text not null check (subject_kind in ('PORT', 'SEA', 'FLEET', 'PLAYER')),
  effect             text not null check (effect in ('SPREAD')),
  magnitude_pct      numeric(5,2) not null check (magnitude_pct > 0 and magnitude_pct <= 100),
  duration_game_days numeric(6,2) not null check (duration_game_days > 0),
  -- The calendar half. NULL in both columns means "this kind is not on a calendar" — a buff some
  -- other rule awards. Nothing authored today is in that state.
  season_game_days   numeric(6,2) check (season_game_days > duration_game_days),
  chance_per_season  numeric(4,3) check (chance_per_season > 0 and chance_per_season <= 1),
  blurb              text not null,
  check ((season_game_days is null) = (chance_per_season is null))
);

comment on table public.buff_kinds is
  'WHAT A TIMED MODIFIER CAN BE — authored world data, the same kind of thing as ports, goods and '
  'officers. Adding a kind of buff is a ROW, never a function. The `effect` CHECK is deliberately '
  'a short list rather than free text: docs/SECTIONS.md warns that a table anything may write is '
  '"the place sections go to tangle", and a new effect must therefore arrive with the rule that '
  'READS it, in the same migration.';
comment on column public.buff_kinds.effect is
  'The ONE number this kind moves, and the direction is part of the effect''s meaning: SPREAD '
  'SHAVES the port''s published cut by magnitude_pct of itself. Exactly one effect per kind, for '
  'the same reason an officer has one specialty (0015) and a skill has one effect (0016).';
comment on column public.buff_kinds.magnitude_pct is
  'What one running buff of this kind is worth, as a percentage OF THE NUMBER IT MOVES — not of a '
  'price. It lives here and nowhere else: public.active_buffs deliberately does NOT copy it, so '
  'retuning a fair retunes every fair and two rows can never disagree about what one is worth.';
comment on column public.buff_kinds.chance_per_season is
  'The probability that a given subject holds one of these in a given season. The draw is '
  'voyage.rng keyed on (subject, season, stream), so the calendar is a pure function of the world '
  'secret and repeats exactly on any replay.';

alter table public.buff_kinds enable row level security;
-- No policy and no grant: world.buffs() serves the catalogue and is the only door, exactly as
-- 0025 shaped public.standings. A second path to the same rows would be a second place to state
-- what a client may see.

-- ── 3. THE TIMED MODIFIER TABLE ────────────────────────────────────────────────────────────────
create table if not exists public.active_buffs (
  id         uuid primary key default gen_random_uuid(),
  kind_code  text not null references public.buff_kinds(code) on delete cascade,
  -- The subject's KIND is not stored here: it is a fact about the kind (buff_kinds.subject_kind)
  -- and storing it twice would let one row claim a fair is running on a fleet.
  subject_id uuid not null,
  -- The calendar season this row was drawn for, or NULL for a buff some rule awarded outright.
  -- It is what makes a retried tick a no-op BY CONSTRUCTION rather than by a guard.
  season     int,
  starts_at  timestamptz not null,
  ends_at    timestamptz not null check (ends_at > starts_at),
  source     text not null,
  created_at timestamptz not null default now()
);

comment on table public.active_buffs is
  'THE TIMED MODIFIER TABLE docs/SECTIONS.md asked for. A row is a fact with a beginning and an '
  'end; a row that has not started and a row that has expired both contribute exactly zero, and '
  'public.buff_multiplier is the ONE thing that decides which is which. Nothing folds these rows '
  'into a stored total on any subject — that is the other half of SECTIONS.md''s instruction and '
  'the self-assert sweeps the catalogue for a violation of it.';

create unique index if not exists active_buffs_calendar
  on public.active_buffs (kind_code, subject_id, season) where season is not null;
create index if not exists active_buffs_subject_window
  on public.active_buffs (subject_id, starts_at, ends_at);

alter table public.active_buffs enable row level security;

-- ── 4. THE ONE READING OF "WHAT IS RUNNING ON THIS SUBJECT" ────────────────────────────────────
-- Shaped exactly like public.fleet_officer_bonus (0015:108) and public.player_skill_bonus
-- (0016:97), and for the same reason: every rule that reads a buff calls THIS, and nothing sums
-- magnitude_pct itself.
create or replace function public.buff_multiplier(
  p_subject_kind text, p_subject uuid, p_effect text, p_at timestamptz default now()
)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- A FRACTION (0.30 = 30 per cent of whatever the effect moves), additive within an effect and
  -- then clamped by the world's cap. Zero when nothing is running, which is the overwhelmingly
  -- common case and the reason world.spread() reduces to 0005's arithmetic exactly.
  select least(coalesce(sum(k.magnitude_pct), 0), public.wc_num('buff_bonus_cap_pct')) / 100.0
    from public.active_buffs ab
    join public.buff_kinds k on k.code = ab.kind_code
   where ab.subject_id  = p_subject
     and k.subject_kind = upper(p_subject_kind)
     and k.effect       = upper(p_effect)
     and ab.starts_at  <= p_at
     and ab.ends_at     > p_at
$$;

comment on function public.buff_multiplier(text, uuid, text, timestamptz) is
  'THE ONE answer to "what timed modifiers are acting on this subject, for this effect, at this '
  'instant". Returns a FRACTION, already capped. A row outside its window contributes nothing, '
  'which is what makes this table TIMED rather than permanent. Every rule that reads a buff calls '
  'this; nothing sums buff_kinds.magnitude_pct itself and nothing stores the answer.';

revoke all on function public.buff_multiplier(text, uuid, text, timestamptz)
  from public, anon, authenticated;

-- ── 5. THE RULE THAT ACTUALLY CHANGES — SUPERSEDES 0005:292 ────────────────────────────────────
-- 0005's body, times one term. With no fair running, buff_multiplier returns 0 and this is
-- arithmetically identical to what 0005 defined — proven below against a captured pre-image, not
-- asserted in prose.
--
-- STILL ONE ARGUMENT, STILL ONE NUMBER PER PORT. 0017:67 rejected making this player-aware and
-- that rejection stands: a fair is the same for every captain in the harbour, which is exactly
-- what separates it from the purser (0017) and the bargain (0022), both of which live one function
-- along in world.spread_effective and are untouched here.
create or replace function world.spread(p_port uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- spread = spread_base - spread_per_dev x dev_commerce, floored (DESIGN G.1) ...
  select greatest(
           public.wc_num('spread_floor'),
           public.wc_num('spread_base') - public.wc_num('spread_per_dev') * p.dev_commerce
         )
         -- ... less whatever the quay has running on it today (0026). Public, capped, and stored
         -- nowhere: it is recomputed on every price this port quotes.
         * (1 - public.buff_multiplier('PORT', p.id, 'SPREAD', now()))
    from public.ports p where p.id = p_port
$$;

comment on function world.spread(uuid) is
  'THE port''s PUBLISHED cut: its development, less any timed modifier running on the quay (0026). '
  'Supersedes the 0005 definition by one factor and is identical to it when nothing is running. '
  'Still takes one argument and still answers the same for every captain in the harbour — what a '
  'given HOUSE executes at is world.spread_effective (0022), which composes onto this.';

-- ── 6. THE CALENDAR, WOUND ─────────────────────────────────────────────────────────────────────
create or replace function public.buff_season_of(p_at timestamptz, p_season_days numeric)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select floor(world.game_day(p_at) / p_season_days)::int $$;

comment on function public.buff_season_of(timestamptz, numeric) is
  'THE season a calendar buff belongs to. public.tick_buff_calendar writes it and world.buffs '
  'reads it back; a second spelling of this arithmetic would let the writer and the reader '
  'disagree about which fair is the current one (0013:64''s drift_slot_of, same shape).';

revoke all on function public.buff_season_of(timestamptz, numeric) from public, anon, authenticated;

create or replace function public.tick_buff_calendar(p_at timestamptz default now())
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  k        public.buff_kinds%rowtype;
  v_season int;
  v_gds    numeric := public.wc_num('game_day_seconds');
  v_n      int;
  v_total  int := 0;
begin
  for k in select * from public.buff_kinds
            where season_game_days is not null and subject_kind = 'PORT'
            order by code
  loop
    v_season := public.buff_season_of(p_at, k.season_game_days);

    -- The draw is deterministic, so a repeat call writes nothing whether or not this short-circuit
    -- fires; it is here so the common case costs one index probe rather than 214 rng calls. If a
    -- season happens to draw no fair anywhere, the loop below simply re-derives the same nothing.
    if not exists (select 1 from public.active_buffs ab
                    where ab.kind_code = k.code and ab.season = v_season) then

      insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
      select k.code, p.id, v_season,
             to_timestamp((d.open_day * v_gds)::double precision),
             to_timestamp(((d.open_day + k.duration_game_days) * v_gds)::double precision),
             'calendar'
        from public.ports p
        -- The fair opens somewhere INSIDE its season, on a game-day this port draws for itself, so
        -- 214 quays do not all open on the same morning. The draw is taken ONCE, here, and both
        -- ends of the window are derived from it: two spellings of the same arithmetic could give
        -- a fair that ends before it starts.
       cross join lateral (
         select v_season * k.season_game_days
                + floor(voyage.rng(p.id, v_season, 'buff-day:' || k.code)
                        * (k.season_game_days - k.duration_game_days)) as open_day
       ) d
       where voyage.rng(p.id, v_season, 'buff:' || k.code) < k.chance_per_season
      on conflict do nothing;
      get diagnostics v_n = row_count;
      v_total := v_total + v_n;
    end if;

    -- A working set, not an archive.
    delete from public.active_buffs ab
     where ab.kind_code = k.code
       and ab.season is not null
       and ab.season <= v_season - public.wc_int('buff_history_seasons');
  end loop;

  return v_total;
end $$;

comment on function public.tick_buff_calendar(timestamptz) is
  'THE ONE writer of the calendar. Every fair it draws is a pure function of (port, season, the '
  'kind''s stream, the world secret), so it is idempotent by construction and identical on any '
  'replay. Wound by pg_cron where the platform has one and by world.buffs() where it does not — '
  'two callers, one definition of when a fair happens.';

revoke all on function public.tick_buff_calendar(timestamptz) from public, anon, authenticated;
grant execute on function public.tick_buff_calendar(timestamptz) to service_role;

-- ── 7. THE READ ────────────────────────────────────────────────────────────────────────────────
create or replace function world.buffs(p_port uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- The effects the RULES actually read today. ONE list, in ONE place, exactly as
  -- world.officers().specialties_read and world.skills().effects_read are (0015/0016/0022): a
  -- card that claimed an effect works when nothing reads it is selling nothing.
  v_read constant text[] := array['SPREAD'];
  v_now  timestamptz := now();
begin
  -- THE READ IS THE CATCH-UP (0009). Idempotent, so every caller after the first in a season
  -- pays one index probe.
  perform public.tick_buff_calendar(v_now);

  return jsonb_build_object(
    'now', v_now,
    'effects_read', to_jsonb(v_read),
    'cap_pct', public.wc_num('buff_bonus_cap_pct'),
    'kinds', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', k.code, 'name', k.name, 'subject_kind', k.subject_kind,
               'effect', k.effect, 'magnitude_pct', k.magnitude_pct,
               'duration_game_days', k.duration_game_days,
               'season_game_days', k.season_game_days,
               'chance_per_season', k.chance_per_season,
               'blurb', k.blurb,
               -- Said out loud, per row, for the reason 0015 had to invent this flag.
               'takes_effect', (k.effect = any(v_read))
             ) order by k.code), '[]'::jsonb)
        from public.buff_kinds k),
    'port', case when p_port is null then null else (
      select jsonb_build_object(
               'code', p.code, 'name', p.name,
               -- What the quay charges right now, from the ONE authority that publishes it, and
               -- what of that is the fair. Nothing here re-derives the base spread: a second
               -- spelling of DESIGN G.1 is exactly the duplication this project keeps deleting.
               'spread_published', round(world.spread(p.id), 6),
               'buff_pct', round(public.buff_multiplier('PORT', p.id, 'SPREAD', v_now) * 100, 2),
               'running', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'code', k.code, 'name', k.name, 'effect', k.effect,
                          'magnitude_pct', k.magnitude_pct, 'blurb', k.blurb,
                          'starts_at', ab.starts_at, 'ends_at', ab.ends_at,
                          'live', (ab.starts_at <= v_now and ab.ends_at > v_now),
                          'takes_effect', (k.effect = any(v_read))
                        ) order by ab.starts_at), '[]'::jsonb)
                   from public.active_buffs ab
                   join public.buff_kinds k on k.code = ab.kind_code
                  where ab.subject_id = p.id and k.subject_kind = 'PORT'
                    and ab.ends_at > v_now))
        from public.ports p where p.id = p_port) end);
end $$;

comment on function world.buffs(uuid) is
  'What timed modifiers exist, and what is running or about to run on one quay. Settles the '
  'calendar before it answers, so a fair happens on a platform with no scheduler too. Carries '
  '`effects_read` and a per-kind `takes_effect`, because a buff nothing reads must never look '
  'like one that works.';

revoke all on function world.buffs(uuid) from public, anon;
grant execute on function world.buffs(uuid) to authenticated;

-- ── 8. THE ONE KIND, AND IT IS READ ────────────────────────────────────────────────────────────
insert into public.buff_kinds (code, name, subject_kind, effect, magnitude_pct,
                               duration_game_days, season_game_days, chance_per_season, blurb) values
  ('FAIR', 'The Fair', 'PORT', 'SPREAD', 30.00, 4, 30, 0.120,
   'For a few days the quay is full of country carts and rival factors, and the brokers cut their '
   'commission to keep the trade moving. Everyone who calls here pays less for it, whoever they are.')
on conflict (code) do nothing;

-- ── 9. WIND IT, WHERE THERE IS A CLOCK TO WIND ─────────────────────────────────────────────────
do $$
declare
  v_have_cron boolean;
  v_expr      text := public.tick_cron_expression(public.wc_int('drift_slot_seconds'));
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_cron') into v_have_cron;
  if not v_have_cron then
    raise notice '0026: pg_cron is not available here, so the buff calendar is NOT scheduled — as expected under PGlite. world.buffs() settles it on every read, so a fair still happens for anyone looking at a quay; it would also have been wound on "%".', v_expr;
    return;
  end if;
  execute 'create extension if not exists pg_cron';
  perform cron.schedule('byeharu-voyage:buff-calendar', v_expr,
                        'select public.tick_buff_calendar()');
  raise notice '0026: pg_cron present — the buff calendar is wound on "%", the same cadence the market steps on. world.buffs() settles it as well, and both call the one writer.', v_expr;
end $$;

-- ── 10. THE CLIENT ENTRY POINTS — SUPERSEDES 0025's LIST ──────────────────────────────────────
create or replace function public.client_rpc_entry_points()
returns table (schema_name text, function_name text, arg_types text, fn regprocedure)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.s, t.f, t.a,
         to_regprocedure(format('%I.%I(%s)', t.s, t.f, t.a))
    from (values
      -- the reads (world)
      ('world'::text, 'snapshot'::text,      ''::text),
      ('world',       'market',              'uuid'),
      ('world',       'fleets',              ''),
      ('world',       'ledger',              'timestamptz, int'),
      ('world',       'buy_capacity',        'uuid, uuid'),
      ('world',       'price_history',       'uuid, int'),
      ('world',       'player',              ''),
      ('world',       'officers',            ''),
      ('world',       'skills',              ''),
      ('world',       'trade_routes',        'uuid, uuid, int, int, uuid'),
      ('world',       'haggle_state',        'uuid, uuid'),
      ('world',       'standings',           'int'),
      -- 0026: what is running on this quay. src/lib/rpc/catalog.ts names it `worldBuffs`.
      ('world',       'buffs',               'uuid'),
      -- the orders (cmd)
      ('cmd',         'issue',               'uuid, text, int'),
      ('cmd',         'preview',             'uuid, text'),
      ('cmd',         'cancel_at',           'uuid, int'),
      ('cmd',         'clear',               'uuid, boolean'),
      ('cmd',         'verb_schema',         ''),
      ('cmd',         'hire_officer',        'text, uuid'),
      ('cmd',         'post_officer',        'text, uuid'),
      ('cmd',         'study_skill',         'text, uuid'),
      ('cmd',         'found_house',         'text, text'),
      ('cmd',         'haggle',              'uuid, uuid, text')
    ) as t(s, f, a)
$$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe constant uuid := '00000000-0026-4000-8000-000000000026';
  v_pre_rows int;
  v_drift    int;
  v_player   uuid;
  v_fleet    uuid;
  v_port     uuid;
  v_good     uuid;
  v_kind     public.buff_kinds%rowtype;
  v_season   int;
  v_wrote    int;
  v_again    int;
  v_ports    int;
  v_drawn    int;
  v_wrong    int;
  v_gds      numeric;
  v_pub0     numeric;  v_pub1 numeric;
  v_mid0     numeric;  v_mid1 numeric;
  v_ask0     numeric;  v_ask1 numeric;
  v_bid0     numeric;  v_bid1 numeric;
  v_sp0      numeric;  v_sp1 numeric;
  v_eff0     numeric;  v_eff1 numeric;
  v_total0   bigint;   v_total1 bigint;
  v_purse0   bigint;   v_purse1 bigint;
  v_market   numeric;
  v_purser   numeric;
  v_conc     numeric;
  v_capped   numeric;
  v_officer  uuid;
  v_buffs    jsonb;
  v_worth    numeric;
  v_avg_sp   numeric;
  -- The percent sign is built INTO the text rather than escaped in the format string: plpgsql
  -- reads '%%%' left to right as (literal %)(placeholder) and prints "%30.00" (0015:407-410).
  v_pct_txt  text;
  v_left     int;
  v_cols     int;
  v_rls      int;
  -- findings recorded inside the throwaway subtransaction and read after it is gone
  f_noop      boolean := false;
  f_calendar  boolean := false;
  f_public    boolean := false;
  f_printed   boolean := false;
  f_charged   boolean := false;
  f_timed     boolean := false;
  f_compose   boolean := false;
  f_cap       boolean := false;
  f_read      boolean := false;
  f_grant     boolean := false;
begin
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- (a) THE ORDINARY ECONOMY DID NOT MOVE. With no fair running, buff_multiplier returns 0 and
  --     world.spread() is 0005's expression exactly. Proven as a COMPARISON against real quotes
  --     taken through the OLD world.spread before it was replaced, in this same transaction and
  --     therefore at the same clock and the same drift.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select count(*) into v_pre_rows from quote_before_0026;
  if v_pre_rows < 60 then
    raise exception '0026 self-assert FAIL: the quote pre-image holds only % row(s); the no-op comparison below would be nearly vacuous', v_pre_rows;
  end if;
  select count(*) into v_drift
    from quote_before_0026 b
    cross join lateral world.quote(b.port_id, b.good_id, b.qty, b.side) a
   where (a.units, a.total, a.avg_price, a.end_stock, world.spread(b.port_id))
         is distinct from (b.units, b.total, b.avg_price, b.end_stock, b.published_spread);
  if v_drift = 0 then f_noop := true; end if;

  -- NOT SUMMED INTO A STORED TOTAL ANYWHERE. docs/SECTIONS.md's other half, checked against the
  -- catalogue rather than trusted — the same shape 0015 used for "no officer column on ships".
  select count(*) into v_cols from information_schema.columns
   where table_schema = 'public'
     and table_name in ('ports', 'players', 'fleets', 'ships', 'port_goods')
     and (column_name like '%buff%' or column_name like '%modifier%');
  if v_cols <> 0 then
    raise exception '0026 self-assert FAIL: % buff-shaped column(s) exist on a subject table; a timed modifier folded into a stored total is what SECTIONS.md forbids', v_cols;
  end if;

  select count(*) into v_rls from pg_class c
   where c.oid in ('public.buff_kinds'::regclass, 'public.active_buffs'::regclass)
     and c.relrowsecurity;
  if v_rls <> 2 then
    raise exception '0026 self-assert FAIL: RLS is enabled on only % of the 2 new tables', v_rls;
  end if;

  select * into v_kind from public.buff_kinds where code = 'FAIR';
  if v_kind.code is null then
    raise exception '0026 self-assert FAIL: the FAIR kind was not seeded, so everything below would be vacuous';
  end if;
  v_gds := public.wc_num('game_day_seconds');

  begin
    -- ── inside the throwaway subtransaction ────────────────────────────────────────────────────

    -- (b) THE CALENDAR IS A PURE FUNCTION OF THE WORLD SECRET, IN BOTH DIRECTIONS. Every port that
    --     drew a fair must pass the draw when it is re-derived here, and every port that did NOT
    --     must fail it. One direction alone would pass a tick that wrote a fair for everybody.
    delete from public.active_buffs;
    v_season := public.buff_season_of(now(), v_kind.season_game_days);
    v_wrote  := public.tick_buff_calendar(now());
    v_again  := public.tick_buff_calendar(now());
    select count(*) into v_ports from public.ports;
    select count(*) into v_drawn from public.active_buffs where kind_code = 'FAIR' and season = v_season;
    select count(*) into v_wrong
      from public.ports p
      left join public.active_buffs ab
             on ab.subject_id = p.id and ab.kind_code = 'FAIR' and ab.season = v_season
     where (ab.id is not null) is distinct from
           (voyage.rng(p.id, v_season, 'buff:FAIR') < v_kind.chance_per_season);
    if v_wrote = v_drawn and v_drawn > 0 and v_again = 0 and v_wrong = 0 then
      f_calendar := true;
    end if;

    -- A HOUSE, and a quay with nothing running on it, so every measurement below starts from the
    -- ordinary world rather than from whatever the calendar happened to draw.
    v_player := public.new_house(c_probe, 'Casa da Feira', 'PRT');
    select f.id, f.port_id into v_fleet, v_port from public.fleets f where f.player_id = v_player;
    perform cmd.assume_identity(c_probe);
    delete from public.active_buffs;

    -- FIND the subject deterministically (0014:248-258), never by heap order.
    select pg.good_id into v_good
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
      join public.ports p on p.id = pg.port_id
     where pg.port_id = v_port and pg.stock > 200 and not (p.culture = any(g.culture_mask))
     order by g.code limit 1;
    if v_good is null then
      raise exception '0026 self-assert FAIL: the starting port holds no tradeable good with stock, so every probe below would be vacuous';
    end if;

    v_pub0    := world.spread(v_port);
    v_pct_txt := round(v_kind.magnitude_pct, 2)::text || '%';
    -- Measured with NO fair anywhere in the world, so the figure below is what a fair is worth
    -- against the ORDINARY economy and not against one this probe has already discounted.
    select avg(world.spread(p.id)) into v_avg_sp from public.ports p;
    v_worth := round(v_kind.magnitude_pct / 100.0 * v_avg_sp * 100, 3);
    select mid, ask, bid, spread into v_mid0, v_ask0, v_bid0, v_sp0 from world.price(v_port, v_good);
    select total into v_total0 from world.quote(v_port, v_good, 20, 'buy', null, v_fleet);
    v_eff0 := world.spread_effective(v_port, v_good, v_fleet);

    -- (c) A FAIR MOVES THE PUBLISHED PRICE — AND THAT IS THE DIFFERENCE FROM A BARGAIN. 0022
    --     required world.price() to be UNCHANGED by haggling, because a negotiation is private.
    --     A fair is public, so the opposite must hold: the ask falls, the bid RISES (the cut
    --     narrows from both sides), and the mid — what the thing is WORTH — does not move at all.
    insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
    values ('FAIR', v_port, null, now() - interval '1 hour', now() + interval '1 hour', 'probe');

    v_pub1 := world.spread(v_port);
    select mid, ask, bid, spread into v_mid1, v_ask1, v_bid1, v_sp1 from world.price(v_port, v_good);
    if v_pub1 = v_pub0 * (1 - v_kind.magnitude_pct / 100.0)
       and v_mid1 = v_mid0
       and v_ask1 < v_ask0 and v_bid1 > v_bid0
       and v_sp1 = v_pub1 then
      f_public := true;
    end if;

    -- (d) AND WHAT THE MARKET SCREEN PRINTS IS WHAT THE TRADE CHARGES. world.market() serves
    --     world.spread(port); if those two ever parted company a player would be quoted one
    --     number and billed another, which is 0005's oldest rule.
    select (world.market(v_port)->'port'->>'spread')::numeric into v_market;
    if v_market = v_pub1 then f_printed := true; end if;

    -- (e) A REAL TRADE IS CHEAPER BY EXACTLY WHAT THE QUOTE PROMISED — through cmd.do_buy, the
    --     verb, not through an inline recomputation of the price.
    select total into v_total1 from world.quote(v_port, v_good, 20, 'buy', null, v_fleet);
    select pl.ducats into v_purse0 from public.players pl where pl.id = v_player;
    perform cmd.do_buy(v_fleet, jsonb_build_object('good', v_good::text, 'qty', 20));
    select pl.ducats into v_purse1 from public.players pl where pl.id = v_player;
    if v_total1 < v_total0 and v_purse0 - v_purse1 = v_total1 then f_charged := true; end if;

    -- (f) IT IS TIMED, AND THAT IS PROVEN IN BOTH DIRECTIONS. A fair that has not opened yet and
    --     one that closed yesterday must each be worth exactly nothing — a table of modifiers with
    --     no window is not a timed table, it is a permanent one with dates written on it.
    delete from public.active_buffs where subject_id = v_port;
    insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
    values ('FAIR', v_port, null, now() + interval '2 hours', now() + interval '3 hours', 'probe-future');
    f_timed := (world.spread(v_port) = v_pub0)
               and (public.buff_multiplier('PORT', v_port, 'SPREAD', now()) = 0);
    delete from public.active_buffs where subject_id = v_port;
    insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
    values ('FAIR', v_port, null, now() - interval '3 hours', now() - interval '2 hours', 'probe-past');
    f_timed := f_timed and (world.spread(v_port) = v_pub0)
               and (public.buff_multiplier('PORT', v_port, 'SPREAD', now()) = 0)
               -- ... and the SAME row, asked about an instant inside its own window, IS worth the
               -- magnitude. Without this the two zeroes above could both be a broken lookup.
               and (public.buff_multiplier('PORT', v_port, 'SPREAD', now() - interval '150 minutes')
                    = v_kind.magnitude_pct / 100.0);

    -- (g) IT COMPOSES WITH THE PURSER AND THE BARGAIN AND DOES NOT DOUBLE-COUNT. The fair enters
    --     world.spread_effective exactly ONCE, through world.spread, so the executed spread must
    --     be the fair's factor times the unfaired executed spread — and strictly MORE than
    --     subtracting the three as a sum would have given (0022's decision 5, re-proved with a
    --     third factor in the stack).
    delete from public.active_buffs where subject_id = v_port;
    insert into public.officers (code, name, specialty, bonus_pct, wage_ducats, blurb)
    values ('PROBE0026', 'A purser for one probe', 'PURSER', 6.00, 1,
            'Exists for the length of one rolled-back probe, to put a third factor on the stack.')
    returning id into v_officer;
    insert into public.player_officers (player_id, officer_id, fleet_id)
    values (v_player, v_officer, v_fleet);
    insert into public.haggle_daily (player_id, port_id, good_id, game_day, attempts, wins, concession)
    values (v_player, v_port, v_good, world.game_day(), 1, 1, public.wc_num('haggle_concession_step'))
    on conflict (player_id, port_id, good_id, game_day)
      do update set attempts = 1, wins = 1, concession = public.wc_num('haggle_concession_step');

    v_purser := public.fleet_officer_bonus(v_fleet, 'PURSER');
    v_conc   := public.haggle_concession(v_player, v_port, v_good);
    v_eff0   := world.spread_effective(v_port, v_good, v_fleet);          -- no fair
    insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
    values ('FAIR', v_port, null, now() - interval '1 hour', now() + interval '1 hour', 'probe');
    v_eff1   := world.spread_effective(v_port, v_good, v_fleet);          -- with the fair

    if v_purser > 0 and v_conc > 0
       and v_eff0 = v_pub0 * (1 - v_purser) * (1 - v_conc)
       and v_eff1 = v_pub0 * (1 - v_kind.magnitude_pct / 100.0) * (1 - v_purser) * (1 - v_conc)
       and v_eff1 = v_eff0 * (1 - v_kind.magnitude_pct / 100.0)
       and v_eff1 > v_pub0 * (1 - v_kind.magnitude_pct / 100.0 - v_purser - v_conc) then
      f_compose := true;
    end if;

    -- (h) AND THE CAP BITES. Two fairs on one quay would sum past the cap; the ONE reading clamps
    --     them, on a precondition this probe sets itself rather than one it borrows.
    insert into public.buff_kinds (code, name, subject_kind, effect, magnitude_pct,
                                   duration_game_days, blurb)
    values ('PROBEFAIR0026', 'A second fair', 'PORT', 'SPREAD', 30.00, 1,
            'Exists for the length of one rolled-back probe, to drive the stack onto the cap.');
    insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
    values ('PROBEFAIR0026', v_port, null, now() - interval '1 hour', now() + interval '1 hour', 'probe');
    v_capped := public.buff_multiplier('PORT', v_port, 'SPREAD', now());
    if v_capped = public.wc_num('buff_bonus_cap_pct') / 100.0
       and v_capped < (2 * v_kind.magnitude_pct) / 100.0
       and world.spread(v_port) = v_pub0 * (1 - v_capped) then
      f_cap := true;
    end if;

    -- (i) THE READ TELLS THE TRUTH ABOUT WHAT IS READ. One effect, and the kind that carries it
    --     reports takes_effect TRUE — no card in this game claims a bonus no rule reads.
    delete from public.active_buffs where kind_code = 'PROBEFAIR0026';
    delete from public.buff_kinds where code = 'PROBEFAIR0026';
    v_buffs := world.buffs(v_port);
    if (v_buffs->'effects_read') ? 'SPREAD'
       and jsonb_array_length(v_buffs->'kinds') >= 1
       and (select bool_and((e->>'takes_effect')::boolean)
              from jsonb_array_elements(v_buffs->'kinds') e)
       and (v_buffs->'port'->>'spread_published')::numeric = round(world.spread(v_port), 6)
       and (v_buffs->'port'->>'buff_pct')::numeric
           = round(public.buff_multiplier('PORT', v_port, 'SPREAD', now()) * 100, 2)
       and jsonb_array_length(v_buffs->'port'->'running') >= 1 then
      f_read := true;
    end if;

    raise exception '__PROBE_ROLLBACK_0026__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0026__' then raise; end if;
  end;
  -- ── the subtransaction is gone; the findings survived it, because plpgsql variables are not
  --    transactional. Assert on them now. ────────────────────────────────────────────────────────

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  if not f_noop then
    raise exception '0026 self-assert FAIL: % of % pre-image quote(s) or published spread(s) moved with NO fair running. A buff is opt-in on the world and this file was not allowed to move the ordinary economy', v_drift, v_pre_rows;
  end if;
  if not f_calendar then
    raise exception '0026 self-assert FAIL: the calendar wrote % row(s) against % re-derived from voyage.rng, % port(s) disagreed with their own draw, and a repeat tick wrote % — the calendar is not the pure function of (port, season, secret) it claims to be', v_wrote, v_drawn, v_wrong, v_again;
  end if;
  if not f_public then
    raise exception '0026 self-assert FAIL: a fair did not take exactly % off the published cut (% -> %), or it moved the mid (% -> %), or the ask and bid did not narrow together (ask % -> %, bid % -> %)',
      v_pct_txt, v_pub0, v_pub1, v_mid0, v_mid1, v_ask0, v_ask1, v_bid0, v_bid1;
  end if;
  if not f_printed then
    raise exception '0026 self-assert FAIL: world.market() prints a spread of % while world.spread() answers % — the screen and the till would disagree', v_market, v_pub1;
  end if;
  if not f_charged then
    raise exception '0026 self-assert FAIL: a 20 tun buy cost % d. with the fair against % without, and the purse moved by % — the quote and the verb are not charging the same number', v_total1, v_total0, v_purse0 - v_purse1;
  end if;
  if not f_timed then
    raise exception '0026 self-assert FAIL: a fair that has not opened, or one that has closed, still moved the spread — or the same row inside its own window moved nothing, which would make both zeroes a broken lookup rather than a window';
  end if;
  if not f_compose then
    raise exception '0026 self-assert FAIL: the fair, the purser (%) and the bargain (%) do not compose multiplicatively — executed % without the fair and % with it, against a published %; one of the three is being summed or counted twice', v_purser, v_conc, v_eff0, v_eff1, v_pub0;
  end if;
  if not f_cap then
    raise exception '0026 self-assert FAIL: two fairs summing past the cap read % rather than the capped %; a bonus that is additive within an effect and never clamped is unbounded', v_capped, public.wc_num('buff_bonus_cap_pct') / 100.0;
  end if;
  if not f_read then
    raise exception '0026 self-assert FAIL: world.buffs() does not report SPREAD as read, or a kind whose effect a rule DOES read reported takes_effect false, or the figures it serves disagree with the authorities that produce them';
  end if;

  -- The rollback really rolled back. NOT "the tables are empty" — this chain deploys onto a live
  -- world — but "this probe left nothing of its own behind".
  select count(*) into v_left from public.players pl where pl.auth_uid = c_probe;
  if v_left <> 0 then
    raise exception '0026 self-assert FAIL: % probe house(s) survived the subtransaction', v_left;
  end if;
  select count(*) into v_left from public.active_buffs;
  if v_left <> 0 then
    raise exception '0026 self-assert FAIL: % buff row(s) were left committed by the probe', v_left;
  end if;
  select count(*) into v_left from public.buff_kinds;
  if v_left <> 1 then
    raise exception '0026 self-assert FAIL: % buff kind(s) exist where exactly 1 was authored', v_left;
  end if;
  select count(*) into v_left from public.officers where code = 'PROBE0026';
  if v_left <> 0 then
    raise exception '0026 self-assert FAIL: the probe left its synthetic purser in the world';
  end if;

  -- POSTURE. Exactly one new client entry point, and the machinery behind it unreachable.
  if has_function_privilege('authenticated', 'world.buffs(uuid)', 'execute')
     and not has_function_privilege('anon', 'world.buffs(uuid)', 'execute')
     and not has_function_privilege('authenticated', 'public.buff_multiplier(text, uuid, text, timestamptz)', 'execute')
     and not has_function_privilege('anon', 'public.buff_multiplier(text, uuid, text, timestamptz)', 'execute')
     and not has_function_privilege('authenticated', 'public.tick_buff_calendar(timestamptz)', 'execute')
     and not has_function_privilege('authenticated', 'public.buff_season_of(timestamptz, numeric)', 'execute')
     and not has_function_privilege('authenticated', 'world.spread(uuid)', 'execute')
     and not has_table_privilege('authenticated', 'public.active_buffs', 'select')
     and not has_table_privilege('authenticated', 'public.buff_kinds', 'select')
     and not has_table_privilege('anon', 'public.active_buffs', 'select')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0 then
    f_grant := true;
  end if;
  if not f_grant then
    raise exception '0026 self-assert FAIL: world.buffs is not exactly granted to authenticated and denied to anon, or the multiplier/tick/season machinery or one of the two tables leaked to a client, or a catalogued entry point does not resolve, or a write/execute grant or a read-wall gap appeared';
  end if;

  raise notice '0026 self-assert ok: BUFFS are a timed modifier table read at the point of use, and the first one is REAL — a fair takes exactly % off the quay''s published cut (% -> %) and, unlike a bargain, it moves the PUBLISHED price for everybody: the ask fell % -> % and the bid ROSE % -> % while the mid stayed at %, because a fair is public and the mid is still nobody''s to move; world.market() prints the very number world.spread() answers, and a real 20 tun cmd.do_buy cost % d. against % without the fair with the purse moving by exactly that; it is TIMED in both directions — a fair that has not opened and one that has closed are each worth zero, while the SAME row asked inside its own window is worth the magnitude; it COMPOSES through world.spread_effective without being touched — fair x purser (%) x bargain (%) gave % where the naive sum would have given more, so three factors stack multiplicatively and none is counted twice; the cap BITES at % on two fairs that would have summed to %; the calendar is a pure function of (port, season, world secret) — % of % port(s) drew a fair, every one of them re-derived from voyage.rng in BOTH directions with % disagreement(s), and a repeat tick wrote %; nothing is folded into a stored total, asserted against the catalogue on 5 subject table(s); the ordinary economy is BYTE-IDENTICAL across % real quotes and published spreads taken before world.spread was replaced, of which % moved — so proofs 04 and 05 measure exactly what they measured before, because no fair is ever wound during a proof run; a fair at both ends of a round trip is worth about % per cent of the stake at this world''s average published spread of %, roughly a tenth of a median voyage and deliberately less than a worked bargain; and the 1 new entry point is granted to authenticated, denied to anon, with the multiplier, the tick, the season authority, world.spread and both tables unreachable by any client, 0 client write grants, 0 client-executable writers and 0 read-wall gaps',
    v_pct_txt, round(v_pub0, 6), round(v_pub1, 6),
    v_ask0, v_ask1, v_bid0, v_bid1, v_mid0,
    v_total1, v_total0,
    round(v_purser, 4), round(v_conc, 4), round(v_eff1, 8),
    round(v_capped, 4), round((2 * v_kind.magnitude_pct) / 100.0, 4),
    v_drawn, v_ports, v_wrong, v_again,
    v_pre_rows, v_drift,
    v_worth, round(v_avg_sp, 4);
end $$;

drop table quote_before_0026;
