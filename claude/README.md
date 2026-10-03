# claude/ — the `ai` plugin (skills, agents, fallback scripts) and shell aliases

Diagrams of how it all fits together (aliases, /ai:loop, the review fallback chain, the commit hook, the cheap lane, limits): [ARCHITECTURE.md](ARCHITECTURE.md).

Install once, in Claude Code:

    claude plugin marketplace add ~/devs/dotfiles/claude && claude plugin install ai@mrk

(or inside Claude Code: `/plugin marketplace add <dotfiles clone>/claude` then `/plugin install ai@mrk`)

The marketplace is a local directory, so the plugin loads in place: edit anything under `ai/` and run `/reload-plugins`.

## What's in it

| Piece | What it does |
| --- | --- |
| `/ai:loop` | Spec → independent spec review → build → verify → independent QA, with gates where you say yes. |
| `/ai:ship` | Wrap up a branch: independent review of the diff, fix what holds up, commit. |
| `/ai:preship [break\|all] [target]` | Pre-launch checks; `break` sends read-only breakers after the app. |
| `/ai:test-audit [path]` | Report-first pruning of low-value tests. |
| `implementer` | Builds from the spec. Opus, effort medium, own worktree. |
| `verifier` | Runs the feature and adds edge-case tests. Opus, effort high. |
| `reviewer` | Last-resort read-only review when Codex and OpenCode are both unavailable. Opus, effort high. |
| `breaker` | Tries to break the running app. Opus, effort high, no Write/Edit. |
| `grunt` | Mechanical work: through the cheap lane while it is on, itself on Sonnet (effort medium) when the lane is off or every cheap model is limited. |
| `ai/bin/grunt-run` | Runs a brief on the cheap OpenCode lane (free models first); exit 76 when the lane is off. |
| `ai/bin/ai-lane` | Shows and switches the cheap lane: `ai-lane off` (this clone), `ai-lane off --global`, `ai-lane on`, `ai-lane free off`. |
| `ai/hooks/review-status.tsx` | A mod: a band above the prompt while a `codex-review` or `grunt-run` lane runs in the background, and the last verdict for ten minutes after. |
| `ai/bin/codex-review` | Codex review with limit-aware fallbacks. |
| `ai/bin/jev-triage` | Optional commit triage through TypeSafe's Jev. |
| `ai/bin/ai-limits` | Which lanes are limited, until when, and the review log. |
| `ai/hook-scripts/review-before-commit.sh` | Reviews a `git commit` Claude Code is about to run. |

`ai/bin/` is on the Bash tool's PATH while the plugin is enabled, and on your shell PATH through `aliases.zsh`. Per-project pieces (hook + settings + the managed `AGENTS.md` block) live in each repo's `.claude/settings.json` and `AGENTS.md`. State: `~/.local/state/ai-loop/` (`ai-limits` shows it, `ai-limits clear` resets it).

## Aliases, models and effort

`.zshrc` sources `aliases.zsh`. Every alias caps subagents at 5 concurrent (the five `/ai:preship` checkers in one wave; the loop itself uses one at a time) and depth 1, and pins its launch effort with `--effort` (session only; beats a level saved with `/effort` + Enter; `/effort` still changes it mid-session).

| Alias | Main | Subagents |
| --- | --- | --- |
| `cc-opus` | `opus[1m]` (Opus 5.5, 1M context), high. The daily driver. | Each agent file decides (`CLAUDE_CODE_SUBAGENT_MODEL=opus` only covers agents that name no model). |
| `cc-fable` | Fable, high. For what Opus gets wrong. | Same as cc-opus. |
| `cc-sonnet` | Sonnet, high, with `--advisor opus`. | Forced to Sonnet. |
| `cc-sonnet-solo` | Sonnet, high, no advisor. | Forced to Sonnet. |

- **Climb effort before switching models:** cc-opus (high) → `/effort xhigh` when high got it wrong → only then cc-fable. `/effort medium` for rote stretches, `/effort ultracode` (xhigh + dynamic workflows) only on purpose. From Claude Code v2.1.280 a mid-session effort change keeps the prompt cache, so `/effort high` for the plan and medium for the build costs nothing.
- **Opus 5.5** starts at effort medium and ignores a top-level `effortLevel` in settings; use `--effort`, `/effort` or `modelSettings` per model.
- **Subagent effort comes only from an agent's `effort:` line.** There is no environment variable for subagents alone: `CLAUDE_CODE_EFFORT_LEVEL` overrides main and subagents together and locks `/effort`, so it stays unused. An agent without the line inherits the session's level; `/effort` in the main session doesn't reach a pinned agent. `/tasks` shows the level on a subagent's row.
- **No `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` on the Opus/Fable aliases.** With it on, Claude Code ignores every agent's `model:` line (that's how the implementer once ran on Sonnet under cc-opus). The Sonnet aliases keep it on purpose: a Sonnet main keeps a Sonnet build, never Haiku. Under an `opus[1m]` main, an `opus` subagent runs on the same 1M model.
- **The build runs at medium** (Opus 5.5's default); for a hard spec set `effort: high` in `implementer.md`. An Opus build spends the Max window faster than a Sonnet one: watch `/usage`.
- `aliases.zsh` sets `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` (one background request per turn that re-reads the context; delete the line if you use Tab to accept suggestions).

## The loop (`/ai:loop`)

- **Stage 1, plan.** Open questions come first, in one message, numbered, each with a recommended answer (reply "ok" or change one by number). It asks only what you alone can decide: facts are looked up in the code or through `grunt`. A second round happens only when answers open new questions, and it stops when nothing the build depends on is assumed. This is the `/grill-me` pattern (Matt Pocock); no need to install mattpocock/skills for the loop. For planning outside the loop, install only `grill-me` and `grilling` (`npx skills@latest add mattpocock/skills`, pick those two): the plugin's model-invoked `tdd`, `code-review` and `diagnosing-bugs` would compete with the loop's stages. Then `docs/specs/SPEC-<slug>.md` (never overwrite an existing spec).
- **Stage 2, challenge the spec** with `codex-review spec`. When you turn down an approach at a gate, or a reviewer finding is dropped because the codebase deliberately does otherwise, the loop proposes one line for `## Patterns we do not use` in the root `AGENTS.md` (the tempting choice, the alternative, the reason), added only on your yes.
- **Stage 3, build.** `implementer` hands precisely specified chunks to the cheap lane and writes the substantive logic itself. For a bug fix it runs the reproducer or writes the failing test before editing. It routes by trust as well as difficulty: chunks touching secrets, env files, auth, payments, migrations or deploy config never go to the cheap lane.
- **Stage 3b, verify.** `verifier` runs the feature, reproduces a fixed bug against the base branch, adds edge-case tests under the repo's `Tests:` rule (randomised comparison against a reference where one exists), never edits production code, and reports `VERIFY: PASS|FAIL`. It runs for input handling, money/state, concurrency/time, auth/data/migrations and bug fixes, and is skipped for UI, copy, config and plumbing. A FAIL goes back to the implementer for one round before the Codex diff review, which then sees the new tests. The idea comes from Thariq's effort study (claude.dev/blog/spending-your-effort): higher effort mostly buys verification and edge-case testing, not a better approach. Cost: one extra Opus-high subagent per qualifying loop; if `/usage` climbs, narrow Stage 3b to bug fixes and auth/data first.
- **Stage 4, QA** by `codex-review`, started in the background and left alone until it exits: no polling, since every check was a main-model turn. The 25-minute self-stop is unchanged; after 26 minutes with no report the skill reads the output once and kills a run still going. Calling `codex-review` again later is fine.
- **Report order:** what needs you first; files; verdicts, reviewers and the verify result; what was run versus only read and what couldn't be checked; cheap-lane chunks; one merge risk with the check that would settle it. The first output line of every helper (`WORKER:` / `REVIEWER:`) names who did the work, and the report carries those names.

## Codex reviews: tiers, weekly budget, stale limits

Tiers, set in `aliases.zsh` (update the Codex CLI so it knows the ids):

| Variable | Value | Used for |
| --- | --- | --- |
| `CODEX_REVIEW_MODEL` / `_EFFORT` | `gpt-6.1-sol` / medium | Spec reviews and loop/ship QA |
| `CODEX_REVIEW_MODEL_RISKY` / `_EFFORT_RISKY` | `gpt-6.1-sol` / xhigh | A focus marks the diff as risky (auth, payments, schema…) |
| `CODEX_REVIEW_MODEL_COMMIT` / `_EFFORT_COMMIT` | `gpt-6-luna` / high | The pre-commit hook only. Unset both to review commits on Sol. |
| `CODEX_REVIEW_MODEL_CHEAP` / `_EFFORT_CHEAP` | `gpt-6-luna` / max | The weekly-budget downgrade |

- **Weekly budget.** The binding Codex limit on Plus is the 7-day window. In the week of 21 September about 90 reviews, mostly Astra and Sol at medium, used all of it in three days. Rule of thumb from that week (tokens mostly cached): one Astra medium review ≈ 2.5 % of the week, one Sol medium ≈ 1.5 %, one Luna high ≈ 0 %. So before each Codex call `codex-review` reads Codex's last usage snapshot (free, from `~/.codex/sessions`). At `CODEX_WEEKLY_DOWNGRADE_AT` % or more (default 80; 0 turns it off), the review runs on the cheap tier and the `REVIEWER:` line says `downgraded: 7-day window at N%`. The cheap effort drops from max to high when `REVIEW_BUDGET` is under 900 s (the commit hook's 540 s). A snapshot whose window has reset since is ignored. Keep interactive Codex, and the Codex plugin inside Claude Code, on Sol or Luna: one Astra session used 12 % of a week.
- **Commit hook.** It keeps the `_COMMIT` model when jev-triage hands it a focus; the effort still rises to `CODEX_REVIEW_EFFORT_RISKY`. `CODEX_REVIEW_MODEL_COMMIT_RISKY` overrides that.
- **No approval prompts.** Reviews run read-only with `-c approval_policy="never"`, so there's nothing to approve and no `codex-auto-review` guardian sub-sessions. `codex exec` has no `-a`/`--ask-for-approval` flag, whatever the CLI reference says; the source (`codex-rs/exec/src/cli.rs`) doesn't have it.
- **Stale limits.** A stored skip is only as good as its date: limits get reset and credits get bought. Once a Codex mark, or a snapshot that would downgrade the review, is older than `CODEX_RECHECK_EVERY` (1800 s), `codex-review` first sends one word ("Reply with exactly: OK") on the cheap tier at low effort, with no tools, capped at `CODEX_PROBE_TIMEOUT` (90 s). A refusal costs nothing and re-dates the mark from Codex's own message. An answer removes the mark, voids older snapshots (`cleared`) and leaves a fresh one, so the pre-flight and the weekly rule work from the real figure. It's logged as lane `codex-probe` (`answered`, `limit` or `unknown`), and `ai-limits` says when the next one is due. `ai-limits clear codex` skips the wait; `CODEX_RECHECK=0` turns the probe off.
- **Review log.** Every call appends one tab-separated line per lane attempt to `~/.local/state/ai-loop/reviews.log`: date, repo, mode, lane, model, verdict, outcome (`ok`, `skipped`, `limit`, `stalled`, `error`, `none`), seconds, and a note. The note holds the weekly % before → after, the reset time and the lane's own words, or the error line. `ai-limits log [N]` prints the last N (12), and `ai-limits` says when the week is past the threshold. A failed lane keeps its full stderr in `~/.local/state/ai-loop/<lane>.stderr`.

## Limits and fallbacks

- **Review chain.** Codex → free OpenCode models → the paid Go models in `REVIEW_FALLBACK_MODELS` → exit 75, which tells `/ai:loop` and `/ai:ship` to use the Claude `reviewer` agent. On 75 the commit hook runs the `reviewer` agent's instructions headless (`claude -p`, Opus at high, read-only tools, flagged same-vendor) when at least two minutes of the hook's 600 s are left; it lets the commit through unreviewed only when that fails too or `AI_HOOK_CLAUDE_FALLBACK=0`. Only an explicit `VERDICT: BLOCK` stops a commit. `AI_HOOK_CLAUDE_MODEL` / `_EFFORT` change the fallback's model.
- **Watchdog.** `opencode run` retries a limited provider forever and prints nothing while it does (anomalyco/opencode #40330, #21960), so every lane runs under `run_lane` (`ai/bin/_common.sh`):
  - stderr is read every 2 s, and the lane is killed the moment it reports a hard limit;
  - a silent lane is killed after `AI_STALL_TIMEOUT` (300 s; Codex 600 s; `grunt-run` 600 s);
  - any lane is killed after `AI_LANE_TIMEOUT` (1200 s; `grunt-run` 2400 s);
  - `codex-review` as a whole ends within `REVIEW_BUDGET` (1500 s; 540 s from the commit hook, under Claude Code's 600 s hook timeout);
  - a heartbeat line goes to stderr every minute.

  OpenCode runs with `--print-logs` so the provider's error reaches stderr. Codex runs with `--json -o` so errors are separate events and a diff that quotes "usage limit" can't trip the detector; if the installed codex refuses the flags it falls back to plain output (`CODEX_REVIEW_JSON=0` forces that).
- **Reset times.** The lane's own words are parsed (`_limits.py reset`): Codex's "try again at Sep 22nd, 2026 9:51 AM" or "in 2 hours 5 minutes", OpenCode Go's "Resets in 2h 13m", `resets_at`, `retry-after`. The lane is skipped until that time. The fixed 30 minutes remains only for a limit that names no time. A lane killed for silence or time is skipped for 15 minutes. Two Go models at their limit in one run mark the whole `opencode-go` provider (anomalyco/opencode #49014).
- **Codex pre-flight.** A usage window at 100 % with a reset in the future skips Codex without sending a request (`CODEX_PREFLIGHT=0` disables).
- **`ai-limits`** lists every lane with "back Tue 09:51 (in 14h)", how that's known, and the lane's own sentence, plus Codex's two windows with their percentages. Run `ai-limits clear [lane]` after buying credits; it also makes the pre-flight ignore older snapshots. OpenCode Go has no usage API (anomalyco/opencode #31084), so its reset time is only known after a refusal.
- **Testing.** Everything was tested against mock `codex` and `opencode` binaries in a Linux sandbox (bash 5), not on macOS bash 3.2 and not against the live services. If `ai-limits` shows "guessed" next to a lane after a real limit, its message wasn't parsed: extend `_limits.py` with the "said:" line.

## The cheap lane and free models

- **Switching it off.** `ai-lane off` in a clone (`git config ai-loop.cheaplane off`), `ai-lane off --global` for every clone, or `export AI_CHEAP_LANE=off` for one shell; `ai-lane` shows what applies and `ai-lane on` reverts. Off means: `grunt-run` exits 76 at once, `codex-review` goes Codex → exit 75 with no OpenCode fallback, and the Claude agents do the work themselves (`grunt` on Sonnet at effort medium, the `implementer` on Opus for the chunks it would have sent out). Nothing to reload: the scripts read the switch at every call. Use it when a repo must not leave the Anthropic/OpenAI vendors, when OpenCode is flaky, or when you would rather spend Max quota than wait.
- **The band.** While a lane runs in the background, the plugin's `review-status` mod draws one line above the prompt per lane (`⟳ codex-review · codex (spec) · 4m12s · snowlan`), and the last result for ten minutes after (`✓ codex-review · gpt-6.1-sol · VERDICT: SHIP · 2m ago`). It reads `~/.local/state/ai-loop/active/*.json` and `last.json`, which `run_lane` and the scripts write; nothing else. Claude Code 2.1.287 or later; `/reload-plugins` after updating.
- **Order.** `grunt-run` tries `OPENCODE_FREE_MODELS` first, then `GRUNT_MODELS`, and its first line says which one worked (`WORKER: <model> (free)`). It appends a closing quality-pass instruction for the build agent (`GRUNT_QA_PASS=0` turns it off). Keep that kind of line out of prompts for frontier models.
- **Free models.** OpenCode Zen regularly runs models for free: ids end in `-free`, listed at opencode.ai/docs/zen or under `/models` in the OpenCode TUI. Put the ones you want in `OPENCODE_FREE_MODELS` (commented example in `aliases.zsh`, next to a note on NVIDIA's free endpoints, which are for dev and eval only).
  - `codex-review` asks them after Codex and before the paid Go fallbacks, and the `REVIEWER:` line says `free`. `REVIEW_FREE=0` keeps them out of reviews.
  - A free model that errors (free period over, id retired) is skipped for 15 minutes, then retried; `ai-limits` shows it.
- **Wider delegation.** `grunt-run --free-status` exits 0 while a free model is usable in this repo. The `implementer`, the `grunt` description, `/ai:loop` and each repo's `Lanes` line use that as the signal to delegate more than rote work: first drafts of well-specified code, tests, docs, long surveys. The main model still reviews and runs the gates, and the trust rule above still applies.
- **Data.** Most free models may use what they're sent for training (Space Bunny Free says zero retention; the NVIDIA trials say no confidential data). Opt a repo out with `git config ai-loop.freelane off`.

## Jev triage (optional)

- **What it does.** `ai/bin/jev-triage` reads a diff and prints SKIP / REVIEW / ADVERSARIAL from five yes/no questions to TypeSafe's Jev, plus local path and credential checks. It fails open to REVIEW, drops lockfiles, env files and generated types, and redacts anything credential-shaped before sending.
- **Modes.** The commit hook uses it per clone:
  - `git config ai-loop.jevtriage shadow` logs its verdict next to the real review and changes nothing.
  - `on` lets SKIP skip the review and hands ADVERSARIAL's focus to the reviewer.
  - It's off by default, because the diff goes to a third party.
- **Setup.** Key: `~/.config/typesafe/api-key` (chmod 600) or `$TYPESAFE_API_KEY`. Log: `~/.local/state/ai-loop/jev-triage.log`.
- **Two calls for a SKIP.** Jev's scores move between identical calls, so a SKIP must hold on two independent calls (`JEV_CONFIRM=0` turns that off); a disagreement or a failed second call means REVIEW. Risk scores within 0.10 of the threshold are logged as `near`.
- **Deciding.** `ai-limits triage` counts those coin flips and ends with a decision: stay in shadow, keep going, or ready (14 days and 30 compared reviews with no bad SKIP). Commit reviews moved to Luna on 22 September 2026, so compare shadow rows from before and after that date separately.
- **Testing.** The Jev call was tested against a mock of the documented API, not the live service.

## Instruction files

- **One `AGENTS.md` per repo**, read by Claude Code through a one-line `CLAUDE.md` (`@AGENTS.md`), and by Codex and OpenCode directly. The `BEGIN:ai-loop` block is managed here for all repos. It holds the working rules, the `Lanes` line, the `Tests:` authoring gate, the long-runs rule and four session habits from `claude-doctor` (read before editing and stop after a third patch to the same spot; restate a correction in one line, then act; change approach after two failures; check the original request before reporting). Repos without the block carry the same four lines as a `## Session habits` section.
- **No model names in `AGENTS.md`.** The Lanes line names agents ("the `implementer` agent builds → the `verifier` agent checks risky changes"), so a model change touches only the agent files and aliases.
- **Gotchas files.** Folders where mistakes recur carry a nested `AGENTS.md` of facts (what broke, the check that catches it, the command that proves it), plus a one-line `CLAUDE.md` containing `@AGENTS.md`.
  - Codex reads the nested `AGENTS.md` directly. Claude Code reads it too when it opens a file in that folder, as long as the folder has no `CLAUDE.md` of its own (code.claude.com/docs/en/memory, since 2.1.277); the one-line `CLAUDE.md` shims from before are harmless and can stay.
  - `/ai:loop` reads them while planning. With `/ai:ship`, it proposes a new line when a review finds a repeatable mistake.

## Pre-ship checks (`/ai:preship`)

```sh
/ai:preship web            # 5 read-only checkers (default)
/ai:preship break          # 4 breakers only
/ai:preship all web        # 5 checkers + 4 breakers on the web app
```

Adapted from @Voxyz_ai's 20-point pre-launch list (26 Sept 2026) and 16 break questions (27 Sept 2026).

- **Checkers (groups 1–5).**
  - Design, checked against `docs/STYLE-GUIDE.md` / `DESIGN.md` (it proposes one if there's none).
  - Mobile: 375 and 768 px, 44 px taps, 200 % text.
  - Every state.
  - Real-user flows.
  - Launch basics.

  They use the installed `agent-browser` and impeccable skills. The result is one table by severity; after your yes, one writer fixes and takes before/after screenshots.
- **Breakers (groups 6–9).** Four `breaker` agents try to break:
  - Security: keys in the bundle or history, direct API calls past RLS, a tampered price or role, rate limits, stored XSS.
  - Data: 10k rows, long emoji and diacritic names, email case duplicates, empty forms.
  - Flows under stress: double submit, webhook replay, Back mid-form, offline save, a 50 MB upload.
  - Environment: 200 % zoom (a real phone through a protected quick tunnel, `cloudflared tunnel --url … --allowed-mail …`), WebKit, other time zones.
- **Breaker rules.** Local or test environment only, two test accounts, payments in test mode, AI mocked or capped, test data removed afterwards; a breaker stops if it finds production keys.
  - Critical items, and fixes touching auth, money or data, go through `/ai:loop`, not the one-pass fixer.
  - All four run at high; raise `breaker.md` to `xhigh` before a payments launch.
  - "Read-only" is an instruction, not a sandbox (Bash can still write): check `git status` after a run.

## Tests (`/ai:test-audit [path]`)

Report-first pruning of low-value tests: tests that restate the code, copied fixtures, test-only seams, and duplicates of a stronger boundary test. Adapted from OpenClaw's test-audit skill (github.com/openclaw/openclaw, `.agents/skills/test-audit`); the optional consolidation stage follows Kent C. Dodds' Kody test surgery. It works one folder per batch, and deletes only on your yes. The `Tests:` line in the managed `AGENTS.md` block is the matching gate for new tests.

## Audits: three jobs, three tools

- **Setup health: `/doctor`** (Claude Code ≥ v2.1.206; alias `/checkup`). It covers install health, unused skills, MCP servers and plugins against their context cost, slow hooks, and a CLAUDE.md trim. Run it once per repo.
  - Decline any move that takes lines out of `AGENTS.md` into `.claude/skills` or `CLAUDE.md`: Codex and OpenCode read `AGENTS.md` only.
  - Expect it to flag `review-before-commit.sh` as slow. That's the Codex review; keep it.
  - "/doctor prompt-audit" is `/doctor` with a hint, not a subcommand.
- **Dated wording: `/claude-api prompt-audit`**, at each model release.
  - Install: `/plugin marketplace add anthropics/skills`, then `/plugin install claude-api@anthropic-agent-skills`.
  - Run it from `~/devs/dotfiles/claude/ai` (skills, agents and the prompts inside `bin/`), and once from a repo root for its `AGENTS.md` tree.
  - It prints findings (`file:line`, quoted evidence, pattern, confidence) and a proposed diff for the High and Medium ones. Apply the hunks by hand.
  - Keep, if flagged:
    - the waiting rule in `loop` and `ship` (its minutes are the scripts' own timeouts);
    - the `VERDICT:` pins (the hook and the skills parse them; the verdict comes right after the `REVIEWER:` line);
    - `never` lines that state their reason.
- **Evidence from transcripts: backpass** (github.com/kunchenguid/backpass, MIT). It proposes `AGENTS.md` edits from your own Claude Code, Codex and OpenCode transcripts, each backed by quotes from two or more sessions, and writes nothing until `backpass apply`.
  - It needs Node ≥ 22.5 and `acpx`, and spends Codex quota, so run it after the weekly review peak.
  - Reject edits inside the managed block (change those here) and EXTRACT→SKILL moves.
  - `.backpass/` is excluded via `.git/info/exclude`.

  ```sh
  npm i -g backpass            # plus acpx, see the backpass README
  cd ~/devs/assigame-next && backpass init
  backpass --since 30d --max-transcripts 60 --max-edits 5
  backpass apply               # accept/reject in the browser
  ```

## Changelog

- **0.12.2** (3 Oct 2026): from the first backpass runs (37 sessions each in assigame-next and snowlan) and the review log: Stage 2 of `/ai:loop` ends the turn before the build; the managed block says a gate counts only once it was seen finishing and a truncated read is not the whole file; a model the account doesn't have is skipped for a day instead of on every call; an OpenCode model without a `high` variant is retried without one; the review log keeps each review's first finding.
- **0.12.1** (3 Oct 2026): the hook's executable bit, lost on 1 Oct when the file was rewritten through the Cowork mount, is restored; each repo's `.claude/settings.json` now calls it as `bash <path>` so a lost bit can't silence it again (`/doctor` showed "Permission denied" on every commit for two days).
- **0.12.0** (3 Oct 2026): `ai-lane` and `AI_CHEAP_LANE` switch the cheap lane off (grunt-run exit 76, no OpenCode review fallback); `grunt` moves to Sonnet and does the work itself when the lane is off; the `review-status` mod (a band above the prompt for background lanes); the commit hook reviews `git diff HEAD` instead of the whole branch; subagent cap 5.
- **0.11.4** (3 Oct 2026): `/ai:preship` group 9 names the protected quick tunnel for testing the local app from a real phone.
- **0.11.3** (1 Oct 2026): prompt audit — attributions moved from `/ai:preship` and `/ai:test-audit` into this README; `codex-review spec` needs the spec path (the old `SPEC.md` default predates `docs/specs/`).
- **0.11.2** (1 Oct 2026): the commit hook falls back to a headless Claude review when Codex and OpenCode are unreachable.
- **0.11.1** (1 Oct 2026): `/ai:test-audit` Stage 4, consolidation with coverage measured before and after; Codex reviews on GPT-6.1 Sol; `--advisor fable` suggested for long cc-opus runs.
- **0.11.0** (1 Oct 2026): docs layout: specs in `docs/specs/`, plans and run notes in `docs/tasks/`, shipped or dropped work in `docs/archive/`; `/ai:ship` archives what the branch finished and proposes the rest; session habits in the managed block.
- **0.10.0** (28 Sept 2026): `breaker` agent, `/ai:preship break` and `all`; Stage 1 questions numbered with recommended answers.
- **0.9.0** (27 Sept): `/ai:preship`; loop report order; AGENTS.md Lanes lines name agents, not models.
- **0.8.0** (26 Sept): `verifier` agent and Stage 3b; Stage 1 asks open questions first; implementer reproduces a bug before fixing it.
- **0.7.0** (26 Sept): builds on Opus at medium; FORCE dropped from cc-opus / cc-fable; the Sonnet aliases force Sonnet subagents (were Haiku).
- **0.6.0** (25 Sept): free OpenCode models first in `grunt-run` and the review chain; `--free-status`; per-repo opt-out; wider delegation while a free model answers.
- **0.5.3** (24 Sept): effort pinned per alias and per agent; `/ai:test-audit`; `Tests:` line; cheap Codex tier at max.
- **0.5.2** (24 Sept): stale-limit probe; `approval_policy` via `-c`; full stderr kept per lane.
- **0.5.1** (24 Sept): weekly-budget downgrade; no guardian sessions; `reviews.log` and `ai-limits log`.
- **0.5.0** (22–23 Sept): GPT-6 Sol/Luna review tiers; no polling of a running review; patterns section; route by trust; prompt suggestions off.
- **0.4.0** (21 Sept): lane watchdog, parsed reset times, Codex pre-flight.
- **0.3.0** (21 Sept): gotchas files; a Jev SKIP must hold twice; triage decision line.
- **0.2.0** (20 Sept): `jev-triage`; `cc-sonnet` with an Opus advisor; subagent caps.
