-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0367 FORWARD ROLLBACK, A DRAFT (docs/ARMADA.md section 13; docs/dev-log/2026-11-13-armada.md). NOT a prod check and NOT a migration yet: it lives in scripts/, so nothing deploys it. Owner only.
--
-- THE FIRST LEVER IS THE SWITCH, and it needs no file:  update public.world_config set value = 'false'::jsonb where key = 'armada_enabled';
--   Forming and sailing then refuse E_NOT_IN_USE at once. Disbanding still works. An armada already at sea finishes her voyage as one.
--
-- THIS FILE is the whole slice taken out, as a forward migration (copy it to supabase/migrations/ under the next number, with a self-assert and its news row, before using it):
--   every armada disbanded (its fleets are each their own again; voyages already at sea keep nothing of it once the tables go, and roll their own days from then on),
--   the six hunks swapped back (each once), voyage.fleet_speed_at put back from voyage.fleet_speed_alone_at (which IS its old body), and what 0367 made dropped.
-- Tested on the local chain: after it, the six re-cut bodies and voyage.fleet_speed_at are byte for byte what main's chain holds at 0356 (docs/dev-log/2026-11-13-armada.md).
-- A VOYAGE AT SEA IN AN ARMADA when this runs: her remaining days are rolled on her own seed, so two sisters may then meet different seas and arrive apart. Nothing is lost.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
-- To use it: strip the guard line, give it the next number, and deploy it as any migration (owner only).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $m$
declare
  v_h   record;
  x     record;
  v_def text;
  v_n   int;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.armadas') is null then
    raise exception 'rollback-0367 refuses: 0367 is not in this world';
  end if;
  create temp table hunks_back_0367 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_back_0367 values
  ('voyage.hazard_roll(uuid,integer)', 1,
$h$  -- 0367 (docs/ARMADA.md section 4): a voyage sailed in an armada rolls her LEAD voyage's days, so every fleet of hers meets the same sea on the same day and they arrive together.
  -- Any other voyage: one primary-key probe of a small table, and the roll it always had.
  p_voyage := coalesce((select av.lead_voyage_id from public.armada_voyages av where av.voyage_id = p_voyage), p_voyage);
  v_leg := voyage.leg_at_day(p_voyage, p_day);
  v_sea := (v_leg->>'sea_id')::uuid;
$h$,
$h$  v_leg := voyage.leg_at_day(p_voyage, p_day);
  v_sea := (v_leg->>'sea_id')::uuid;
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$  v_leg     jsonb;     -- 0339: the day's frozen segment, read once for its danger and its raider
  v_arm     jsonb;     -- 0367: an armada's one fight of the day (voyage.armada_fight); null for a voyage in no armada
$h$,
$h$  v_leg     jsonb;     -- 0339: the day's frozen segment, read once for its danger and its raider
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 2,
$h$      -- 0367 (docs/ARMADA.md section 6): a voyage sailed in an armada meets the raid with every hull of the armada on one side, against the raiders all her fleets draw; the
      -- fight is fought once and every fleet of hers reads it (voyage.armada_fight). Below, each fleet takes her own hulls', crew's and hold's share as ever. Null: the day it always was.
      v_arm := voyage.armada_fight(v.id, d, p_fleet, v_pirate, v_raider);
      if v_arm is not null then
        v_raider := (v_arm->>'raider')::numeric;
        v_escort := (v_arm->>'escort')::numeric;
        v_fight := v_arm->'fight';
      else
      v_fight := case when public.combat_bite_on() then voyage.fight(v.id, d, p_fleet, v_raider) end;
      end if;
$h$,
$h$      v_fight := case when public.combat_bite_on() then voyage.fight(v.id, d, p_fleet, v_raider) end;
$h$),
  ('cmd.do_sail(uuid,jsonb)', 1,
$h$  select * into f from public.fleets where id = p_fleet;

  -- 0367 (docs/ARMADA.md section 4): a fleet of an armada sails on the armada's order only (cmd.armada_sail, which marks its own transaction on the armada's row).
  if exists (select 1 from public.armada_fleets af join public.armadas a on a.id = af.armada_id where af.fleet_id = p_fleet and not a.ordering) then
    raise exception 'E_IN_ARMADA: % sails with her armada; send the armada, or disband it', f.name using errcode = 'P0001';
  end if;

  -- the gates that need no distance, first (status, crew, flagship, and the berth facts)
$h$,
$h$  select * into f from public.fleets where id = p_fleet;

  -- the gates that need no distance, first (status, crew, flagship, and the berth facts)
$h$),
  ('cmd.divert(uuid,uuid,jsonb,jsonb)', 1,
$h$  -- 0367 (docs/ARMADA.md section 4): a fleet of an armada does not turn alone.
  if public.armada_of(p_fleet) is not null then
    return jsonb_build_object('ok', false, 'error_code', 'E_IN_ARMADA',
      'error_message', format('%s sails with her armada; disband it to turn her alone.', f.name), 'fixes', '[]'::jsonb);
  end if;

  -- Catch up first: an act must not reason about a stale position (D.2).
  perform voyage.settle(p_fleet, v_now);
$h$,
$h$  -- Catch up first: an act must not reason about a stale position (D.2).
  perform voyage.settle(p_fleet, v_now);
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'rename_fleet',          'uuid, text'),
      -- 0367: an armada: the read, and the doors to form, disband and send one (and the send's dry run).
      ('world',       'armadas',               ''),
      ('cmd',         'armada_form',           'jsonb, text'),
      ('cmd',         'armada_disband',        'uuid'),
      ('cmd',         'armada_sail',           'uuid, text, jsonb, boolean, boolean'),
      ('cmd',         'preview_armada_sail',   'uuid, text, jsonb, boolean'),
$h$,
$h$      ('cmd',         'rename_fleet',          'uuid, text'),
$h$);
  for v_h in select h.fn from hunks_back_0367 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_back_0367 h where h.fn = v_h.fn order by h.ord desc loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception 'rollback-0367: hunk % of % occurs % time(s), not once: the deployed body is not 0367''s', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
  end loop;
  -- the speed: the old body back under its own name
  execute replace(replace(pg_get_functiondef('voyage.fleet_speed_alone_at(uuid,numeric)'::regprocedure), E'\r', ''),
                  'CREATE OR REPLACE FUNCTION voyage.fleet_speed_alone_at(', 'CREATE OR REPLACE FUNCTION voyage.fleet_speed_at(');
  drop function cmd.preview_armada_sail(uuid, text, jsonb, boolean);
  drop function cmd.armada_sail(uuid, text, jsonb, boolean, boolean);
  drop function cmd.armada_disband(uuid);
  drop function cmd.armada_form(jsonb, text);
  drop function world.armadas();
  drop function public.armada_sail_for(uuid, uuid, text, jsonb, boolean);
  drop function public.armada_disband_for(uuid, uuid);
  drop function public.armada_form_for(uuid, jsonb, text);
  drop function voyage.armada_fight(uuid, int, uuid, uuid, numeric);
  drop function voyage.armada_side(uuid);
  drop function voyage.fleet_speed_alone_at(uuid, numeric);
  drop function public.armada_of(uuid);
  drop function public.armada_on();
  drop table public.armada_fights;
  drop table public.armada_voyages;
  drop table public.armada_fleets;
  drop table public.armadas;
  delete from public.world_config where key in ('armada_enabled', 'armada_fleet_max', 'armada_raid_scale');
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%armada%') then
    raise exception 'rollback-0367: a function still names an armada';
  end if;
end
$m$;
