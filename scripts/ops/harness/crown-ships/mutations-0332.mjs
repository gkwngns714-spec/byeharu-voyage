// The deliberate breakages of migration 0332: [label, mutate(file), the error it must fail with, optional SQL run after the file].
// The last three do not touch the file: they break the live rule the proof leans on, so a proof that merely trusted the old code would stay green.
const body = (fn, from, to) => `do $x$
declare v text := replace(pg_get_functiondef('${fn}'::regprocedure), E'\\r', '');
begin
  if position($q$${from}$q$ in v) = 0 then raise exception 'mutation text is gone in ${fn}'; end if;
  execute replace(v, $q$${from}$q$, $q$${to}$q$);
end $x$;`

export const mutations = (swap) => {
  const yardMark = `        || case when cu.crown is null then '{}'::jsonb else jsonb_build_object('crown', cu.crown) end\n        -- 0165`
  const snapMark = `        || case when cu.crown is null then '{}'::jsonb else jsonb_build_object('crown', cu.crown) end   -- 0332`
  return [
    ['the navy knob is left out', (s) => swap(s, `(values (public.wc_text('navy_ship_class'), 'NAVY', 1),\n                 (public.wc_text('convoy_ship_class'), 'CARGO', 2),`, `(values (public.wc_text('convoy_ship_class'), 'CARGO', 2),`), /0332 self-assert FAIL: public.crown_classes is not the three knobs/],
    ['the armed cargo class is left out', (s) => swap(s, `(public.wc_text('convoy_ship_class'), 'CARGO', 2),\n                 (public.wc_text('convoy_armed_class'), 'CARGO', 3)) k`, `(public.wc_text('convoy_ship_class'), 'CARGO', 2)) k`), /0332 self-assert FAIL: public.crown_classes is not the three knobs/],
    ['the navy class is written down', (s) => swap(s, `(values (public.wc_text('navy_ship_class'), 'NAVY', 1),`, `(values ('galion', 'NAVY', 1),`), /PROOF 39 FAIL: the navy mark did not follow navy_ship_class/],
    ['a class named twice is the cargo ship', (s) => swap(s, `'NAVY', 1),`, `'NAVY', 4),`), /PROOF 39 FAIL: a class named twice/],
    ['the Codex is not told', (s) => swap(s, snapMark, `        --`), /0332 self-assert FAIL: the snapshot does not serve the mark/],
    ['the yard is not told', (s) => swap(s, yardMark, `        -- 0165`), /0332 self-assert FAIL: the yard does not serve the mark/],
    ['every class is marked in the Codex', (s) => swap(s, snapMark, `        || jsonb_build_object('crown', cu.crown)   -- 0332`), /0332 self-assert FAIL: the snapshot does not serve the mark/],
    ['every hull is marked in the yard', (s) => swap(s, yardMark, `        || jsonb_build_object('crown', cu.crown)\n        -- 0165`), /0332 self-assert FAIL: the yard does not serve the mark/],
    ['a client can call it', (s) => swap(s, `  revoke all on function public.crown_classes() from public, anon, authenticated;\n`, `  grant execute on function public.crown_classes() to authenticated;\n`), /0332 self-assert FAIL: public.crown_classes can be called from a client/],
    ['a price is touched', (s) => swap(s, `  -- ── 3. THE SELF-ASSERT`, `  update public.hull_recipes set ducats = ducats + 1 where class_code = 'navire';\n  -- ── 3. THE SELF-ASSERT`), /0332 self-assert FAIL: a class or recipe moved/],
    ['a knob is touched', (s) => swap(s, `  -- ── 3. THE SELF-ASSERT`, `  update public.world_config set updated_at = now() - interval '1 day' where key = 'navy_ship_class';\n  -- ── 3. THE SELF-ASSERT`), /0332 self-assert FAIL: a world_config row moved/],
    ['a hull answers to her class', (s) => s, /PROOF 39 FAIL: .* made her house a crown's/, body('public.fleet_kind(uuid)', `'COMPANY'`, `(case when exists (select 1 from public.ships s join public.crown_classes() cu on cu.class_code = (select c.code from public.ship_classes c where c.id = s.class_id) where s.fleet_id = p_fleet) then 'NAVY' else 'COMPANY' end)`)],
    ['a crown hull skips her skills', (s) => s, /PROOF 39 FAIL: .* with no skills|PROOF 39 FAIL: .* with an empty shed/, body('public.requirements_unmet(uuid,text,text)', `where r.subject_kind = p_kind and r.subject_code = p_code and x.lvl < r.level`, `where r.subject_kind = p_kind and r.subject_code = p_code and x.lvl < r.level and p_code not in (select c.class_code from public.crown_classes() c)`)],
    ['a crown hull is half price', (s) => s, /PROOF 39 FAIL: the gold of/, body('public.yard_labour(uuid,text)', `v_base bigint := public.hull_labour(p_class);`, `v_base bigint := case when p_class in (select c.class_code from public.crown_classes() c) then public.hull_labour(p_class) / 2 else public.hull_labour(p_class) end;`)],
  ]
}
