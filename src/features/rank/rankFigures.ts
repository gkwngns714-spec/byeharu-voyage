import type { NationStandings, StandingsBoard } from '../../lib/rpc'

// THE BOARD'S FIGURES — what the Rank page's side column prints, read off the SERVED board and nothing else (2026-11-03, the
// page slice; owner row 267: *"too packed"* — the side column is the tray's and is used).
//
// WHAT THIS IS. Pure readings of `world.standings` (0025) and `world.nation_standings` (0148): one house's line in one shape
// whether it is a row of the board or the `you` the board carries off its end, the leaders (the first rows, as served — the
// server ranks, this file sorts nothing), and your country's line on the countries' board. Every figure is a served field or a
// slice of served rows — never a place computed here, never a fame summed here: 0025 says what a place is (competition rank,
// ties and all) and 0014 what fame is, and a client that re-derived either would be a second authority
// (docs/NO_SPAGHETTI.md §1, §2: a reading of a served payload with no React, no store and no screen in it).
//
// WHERE IT LIVES, AND WHY. It is the Rank screen's own vocabulary over its own reads; no other screen reads the board
// (tests/consistency.spec.ts: the captains' board is Rank's, Stats/Me no longer repeats it). THE SECOND CALLER is implausible by
// construction — a second screen printing a house's place would be the duplicate "one fact, one home" refuses — so it stays
// in the screen rather than in src/domain; the day it is wanted twice, it moves there whole. In its own file rather than
// RankScreen.tsx so the screen file holds components and the readings can be read without a browser.

/** ONE HOUSE'S LINE, in one shape: a row of the board, or you off the board's end. `name` and `nation` are the server's for a
 *  row; for `you` they are `world.player()`'s (0025 serves `you` without them — the one place a company reads itself). */
export interface Line {
  position: number
  tied: boolean
  name: string
  nation: string | null
  trade_fame: number
  exploration_fame: number
  total_fame: number
  ports_reached: number
  /** 0148 — the cities this company is mayor of (names); empty when none. */
  mayor_of: readonly string[]
  /** Yours: drawn in the accent tone, and the one line with a test id of its own. */
  mine: boolean
}

export interface Lines {
  /** The board's rows, in the served order (by place). */
  rows: Line[]
  /** Your line — a row of the board when you placed, else the `you` the board carries off its end; null with no company. */
  mine: Line | null
  /** Whether your line is one of `rows` (drawn in place) or stands under its own heading after them. */
  onBoard: boolean
}

/** The board as lines. `you` is what `world.player()` says your company is called and sails under. */
export function linesOf(board: StandingsBoard, you: { name: string; nation: string | null }): Lines {
  const rows: Line[] = board.board.map((r) => ({
    position: r.position,
    tied: r.tied,
    name: r.company_name,
    nation: r.nation,
    trade_fame: r.trade_fame,
    exploration_fame: r.exploration_fame,
    total_fame: r.total_fame,
    ports_reached: r.ports_reached,
    mayor_of: r.mayor_of ?? [],
    mine: r.is_you,
  }))
  if (board.you === null) return { rows, mine: null, onBoard: false }
  const placed = rows.find((r) => r.mine) ?? null
  if (board.you.on_board && placed !== null) return { rows, mine: placed, onBoard: true }
  return {
    rows,
    mine: {
      position: board.you.position,
      tied: board.you.tied,
      name: you.name,
      nation: you.nation,
      trade_fame: board.you.trade_fame,
      exploration_fame: board.you.exploration_fame,
      total_fame: board.you.total_fame,
      ports_reached: board.you.ports_reached,
      mayor_of: board.you.mayor_of ?? [],
      mine: true,
    },
    onBoard: false,
  }
}

/** The first `n` lines of the board — the server's order is the ranking, so the leaders are a slice, never a sort. */
export function leadersOf(rows: readonly Line[], n: number): Line[] {
  return rows.slice(0, n)
}

/** Your country's line on the countries' board, or null: no company, no country, or a country the board does not list. */
export function myCountryOf(board: NationStandings, nation: string | null): NationStandings['countries'][number] | null {
  if (nation === null) return null
  return board.countries.find((c) => c.nation === nation) ?? null
}
