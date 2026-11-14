-- ROLLBACK DRAFT for 0422 (a combat ship sails three times as fast as a merchant). OWNER ONLY. Not a migration as it stands: to roll back,
-- copy it into the next free migration number and deploy it with ~/bin/bv-deploy.sh.
--
-- What it does: the navy's and the pirates' ships sail at their own speed again, through the same door 0422 moved them with
-- (public.fleet_speed_set): the knob loses both kinds, and every navy and pirate voyage at sea is re-timed continuously (the segment she is on
-- keeps its speed; every later segment's frozen speed is divided by 4.5; her arrival moves later by exactly those hours). No ship jumps.
-- What stays: the hunk in voyage.fleet_speed_at, public.fleet_speed_mult and the door (with the knob empty they multiply by 1: every fleet
-- sails exactly as before 0422, to the digit, as 0422's own probe asserts).
-- A softer step back (e.g. 3.5 instead of 4.5) is the same call with that figure: public.fleet_speed_set('NAVY', 3.5).
-- news: a rollback says so in the news if the owner wants it: public.news_update('<number>', 'Navy and pirate ships sail at their own speed again', '해군과 해적선이 다시 원래 속도로 항해합니다').
do $r$
declare
  v_n jsonb;
  v_p jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);
  v_n := public.fleet_speed_set('NAVY', 1, now());
  v_p := public.fleet_speed_set('PIRATE', 1, now());
  if (select value from public.world_config where key = 'fleet_speed_by_kind') <> '{}'::jsonb then
    raise exception 'rollback of 0422 FAIL: the knob is not empty';
  end if;
  raise notice 'rollback of 0422 ok: navy % voyage(s) and pirate % voyage(s) at sea re-timed; every kind sails at its own speed', v_n ->> 'voyages', v_p ->> 'voyages';
end $r$;
