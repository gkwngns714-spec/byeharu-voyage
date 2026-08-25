// Types for market-fixture.mjs — hand-written for the same reason chainSource.node.d.mts is: a
// spec may import the fixture without dragging Node's ambient globals into its scope.

/** The receipt `proof.pin_market` returns, and the installer's own rolled-back probe. */
export interface PinMarketReceipt {
  rows: number
  nonzero: number
  distinct: number
  stddev: string
  amplitude: string
  slot: number
}

/** The narrow slice of a PGlite this module uses. */
export interface FixtureDb {
  exec(sql: string): Promise<unknown>
  query(sql: string, params?: unknown[]): Promise<{ rows: unknown[] }>
}

/**
 * Create `proof.pin_market(p_key, p_secret, p_a, p_b, p_hold)` on an applied chain, and prove it
 * works inside a transaction that is rolled back.
 */
export declare function installMarketFixture(
  db: FixtureDb,
  options?: { log?: (message: string) => void },
): Promise<PinMarketReceipt>
