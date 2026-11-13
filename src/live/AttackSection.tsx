import { useEffect, useState } from 'react'
import { Button, Note, Row, SheetSection, Skeleton } from '../components/ui'
import { formatInt } from '../lib/format'
import { cmdAttack, cmdPreviewAttack } from '../lib/rpc'
import type { AttackReceipt, Refusal } from '../lib/rpc'
import { useT } from '../lib/i18n'
import { BattleCard } from './BattleCard'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ATTACK, on a cargo ship's card and a navy ship's (0327, 0333, docs/WORLD_POWERS.md §4.2)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The server judges everything here: `card.attack` is served only while attacks are lit, the dry run
// (`cmd.preview_attack`) says the words or the refusal, and `cmd.attack` judges the press. Nothing here decides
// who may attack whom. Your fleets are listed because the sheet must ask which one; a fleet that cannot go is told so by the server.

export function AttackSection({ card }: { card: { fleet: { id: string }; attack?: true } }) {
  if (!card.attack) return null
  return <Attack key={card.fleet.id} target={card.fleet.id} />
}

function Attack({ target }: { target: string }) {
  const t = useT()
  const fleets = useWorld((s) => s.fleets)
  const refresh = useWorld((s) => s.refresh)
  const [pick, setPick] = useState<string | null>(fleets[0]?.id ?? null)
  const [read, setRead] = useState<{ fleet: string; preview: AttackReceipt | null; refusal: Refusal | null } | null>(null)
  const [press, setPress] = useState<Refusal | null>(null)
  const [busy, setBusy] = useState(false)
  const [started, setStarted] = useState(false)

  useEffect(() => {
    if (!pick) return
    let live = true
    void cmdPreviewAttack(pick, target).then((r) => {
      if (live) setRead({ fleet: pick, preview: r.ok ? r.value : null, refusal: r.ok ? null : r.refusal })
    })
    return () => {
      live = false
    }
  }, [pick, target])

  if (fleets.length === 0) return null
  const now = read?.fleet === pick ? read : null

  const go = () => {
    if (busy || !pick) return
    setBusy(true)
    setPress(null)
    void (async () => {
      const r = await cmdAttack(pick, target, fleets.find((f) => f.id === pick)?.version ?? null)
      setBusy(false)
      if (r.ok) {
        setStarted(true)
        await refresh()
      } else {
        setPress(r.refusal)
      }
    })()
  }

  return (
    <SheetSection heading={t('map.attack')}>
      <div data-testid="cargo-attack" className="flex flex-col gap-2">
        {fleets.length > 1 && (
          <div className="flex flex-wrap gap-2">
            {fleets.map((f) => (
              <Button key={f.id} size="sm" variant={f.id === pick ? 'primary' : 'secondary'} onClick={() => setPick(f.id)} data-testid="cargo-attack-fleet">
                {f.name}
              </Button>
            ))}
          </div>
        )}
        {!now && <Skeleton className="h-10 w-full" />}
        {now?.preview && (
          <>
            {/* 0379: a fleet of an armada attacks with every fleet of hers that is there; the word below is read with all of them */}
            {now.preview.armada && (
              <Row
                label={t('fight.armada')}
                value={<span className="break-words text-right" data-testid="cargo-attack-armada-name">{now.preview.armada.name}</span>}
                data-testid="cargo-attack-armada"
                data-fleets={now.preview.armada.fleets.length}
              >
                <span className="break-words text-t-caption text-ink-muted">
                  <span data-testid="cargo-attack-armada-size">{t('fight.fleetsShips', { f: formatInt(now.preview.armada.fleets.length), s: formatInt(now.preview.armada.ships) })}</span>
                  {' · '}
                  <span data-testid="cargo-attack-armada-fleets">{now.preview.armada.fleets.join(' · ')}</span>
                </span>
              </Row>
            )}
            <Row label={t('map.attackFoe')} value={t(`map.attackWord_${now.preview.word}`)} data-testid="cargo-attack-word" />
            <Row label={t('map.funds')} value={t(`map.attackFunds_${now.preview.funds}`)} data-testid="cargo-attack-funds" />
            <Row label={t('map.attackRange')} value={t('map.attackMiles', { n: formatInt(now.preview.nm) })} hairline={now.preview.navy_minutes != null} />
            {now.preview.navy_minutes != null && (
              <Row label={t('map.attackNavy')} value={t('map.attackNavyIn', { n: formatInt(now.preview.navy_minutes) })} hairline={false} data-testid="cargo-attack-navy" />
            )}
            {!started && (
              <Button busy={busy} busyLabel={t('map.attack')} onClick={go} data-testid="cargo-attack-go">
                {t('map.attack')}
              </Button>
            )}
          </>
        )}
        {now?.refusal && (
          <Note tone="danger" code={now.refusal.code} figures={now.refusal.figures}>
            {now.refusal.sentence}
          </Note>
        )}
        {press && (
          <Note tone="danger" code={press.code} figures={press.figures}>
            {press.sentence}
          </Note>
        )}
        {started && <Note data-testid="cargo-attack-started">{t('map.attackStarted')}</Note>}
        {/* 0357: the battle she just opened, round by round: the log, the clock, Fight and Flee */}
        {started && pick && <BattleCard fleetId={pick} />}
      </div>
    </SheetSection>
  )
}
