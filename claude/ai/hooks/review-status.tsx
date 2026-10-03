// review-status — a band above the prompt while a codex-review or grunt-run lane runs in the background, and the last
// result for ten minutes after it ends. Reads the status files the plugin's scripts write under
// ${XDG_STATE_HOME:-~/.local/state}/ai-loop (active/<pid>.json while a lane runs, last.json when one ends); no process is
// started and nothing is sent anywhere.
import type { Register } from 'claude-code'

import type { LaneRow, LastRow } from '../types'

const POLL_MS = 4000
const STALE_S = 3 * 3600      // an active file older than this belongs to a lane that died without cleaning up
const SHOW_LAST_S = 10 * 60   // how long the last result stays on the band

const dur = (s: number): string => {
  if (s < 60) return `${s}s`
  if (s < 3600) return `${Math.floor(s / 60)}m${String(s % 60).padStart(2, '0')}s`
  return `${Math.floor(s / 3600)}h${String(Math.floor((s % 3600) / 60)).padStart(2, '0')}m`
}

export const register: Register = on => {
  let stateDir = ''

  on('session.start', async ($, e, next) => {
    const xdg = await $.env.get('XDG_STATE_HOME')
    const home = await $.env.get('HOME')
    stateDir = `${xdg || `${home ?? ''}/.local/state`}/ai-loop`

    const poll = async () => {
      const now = Math.floor((await $.clock.now()) / 1000)
      const rows: LaneRow[] = []
      try {
        const entries = await $.fs.list(`${stateDir}/active`)
        for (const entry of entries) {
          if (entry.kind !== 'file' || !entry.name.endsWith('.json')) continue
          try {
            const text = await $.fs.read(`${stateDir}/active/${entry.name}`)
            const j = JSON.parse(text) as Partial<LaneRow> & { started?: number }
            const started = Number(j.started ?? 0)
            if (!started || now - started > STALE_S) continue
            rows.push({
              tool: String(j.tool ?? ''),
              lane: String(j.lane ?? ''),
              detail: String(j.detail ?? ''),
              repo: String(j.repo ?? ''),
              started,
              elapsed: dur(Math.max(0, now - started)),
            })
          } catch {
            // a file mid-write or already gone: skip it this round
          }
        }
      } catch {
        // no active/ directory yet: nothing runs
      }
      rows.sort((a, b) => a.started - b.started)
      await $.state.set({ plugin: 'ai', key: 'lanes' }, rows)

      let recent: LastRow | null = null
      try {
        const j = JSON.parse(await $.fs.read(`${stateDir}/last.json`)) as Partial<LastRow> & { finished?: number }
        const finished = Number(j.finished ?? 0)
        if (finished && now - finished <= SHOW_LAST_S) {
          recent = {
            tool: String(j.tool ?? ''),
            lane: String(j.lane ?? ''),
            result: String(j.result ?? ''),
            detail: String(j.detail ?? ''),
            repo: String(j.repo ?? ''),
            finished,
            ago: dur(Math.max(0, now - finished)),
          }
        }
      } catch {
        // no last.json yet
      }
      await $.state.set({ plugin: 'ai', key: 'last' }, recent)
    }

    void poll()
    $.clock.every(POLL_MS, () => {
      void poll()
    })

    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const heldLanes = await $.state.get({ plugin: 'ai', key: 'lanes' })
    const heldLast = await $.state.get({ plugin: 'ai', key: 'last' })
    const running: LaneRow[] = heldLanes?.value ?? []
    const recent: LastRow | null = heldLast?.value ?? null
    if (e.props.hasSurvey || (running.length === 0 && recent === null)) {
      return next(e)
    }

    const { Box, Text } = $.ui.resolve(e)

    const isBad = recent !== null && (recent.result.includes('BLOCK') || recent.result.startsWith('no '))

    return (
      <Box flexDirection="column">
        {running.map(row => (
          <Box key={`${row.tool}-${row.started}`}>
            <Text color="yellow">{'⟳ '}</Text>
            <Text bold>{row.tool}</Text>
            <Text dimColor>
              {` · ${row.lane}${row.detail ? ` (${row.detail})` : ''} · ${row.elapsed}${row.repo ? ` · ${row.repo}` : ''}`}
            </Text>
          </Box>
        ))}
        {running.length === 0 && recent !== null && (
          <Box key="last">
            <Text color={isBad ? 'red' : 'green'}>{isBad ? '✗ ' : '✓ '}</Text>
            <Text bold>{recent.tool}</Text>
            <Text dimColor>{` · ${recent.lane} · ${recent.result} · ${recent.ago} ago${recent.repo ? ` · ${recent.repo}` : ''}`}</Text>
          </Box>
        )}
      </Box>
    )
  })
}
