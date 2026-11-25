-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 231 - WHAT EACH ASK WOULD CLOSE  (migration 0525; docs/dev-log/2026-11-25-sea-asks-more.md)
--
--   The table the owner sets the figures from, held to the world's own data: the hulls (public.sea_stats_class, ship_classes.wave), the 254 harbours (public.sea_leg_asks). Nothing is
--   set. The kits by grade are the script's (scripts/ops/harness/sea-asks-more/table.mjs); the bare hulls, the closures and the Cape's limit are held here.
--
-- @pass WC_CAPE     every hull that holds the Cape's wave bare (44) has Current strength 16 or more, and some have exactly 16: an ask of 16 closes nobody, 17 closes a hull;
--                   shut, the Cape shuts 11 harbours at rung 2, 44 at 5, 92 at 6 and 97 at 7
-- @pass WC_CLOSES   shut, each other sea of section 3.2 shuts what the table says (ice 1, Kuroshio 2, open Pacific 21, Doldrums 0, Indian Ocean crossing 2, Philippine Sea 1)
-- @pass WC_BARE     the bare hulls that hold the way and meet each figure of 3.2 are the table's (ice 50: 0 of 121; Cape 20: 41 of 48; Kuroshio 25: 14; Pacific 50: 0 of 8;
--                   Doldrums 20: 62 of 121; Indian Ocean 20: 9 of 48; Philippine Sea 35: 0 of 45)
-- @pass WC_OARS     light wind is met by oars or by sails: at each figure of 3.2 that a bare hull meets, both an oared hull and a sailing one of size 2 meet it
-- @pass WC_LOOSE    with the Cape at 16 and the rest at 0, all 254 harbours stay open to every hull that held the way before
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
create function pg_temp.shut231(p_rung int, p_shut text[]) returns int language plpgsql as $f$
declare v text[] := array['LIS']; f text[] := array['LIS'];
begin
  while cardinality(f) > 0 loop
    select array_agg(distinct l.b) into f from leg231 l where l.a = any (f) and l.rung <= p_rung and not l.z && p_shut and l.b <> all (v);
    f := coalesce(f, '{}'); v := v || f;
  end loop;
  return cardinality(v);
end $f$;
do $p$
declare v_got int[]; v_want int[]; r record; v_n int; v_m int;
begin
  create temp table leg231 on commit drop as
    select a.code as a, b.code as b, s.title_min as rung, s.zones || own.zones as z from public.sea_leg_asks s join public.ports a on a.id = s.from_port and a.kind = 'HARBOUR'
      join public.ports b on b.id = s.to_port and b.kind = 'HARBOUR' join public.sea_leg_asks own on own.from_port = s.to_port and own.to_port = s.to_port where a.id <> b.id;
  create index on leg231 (a); analyze leg231;
  create temp table h231 on commit drop as
    select c.code, c.rig, p.size, c.wave, k.ice, k.current, k.light from public.ship_classes c join public.class_profile p on p.class_code = c.code join public.sea_stats_class k on k.class_code = c.code;

  -- ── WC_CAPE ──
  select min(h.current), count(*) filter (where h.current = 16) into v_n, v_m from h231 h where h.wave >= (select z.wave_min from public.sea_zones z where z.code = 'SOU-CAPE');
  if v_n <> 16 or v_m < 1 then raise exception 'PROOF 231 FAIL: the Cape''s weakest bare hull holds %', v_n; end if;
  select array_agg(pg_temp.shut231(g.r, '{}') - pg_temp.shut231(g.r, array['SOU-CAPE']) order by g.r) into v_got from unnest(array[2, 5, 6, 7]) g(r);
  if v_got <> array[11, 44, 92, 97] then raise exception 'PROOF 231 FAIL: the Cape shut shuts %', v_got; end if;
  raise notice 'PASS: WC_CAPE - bare hulls of wave 44 hold 16 and up: an ask of 16 closes nobody; shut, the Cape shuts % harbours at rungs 2, 5, 6, 7', v_got;

  -- ── WC_CLOSES ──
  select array_agg(pg_temp.shut231(8, '{}') - pg_temp.shut231(8, g.z) order by g.o) into v_got
    from (values (1, array['ARC']), (2, array['PHI-JP']), (3, array['NRT-OPEN', 'STH-OPEN']), (4, array['NOR-DOL']), (5, array['IND-E']), (6, array['PHI'])) g(o, z);
  if v_got <> array[1, 2, 21, 0, 2, 1] then raise exception 'PROOF 231 FAIL: the others shut shut %', v_got; end if;
  raise notice 'PASS: WC_CLOSES - ice %, Kuroshio %, open Pacific %, Doldrums %, Indian Ocean crossing %, Philippine Sea % harbours', v_got[1], v_got[2], v_got[3], v_got[4], v_got[5], v_got[6];

  -- ── WC_BARE ──
  for r in select * from (values ('ice', 20, 50, 121, 0), ('current', 44, 20, 48, 41), ('current', 44, 25, 48, 14), ('current', 70, 50, 8, 0), ('light', 24, 20, 121, 62), ('light', 44, 20, 48, 9), ('light', 50, 35, 45, 0)) x(stat, wave, ask, hold, meet) loop
    select count(*), count(*) filter (where (to_jsonb(h)->>r.stat)::int >= r.ask) into v_n, v_m from h231 h where h.wave >= r.wave;
    if v_n <> r.hold or v_m <> r.meet then raise exception 'PROOF 231 FAIL: % % at wave %: % of % (table % of %)', r.stat, r.ask, r.wave, v_m, v_n, r.meet, r.hold; end if;
  end loop;
  raise notice 'PASS: WC_BARE - the seven figures of 3.2 against the bare hulls that hold the way, as the table says';

  -- ── WC_OARS ──
  if (select count(*) from h231 h where h.size = 2 and h.rig = 'oared' and h.light >= 20) = 0 or (select count(*) from h231 h where h.size = 2 and h.rig <> 'oared' and h.light >= 20) = 0
     or (select count(*) from h231 h where h.rig = 'oared' and h.light < 28) > 0 then
    raise exception 'PROOF 231 FAIL: light wind wants one kind of ship';
  end if;
  raise notice 'PASS: WC_OARS - at 20, % oared and % sailing hulls meet it bare', (select count(*) from h231 h where h.rig = 'oared' and h.light >= 20), (select count(*) from h231 h where h.rig <> 'oared' and h.light >= 20);

  -- ── WC_LOOSE ──
  if pg_temp.shut231(8, '{}') <> 254 or exists (select 1 from h231 h where h.wave >= 44 and h.current < 16) then raise exception 'PROOF 231 FAIL: 254'; end if;
  raise notice 'PASS: WC_LOOSE - the Cape at 16 and the rest at 0: 254 harbours, no hull that held the way is stopped';
end
$p$;
