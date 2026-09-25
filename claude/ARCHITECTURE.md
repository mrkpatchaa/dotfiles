# How the `ai` setup works

A map of `dotfiles/claude`: what launches what, who reviews what, and where each fallback goes. The diagrams are Mermaid, so GitHub and VS Code's Markdown preview render them. The README explains why things are the way they are; this file shows how they fit together. As of plugin 0.6.0 (25 September 2026).

1. [The pieces](#1-the-pieces)
2. [Models and effort per launch alias](#2-models-and-effort-per-launch-alias)
3. [`/ai:loop`, one feature end to end](#3-ailoop-one-feature-end-to-end)
4. [`codex-review`: who reviews, and the fallback chain](#4-codex-review-who-reviews-and-the-fallback-chain)
5. [The pre-commit hook](#5-the-pre-commit-hook)
6. [`grunt-run`: the cheap lane](#6-grunt-run-the-cheap-lane)
7. [`/ai:ship` and `/ai:test-audit`](#7-aiship-and-aitest-audit)
8. [Limits and state](#8-limits-and-state)

---

## 1. The pieces

```mermaid
flowchart LR
  subgraph shell["Your shell · aliases.zsh"]
    A1["cc-opus<br/>Opus 5.5 · 1M · high"]
    A2["cc-fable<br/>Fable · high"]
    A3["cc-sonnet<br/>Sonnet · high + Opus advisor"]
    A4["cc-sonnet-solo<br/>Sonnet · high"]
  end

  subgraph cc["Claude Code session · Max 5x"]
    MAIN["Main agent<br/>plans, decides, talks to you"]
    subgraph plugin["ai plugin · dotfiles/claude/ai"]
      SK["Skills<br/>/ai:loop · /ai:ship · /ai:test-audit"]
      AG["Agents<br/>implementer · grunt · reviewer"]
      BIN["bin/<br/>codex-review · grunt-run · jev-triage · ai-limits"]
    end
  end

  subgraph repo["Each repo"]
    AGM["AGENTS.md<br/>managed ai-loop block + gotchas"]
    HOOK[".claude/settings.json<br/>PreToolUse hook on git commit"]
  end

  subgraph ext["Outside Claude"]
    CX["Codex CLI<br/>ChatGPT Plus · GPT-6 Sol / Luna"]
    OC["OpenCode<br/>Go models (GRUNT_MODELS, REVIEW_FALLBACK_MODELS)<br/>+ Zen free models (OPENCODE_FREE_MODELS)"]
    JEV["TypeSafe Jev<br/>optional commit triage"]
  end

  STATE[("~/.local/state/ai-loop<br/>limit marks · reviews.log · jev-triage.log")]

  A1 & A2 & A3 & A4 --> MAIN
  MAIN --> SK
  SK --> AG
  SK --> BIN
  AG --> BIN
  BIN -->|reviews| CX
  BIN -->|reviews + rote work| OC
  BIN -->|triage| JEV
  HOOK --> BIN
  MAIN -. reads .-> AGM
  CX & OC -. read .-> AGM
  BIN <--> STATE
```

Everything outside Claude is reached through the scripts in `bin/`, never directly by an agent. That is what makes limits, time-outs and fallbacks work the same way from a skill, an agent or the commit hook.

---

## 2. Models and effort per launch alias

| Alias | Main session | Subagents | Effort at launch | Use it for |
|---|---|---|---|---|
| `cc-opus` | Opus 5.5, 1M context | per agent file (default Opus) | high | the daily driver |
| `cc-fable` | Fable | per agent file (default Opus 5.5) | high | what Opus at xhigh got wrong |
| `cc-sonnet` | Sonnet + Opus advisor | Sonnet (forced) | high | short sessions, cheaper |
| `cc-sonnet-solo` | Sonnet | Sonnet (forced) | high | comparing `/usage` |

`--effort` applies to that session only and wins over a level saved with `/effort`; `/effort` still changes it mid-session.

| Agent | Model in its file | Effort | Runs where |
|---|---|---|---|
| `implementer` | opus (Sonnet under cc-sonnet, which forces) | medium (pinned) | its own git worktree |
| `reviewer` | opus (Sonnet under cc-sonnet, which forces) | high (pinned) | read-only |
| `grunt` | haiku | none (Haiku has no effort setting) | relays to `grunt-run` |

```mermaid
flowchart LR
  S["cc-opus · high"] -->|"high got it wrong"| X["/effort xhigh<br/>same session, cache kept"]
  X -->|"still wrong"| F["cc-fable"]
  S -.->|"long rote stretch"| M["/effort medium"] -.-> S
```

---

## 3. `/ai:loop`, one feature end to end

```mermaid
sequenceDiagram
  autonumber
  actor You
  participant Main as Main agent
  participant Grunt as grunt → grunt-run
  participant Rev as codex-review
  participant Impl as implementer (Opus medium, worktree)
  participant Claude as reviewer agent (Opus)

  You->>Main: /ai:loop <feature>
  opt research first
    Main->>Grunt: self-contained brief (survey, read logs)
    Grunt-->>Main: summary · WORKER: <model>
  end
  Main->>Main: Stage 1: write SPEC-<slug>.md with "Done means"
  Main->>Rev: Stage 2: codex-review spec SPEC-<slug>.md (background)
  alt a reviewer answered
    Rev-->>Main: VERDICT + findings · REVIEWER: <who>
  else exit 75, nobody reachable
    Main->>Claude: same review
    Claude-->>Main: VERDICT (flagged same-vendor)
  end
  Main->>You: revised spec + verdict (+ proposed "Patterns we do not use" line)
  You->>Main: yes
  Main->>Impl: Stage 3: build from the spec
  Impl->>Grunt: mechanical chunks (grunt-run)
  Grunt-->>Impl: done · WORKER: <model> (75: do it yourself)
  Impl-->>Main: changed files, test commands with exit codes
  Main->>Rev: Stage 4: codex-review diff <base> [focus]
  Rev-->>Main: VERDICT (or exit 75 → reviewer agent)
  loop Stage 5: at most two fix rounds
    Main->>Impl: findings as the brief
    Impl-->>Main: fixes
    Main->>Rev: re-run Stage 4
  end
  Main->>You: report: files, both verdicts and who gave them, cheap-lane models, gotcha proposals
```

The loop stops for you twice: after the spec review (step "yes") and on a second BLOCK in Stage 5. It never merges.

---

## 4. `codex-review`: who reviews, and the fallback chain

```mermaid
flowchart TD
  START(["codex-review spec|diff [base] [focus]"]) --> TIER["Pick the Codex tier<br/>focus → MODEL_RISKY / EFFORT_RISKY<br/>else CODEX_REVIEW_MODEL / EFFORT"]
  TIER --> MARK{"Codex limit<br/>mark stored?"}
  MARK -->|"yes, older than 30 min"| PROBE["Probe: one-word Luna turn"]
  PROBE -->|answered| CLEAR["Remove the mark"] --> WEEK
  PROBE -->|"refused"| SKIPC["Skip Codex<br/>(mark renewed with reset time)"]
  MARK -->|"yes, recent"| SKIPC
  MARK -->|no| PRE{"Pre-flight: Codex usage file<br/>shows a window at 100 %?"}
  PRE -->|yes| SKIPC
  PRE -->|no| WEEK{"7-day window<br/>≥ 80 %?"}
  WEEK -->|yes| DOWN["Downgrade: gpt-6-luna at max<br/>(high when budget < 900 s)"] --> RUNC
  WEEK -->|no| RUNC["Run Codex<br/>codex exec --json, read-only sandbox"]
  RUNC -->|verdict| OK(["Exit 0 · REVIEWER: codex (model)"])
  RUNC -->|"limit / stall / time-out"| MARKC["Mark Codex limited"] --> OCLOOP
  SKIPC --> OCLOOP

  subgraph OCLOOP["OpenCode, one model after another"]
    direction TB
    FR["free models first<br/>OPENCODE_FREE_MODELS<br/>(unless REVIEW_FREE=0 or repo opted out)"] -->|"limit / error / stall"| O1["REVIEW_FALLBACK_MODELS<br/>model 1 → 2 → 3"]
  end
  OCLOOP -->|"a model answered"| OK2(["Exit 0 · REVIEWER: opencode-go/…"])
  OCLOOP -->|"all failed or budget spent"| E75(["Exit 75 · REVIEWER: none<br/>+ 'codex back Mon 01:11' line"])

  E75 --> WHO{"Who called?"}
  WHO -->|"/ai:loop or /ai:ship"| CL["reviewer agent (Claude Opus)<br/>flagged same-vendor"]
  WHO -->|"commit hook"| LET["Commit allowed<br/>without review, warning printed"]
```

Every attempt, including the skipped ones, is a line in `reviews.log`: date, repo, mode, lane, model, verdict, outcome, seconds. Two Go models at their limit in one run mark the whole `opencode-go` provider, so the next call skips all of them. The whole call ends within `REVIEW_BUDGET` (1500 s; 540 s from the hook).

---

## 5. The pre-commit hook

```mermaid
flowchart TD
  C(["Claude runs git commit"]) --> SKIP{"AI_LOOP_SKIP_REVIEW=1<br/>in the command?"}
  SKIP -->|yes| PASS(["Commit goes through<br/>(a review just ran)"])
  SKIP -->|no| JT{"git config ai-loop.jevtriage"}
  JT -->|off| REV
  JT -->|shadow| JS["jev-triage logs its verdict<br/>changes nothing"] --> REV
  JT -->|on| JON{"Jev verdict"}
  JON -->|SKIP| PASS2(["Commit goes through<br/>(judged trivial)"])
  JON -->|"REVIEW / ADVERSARIAL + focus"| REV
  REV["codex-review diff<br/>Luna high · budget 540 s"] --> V{"Result"}
  V -->|"VERDICT: BLOCK"| BLOCK(["Commit blocked<br/>findings shown to Claude"])
  V -->|"SHIP / NEEDS WORK"| PASS3(["Commit goes through<br/>verdict shown"])
  V -->|"exit 75 or error"| PASS4(["Commit goes through<br/>'no reviewer reachable' warning"])
```

The hook never falls back to Claude, so a commit never waits on a Claude review. It lives in each repo's `.claude/settings.json` and only fires on commits made through Claude Code.

---

## 6. `grunt-run`: the cheap lane

```mermaid
flowchart LR
  B(["Brief from grunt or implementer"]) --> L0["Free models<br/>OPENCODE_FREE_MODELS<br/>(repo not opted out)"]
  L0 -->|"limit / error / stall"| L1["GRUNT_MODELS 1<br/>default deepseek-v4.1-flash"]
  L1 -->|"limit / stall / time-out"| L2["GRUNT_MODELS 2<br/>default glm-5.3-flash"]
  L2 -->|"limit / stall / time-out"| L3["GRUNT_MODELS 3<br/>default qwen3.8-flash"]
  L0 -->|done| WF(["Exit 0 · WORKER: model (free)"])
  L1 & L2 & L3 -->|done| W(["Exit 0 · WORKER: model<br/>caller re-runs the tests"])
  L3 -->|"all limited"| X(["Exit 75<br/>the implementer does the chunk itself"])
```

Override the order with `GRUNT_MODELS`; any OpenCode model id works. A free model that errors is skipped for 15 minutes (free periods end without notice). Each model gets `GRUNT_TIMEOUT` (2400 s) and `GRUNT_STALL_TIMEOUT` (600 s of silence). Secrets, env files, auth, payments, migrations and deploy config never go to this lane.

```mermaid
flowchart TD
  Q{"grunt-run --free-status<br/>exits 0?"} -->|"no: the lane uses paid quota"| R["Delegate the rote parts<br/>renames, boilerplate, scaffolds, surveys"]
  Q -->|"yes: a free model is on"| W["Delegate more<br/>first drafts of well-specified code,<br/>tests under the Tests rule, docs, long surveys"]
  R & W --> G["Main model / implementer reads the result<br/>and runs the gates"]
```

When a free model is on, the implementer, `/ai:loop`, the `grunt` agent and each repo's AGENTS.md shift work from Claude to that free model. That is where the Claude token savings come from. Most free models may train on what they are sent, so opt a repo out with `git config ai-loop.freelane off`.

---

## 7. `/ai:ship` and `/ai:test-audit`

```mermaid
flowchart LR
  subgraph ship["/ai:ship"]
    direction TB
    S1["codex-review diff base<br/>(75 → reviewer agent)"] --> S2["Fix BLOCK + agreed NEEDS WORK"]
    S2 --> S3["Review once more · run tests and build"]
    S3 --> S4["AI_LOOP_SKIP_REVIEW=1 git commit<br/>message ends with the verdict"]
  end
  subgraph audit["/ai:test-audit path"]
    direction TB
    T1["grunt: inventory<br/>test files, lines, dates"] --> T2["Main: candidates with evidence<br/>one folder"]
    T2 --> T3{"Your yes?"}
    T3 -->|yes| T4["Delete that batch · tests + type check<br/>report test vs production lines"]
    T3 -->|no| T5["Stop"]
  end
```

Neither pushes or merges.

---

## 8. Limits and state

```mermaid
flowchart LR
  subgraph lane["Any lane run (run_lane in _common.sh)"]
    W["stderr read every 2 s"] --> H{"hard-limit wording?"}
    H -->|yes| K["kill the process tree<br/>parse the reset time"]
    W --> S{"silent too long / over time?"}
    S -->|yes| K2["kill · skip 15 min"]
  end
  K --> F[("&lt;lane&gt;.limited<br/>until · how · the lane's sentence")]
  K2 --> F
  F --> AL["ai-limits<br/>'codex back Mon 01:11 (in 2d)'"]
  F --> NEXT["next codex-review / grunt-run<br/>skips the lane until then"]
  AL --> CLR["ai-limits clear [lane]<br/>after a reset or buying credits"]
```

Files in `~/.local/state/ai-loop/`: `<lane>.limited`, `<lane>.stderr` (the last error in full), `codex.probed`, `cleared`, `reviews.log`, `jev-triage.log`. `ai-limits log` shows the last review calls; `ai-limits triage` compares Jev with the reviews.
