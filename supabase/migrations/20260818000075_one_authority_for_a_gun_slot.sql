-- ===============================================================================================
-- 0075 - ONE AUTHORITY FOR A GUN SLOT
-- ===============================================================================================
--
-- A CORRECTION TO 0074, FOUND BY PLAYING THE GAME.
--
-- 0074 said `guns` "stops being a stat and becomes what it always was: how many WEAPON fittings a
-- hull can mount", and then did not move a single value in that column. So the world came out of
-- that migration with TWO authorities for one number, disagreeing:
--
--     ship_classes.guns   barca 0   carlat 2   nau 12
--     class_slots.weapon  barca 1   carlat 2   nau  3
--
-- cmd.do_fit read the first and world.fleets printed the first, so a BARCA COULD MOUNT NO WEAPON
-- AT ALL - against the owner's own sentence, "for tier 1, sail, weapon, anchor would do" - and a
-- nau would have taken twelve. It showed up on the FLEETS screen as `rig 0/1 · ground-tackle 0/1`
-- with no weapon slot listed, which is what a two-authority bug looks like from the outside: not
-- an error, just a thing quietly missing.
--
-- -- AND THE CLAIM ITSELF WAS WRONG --------------------------------------------------------------
-- `guns` was never a dead column. voyage.settle reads it for the escort score - how well a fleet
-- shrugs off a hazard at sea - and has since 0006. 0074's header asserted otherwise and nobody
-- checked, which is the more useful half of this lesson: the sentence "this retires a dead column"
-- is a CLAIM ABOUT CALLERS and should have been a query about callers.
--
-- -- THE FIX: THE GENERAL TABLE WINS ------------------------------------------------------------
-- public.class_slots already holds every other kind of slot, and it holds the numbers DESIGN_V1
-- 1.5 actually specifies. So it is the authority for the weapon slot too, and the special case in
-- cmd.do_fit disappears rather than being corrected - a branch that exists only because two tables
-- disagreed is a branch that should not exist once they do not.
--
-- `guns` goes back to being what it has always genuinely been: how many cannon she carries, read
-- by the escort score. Its comment says so again.
--
-- -- WHY THIS IS NOT A SUPERSEDE OF THE SLOT NUMBERS ---------------------------------------------
-- No authored value changes. class_slots already said 1 / 2 / 3 and still says 1 / 2 / 3; guns
-- already said 0 / 2 / 12 and still says 0 / 2 / 12. What changes is WHICH ONE IS READ, and the
-- only behaviour that moves is the one that was wrong: a barca can carry the weapon the owner said
-- she carries, and a nau can carry three rather than twelve.
-- ===============================================================================================

create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $fn$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0075 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

-- -- 1. THE BRANCH GOES ---------------------------------------------------------------------------
select pg_temp.recut('cmd.do_fit(uuid, jsonb)'::regprocedure, false,
  $f0$  if k.slot = 'weapon' then
    select c.guns into v_slots from public.ship_classes c where c.id = v_ship.class_id;
  else
    select coalesce(cs.count, 0) into v_slots
      from public.ship_classes c
      left join public.class_slots cs on cs.class_code = c.code and cs.slot = k.slot
     where c.id = v_ship.class_id;
  end if;$f0$,
  $f1$  -- 0075: ONE TABLE FOR EVERY KIND OF SLOT, weapons included. This was a branch on
  -- ship_classes.guns, which disagreed with class_slots and left a barca unable to mount the
  -- weapon the owner said she carries.
  select coalesce(cs.count, 0) into v_slots
    from public.ship_classes c
    left join public.class_slots cs on cs.class_code = c.code and cs.slot = k.slot
   where c.id = v_ship.class_id;$f1$);

-- -- 2. AND SO DOES THE OVERRIDE ON THE WIRE --------------------------------------------------------
select pg_temp.recut('world.fleets()'::regprocedure, false,
  $w0$                 'slots', (select coalesce(jsonb_object_agg(cs.slot, cs.count), '{}'::jsonb)
                   from public.class_slots cs where cs.class_code = c.code)
                 || jsonb_build_object('weapon', c.guns),$w0$,
  $w1$                 -- 0075: class_slots alone. An override used to be appended here that replaced a
                 -- correct weapon count with the cannon column, which is a different number.
                 'slots', (select coalesce(jsonb_object_agg(cs.slot, cs.count), '{}'::jsonb)
                   from public.class_slots cs where cs.class_code = c.code),$w1$);

comment on column public.ship_classes.guns is
  'How many cannon she carries. Read by voyage.settle for the escort score - how well a fleet '
  'shrugs off a hazard - and it has been read there since 0006. 0074 briefly claimed this was a '
  'dead column being retired into the weapon-SLOT count; it was neither dead nor the slot count, '
  'and public.class_slots is the one authority for how many fittings of any kind a hull may carry.';

-- -- SELF-ASSERT ------------------------------------------------------------------------------------
do $$
declare
  v_bad    int;
  v_player uuid;
  v_fleet  uuid;
  v_port   uuid;
  v_ship   uuid;
  v_res    jsonb;
  v_grants int;
  c_uid constant uuid := '00000000-0075-4000-8000-000000000001';
begin
  -- (a) EVERY CLASS HAS A WEAPON SLOT IN THE ONE TABLE. If class_slots did not carry it, removing
  --     the branch would have silently taken weapons away from every hull instead of giving the
  --     barca hers.
  select count(*) into v_bad from public.ship_classes c
   where not exists (select 1 from public.class_slots cs
                      where cs.class_code = c.code and cs.slot = 'weapon');
  if v_bad <> 0 then
    raise exception '0075 self-assert FAIL: % class(es) have no weapon slot in class_slots', v_bad;
  end if;

  -- (b) NOTHING READS guns FOR A SLOT ANY MORE. The two functions that did are re-cut; this is the
  --     check that they stay re-cut, and it names the column rather than the line.
  if position('c.guns' in pg_get_functiondef('cmd.do_fit(uuid, jsonb)'::regprocedure)) <> 0 then
    raise exception '0075 self-assert FAIL: cmd.do_fit still reads ship_classes.guns for a slot';
  end if;
  -- Precise on purpose, and the comment above the re-cut hunk deliberately does NOT quote the
  -- removed code: an earlier draft of this assert found its own explanation and failed. A body may
  -- describe what it used to do, so a check on a body must look for the CALL, not the words.
  if position('''weapon'', c.guns' in pg_get_functiondef('world.fleets()'::regprocedure)) <> 0 then
    raise exception '0075 self-assert FAIL: world.fleets still overrides the weapon slot with guns';
  end if;

  -- (c) AND guns IS STILL READ WHERE IT BELONGS. Removing a branch must not quietly retire a column
  --     the sea depends on - the escort score has read it since 0006.
  if position('guns' in pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure)) = 0 then
    raise exception '0075 self-assert FAIL: the escort score stopped reading guns';
  end if;

  -- (d) THE BUG ITSELF, PROVEN GONE: a BARCA can mount a weapon. This is the owner's own sentence -
  --     "for tier 1, sail, weapon, anchor would do" - and before this file she could not.
  v_player := public.new_house(c_uid, 'Casa Canhao', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  select port_id into v_port from public.fleets where id = v_fleet;
  select id into v_ship from public.ships where fleet_id = v_fleet;
  perform cmd.assume_identity(c_uid);
  if (select c.code from public.ships s join public.ship_classes c on c.id = s.class_id
       where s.id = v_ship) <> 'barca' then
    raise exception '0075 self-assert FAIL: the founding hull is not a barca, so this probe proves nothing';
  end if;

  insert into public.player_items (player_id, port_id, item_code, qty)
  values (v_player, v_port, 'boarding-gear', 1)
  on conflict (player_id, port_id, item_code) do update set qty = 1;

  v_res := cmd.issue(v_fleet, 'FIT boarding', null, null);
  if not (v_res->>'ok')::boolean then
    raise exception '0075 self-assert FAIL: a barca still cannot mount a weapon: %', v_res->'order';
  end if;
  if not exists (select 1 from public.ship_fittings where ship_id = v_ship and item_code = 'boarding-gear') then
    raise exception '0075 self-assert FAIL: FIT said yes and mounted nothing';
  end if;

  -- AND HER ONE SLOT IS ONE. A fix that gave her unlimited weapons would pass everything above.
  insert into public.player_items (player_id, port_id, item_code, qty)
  values (v_player, v_port, 'broadside-guns', 1)
  on conflict (player_id, port_id, item_code) do update set qty = 1;
  perform cmd.clear(v_fleet, true);
  v_res := cmd.issue(v_fleet, 'FIT broadside', null, null);
  if (v_res->>'ok')::boolean then
    raise exception '0075 self-assert FAIL: a barca mounted TWO weapons in her one slot';
  end if;
  if v_res->'refusal'->>'code' <> 'E_SLOTS_FULL' then
    raise exception '0075 self-assert FAIL: her full weapon slot refused with % rather than E_SLOTS_FULL',
      v_res->'refusal'->>'code';
  end if;

  -- (e) POSTURE.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0075 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0075 self-assert ok: ONE AUTHORITY FOR A GUN SLOT. 0074 claimed ship_classes.guns was a dead column being retired into the weapon-slot count, moved none of its values, and left TWO authorities disagreeing - guns said a barca carried 0 weapon slots while class_slots said 1, and do_fit read the wrong one. So a tier-1 hull could mount no weapon at all, against the owner''s own "sail, weapon, anchor would do", and it showed on the fleets screen as a slot that simply was not listed. public.class_slots is now the one table for every kind of slot and the branch is GONE rather than corrected. guns was never dead either - voyage.settle has read it for the escort score since 0006 - so it keeps that job and its comment says so. Proven by behaviour: a barca mounted boarding gear, and a second weapon was refused E_SLOTS_FULL because her one slot is one; 0 client write grants.';
end $$;
