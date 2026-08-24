-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0045 — THE WORLD RUNS TWENTY TIMES FASTER
--        time_compression 480 → 9600. A voyage-day was 3 real minutes; it is 9 real seconds.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ─────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-08-24: *"make the speed of moving ships faster 20 times, for faster testing"*.
-- The whole game is being rebuilt around free sailing, and every check of it costs a voyage in real
-- time. At 3 real minutes to the voyage-day, a Lisboa→Nagasaki passage is over two real hours; the
-- work cannot be driven at that speed.
--
-- ── WHY A MIGRATION AND NOT A DEV FLAG ──────────────────────────────────────────────────────────
-- `time_compression` is a world_config knob and the SERVER owns how fast time runs — that is the
-- whole point of DESIGN D.1 and of `voyage.position` being closed-form. A client-side "test mode"
-- would be a SECOND authority for the rate at which the world turns, and the two would disagree the
-- first time anyone read a voyage from the other side. One knob, changed in the open.
--
-- **THIS REACHES PRODUCTION ON THE NEXT DEPLOY.** It is not a local override and there is no
-- pretending otherwise. If the live world should keep 3-minute days, this file is reverted by a
-- superseding migration that sets it back — not by a flag, and not by leaving prod un-deployed.
--
-- ── THE THING THAT MADE THIS MORE THAN A ONE-LINE UPDATE ────────────────────────────────────────
-- A voyage's `eta` is STORED at departure (0006:435) and computed with the compression in force at
-- that moment. But the day boundaries are RE-DERIVED on every read, from
-- `departed_at + hours / wc_num('time_compression')`, clamped by `least(v.eta, …)` (0006:503-508).
--
-- So raising the knob under a fleet already at sea splits her in two: every remaining day of the
-- passage completes at once, because the re-derived boundaries all fall in the past — while the
-- fleet keeps waiting for a stored `eta` computed at the old rate. Her hazards would all roll in
-- one tick and she would then sit becalmed off her destination for the rest of an hour.
--
-- That is not a hypothetical; it is what `least()` does with an eta the knob no longer agrees with.
-- So every SAILING voyage is re-ETA'd here, through `voyage.recompute_eta` — the ONE ETA authority
-- (0006:533), the same one `cmd.divert` uses — so the stored instant and the derived boundaries
-- agree again. The past is untouched: `voyage_events` already written stay written, and
-- `speed_profile` is not re-frozen. Only the arrival instant moves, and it moves EARLIER.
--
-- ── WHAT IS DELIBERATELY NOT TOUCHED ────────────────────────────────────────────────────────────
-- `game_day_seconds` (2880) is the CALENDAR clock — the one fairs and seasons run on (0028 put both
-- clocks on the wire and asserted they differ by 16x). The owner asked for SHIPS to move faster,
-- not for the world's seasons to blur past. Leaving it alone means the two clocks now differ by
-- 0.3x rather than 16x, which is a real change in feel: a fair lasts many more voyages than it did.
-- Stated here rather than discovered later; if seasons should scale too, that is a second decision.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

update public.world_config
   set value = to_jsonb(9600)
 where key = 'time_compression';

update public.world_config
   set description = 'DESIGN D.1, x20 for testing (0045). 1 real second = 2.67 voyage-hours; '
                     '1 voyage-day = 9 real seconds. Was 480 (3 real minutes to the day).'
 where key = 'time_compression';

-- Every fleet already at sea keeps a coherent passage: the stored arrival and the derived day
-- boundaries must agree, or `least()` settles her whole voyage and then strands her.
do $$
declare
  v_id      uuid;
  v_moved   int := 0;
begin
  for v_id in select id from public.voyages where status = 'SAILING' loop
    perform voyage.recompute_eta(v_id);
    v_moved := v_moved + 1;
  end loop;
  if v_moved > 0 then
    raise notice '0045: % voyage(s) at sea were re-ETAd through the one ETA authority', v_moved;
  end if;
end $$;

do $$
declare
  v_comp    numeric;
  v_secs    numeric;
  v_fleet   uuid;
  v_player  uuid;
  v_voy     uuid;
  v_eta_old timestamptz;
  v_eta_new timestamptz;
  v_lis     uuid;
  v_dest    uuid;
  v_res     jsonb;
  f_probe   boolean := false;
  f_clock   boolean := false;
  v_dest_code text;
  v_legs    int;
begin
  -- 1. THE KNOB MOVED, and it moved to exactly twenty times what it was.
  v_comp := public.wc_num('time_compression');
  if v_comp <> 9600 then
    raise exception '0045 self-assert FAIL: time_compression is %, expected 9600', v_comp;
  end if;
  if v_comp / 480 <> 20 then
    raise exception '0045 self-assert FAIL: % is not twenty times the 480 it replaced', v_comp;
  end if;

  -- 2. A VOYAGE-DAY IS NINE REAL SECONDS. Derived from the knob, never retyped — a second copy of
  --    this arithmetic is how the two clocks in 0028 came to disagree by a factor of sixteen.
  v_secs := 24 * 3600 / v_comp;
  if round(v_secs, 3) <> 9 then
    raise exception '0045 self-assert FAIL: a voyage-day is % real second(s), expected 9', v_secs;
  end if;
  f_clock := true;

  -- 3. THE POSITIVE CONTROL, and it is what stops this file passing vacuously. A fresh chain has no
  --    fleet at sea, so the re-ETA loop above would run zero times and prove nothing. So: put a
  --    real house to sea inside a subtransaction, recompute, and require the arrival to move
  --    EARLIER — then roll the whole probe back so the live world is untouched.
  begin
    select id into v_lis from public.ports where code = 'LIS';
    v_player := public.new_house(
      '00000000-0000-4000-8000-00000000d045'::uuid, 'Casa Rapida', 'PRT');
    select f.id into v_fleet from public.fleets f where f.player_id = v_player limit 1;

    -- THE NEAREST HARBOUR OUT OF LISBOA, and the reason is a bug this probe already hit: picking a
    -- destination alphabetically put a starter fleet on an ocean crossing, cmd.issue refused it
    -- E_ENDURANCE, and the probe reported "never got a fleet to sea" for a reason that had nothing
    -- to do with the clock. A one-leg hop is inside any fleet's stores by construction.
    -- Deterministic: ordered by distance then code, so a tie cannot make this a lottery.
    select l.to_port_id into v_dest
      from public.legs l
      join public.ports p on p.id = l.to_port_id
     where l.from_port_id = v_lis
       and p.max_draft >= (select max(c.draft) from public.ships s
                             join public.ship_classes c on c.id = s.class_id
                            where s.fleet_id = v_fleet)
     order by l.distance_nm, p.code
     limit 1;

    select count(*) into v_legs from public.legs where from_port_id = v_lis;
    select code into v_dest_code from public.ports where id = v_dest;

    -- SHE IS PUT TO SEA THROUGH voyage.depart, NOT cmd.issue. The command layer reads the signed-in
    -- captain from auth.uid(), and a migration has no session -- the first draft of this probe
    -- called cmd.issue and was told "That fleet is not yours" (E_NO_SUCH_FLEET), which is the
    -- read wall working exactly as designed. 0037's probe departs the same way for the same reason.
    v_res := to_jsonb(voyage.depart(v_fleet, voyage.route(v_lis, v_dest), now()));
    select id, eta into v_voy, v_eta_old
      from public.voyages where fleet_id = v_fleet and status = 'SAILING';

    if v_voy is not null then
      -- Wind the knob back to what it was, re-ETA, and the arrival must land LATER; then forward
      -- again and it must land earlier. Moving it in BOTH directions is what proves the ETA
      -- follows the knob rather than merely differing from a number typed here.
      update public.world_config set value = to_jsonb(480) where key = 'time_compression';
      v_eta_new := voyage.recompute_eta(v_voy);
      if v_eta_new <= v_eta_old then
        raise exception '0045 self-assert FAIL: at the OLD rate the arrival did not move later (% -> %)',
          v_eta_old, v_eta_new;
      end if;
      update public.world_config set value = to_jsonb(9600) where key = 'time_compression';
      v_eta_new := voyage.recompute_eta(v_voy);
      if v_eta_new >= v_eta_old + interval '1 second' then
        raise exception '0045 self-assert FAIL: at the NEW rate the arrival did not come back in (% vs %)',
          v_eta_new, v_eta_old;
      end if;
      f_probe := true;
    end if;
    raise exception 'ROLLBACK_0045_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0045_PROBE' then raise; end if;
  end;
  -- the subtransaction rolled back, so re-read nothing from it: v_res / v_legs / v_dest_code are
  -- plpgsql variables and survive, which is exactly why the diagnostics are held in them.

  if not f_probe then
    raise exception '0045 self-assert FAIL: the probe never got a fleet to sea (dest %, legs out of LIS %, issue said %) - nothing here was proven',
      coalesce(v_dest_code, '(none chosen)'), v_legs, coalesce(v_res::text, '(null)');
  end if;

  -- 4. THE PROBE LEFT NOTHING BEHIND. A DELTA, never a count: production carries real houses, and
  --    asserting "zero players exist" is a claim about the world rather than about this file.
  if exists (select 1 from public.players
              where auth_uid = '00000000-0000-4000-8000-00000000d045'::uuid) then
    raise exception '0045 self-assert FAIL: the probe house survived the subtransaction';
  end if;

  raise notice '0045 self-assert ok: THE WORLD RUNS TWENTY TIMES FASTER. time_compression is %, '
    'exactly twenty times the 480 it replaced, and a voyage-day is % real second(s) derived from '
    'the knob rather than retyped; every fleet already at sea was re-ETAd through voyage.recompute_eta, '
    'the one ETA authority, so the stored arrival and the re-derived day boundaries agree and no '
    'fleet settles her whole passage in a tick and then sits becalmed; proven on a real voyage put '
    'to sea and rolled back, whose arrival moved LATER when the knob was wound back to 480 and '
    'EARLIER when it was returned to 9600 — so the ETA follows the knob in both directions rather '
    'than merely differing from a number typed here; the probe house left no row behind; and '
    'game_day_seconds is deliberately untouched, so the calendar clock is unchanged and a fair now '
    'lasts many more voyages than it did (0028 asserts both clocks cross the wire)',
    v_comp, round(v_secs, 3);
end $$;
