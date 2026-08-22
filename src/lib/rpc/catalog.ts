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
  // 0019 — the comparison. `p_fleet` is optional and is what makes the quantities REAL: name her
  // and every row is priced at what she can actually afford and carry, and at what she may sail to.
  worldTradeRoutes: {
    schema: 'world',
    fn: 'trade_routes',
    args: [
      { name: 'p_from', type: 'uuid' },
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_max_legs', type: 'int' },
      { name: 'p_limit', type: 'int' },
      // Pin the destination and the read answers the other question a trader has: not "where is
      // this worth more" but "what should I carry THERE".
      { name: 'p_to', type: 'uuid' },
    ],
  },
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
    ],
  },
  cmdPreview: {
    schema: 'cmd',
    fn: 'preview',
    args: [
      { name: 'p_fleet', type: 'uuid' },
      { name: 'p_text', type: 'text' },
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
