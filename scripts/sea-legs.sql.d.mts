// Types for sea-legs.sql.mjs, hand-written so a spec may import the pair table's laws.

/** One select: `own` (harbour codes whose own row is not their roadstead's sea), `lanes` (remembered courses off their pair's row), `asks` (rows asking other than their seas). */
export declare const LAWS_SQL: string
export declare const KEEP_FN: string
export declare function migrationSql(x: Record<string, unknown>): string
