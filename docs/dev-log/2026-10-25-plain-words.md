# 2026-10-25 — Plain words everywhere: short labels, one-line hints, EN and KO (owner row 202, `osn-plain-words`)

> *"i hate long sentences, words. you pay - buy. change it so that it is strightforward, more simple and easy - all
> parts of the game"* (2026-10-25)

Client wording only. **No layout, no logic, no migration.** Every change is a dictionary VALUE in
`src/lib/i18n/dict/*.ts`; no key, placeholder or plural shape changed (checked mechanically: the set of `{holes}`
in every `en` and `ko` value is the same before and after).

## GLOSSARY — one word per concept, across the whole game

| Concept | EN | KO | Never again |
|---|---|---|---|
| buy goods (verb, tab, column, row) | **Buy** | **사기** | You pay, purchase, 매수 |
| sell goods | **Sell** | **팔기** | You receive, 매도 |
| leave port | **Sail** | **출항** | depart, set out |
| money gained on a trade | **Profit** | **이익** | gain, takings, 수익 |
| money spent on this buy (the tray's total) | **Cost** | **비용** | You pay, what it costs |
| money from this sell (the tray's total) | **Sale** | **판매** | You get, fetches |
| what a unit was bought for | **Paid** | **산 값** | Bought at, purchase price, 매입가 |
| the market's price for a unit | **Price** | **가격** | Sells at, 매도가, 시세 (kept only for the Markets face name) |
| a span of time | **Days** (`3 days`) | **일** (`3일`) | game days, days of sailing |
| what a ship carries | **Cargo** | **화물** | hold, load, aboard |
| the people on a ship | **Crew** | **선원** | hands, complement |
| food and water | **Supplies** | **보급** | provisions, stores |
| the loop a fleet sails by itself | **Route** / **Lap** | **항로** / **바퀴** | circuit, trade route |
| a trade you are drafting | **Plan** | **계획** | draft, order sheet |
| the player's money | **Money** | **돈** | purse, funds, ducats (the unit name stays) |
| the port's goods store | **Storage** | **창고** | warehouse, shed |
| someone you hire to lead | **Captain** | **선장** | officer |
| the city's share market | **Shares** | **지분** | holdings, stake |
| a server refusal with no sentence | **Refused, no reason given.** | **이유 없이 거절됨.** | The server refused, without a reason. |

**The rule, applied everywhere** (docs/WORDS.md carries it as law): a label is 1–2 plain words; a hint is ONE short
line; a number stands alone (`+1,231`, never *"you would make 1,231 ducats"*); Korean is as short as the English
(짧고 쉬운 말), never a word-for-word translation; no "You/Your" in a label.

## What changed

| Part | Where | Count |
|---|---|---|
| Dictionary values, EN + KO | `src/lib/i18n/dict/*.ts` (25 of 27 files; `format.ts`, `common.ts` untouched) | 1,147 values rewritten: 565 EN, 582 KO |
| Hard-coded refusal fallback moved into the dictionary | `src/domain/order/text.ts`, `src/live/useStepOrder.ts` → `t('trade.noReason')` | 2 literals |
| Specs that pinned the old sentences | see below | 3 files |

The sweep of `src/{features,app,components/ui,domain,lib/format,live,store}` for player-facing literals outside
the dictionary (the same literal reader `tests/words.spec.ts` uses) found, besides the two refusal fallbacks:
`src/domain/fleet/statGloss.ts` (long per-stat sentences — but `shipStatItems`/`SHIP_STATS` has **no caller** in
`src` today, so nothing prints them; left for the owner of that table), the buy-capacity caption words in
`src/live/useBuyCapacity.ts` (state keys a caller compares, translated at the screen through `ui.bound*` — those
dictionary words were shortened), and boot/auth errors in `worldStore.ts`/`authStore.ts` (developer-facing).

## The 30 most-seen labels, before → after

| Where | Before (EN) | After (EN) | Before (KO) | After (KO) |
|---|---|---|---|---|
| Trade tray, buy | You pay | Cost | 내는 돈 | 비용 |
| Trade tray, sell | You get | Sale | 받는 돈 | 판매 |
| Trade tray, sell | Bought at | Paid | 매입가 | 산 값 |
| Trade tray, sell | Sells at | Price | 매도가 | 가격 |
| Trade tray, sell | +12% on what it cost | +12% on cost | 매입가 대비 +12% | 산 값 대비 +12% |
| Trade tray | Add to basket | Add | 장바구니에 담기 | 담기 |
| Trade tray | Checking how much you can buy… | Checking max… | 살 수 있는 양을 확인하는 중… | 최대 확인 중… |
| Trade tray | 5.0 tons of cargo space · limited by your money | 5.0 tons of space · limit: money | 화물칸 5.0톤 · 제한: 보유 자금 | 화물칸 5.0톤 · 제한: 돈 |
| Trade tabs / columns | Buy / Sell | Buy / Sell | 매수 / 매도 | 사기 / 팔기 |
| Market row | low, so the price is high | low · price high | 적어서 비쌈 | 적음 · 비쌈 |
| Market row | Your company is #3 among this city's givers | #3 giver here | 내 상회는 이 도시 기부자 중 3위 | 이 도시 기부 3위 |
| Market card | Tax on your profit · your own country | Profit tax · own country | 이익에 대한 세금 · 내 모국 | 이익세 · 자국 |
| Best trade | No buyer you can reach from here. | No buyer in reach. | 여기서 닿는 곳에 사는 도시가 없습니다. | 갈 수 있는 사는 곳 없음. |
| Best trade | Net, the hold | Profit, full load | 화물칸 전체 순이익 | 이익, 가득 실을 때 |
| Plan builder | Units (blank: all that fit) | Units · blank = all | 수량 (비우면 실을 수 있는 만큼) | 수량 · 비우면 전부 |
| Plan builder | The most to pay a unit | Max price each | 개당 최고 지불가 | 개당 최고가 |
| Plan builder | Queue it once / Make it a route | Go once / Make route | 한 번 실행 / 항로로 만들기 | 한 번 가기 / 항로 만들기 |
| Plan builder | If pirates take the cargo, you carry the loss. | No cover for pirate losses. | 해적에게 화물을 빼앗기면 손실은 모두 내 몫입니다. | 해적 손실 보상 없음. |
| Plan, reach | too far to sail in one go: your navigator can only plan 14.2 days at sea without a stop. A captain with Navigation 3 could take you there | too far in one go: longest leg 14.2 days. Navigation 3 would reach it | 한 번에 가기에는 너무 멉니다: 항해사가 기항 없이 짤 수 있는 항해는 14.2일까지입니다. 항해술 3의 선장이라면 갈 수 있습니다 | 한 번에 가기엔 너무 멂: 최장 구간 14.2일. 항해술 3이면 갈 수 있음 |
| Plan, crew | Hire 2 more: below the minimum the fleet cannot sail. | Hire 2 more to sail. | 2명을 더 고용하세요: 최소 인원보다 적으면 선단이 출항할 수 없습니다. | 2명 더 고용해야 출항. |
| Plan, sea rules | Can you go there? | Sea rules | 갈 수 있나요? | 해역 조건 |
| Invest face | Your holdings | Shares | 내 지분 | 지분 |
| Profit face | Nothing earned or spent in the last 7 days. | No money in or out, 7 days. | 최근 7일 동안 수입도 지출도 없었습니다. | 7일간 수입·지출 없음. |
| Command, fleet state | waiting for orders | waiting | 명령 대기 | 대기 |
| Route lap line | … · Wages from profit 120 | … · Wages 120 | … · 급여(이익에서) 120 | … · 급여 120 |
| Map, send | She did not sail, and the server gave no reason — try once more. | Not sailed, no reason given. Try again. | 출항하지 않았고 서버가 이유를 알려 주지 않았습니다 — 한 번 더 시도하세요. | 출항 안 됨, 이유 없음. 다시 시도. |
| Map, send | Nothing to send — it is already at Lisbon. | Already at Lisbon. | 보낼 선단이 없습니다 — 이미 리스본에 있습니다. | 이미 리스본에 있음. |
| Stats | Your purse | Money | 내 자금 | 돈 |
| Refusals (every E_ code) | There is no such fleet. / You do not have enough ducats. | No such fleet. / Not enough money. | 그런 선단이 없습니다. / 두캇이 부족합니다. | 그런 선단 없음. / 돈 부족. |
| Start | Start your company · You start with one ship, Gaivota, and 8,000 ducats at … | Start · One ship, Gaivota, and 8,000 ducats at … | 상회 설립 · 바르카 가이보타 한 척과 두캇 8,000으로 …에서 시작합니다. 이름과 나라는 직접 고릅니다. | 시작 · 배 한 척 가이보타와 8,000두캇, …에서. |

## Specs updated to the new words

- `tests/planWords.spec.ts` — the three pinned `reachWords` sentences (`desk.tooFar/navigatorOnly/captainCould/noCaptain/longest/suppliesOnly`).
- `tests/trade.ceiling.spec.ts` — `/% on what it cost$/` → `/% on cost$/` (`ui.onCost`).
- `tests/desk.city.spec.ts` — `/Nothing earned or spent|Today/` → `/No money in or out|Today/` (`desk.nothingEarned`).
- `tests/countUp.spec.ts` — `moved between purses` → `moved` (`stats.noteMoved`).
- `tests/rpc.why.spec.ts` — the volume, stake, glut and tariff lines (`markets.traded/nobodyTraded/stakeShave/glut/tariff/ownCountry/rival`).

Five values the specs lean on were kept at their old words on purpose, after the first CI round showed them:
`port.opening` (`Opening the world.` — the boot screen the fixtures wait on), `map.chartLabel` (keeps the
`Chart of the world` prefix `map.sendfleet` selects by), `map.alreadyHeading`, `history.insured` and
`history.portInsurance` (the History sentence `insurance.spec` pins).

Every other text assertion in `tests/` (`getByText`, `toHaveText`, `toContainText`, role names) was read against the
new values before the push: the words they pin (`Buy`, `Sell`, `Here`, `Net`, `Sell at`, `Take it`, `Try again`,
`tries left`, `Put N units in storage`, `Keep N days`, `Hire 1`, `Dismiss 1`, `No change`, `Dock here to invest.`,
`Not taking gifts yet.`, `Hire one at an inn`, `checking the route`, `Under way`, `Everything on board`, `All that
fit`, `Any price`, `Route ·`, `No route`, `Not open yet`, `units on board`, `in storage`) were kept on purpose.

## Checks

`npx tsc -b`, `npx eslint .`, `npm run build`, and locally `tests/words.spec.ts`, `tests/i18n.keys.spec.ts`,
`tests/planWords.spec.ts` (pure) plus the browser specs whose words changed (`trade.ceiling`, `desk.city`) — results
in the PR.
