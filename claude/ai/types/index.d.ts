export type LaneRow = { tool: string; lane: string; detail: string; repo: string; started: number; elapsed: string }
export type LastRow = { tool: string; lane: string; result: string; detail: string; repo: string; finished: number; ago: string }

declare module 'claude-code' {
  interface PluginState {
    ai: { lanes: LaneRow[]; last: LastRow | null }
  }
}
