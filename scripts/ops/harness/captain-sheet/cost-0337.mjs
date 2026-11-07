// What one sheet costs on the local world (PGlite: a floor, not a forecast; prod measured 3 to 10 times slower in the dev-logs): the file applied, a probe house of five seated captains, then the read timed, rolled back.
export async function cost(db, file, say) {
  await db.exec('begin')
  await db.exec(file)
  await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('levels_bite', 'crew_bite', 'combat_bite', 'skills_bite')`)
  await db.exec(`update public.world_config set value = 'false'::jsonb where key = 'economy_closed'`)
  await db.exec(`
    do $c$
    declare v_p uuid; v_f uuid; v_s uuid; v_c text; v_n int := 0; v_r jsonb;
    begin
      v_p := public.new_house('00000000-0337-4000-8000-0000000000c1', 'Casa do Custo 0337', 'PRT', 'LIS', 'Custo', 'navire', 'Custo', 400000);
      select f.id into v_f from public.fleets f where f.player_id = v_p;
      select s.id into v_s from public.ships s where s.fleet_id = v_f;
      foreach v_c in array array['PIRIREIS', 'YIJANGSON', 'ELCANO', 'TURGUT', 'TARTAGLIA'] loop
        v_n := v_n + 1;
        v_r := public.sign_officer(v_p, v_c, null);
        v_r := public.seat_captain_for(v_p, v_c, v_s, v_n);
      end loop;
      perform public.emit_event(v_p, 'VOYAGE_REPORT', jsonb_build_object('to', 'LIS', 'total_nm', 30000));
      update public.captain_xp set exploration = public.level_points(10), trading = public.level_points(10), combat = public.level_points(10);
      perform cmd.assume_identity('00000000-0337-4000-8000-0000000000c1');
    end $c$;`)
  const timed = async (label, sql, n = 20) => {
    const a = []
    for (let i = 0; i < n; i++) {
      const t = performance.now()
      await db.query(sql)
      a.push(performance.now() - t)
    }
    a.sort((x, y) => x - y)
    say(`COST: ${label}: median ${a[n >> 1].toFixed(1)} ms, max ${a[n - 1].toFixed(1)} ms`)
  }
  const fleet = `(select f.id from public.fleets f join public.players p on p.id = f.player_id where p.company_name = 'Casa do Custo 0337')`
  const signing = (code) =>
    `(select po.id from public.player_officers po join public.officers o on o.id = po.officer_id where o.code = '${code}' and po.player_id = (select id from public.players where company_name = 'Casa do Custo 0337'))`
  await timed('crew_pct, one effect (speed)', `select public.crew_pct(${fleet}, null, 'speed')`)
  await timed('crew_terms, the fleet', `select count(*) from public.crew_terms(${fleet})`)
  await timed('captain_level, one track', `select public.captain_level(${signing('ELCANO')}, 'combat')`)
  await timed('world.captain_stats, a seated captain with three active traits', `select world.captain_stats('ELCANO')`)
  await timed('world.captain_stats, a seated Gunner and Boarder', `select world.captain_stats('TURGUT')`)
  await timed('world.captain_stats, a stranger (the null)', `select world.captain_stats('NOBODY')`)
  await db.exec('rollback')
}
