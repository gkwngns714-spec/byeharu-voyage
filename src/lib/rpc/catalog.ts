// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CATALOGUE — every RPC the client may call, named once
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Both backends are built FROM this table, not beside it: the local one turns a row into
// `select world.market($1::uuid) as result`, the cloud one turns the same row into
// `supabase.schema('world').rpc('market', { p_port })`. Adding an RPC therefore cannot mean
// "adding it in two places and hoping", and a parameter cannot be named one thing over the wire
// and another in SQL.
//
// The argument NAMES are PostgREST's contract (it calls functions by named argument), and the
// TYPES are Postgres's: a bare `$1` carrying null gives "could not determine data type of
// parameter", so every parameter is cast at the call site.
//
// NOT LISTED HERE, deliberately:
//   * `public.new_house()` and `cmd.assume_identity()` — server-only, revoked from every client
//     role by 0004/0008. The local adapter calls them as the superuser it is; a browser talking to
//     Supabase must never be able to.
//   * `voyage.settle()` — every read RPC settles first (D.2). A client-callable settle would be a
//     second way to advance time.
//   * the `tick_*` functions — those are the world's clock, not a player's verb.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export interface RpcArg {
  /** PostgREST calls functions by named argument; this is that name. */
  readonly name: string
  /** The Postgres type to cast to in a local call. */
  readonly type: string
}

export interface RpcSpec {
  readonly schema: 'world' | 'cmd'
  readonly fn: string
  readonly args: readonly RpcArg[]
}

export const RPCS = {
  worldSnapshot: { schema: 'world', fn: 'snapshot', args: [] },
  worldMarket: { schema: 'world', fn: 'market', args: [{ name: 'p_port', type: 'uuid' }] },
  worldFleets: { schema: 'world', fn: 'fleets', args: [] },
  // 0068 — the workstation face's ONE read: what this city can make, what each costs, whether her
  // hold carries it, and what you already own here. `p_fleet` is optional because the face is
  // readable with no fleet alongside; name her and every recipe line says what is aboard.
  // 0070 — the warehouse face's ONE read: the shed's size, how full it is, what is ashore here and
  // what she is carrying that could join it. Both sides in one read, because the screen's whole job
  // is to move things between them and asking twice would let them disagree by a trade in between.
  worldWarehouse: {
    schema: 'world',
    fn: 'warehouse',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_fleet', type: 'uuid' },
    ],
  },
  // 0072 — the building yard's ONE read: what this yard can lay down, what each hull wants, and
  // how much of it is already ashore HERE. It takes no fleet: the materials come out of the city,
  // not out of a hold, which is the whole point of the building.
  // 0073 — who is drinking in this city's inn TODAY. A read with no fleet and no day argument: the
  // day is the world's own (world.game_day()), because an inn that took the day as a parameter
  // could be asked about tomorrow, and being able to look ahead is the same defect as re-rolling.
  worldInn: {
    schema: 'world',
    fn: 'inn',
    args: [{ name: 'p_port', type: 'uuid' }],
  },
  worldBuildingYard: {
    schema: 'world',
    fn: 'building_yard',
    args: [{ name: 'p_port', type: 'uuid' }],
  },
  worldWorkstation: {
    schema: 'world',
    fn: 'workstation',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_fleet', type: 'uuid' },
    ],
  },
  // 0039 — THE FREE SEA. The raster the client's pathfinder proposes over (the same row the
  // server verifies by — one authority, fetched once per session), and one place's sailed
  // distances to everywhere (the SAIL picker's ordering and figures).
  worldSeaRaster: { schema: 'world', fn: 'sea_raster', args: [] },
  worldReach: { schema: 'world', fn: 'reach', args: [{ name: 'p_from', type: 'uuid' }] },
  worldLedger: {
    schema: 'world',
    fn: 'ledger',
    args: [
      { name: 'p_cursor', type: 'timestamptz' },
      { name: 'p_limit', type: 'int' },
    ],
  },
  worldBuyCapacity: {
    schema: 'world',
    fn: 'buy_capacity',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_good', type: 'uuid' },
    ],
  },
  // 0022 — THE BARGAIN. The read and the verb are named here together because they are one feature,
  // and because 0022 grants EXECUTE to `authenticated` on exactly the entry points this catalogue
  // declares (0018's sweep reads it BY NAME). A grant with no row here is a door nobody opens —
  // which is what 0022 shipped as, until this entry.
  //
  // Neither takes a player id: both read `public.current_player_id()` and refuse a fleet that is not
  // yours (E_NOT_YOURS / E_NOT_YOUR_FLEET). That is the same property that makes `cmd.found_house`
  // safe for a browser to hold.
  worldHaggleState: {
    schema: 'world',
    fn: 'haggle_state',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_good', type: 'uuid' },
    ],
  },
  cmdHaggle: {
    schema: 'cmd',
    fn: 'haggle',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_good', type: 'uuid' },
      // LOAD-BEARING, not decoration (0022:470-486): a BUY bargain is gated on the quay HAVING the
      // stock and a SELL one on her CARRYING the cargo, so the side decides which refusal you get.
      { name: 'p_side', type: 'text' },
    ],
  },
  cmdIssue: {
    schema: 'cmd',
    fn: 'issue',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_text', type: 'text' },
      { name: 'p_expected_version', type: 'int' },
      // 0039: a SAIL carries the PROPOSED course ([[lat,lon], …]). The server verifies it against
      // its own raster and measures it itself — a client cannot gain by lying here.
      { name: 'p_path', type: 'jsonb' },
    ],
  },
  cmdPreview: {
    schema: 'cmd',
    fn: 'preview',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_text', type: 'text' },
      { name: 'p_path', type: 'jsonb' },
    ],
  },
  cmdCancel: {
    schema: 'cmd',
    fn: 'cancel_at',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_index', type: 'int' },
    ],
  },
  cmdClear: {
    schema: 'cmd',
    fn: 'clear',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_include_active', type: 'boolean' },
    ],
  },
  cmdVerbSchema: { schema: 'cmd', fn: 'verb_schema', args: [] },
  // 0013-0016: the record, the house, the roster and the school.
  worldPriceHistory: {
    schema: 'world',
    fn: 'price_history',
    args: [
      { name: 'p_port', type: 'uuid' },
      { name: 'p_slots', type: 'int' },
    ],
  },
  // Takes NO id — the server reads auth.uid(), so a caller can only ever read their own house.
  worldPlayer: { schema: 'world', fn: 'player', args: [] },
  worldOfficers: { schema: 'world', fn: 'officers', args: [] },
  worldSkills: { schema: 'world', fn: 'skills', args: [] },
  // THE BOARD (0025). `p_limit` bounds the rows returned, never who may be on them — the server
  // decides what a board row may carry (name, nation, standing, and the fames the standing is
  // computed from) and `public.standings` is unreadable to every client role, so a wider limit
  // cannot widen a row. Your own position comes back in `you` even when you are off the board.
  worldStandings: { schema: 'world', fn: 'standings', args: [{ name: 'p_limit', type: 'int' }] },
  // WHAT IS ON AT THE QUAY (0026). Null port = the catalogue of kinds with no port's own running
  // list. Reading it is also what WINDS the calendar where pg_cron is absent, which is 0009's
  // catch-up idiom and the reason this is a read the client makes rather than a job someone runs.
  worldBuffs: { schema: 'world', fn: 'buffs', args: [{ name: 'p_port', type: 'uuid' }] },
  cmdHireOfficer: {
    schema: 'cmd',
    fn: 'hire_officer',
    args: [
      { name: 'p_code', type: 'text' },
      { name: 'p_fleet', type: 'uuid' },
    ],
  },
  cmdPostOfficer: {
    schema: 'cmd',
    fn: 'post_officer',
    args: [
      { name: 'p_code', type: 'text' },
      { name: 'p_fleet', type: 'uuid' },
    ],
  },
  cmdStudySkill: {
    schema: 'cmd',
    fn: 'study_skill',
    args: [
      { name: 'p_code', type: 'text' },
      { name: 'p_fleet', type: 'uuid' },
    ],
  },
  // 0034 — THE BOOK OF STANDING ORDERS. One read and three verbs, landed here together with the
  // migration's grant rows because a grant with no catalogue entry is a door nobody opens — the
  // 0022 lesson, written into that migration's own header. None takes a player id: each reads
  // `public.current_player_id()` server-side and refuses what is not yours, the same property
  // that makes cmd.found_house safe for a browser to hold. `provision_preset_apply` with a null
  // `p_preset` CLEARS the fleet's standing order — clearing is not a second verb.
  worldProvisionPresets: { schema: 'world', fn: 'provision_presets', args: [] },
  cmdProvisionPresetSave: {
    schema: 'cmd',
    fn: 'provision_preset_save',
    args: [
      { name: 'p_preset', type: 'uuid' },
      { name: 'p_name', type: 'text' },
      { name: 'p_days', type: 'int' },
    ],
  },
  cmdProvisionPresetDelete: {
    schema: 'cmd',
    fn: 'provision_preset_delete',
    args: [{ name: 'p_preset', type: 'uuid' }],
  },
  cmdProvisionPresetApply: {
    schema: 'cmd',
    fn: 'provision_preset_apply',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_preset', type: 'uuid' },
    ],
  },
  // 0039: the helm order at sea — she turns WHERE SHE IS. The destination is a port OR any point
  // of open water, and the proposed onward course rides along (bridged server-side to her true
  // position and verified as water like every other course). Not a verb: it acts on the queue and
  // the voyage NOW, like cancel_at and clear.
  cmdDivert: {
    schema: 'cmd',
    fn: 'divert',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_dest', type: 'uuid' },
      { name: 'p_dest_point', type: 'jsonb' },
      { name: 'p_path', type: 'jsonb' },
    ],
  },
  // The ONE way a signed-in captain gets a house (0011). It takes no uid — the server reads
  // auth.uid() — which is why it is safe for a browser to hold, unlike public.new_house().
  cmdFoundHouse: {
    schema: 'cmd',
    fn: 'found_house',
    args: [
      { name: 'p_company_name', type: 'text' },
      { name: 'p_nation_code', type: 'text' },
    ],
  },
} as const satisfies Record<string, RpcSpec>

export type RpcName = keyof typeof RPCS

/** `world.snapshot()` — for logs and error messages, spelled the way the migration spells it. */
export function rpcLabel(name: RpcName): string {
  const spec: RpcSpec = RPCS[name]
  return `${spec.schema}.${spec.fn}(${spec.args.map((a) => a.name).join(', ')})`
}

/** The SQL a local call runs. One `select`, aliased `result`, so the caller reads one column. */
export function localSql(name: RpcName): string {
  const spec: RpcSpec = RPCS[name]
  const params = spec.args.map((a, i) => `$${i + 1}::${a.type}`).join(', ')
  return `select ${spec.schema}.${spec.fn}(${params}) as result`
}

/** The named-argument object a PostgREST call posts. */
export function namedArgs(name: RpcName, values: readonly unknown[]): Record<string, unknown> {
  const spec: RpcSpec = RPCS[name]
  const out: Record<string, unknown> = {}
  spec.args.forEach((arg, i) => {
    out[arg.name] = values[i] ?? null
  })
  return out
}
