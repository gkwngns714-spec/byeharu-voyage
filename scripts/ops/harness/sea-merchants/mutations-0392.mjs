// mutations-0392.mjs: the mutation controls of proof-0392.mjs: deliberate breakages of 0392, each REQUIRED to fail for its own reason.
// Each entry: [label, mutate(sql) -> sql, the error it must raise]. SELF = the file's own self-assert must catch it; AFTER = the file is clean in itself and
// only proof 92 (run right after it) can see it. A mutation that passes, or fails for another reason, fails the harness.

export function mutations(swap) {
  return [
    // SELF
    ['SELF a hunk no longer occurs (npc_loop_candidates hunk 1, old text moved)', (s) => swap(s, '$h$public.npc_feasible_legs(p_home, p_speed, v_days_cap)$h$,', '$h$public.npc_feasible_legs(p_home, p_speed, v_days_cap )$h$,'), /hunk 1 of public\.npc_loop_candidates.* occurs 0 time/],
    ['SELF a hunk no longer occurs (npc_plan hunk 3, old text moved)', (s) => swap(s, '$h$        if i = 0 and v_choose and (v_net <= 0 or v_off or sr.lap_no % greatest(v_review, 1) = 0) then\n$h$,', '$h$        if i = 0 and v_choose and (v_net <= 0 or v_off) then\n$h$,'), /hunk 3 of public\.npc_plan.* occurs 0 time/],
    ['SELF the switch is shipped lit', (s) => swap(s, "('sea_conditions_bite_npc', 'false'::jsonb,", "('sea_conditions_bite_npc', 'true'::jsonb,"), /not shipped false|not what they were/],
    ['SELF the old three-argument function is kept', (s) => swap(s, '  drop function public.npc_feasible_legs(uuid, numeric, integer);\n', ''), /the old npc_feasible_legs still stands|a function this file does not re-cut moved/],
    ['SELF the memo is readable by a client', (s) => swap(s, '  revoke all on table public.npc_course_zones_memo from public, anon, authenticated;\n', '  grant select on table public.npc_course_zones_memo to authenticated;\n'), /readable by a client/],
    ['SELF the memo is filled with the wrong zones', (s) => swap(s, 'select c.course, public.course_zones(c.course) as zones from c)', "select c.course, array['MED']::text[] as zones from c)"), /the memo disagrees with public\.course_zones/],
    ['SELF dark is not the old answer (the stores test dropped)', (s) => swap(s, '       and public.npc_leg_days(l.nm, p_speed) <= p_days)   -- 0203', '       and true)   -- 0203'), /with the switch off the feasible legs .* are not what they were/],
    ['SELF dark judges the sea (the switch is not read)', (s) => swap(s, '   where case when (select public.sea_conditions_npc_on())\n', '   where case when true\n'), /with the switch off the feasible legs .* are not what they were/],
    ['SELF lit, nothing is taken away (the rule is not asked)', (s) => swap(s, 'then public.npc_sea_shut((select public.fleet_wave(p_fleet)), l.to_port, l.course) is null\n              else true end\n$body$', 'then true\n              else true end\n$body$'), /lit, the feasible legs are not the dark ones less those her hull cannot hold/],
    // AFTER
    ['AFTER the merchant is judged on a title too (title 1 passed to the one rule)', (s) => swap(s, 'select public.sea_refusal(null, p_wave,', 'select public.sea_refusal(1, p_wave,'), /PROOF 92 FAIL/],
    ['AFTER the planner does not mark her present loop (hunk 2 does nothing)', (s) => swap(s, '          v_unsail := v_unsail or v_sea;\n', ''), /PROOF 92 FAIL: lit, the planner left a merchant buying into a loop her hull cannot hold/],
  ]
}
