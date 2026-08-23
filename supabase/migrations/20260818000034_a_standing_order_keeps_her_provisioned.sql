-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0034 — A STANDING ORDER KEEPS HER PROVISIONED
--        The owner: "yes build set ratio but let me set it personally - adjust. Save it as
--        preset. Give something like 6 presets" · "the ratio must account for number of crews
--        as well" · "crew now, but show it clearly."
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE CONCEPT, IN ONE NOUN PHRASE (docs/NO_SPAGHETTI.md §7B) ─────────────────────────────────
-- A PROVISION PRESET: a house-authored standing order — "keep her at N days of stores" — written
-- once, named by the player, applied to any fleet, and executed by the server when that fleet
-- makes port. It removes the TYPING of PROVISION at every quay. It removes none of the COST:
-- stores still share the hold with cargo (0017's one capacity authority) and still leave the
-- purse through the one money mover, so every tun of water is still a tun of pepper not carried.
--
-- ── THE FIVE DECISIONS, AND WHY (§7B: written before the SQL existed) ──────────────────────────
--
-- 1. WHERE THE SETTING LIVES. `public.provision_presets` — a HOUSE table, because the owner asked
--    for reusable named presets, not a per-fleet number. A fleet holds a REFERENCE
--    (`fleets.provision_preset_id`, FK `on delete set null`) and NEVER a copy of the days figure,
--    so editing a preset changes what every fleet using it does at its next arrival — a copy on
--    the fleet is exactly the stale-copy defect this repo keeps tearing out. `ships.store_ratio`
--    (0004) was considered and REJECTED as the home: it is the PROVISION FULL fraction, a
--    different rule with a different unit, and widening it would give one column two meanings.
--
-- 2. WHEN IT FIRES. On arrival, and ONLY there — inside `voyage.settle()`'s arrival arm (the one
--    place a fleet makes port, reached by every read and by tick_arrivals since 0009/0010), AFTER
--    she docks and BEFORE `cmd.advance()` runs her queued orders, so a queued onward SAIL departs
--    provisioned and the endurance gate in `voyage.sail_refusal` passes without a typed
--    PROVISION between legs. It does NOT fire on apply, on edit, or on crew change (the owner
--    closed this: a standing order that reached into a fleet outside the arrival path would be a
--    second place her stores change). The settle body is SLICED from `pg_get_functiondef`, not
--    retyped — one hunk, asserted to occur exactly once, with reverse-substitution parity proven
--    below — so the wage, ration and day-boundary arithmetic proof 01 matches to the character is
--    unchanged BY CONSTRUCTION.
--
-- 3. HOW IT SPENDS. It composes `cmd.do_provision` (0017) in DAYS mode — the SAME rule the manual
--    verb runs, so cost, fit, the water/food split and the hold clamp have exactly one author and
--    cannot drift. do_provision pays through `public.credit` (the ONE money mover), so the charge
--    is a 'PROVISION' ledger row reconciled by 0004's constraint triggers, referencing a
--    'PROVISIONED' event which — via the second slice below — now carries `standing: true`, the
--    preset's name and the days target when the standing order placed it. The player can see
--    where the ducats went, and that it was the standing order that sent them.
--
-- 4. WHAT IT DOES WHEN IT CANNOT COMPLETE (§7C — each branch chooses between two ACCEPTABLE
--    outcomes, and every one of them is findable):
--      * already at target (endurance ≥ days) — nothing to buy, nothing written. Silence about a
--        non-event is not a hidden failure; the FLEETS galley face shows range ≥ target.
--      * cargo leaves SOME room — do_provision's own hold clamp buys what fits (partial IS the
--        trade-off working: the player's cargo outranks the automatic order). The PROVISIONED
--        event records what landed; the galley face shows range < target in warning tone.
--      * cargo leaves NO room, or the purse cannot pay — the order buys NOTHING and a
--        'PROVISION_REFUSED' event is written with the code and the server's own sentence.
--        Partial-on-money was REJECTED: an automatic order that drains the last ducat chooses
--        between an acceptable outcome and an unacceptable one; the manual verb refuses a short
--        purse wholesale and the standing order composes that rule rather than inventing a
--        gentler second one. A docked, refused fleet loses nothing irrecoverable — she is at a
--        quay, and the manual verb is one tap away.
--      * there is no "no chandler" branch: provisions are priced by world knobs
--        (provision_water_price / provision_food_price) at every port; no port lacks them.
--      * not DOCKED on arrival (flagship dead → UNABLE_TO_SAIL) — skipped silently: she cannot
--        sail at all, so stores are moot until the shipyard, and the mismatch stays on FLEETS.
--
-- 5. THE MANUAL PROVISION VERB IS NOT FORKED. No second cost rule, no second fit rule, no second
--    event shape: the executor calls the verb's own `cmd.do_provision`, and the only change to
--    that function is three payload keys on its event, present only when the standing order is
--    the caller. The verb's grammar (cmd.verb_schema) is untouched.
--
-- ── CREW: COUNTED AT FIRE TIME, "crew now", AND SHOWN CLEARLY ──────────────────────────────────
-- The tonnage is computed WHEN THE ORDER FIRES, from the crew aboard at that moment, because
-- do_provision's DAYS mode already reads `ships.crew` — the same figure `voyage.settle` burns per
-- day and `voyage.endurance_days` divides by. Nothing here re-derives crew × (water + food); the
-- arithmetic exists once, in the verb. Full-berths sizing was rejected (buys water no one drinks,
-- taking hold from cargo she may never need); a per-preset choice was rejected by the owner
-- ("crew now" — one reading, no setting). The known consequence — provision at Lisbon for 8
-- crew, hire 20 at Cádiz, range collapses — is made VISIBLE, not patched: the served
-- `endurance_days` (the ONE range figure, 0016's authority — deliberately not recomputed here)
-- already falls the moment crew rises, and the FLEETS galley face prints the preset's target
-- beside the crew aboard now and tones the range when a docked fleet no longer meets it.
-- Satisfaction is judged on that same served figure, with a 0.01-day tolerance because stores are
-- numeric(10,3) tuns: the 0.0005 t that rounding can owe is ~0.003 days on a Barca, and chasing
-- it would refuse for ever a top-up too small to buy.
--
-- ── THE CAP IS A RULE, NOT A SENTENCE ──────────────────────────────────────────────────────────
-- `provision_preset_max` (6) is a world_config knob read by a trigger ON THE TABLE
-- (0021's `assert_house_caps` shape), so any future writer inherits it. Proven by a refusal of a
-- seventh, below. Presets are NOT seeded: a preset is the player's own standing order in their
-- own words, and six rows they did not write are clutter (the client's New control composes one
-- in two taps). Deleting a preset DETACHES the fleets that use it — the FK's `on delete set
-- null`, a structural rule that cannot drift, chosen over refusal because hunting down every
-- fleet before a delete is the busywork this feature exists to remove; the delete RPC reports how
-- many fleets it released, and FLEETS shows the empty slot.
--
-- ── WHAT THIS FILE SUPERSEDES ──────────────────────────────────────────────────────────────────
--   voyage.settle(uuid, timestamptz)       0007:887, re-cut 0027:237 — SLICED: one hunk in the
--                                          arrival arm inserts the standing-order call before
--                                          cmd.advance. Nothing else moves.
--   cmd.do_provision(uuid, jsonb)          0007:550, re-cut 0017:260 — SLICED: the PROVISIONED
--                                          event gains three keys when the standing order is the
--                                          caller. Cost, fit, split: untouched.
--   public.client_rpc_entry_points()       0018:183, re-cut 0019/0022/0025/0026 — four rows
--                                          added for the new read and the three preset verbs.
-- They move together because they are one contract: the table without the fire is a note nobody
-- reads; the fire without the event is a charge nobody can explain; the RPCs without the grant
-- rows are doors nobody opens (0022 shipped that way once).
--
-- ── WHAT IT DELIBERATELY DOES NOT TOUCH ────────────────────────────────────────────────────────
--   * voyage.endurance_days — the range figure keeps its one owner; this file only READS it.
--   * cmd.verb_schema / the PROVISION card — the manual verb's grammar is not restated.
--   * world.fleets — untouched; preset state crosses the wire through the new
--     world.provision_presets read, so the fleet read's byte-parity chain (0028/0029) is unrisked.
--   * ships.store_ratio and PROVISION FULL — a different rule, left alone.
--   * The executor's return is `perform`-discarded in settle ON PURPOSE: unlike 0014's discarded
--     order, every outcome is already written (event or ledger) before it returns.
--
-- ── SECOND CALLERS, NAMED NOW (§7B) ────────────────────────────────────────────────────────────
--   cmd.run_standing_provision has ONE caller (voyage.settle's arrival arm) and its plausible
--   second is a future SHIPYARD/refit arm that docks a fleet outside a voyage — it would compose
--   the same function. world.provision_presets' second caller is the COMMAND composer showing
--   which order stands while drafting a SAIL; it would read the same payload.
--
-- Depends ONLY on: 0001 (wc/lockdown), 0004 (players/fleets/credit/emit_event/current_player_id),
--                  0016 (endurance_days), 0017 (do_provision, the capacity authority),
--                  0027 (the live settle body), 0018/0026 (client_rpc_entry_points).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. THE CAP IS A KNOB ───────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('provision_preset_max', to_jsonb(6),
   '0034: how many provision presets (standing orders) one house may keep. Read by the '
   'provision_presets_cap trigger — the refusal is on the TABLE, so any future writer inherits '
   'it — and served to the client by world.provision_presets so the book can say how full it is.')
on conflict (key) do nothing;

-- ── 2. THE BOOK OF STANDING ORDERS ─────────────────────────────────────────────────────────────
create table if not exists public.provision_presets (
  id         uuid primary key default gen_random_uuid(),
  player_id  uuid not null references public.players(id) on delete cascade,
  name       text not null,
  days       int  not null,
  created_at timestamptz not null default now(),
  constraint provision_presets_name_length check (length(btrim(name)) between 2 and 24),
  -- An input sanity bound, not a balance knob: the hold clamp in cmd.do_provision is what really
  -- limits a target, so 999 can never over-buy — it only keeps the figure printable.
  constraint provision_presets_days_sane check (days between 1 and 999)
);
create unique index if not exists provision_presets_player_name_unique
  on public.provision_presets (player_id, lower(name));

comment on table public.provision_presets is
  'THE house''s standing provision orders (0034): "keep her at N days of stores", named by the '
  'player, applied to fleets by reference. The days are a RANGE target judged against '
  'voyage.endurance_days at fire time; the tonnage is computed then, from the crew aboard then, '
  'by cmd.do_provision — never stored here and never cached on a fleet.';

-- The cap, on the table (0021's shape), so no future verb can forget it.
create or replace function public.provision_presets_cap()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_max int := public.wc_int('provision_preset_max');
begin
  if (select count(*) from public.provision_presets where player_id = new.player_id) >= v_max then
    raise exception 'E_PRESET_CAP: the book holds % standing orders already, which is all it holds',
      v_max using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger provision_presets_cap
  before insert on public.provision_presets
  for each row execute function public.provision_presets_cap();

-- A fleet POINTS AT a preset. `on delete set null` makes "pointing at a preset that does not
-- exist" structurally impossible, and is the detach rule decision 5 in the header defends.
alter table public.fleets
  add column if not exists provision_preset_id uuid
  references public.provision_presets(id) on delete set null;

comment on column public.fleets.provision_preset_id is
  '0034: which standing provision order this fleet sails under, or null for none. A REFERENCE, '
  'never a copy — editing the preset changes what this fleet does at its next arrival.';

-- Read-own, exactly the 0004 posture of the sibling player tables. Writes go through the
-- SECURITY DEFINER verbs below only; no client role holds a table write.
alter table public.provision_presets enable row level security;
create policy provision_presets_read_own on public.provision_presets for select to authenticated
  using (player_id = public.current_player_id());
grant select on public.provision_presets to authenticated;

revoke all on function public.provision_presets_cap() from public, anon, authenticated;

-- ── 3. THE EXECUTOR — one function, called from the one arrival place ──────────────────────────
create or replace function cmd.run_standing_provision(p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f        public.fleets%rowtype;
  pr       public.provision_presets%rowtype;
  v_before numeric;
  v_res    jsonb;
  v_msg    text;
  v_code   text;
begin
  select * into f from public.fleets where id = p_fleet;
  -- No preset standing, or nothing a chandler can serve (UNABLE_TO_SAIL waits for the shipyard;
  -- at sea nothing fires by the owner's rule). Both outcomes acceptable; header decision 4.
  if f.id is null or f.provision_preset_id is null or f.status <> 'DOCKED' then
    return null;
  end if;
  select * into pr from public.provision_presets where id = f.provision_preset_id;
  if pr.id is null then
    return null;  -- unreachable while the FK stands; refusing to guess costs one line.
  end if;

  -- Judged on THE served range figure (0016's authority), minus the numeric(10,3) dust floor —
  -- see the CREW paragraph in the header for the 0.01 derivation.
  v_before := voyage.endurance_days(p_fleet);
  if v_before >= pr.days - 0.01 then
    return jsonb_build_object('ok', true, 'satisfied', true, 'days', pr.days);
  end if;

  begin
    -- THE ONE provisioning rule, in DAYS mode, marked so its event says who placed it.
    v_res := cmd.do_provision(p_fleet, jsonb_build_object(
               'mode', 'DAYS', 'days', pr.days, 'standing', true, 'preset', pr.name));
  exception when others then
    v_msg  := sqlerrm;
    v_code := case when v_msg ~ '^E_[A-Z_]+:' then split_part(v_msg, ':', 1) else 'E_PARSE' end;
    -- The refusal is WRITTEN, or an automatic order that quietly did nothing would be
    -- indistinguishable from a bug (header decision 4). world.ledger serves this row.
    perform public.emit_event(f.player_id, 'PROVISION_REFUSED', jsonb_build_object(
      'fleet', f.name, 'preset', pr.name, 'days', pr.days,
      'code', v_code, 'reason', btrim(substr(v_msg, length(v_code) + 2))));
    return jsonb_build_object('ok', false, 'error_code', v_code);
  end;

  return jsonb_build_object('ok', true, 'satisfied', false, 'days', pr.days) || v_res;
end $$;

comment on function cmd.run_standing_provision(uuid) is
  'THE standing-order executor (0034). One caller: voyage.settle''s arrival arm. Composes '
  'cmd.do_provision (the one cost/fit rule) and voyage.endurance_days (the one range figure); '
  'writes PROVISION_REFUSED when the order cannot buy at all. Server-only.';

revoke all on function cmd.run_standing_provision(uuid) from public, anon, authenticated;

-- ── 4. THE TWO SLICES — read back live, replaced by hunk, never retyped ────────────────────────
-- THE PRE-IMAGES, for the exactly-once asserts and the reverse-substitution parity proof below.
create temporary table defs_before_0034 as
  select 'voyage.settle'::text as fn,
         pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure) as def,
         (select p.proacl::text from pg_proc p
           where p.oid = 'voyage.settle(uuid, timestamptz)'::regprocedure) as acl
  union all
  select 'cmd.do_provision',
         pg_get_functiondef('cmd.do_provision(uuid, jsonb)'::regprocedure),
         (select p.proacl::text from pg_proc p
           where p.oid = 'cmd.do_provision(uuid, jsonb)'::regprocedure);

do $$
declare
  r     record;
  v_new text;
  v_n   int;
  h     jsonb;
  -- Hunk S1 anchors on the VOYAGE_REPORT emit so it cannot match settle's other advance call
  -- (the early-return path). Hunk P1 is the PROVISIONED event emit, whole.
  hunks constant jsonb := jsonb_build_array(
    jsonb_build_object('fn', 'voyage.settle',
      'old', $s1$                  from public.voyage_events ve where ve.voyage_id = v.id)));
    perform cmd.advance(p_fleet, p_now);$s1$,
      'new', $s2$                  from public.voyage_events ve where ve.voyage_id = v.id)));
    -- 0034 STANDING ORDER: fires HERE, the one place a fleet makes port — after she docks,
    -- before her queued orders run, so a queued onward SAIL departs provisioned.
    perform cmd.run_standing_provision(p_fleet);
    perform cmd.advance(p_fleet, p_now);$s2$),
    jsonb_build_object('fn', 'cmd.do_provision',
      'old', $p1$    public.emit_event(f.player_id, 'PROVISIONED', jsonb_build_object(
      'fleet', f.name, 'water_t', v_water, 'food_t', v_food, 'cost', v_cost)));$p1$,
      'new', $p2$    public.emit_event(f.player_id, 'PROVISIONED', jsonb_build_object(
      'fleet', f.name, 'water_t', v_water, 'food_t', v_food, 'cost', v_cost)
      -- 0034: when the STANDING ORDER placed this purchase the record says so — same event,
      -- same ledger row, three more keys, present only on that path.
      || (case when p_args ? 'standing'
               then jsonb_build_object('standing', true, 'preset', p_args->>'preset',
                                       'days_target', (p_args->>'days')::numeric)
               else '{}'::jsonb end)));$p2$));
begin
  for r in select fn, def from defs_before_0034 loop
    v_new := r.def;
    for h in select * from jsonb_array_elements(hunks) loop
      continue when h->>'fn' <> r.fn;
      -- EXACTLY ONCE, or this migration was generated against a different deployment and must
      -- not guess (the slice rule this repo inherited the hard way).
      v_n := (length(v_new) - length(replace(v_new, h->>'old', ''))) / length(h->>'old');
      if v_n <> 1 then
        raise exception '0034: hunk for % occurs % time(s) in the deployed body — expected exactly 1; the deployed body is not what this migration was written against', r.fn, v_n;
      end if;
      v_new := replace(v_new, h->>'old', h->>'new');
    end loop;
    execute v_new;
  end loop;
end $$;

-- ── 5. THE VERBS — the same direct-RPC shape as cmd.study_skill (0016) ─────────────────────────
-- None takes a player id: identity is the JWT's, which is what makes them safe for a browser.

-- CREATE (p_preset null) or ADJUST (rename and/or re-days). One verb, because "create" and
-- "adjust" differ only in whether the row exists yet, and two verbs would restate every guard.
create or replace function cmd.provision_preset_save(p_preset uuid, p_name text, p_days int)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  pr       public.provision_presets%rowtype;
  v_name   text := nullif(btrim(coalesce(p_name, '')), '');
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in, so there is no book of standing orders.',
      'fixes', jsonb_build_array('(sign in first)'));
  end if;

  begin
    if p_preset is null then
      if v_name is null or p_days is null then
        return jsonb_build_object('ok', false, 'error_code', 'E_PARSE',
          'error_message', 'A standing order needs a name and a number of days.',
          'fixes', jsonb_build_array('(name it, then set the days)'));
      end if;
      insert into public.provision_presets (player_id, name, days)
      values (v_player, v_name, p_days)
      returning * into pr;
    else
      select * into pr from public.provision_presets
       where id = p_preset and player_id = v_player;
      if pr.id is null then
        return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_PRESET',
          'error_message', 'The book holds no such standing order.',
          'fixes', jsonb_build_array('(read the book again)'));
      end if;
      update public.provision_presets
         set name = coalesce(v_name, name), days = coalesce(p_days, days)
       where id = pr.id
      returning * into pr;
    end if;
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'error_code', 'E_NAME_TAKEN',
        'error_message', format('The book already holds an order named "%s".', v_name),
        'fixes', jsonb_build_array('(pick another name)'));
    when check_violation then
      if sqlerrm like '%days_sane%' then
        return jsonb_build_object('ok', false, 'error_code', 'E_PARSE',
          'error_message', 'Days must be a whole number from 1 to 999.',
          'fixes', jsonb_build_array('(set the days between 1 and 999)'));
      end if;
      return jsonb_build_object('ok', false, 'error_code', 'E_PARSE',
        'error_message', 'A name is 2 to 24 characters.',
        'fixes', jsonb_build_array('(shorten or lengthen the name)'));
    when others then
      -- The cap trigger raises 'E_PRESET_CAP: …'; anything else in that shape passes through in
      -- the server's own words (execute_order's split, 0007).
      if sqlerrm ~ '^E_[A-Z_]+:' then
        return jsonb_build_object('ok', false, 'error_code', split_part(sqlerrm, ':', 1),
          'error_message', btrim(substr(sqlerrm, length(split_part(sqlerrm, ':', 1)) + 2)),
          'fixes', jsonb_build_array('(strike an order from the book first)'));
      end if;
      raise;
  end;

  return jsonb_build_object('ok', true, 'id', pr.id, 'name', pr.name, 'days', pr.days);
end $$;

-- STRIKE an order from the book. The FK detaches every fleet that sailed under it; the answer
-- says how many, so the client can show what was released.
create or replace function cmd.provision_preset_delete(p_preset uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player   uuid := public.current_player_id();
  pr         public.provision_presets%rowtype;
  v_detached int;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in, so there is no book of standing orders.',
      'fixes', jsonb_build_array('(sign in first)'));
  end if;
  select * into pr from public.provision_presets
   where id = p_preset and player_id = v_player;
  if pr.id is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_PRESET',
      'error_message', 'The book holds no such standing order.',
      'fixes', jsonb_build_array('(read the book again)'));
  end if;
  select count(*) into v_detached from public.fleets where provision_preset_id = pr.id;
  delete from public.provision_presets where id = pr.id;
  return jsonb_build_object('ok', true, 'deleted', pr.name, 'detached_fleets', v_detached);
end $$;

-- APPLY an order to a fleet, or CLEAR it (p_preset null). Does NOT fire the top-up — the order
-- fires on arrival, and only there (the owner's rule; header decision 2) — and does NOT bump
-- fleets.version: the version guards order-issue races, and a standing order invalidates no
-- drafted order.
create or replace function cmd.provision_preset_apply(p_fleet uuid, p_preset uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  f        record;
  pr       public.provision_presets%rowtype;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in, so there is no book of standing orders.',
      'fixes', jsonb_build_array('(sign in first)'));
  end if;
  select id, player_id, name into f from public.fleets where id = p_fleet;
  if f.id is null or f.player_id is distinct from v_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_FLEET',
      'error_message', 'That fleet is not yours.',
      'fixes', jsonb_build_array('(name one of your own fleets)'));
  end if;
  if p_preset is not null then
    select * into pr from public.provision_presets
     where id = p_preset and player_id = v_player;
    if pr.id is null then
      return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_PRESET',
        'error_message', 'The book holds no such standing order.',
        'fixes', jsonb_build_array('(read the book again)'));
    end if;
  end if;
  update public.fleets set provision_preset_id = p_preset where id = f.id;
  return jsonb_build_object('ok', true, 'fleet', f.name,
                            'preset', pr.name, 'days', pr.days);
end $$;

-- ── 6. THE READ ────────────────────────────────────────────────────────────────────────────────
create or replace function world.provision_presets()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
begin
  return jsonb_build_object(
    'max', public.wc_int('provision_preset_max'),
    'presets', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', pr.id, 'name', pr.name, 'days', pr.days,
               'fleets', (
                 select coalesce(jsonb_agg(jsonb_build_object('id', fl.id, 'name', fl.name)
                                           order by fl.name), '[]'::jsonb)
                   from public.fleets fl where fl.provision_preset_id = pr.id)
             ) order by pr.created_at, pr.id), '[]'::jsonb)
        from public.provision_presets pr
       where pr.player_id = v_player));
end $$;

comment on function world.provision_presets() is
  'The house''s book of standing provision orders, with the fleets sailing under each and the '
  'cap. Takes no id — identity is the JWT''s. The days figure is a RANGE target; what it costs '
  'in tuns is decided at fire time from the crew aboard then (0034 header, CREW paragraph).';

-- ── 7. GRANTS, and the one sanctioned list — SUPERSEDES 0026's ─────────────────────────────────
revoke all on function world.provision_presets()                       from public, anon;
grant execute on function world.provision_presets()                    to authenticated;
revoke all on function cmd.provision_preset_save(uuid, text, int)     from public, anon;
grant execute on function cmd.provision_preset_save(uuid, text, int)  to authenticated;
revoke all on function cmd.provision_preset_delete(uuid)              from public, anon;
grant execute on function cmd.provision_preset_delete(uuid)           to authenticated;
revoke all on function cmd.provision_preset_apply(uuid, uuid)         from public, anon;
grant execute on function cmd.provision_preset_apply(uuid, uuid)      to authenticated;

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
      ('world',       'buffs',               'uuid'),
      -- 0034: the book of standing orders. src/lib/rpc/catalog.ts names it worldProvisionPresets.
      ('world',       'provision_presets',   ''),
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
      ('cmd',         'haggle',              'uuid, uuid, text'),
      -- 0034: write, adjust, strike and apply a standing provision order. None takes a player id.
      ('cmd',         'provision_preset_save',   'uuid, text, int'),
      ('cmd',         'provision_preset_delete', 'uuid'),
      ('cmd',         'provision_preset_apply',  'uuid, uuid')
    ) as t(s, f, a)
$$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_auth   constant uuid := '00000000-0034-4000-8000-000000000001';
  c_auth2  constant uuid := '00000000-0034-4000-8000-000000000002';
  v_old    text;
  v_new    text;
  v_back   text;
  v_acl0   text;
  v_acl1   text;
  v_player uuid;
  v_player2 uuid;
  v_fleet  uuid;
  v_lis    uuid;
  v_cad    uuid;
  v_res    jsonb;
  v_id     uuid;
  v_id7    uuid;
  v_foreign uuid;
  v_purse0 bigint;
  v_purse1 bigint;
  v_cost1  numeric;
  v_cost2  numeric;
  v_b1     numeric;   -- tuns bought at the first arrival
  v_b2     numeric;   -- tuns bought at the second (more crew aboard)
  v_end1   numeric;
  v_end2   numeric;
  v_free0  numeric;
  v_free1  numeric;
  v_s0     numeric;
  v_s1     numeric;
  v_crew1  int;
  v_crew2  int;
  v_events int;
  v_ev1    uuid;
  v_ref    jsonb;
  v_ledger bigint;
  v_left   int;
  v_base   int;   -- houses present BEFORE the probe; see the rollback assert
  v_grants int;
  v_writers int;
  e        record;
  k        int;
  -- findings, recorded inside the rolled-back probe
  f_crud      boolean := false;
  f_cap       boolean := false;
  f_name      boolean := false;
  f_days      boolean := false;
  f_foreign   boolean := false;
  f_detach    boolean := false;
  f_fired     boolean := false;
  f_ledgered  boolean := false;
  f_room      boolean := false;
  f_crewfire  boolean := false;
  f_refused   boolean := false;
begin
  -- (a) SETTLE PARITY BY CONSTRUCTION, verified: substituting the 0034 lines back OUT of the live
  --     definition must reproduce the pre-image to the character — so the wage, ration and
  --     day-boundary arithmetic proof 01 matches is untouched.
  select def, acl into v_old, v_acl0 from defs_before_0034 where fn = 'voyage.settle';
  v_new := pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure);
  v_back := replace(v_new,
    $s2$                  from public.voyage_events ve where ve.voyage_id = v.id)));
    -- 0034 STANDING ORDER: fires HERE, the one place a fleet makes port — after she docks,
    -- before her queued orders run, so a queued onward SAIL departs provisioned.
    perform cmd.run_standing_provision(p_fleet);
    perform cmd.advance(p_fleet, p_now);$s2$,
    $s1$                  from public.voyage_events ve where ve.voyage_id = v.id)));
    perform cmd.advance(p_fleet, p_now);$s1$);
  if v_back <> v_old or v_new = v_old then
    raise exception '0034 self-assert FAIL: voyage.settle is not its pre-image plus only the standing-order call';
  end if;
  select p.proacl::text into v_acl1 from pg_proc p
   where p.oid = 'voyage.settle(uuid, timestamptz)'::regprocedure;
  if v_acl1 is distinct from v_acl0 then
    raise exception '0034 self-assert FAIL: the settle re-cut moved its ACL from % to %', v_acl0, v_acl1;
  end if;

  -- (b) DO_PROVISION PARITY, the same way.
  select def, acl into v_old, v_acl0 from defs_before_0034 where fn = 'cmd.do_provision';
  v_new := pg_get_functiondef('cmd.do_provision(uuid, jsonb)'::regprocedure);
  v_back := replace(v_new,
    $p2$    public.emit_event(f.player_id, 'PROVISIONED', jsonb_build_object(
      'fleet', f.name, 'water_t', v_water, 'food_t', v_food, 'cost', v_cost)
      -- 0034: when the STANDING ORDER placed this purchase the record says so — same event,
      -- same ledger row, three more keys, present only on that path.
      || (case when p_args ? 'standing'
               then jsonb_build_object('standing', true, 'preset', p_args->>'preset',
                                       'days_target', (p_args->>'days')::numeric)
               else '{}'::jsonb end)));$p2$,
    $p1$    public.emit_event(f.player_id, 'PROVISIONED', jsonb_build_object(
      'fleet', f.name, 'water_t', v_water, 'food_t', v_food, 'cost', v_cost)));$p1$);
  if v_back <> v_old or v_new = v_old then
    raise exception '0034 self-assert FAIL: cmd.do_provision is not its pre-image plus only the standing keys';
  end if;
  select p.proacl::text into v_acl1 from pg_proc p
   where p.oid = 'cmd.do_provision(uuid, jsonb)'::regprocedure;
  if v_acl1 is distinct from v_acl0 then
    raise exception '0034 self-assert FAIL: the do_provision re-cut moved its ACL from % to %', v_acl0, v_acl1;
  end if;

  -- (c) THE PROBE — a real house, a real preset, three real arrivals, then rolled back.
  --
  -- THE BASELINE IS TAKEN FIRST, and this is the whole reason: the rollback check below used to
  -- assert `count(*) = 0`, which is a claim about THE WORLD and not about this probe. It passed on
  -- every empty local apply and FAILED on production 2026-08-23 the first time it met a database
  -- with real houses in it — reporting a leak that had not happened. A count is an ambient default;
  -- the DELTA is the only thing this file owns.
  select count(*) into v_base from public.players;
  begin
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_cad from public.ports where code = 'CAD';
    -- THE PROBE OWNS ITS WEATHER. 0031 rotates the world secret on a fresh apply, so hazard rolls
    -- differ per deployment; a CALM would push a warped ETA back out and a STORM could ground the
    -- flagship — either turns this probe into a lottery. Zeroed HERE, inside the subtransaction
    -- that is rolled back, so the live world's weather is untouched.
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    v_player := public.new_house(c_auth,  'Casa Ordem', 'PRT');
    v_player2 := public.new_house(c_auth2, 'Casa Alheia', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;

    -- The verbs read the JWT; the probe signs in as the house it made (proof 06's idiom).
    perform cmd.assume_identity(c_auth2);
    v_res := cmd.provision_preset_save(null, 'Not Mine', 12);
    v_foreign := (v_res->>'id')::uuid;

    perform cmd.assume_identity(c_auth);

    -- CRUD: write, adjust the days, rename — one row, moved on purpose. One statement per
    -- side-effecting call: the arms of one AND have no guaranteed evaluation order, and the first
    -- draft of this check read the row's days BEFORE the call that moved them had run.
    v_res  := cmd.provision_preset_save(null, 'Long haul', 25);
    v_id   := (v_res->>'id')::uuid;
    f_crud := (v_res->>'ok')::boolean;
    v_res  := cmd.provision_preset_save(v_id, null, 30);
    f_crud := f_crud and (v_res->>'days')::int = 30;
    v_res  := cmd.provision_preset_save(v_id, 'Long road', null);
    f_crud := f_crud and (v_res->>'name') = 'Long road';
    f_crud := f_crud and (select days from public.provision_presets where id = v_id) = 30;

    -- THE CAP BITES: five more fill the book to wc provision_preset_max (6); the seventh is
    -- refused by the TRIGGER, through the verb, with the code the client will render.
    for k in 1 .. public.wc_int('provision_preset_max') - 1 loop
      perform cmd.provision_preset_save(null, 'Order ' || k, 5 + k);
    end loop;
    v_res := cmd.provision_preset_save(null, 'One Too Many', 9);
    if (v_res->>'ok')::boolean = false and v_res->>'error_code' = 'E_PRESET_CAP' then
      f_cap := true;
    end if;

    -- A taken name and a nonsense day count are refusals, not rows.
    v_res := cmd.provision_preset_save(v_id, 'Order 1', null);
    if (v_res->>'ok')::boolean = false and v_res->>'error_code' = 'E_NAME_TAKEN' then
      f_name := true;
    end if;
    v_res := cmd.provision_preset_save(v_id, null, 0);
    if (v_res->>'ok')::boolean = false and v_res->>'error_code' = 'E_PARSE' then
      f_days := true;
    end if;

    -- Another house's preset is not appliable — and not distinguishable from an absent one.
    v_res := cmd.provision_preset_apply(v_fleet, v_foreign);
    if (v_res->>'ok')::boolean = false and v_res->>'error_code' = 'E_NO_SUCH_PRESET' then
      f_foreign := true;
    end if;

    -- APPLY, one row moved; then the FIRST ARRIVAL fires it.
    perform cmd.provision_preset_apply(v_fleet, v_id);

    select ducats into v_purse0 from public.players where id = v_player;
    v_free0 := public.fleet_free_hold(v_fleet);
    select water_t + food_t into v_s0 from public.ships where fleet_id = v_fleet;
    select crew into v_crew1 from public.ships where fleet_id = v_fleet;

    perform cmd.issue(v_fleet, 'SAIL CAD');
    for k in 1 .. 12 loop
      exit when (select status from public.fleets where id = v_fleet) <> 'SAILING';
      update public.voyages
         set departed_at = departed_at - (eta - now()) - interval '1 minute',
             eta         = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      perform voyage.settle(v_fleet);
    end loop;

    v_end1 := voyage.endurance_days(v_fleet);
    -- Exactly ONE standing event exists at this point, and the count is asserted with the pick:
    -- every row this transaction writes shares one created_at, so "order by created_at" cannot
    -- break a tie here — the discriminator is the captured id, below.
    select e2.id,
           (e2.payload->>'water_t')::numeric + (e2.payload->>'food_t')::numeric,
           (e2.payload->>'cost')::numeric
      into v_ev1, v_b1, v_cost1
      from public.events e2
     where e2.player_id = v_player and e2.kind = 'PROVISIONED'
       and (e2.payload->>'standing')::boolean
       and e2.payload->>'preset' = 'Long road'
       and (e2.payload->>'days_target')::numeric = 30;
    if v_b1 is not null and v_b1 > 0 and v_end1 >= 30 - 0.01
       and (select status from public.fleets where id = v_fleet) = 'DOCKED'
       and (select port_id from public.fleets where id = v_fleet) = v_cad then
      f_fired := true;
    end if;

    -- THE CHARGE IS ON THE LEDGER, through the one money mover, tied to that very event.
    select l.ducats_delta into v_ledger
      from public.ledger l
      join public.events e2 on e2.id = l.ref_event_id
     where l.player_id = v_player and l.kind = 'PROVISION'
       and (e2.payload->>'standing')::boolean
     order by l.created_at desc limit 1;
    if v_ledger = -round(v_cost1) and v_cost1 > 0 then
      f_ledgered := true;
    end if;

    -- THE TRADE-OFF SURVIVES: every tun of stores the order put aboard is a tun of hold a cargo
    -- cannot have. Free hold is read from the SAME authority a BUY checks (0017), and the fall in
    -- it must equal the net rise in stores TO THE THOUSANDTH — if stores were ever minted outside
    -- the hold accounting, this is the line that goes red.
    v_free1 := public.fleet_free_hold(v_fleet);
    select water_t + food_t into v_s1 from public.ships where fleet_id = v_fleet;
    if v_s1 > v_s0 and v_free1 < v_free0
       and abs((v_free0 - v_free1) - (v_s1 - v_s0)) < 0.01 then
      f_room := true;
    end if;

    -- (d) CREW IS READ AT FIRE TIME: sign more crew, sail again, and the SAME preset buys MORE —
    --     with the range landing on the target both times.
    perform cmd.issue(v_fleet, 'HIRE ' ||
      (select c.crew_max - s.crew from public.ships s
         join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fleet));
    select crew into v_crew2 from public.ships where fleet_id = v_fleet;
    perform cmd.issue(v_fleet, 'SAIL LIS');
    for k in 1 .. 12 loop
      exit when (select status from public.fleets where id = v_fleet) <> 'SAILING';
      update public.voyages
         set departed_at = departed_at - (eta - now()) - interval '1 minute',
             eta         = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      perform voyage.settle(v_fleet);
    end loop;

    v_end2 := voyage.endurance_days(v_fleet);
    -- The SECOND standing event is the one that is not the first — by captured id, never by a
    -- created_at that this transaction has made a constant.
    select (e2.payload->>'water_t')::numeric + (e2.payload->>'food_t')::numeric,
           (e2.payload->>'cost')::numeric
      into v_b2, v_cost2
      from public.events e2
     where e2.player_id = v_player and e2.kind = 'PROVISIONED'
       and (e2.payload->>'standing')::boolean and e2.id <> v_ev1;
    if v_crew2 > v_crew1 and v_b2 > v_b1 and v_end2 >= 30 - 0.01 then
      f_crewfire := true;
    end if;

    -- (e) A SHORT PURSE IS A WRITTEN REFUSAL, and nothing is bought.
    select ducats into v_purse1 from public.players where id = v_player;
    perform public.credit(v_player, 'PROBE_DRAIN', -(v_purse1 - 1));
    perform cmd.issue(v_fleet, 'SAIL CAD');
    for k in 1 .. 12 loop
      exit when (select status from public.fleets where id = v_fleet) <> 'SAILING';
      update public.voyages
         set departed_at = departed_at - (eta - now()) - interval '1 minute',
             eta         = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      perform voyage.settle(v_fleet);
    end loop;

    select count(*) into v_events from public.events
     where player_id = v_player and kind = 'PROVISIONED' and (payload->>'standing')::boolean;
    select payload into v_ref from public.events
     where player_id = v_player and kind = 'PROVISION_REFUSED'
     order by created_at desc limit 1;
    if v_events = 2 and v_ref is not null
       and v_ref->>'code' = 'E_INSUFFICIENT_FUNDS'
       and v_ref->>'preset' = 'Long road'
       and length(coalesce(v_ref->>'reason', '')) > 10 then
      f_refused := true;
    end if;

    -- (f) DELETE DETACHES: strike the order; the fleet must point at nothing, not at a ghost.
    v_res := cmd.provision_preset_delete(v_id);
    if (v_res->>'detached_fleets')::int = 1
       and (select provision_preset_id from public.fleets where id = v_fleet) is null then
      f_detach := true;
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  if not f_crud then
    raise exception '0034 self-assert FAIL: save could not write, re-day and rename one standing order';
  end if;
  if not f_cap then
    raise exception '0034 self-assert FAIL: a seventh standing order was ACCEPTED — the % cap does not bite',
      public.wc_int('provision_preset_max');
  end if;
  if not f_name then
    raise exception '0034 self-assert FAIL: a duplicate name was accepted into the book';
  end if;
  if not f_days then
    raise exception '0034 self-assert FAIL: zero days was accepted as a standing order';
  end if;
  if not f_foreign then
    raise exception '0034 self-assert FAIL: another house''s preset was appliable, or the refusal disclosed it';
  end if;
  if not f_fired then
    raise exception '0034 self-assert FAIL: the standing order did not top the fleet up on arrival (bought %, range % against 30)', v_b1, v_end1;
  end if;
  if not f_ledgered then
    raise exception '0034 self-assert FAIL: the top-up''s charge is not on the ledger tied to its own standing event (delta %, cost %)', v_ledger, v_cost1;
  end if;
  if not f_room then
    raise exception '0034 self-assert FAIL: the stores took no room — free hold %, was % before % tuns landed', v_free1, v_free0, v_b1;
  end if;
  if not f_crewfire then
    raise exception '0034 self-assert FAIL: more crew did not mean a bigger top-up (crew %→%, bought %→%, range %)', v_crew1, v_crew2, v_b1, v_b2, v_end2;
  end if;
  if not f_refused then
    raise exception '0034 self-assert FAIL: a short purse did not leave a written PROVISION_REFUSED (standing events %, refusal %)', v_events, v_ref;
  end if;
  if not f_detach then
    raise exception '0034 self-assert FAIL: striking the order left a fleet pointing at a ghost';
  end if;

  -- The rollback really rolled back — measured as a DELTA against the world this file found, never
  -- as an absolute count (see the baseline above).
  select count(*) into v_left from public.players;
  if v_left <> v_base then
    raise exception '0034 self-assert FAIL: the probe subtransaction left % player row(s) behind (% before, % after)',
      v_left - v_base, v_base, v_left;
  end if;

  -- (g) THE LOCKDOWN HOLDS. No client table write, no unsanctioned executable writer, and the
  --     four new entry points resolve and are reachable by authenticated and not by anon.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0034 self-assert FAIL: the standing-order tables minted % client write grant(s)', v_grants;
  end if;
  select count(*) into v_writers from public.client_executable_writers();
  if v_writers <> 0 then
    raise exception '0034 self-assert FAIL: % unsanctioned client-executable writer(s) exist after 0034', v_writers;
  end if;
  for e in select * from public.client_rpc_entry_points() loop
    if e.fn is null then
      raise exception '0034 self-assert FAIL: client_rpc_entry_points names %.%(%), which does not exist',
        e.schema_name, e.function_name, e.arg_types;
    end if;
  end loop;
  for e in
    select * from (values ('world.provision_presets()'),
                          ('cmd.provision_preset_save(uuid, text, int)'),
                          ('cmd.provision_preset_delete(uuid)'),
                          ('cmd.provision_preset_apply(uuid, uuid)')) as t(sig)
  loop
    if not has_function_privilege('authenticated', e.sig::regprocedure, 'execute')
       or has_function_privilege('anon', e.sig::regprocedure, 'execute') then
      raise exception '0034 self-assert FAIL: % is not authenticated-only', e.sig;
    end if;
  end loop;
  if has_function_privilege('authenticated', 'cmd.run_standing_provision(uuid)'::regprocedure, 'execute')
     or has_function_privilege('anon', 'cmd.run_standing_provision(uuid)'::regprocedure, 'execute') then
    raise exception '0034 self-assert FAIL: the executor is client-callable — a second way to spend the purse';
  end if;

  raise notice '0034 self-assert ok: both slices are their pre-images plus only the 0034 lines (ACLs unmoved); one probe house wrote, re-dayed and renamed a standing order; the 7th was REFUSED E_PRESET_CAP, a taken name and zero days refused, a foreign preset unappliable; the first arrival bought % tuns of stores for % d. on the ledger against its own standing event and the second — after signing % more crew — bought % tuns for % d., range landing >= 30 d both times; free hold fell by exactly the stores taken aboard; a drained purse left a written PROVISION_REFUSED and bought nothing; the strike detached 1 fleet; probe rolled back to 0 players; 0 client write grants, 0 unsanctioned writers, 4 entry points authenticated-only, executor server-only',
    v_b1, v_cost1, v_crew2 - v_crew1, v_b2, v_cost2;
end $$;

drop table if exists defs_before_0034;
