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
