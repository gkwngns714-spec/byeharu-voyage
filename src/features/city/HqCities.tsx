import { useSearchParams } from 'react-router-dom'
import { Button, DetailPage, Icon, KEEP_WORDS_CLASS, Row } from '../../components/ui'
import { PortFlag } from '../../live/PortFlag'
import { useWorld } from '../../live/worldStore'
import { formatDucats, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { HqCard, SnapshotPort } from '../../lib/rpc'

// HQ'S CITY NAME IS THE SWITCH (0509; the owner's specification, 2026-11-25: "by clicking the city name, you can change cities that have
// your HQ. The whole HQ screen will change"). The list is the server's (`world.player().hq`); choosing one writes the address (`?port=`),
// the one thing that says which city HQ shows, so back returns. The list stands on a pop-up page: the press moves nothing behind it.
// A server before 0509 serves no list: the name is then only the name.

/** The name, in HQ's title. The list itself is drawn by the screen, outside the title: a pop-up page is no part of a heading. */
export function HqCityName({ port, onOpen }: { port: SnapshotPort; onOpen: () => void }) {
  const t = useT()
  const hq = useWorld((s) => s.player?.hq)
  const name = (
    <span className={KEEP_WORDS_CLASS} data-testid="city-name">
      {port.name}
    </span>
  )
  // one HQ and none to open (0512: what a step asks is the owner's to set; unset, the server serves none of its figures): the list would say only what the title does
  if (!hq || hq.list.length === 0 || (hq.list.length === 1 && hq.next?.total_level == null)) return name
  return (
    <button
      type="button"
      onClick={onOpen}
      aria-label={`${port.name}: ${t('hq.cities')}`}
      className="-my-2 flex min-h-11 min-w-11 items-center gap-1 text-left"
      data-testid="hq-city-switch"
    >
      {name}
      <Icon name="chevron" size={18} className="shrink-0 rotate-90 text-ink-muted" />
    </button>
  )
}

export function HqCitiesPage({ here, onClose }: { here: string; onClose: () => void }) {
  const t = useT()
  const list: HqCard['list'] = useWorld((s) => s.player?.hq?.list) ?? []
  const next = useWorld((s) => (s.player?.hq?.next?.total_level == null ? null : s.player.hq.next))
  const [params, setParams] = useSearchParams()
  const portByCode = useWorld((s) => s.portByCode)
  const show = (code: string) => {
    const to = new URLSearchParams(params)
    to.set('port', code)
    onClose()
    setParams(to)
  }
  return (
    <DetailPage title={t('hq.cities')} onClose={onClose} data-testid="hq-cities-page">
      {list.map((h, i) => (
        <Row
          key={h.slot}
          label={
            <span className="flex items-center gap-2">
              <PortFlag code={h.port} />
              {portByCode[h.port]?.name ?? h.port}
            </span>
          }
          hairline={i < list.length - 1 || next !== null}
          tone={h.port === here ? 'accent' : 'default'}
          value={
            h.port === here ? (
              <span className="text-t-caption text-ink-muted">{t('hq.shown')}</span>
            ) : (
              <Button variant="secondary" onClick={() => show(h.port)} data-testid={`hq-city-${h.port}`}>
                {t('hq.show')}
              </Button>
            )
          }
        />
      ))}
      {next && (
        <Row label={t('hq.nextHq')} hairline={false} data-testid="hq-next">
          <span className="block text-t-caption text-ink-muted">{t('hq.nextHqAsks', { level: formatInt(next.total_level ?? 0), rep: formatInt(next.reputation ?? 0), coin: formatDucats(next.ducats ?? 0) })}</span>
        </Row>
      )}
    </DetailPage>
  )
}
