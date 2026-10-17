// review-status — a band above the prompt while a codex-review or grunt-run lane runs in the background, and the last
// result for ten minutes after it ends. Reads the status files the plugin's scripts write under
// ${XDG_STATE_HOME:-~/.local/state}/ai-loop (active/<pid>.json while a lane runs, last.json when one ends); no process is
// started and nothing is sent anywhere.
// 0.16.0: a context row from AI_CONTEXT_WARN tokens (300k; red from 5/3 of it), and the work rules below added to every session's
// system prompt (prompt.compose).
import type { Register } from 'claude-code'

import type { LaneRow, LastRow } from '../types'

const POLL_MS = 4000
const STALE_S = 3 * 3600      // an active file older than this belongs to a lane that died without cleaning up
const SHOW_LAST_S = 10 * 60   // how long the last result stays on the band

// 10–17 Oct 2026 transcripts: 817 sleep/poll calls (17.8 h), 2,238 test runs, 40 general-purpose subagents at the session's effort.
const WORK_RULES = [
  'Work rules from the ai plugin:',
  '- New tests: write one only for a bug reproducer or a check the spec\'s "Done means" names, e2e or integration first. No tests for refactors, UI layout, copy or config. Never add a test that repeats an existing one or a flow an e2e test covers.',
  '- Tests: while you work, run only the tests for the code you changed. Run the full suite once, before you report or commit. A run that reports zero tests, or stops before it loads the test files, is a failure.',
  '- Waiting: never poll with sleep loops or repeated status checks. Run a long command in the foreground with a timeout, or in the background and wait for its exit notice. Watch CI the same way (`gh run watch <id> --exit-status` in the background).',
  '- Delegation: routine read-only checks (device or simulator QA, screenshot and store-listing reviews, audits) go to the ai `checker` agent, builds to the `implementer`, not to `general-purpose`.',
].join('\n')

const dur = (s: number): string => {
  if (s < 60) return `${s}s`
  if (s < 3600) return `${Math.floor(s / 60)}m${String(s % 60).padStart(2, '0')}s`
  return `${Math.floor(s / 3600)}h${String(Math.floor((s % 3600) / 60)).padStart(2, '0')}m`
}

export const register: Register = on => {
  let stateDir = ''
  let warnAt = 300_000

  on('session.start', async ($, e, next) => {
    const xdg = await $.env.get('XDG_STATE_HOME')
    const home = await $.env.get('HOME')
    stateDir = `${xdg || `${home ?? ''}/.local/state`}/ai-loop`
    const w = Number(await $.env.get('AI_CONTEXT_WARN'))
    if (Number.isFinite(w) && w > 0) warnAt = w

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

      let ctx = 0
      try {
        ctx = (await $.session.usage()).context.tokens ?? 0
      } catch {
        // no reading yet
      }
      await $.state.set({ plugin: 'ai', key: 'ctx' }, ctx)
    }

    void poll()
    $.clock.every(POLL_MS, () => {
      void poll()
    })

    return next(e)
  })

  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)
    return { sections: [...r.sections, { id: 'ai:work-rules', text: WORK_RULES, scope: 'session' as const }] }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const heldLanes = await $.state.get({ plugin: 'ai', key: 'lanes' })
    const heldLast = await $.state.get({ plugin: 'ai', key: 'last' })
    const running: LaneRow[] = heldLanes?.value ?? []
    const recent: LastRow | null = heldLast?.value ?? null
    const ctx: number = (await $.state.get({ plugin: 'ai', key: 'ctx' }))?.value ?? 0
    const isBig = ctx >= warnAt
    if (e.props.hasSurvey || (running.length === 0 && recent === null && !isBig)) {
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
        {isBig && (
          <Box key="ctx">
            <Text color={ctx >= (warnAt * 5) / 3 ? 'red' : 'yellow'}>{'⚠ '}</Text>
            <Text bold>{`context ${Math.round(ctx / 1000)}k`}</Text>
            <Text dimColor>{' · every call re-reads it · finish this step, run /ai:handoff, start a new session'}</Text>
          </Box>
        )}
      </Box>
    )
  })
}
