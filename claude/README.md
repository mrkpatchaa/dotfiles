# claude/ — the `ai` plugin (skills, agents, fallback scripts) and shell aliases

Install once, in Claude Code:

    claude plugin marketplace add ~/devs/dotfiles/claude && claude plugin install ai@mrk

(or inside Claude Code: `/plugin marketplace add <dotfiles clone>/claude` then `/plugin install ai@mrk`)

The marketplace is a local directory, so the plugin loads in place: edit anything under `ai/` and run `/reload-plugins`.
Skills are namespaced: `/ai:loop`, `/ai:ship`. Agents: `implementer`, `grunt`, `reviewer`. `ai/bin/` is on the Bash tool's PATH while the plugin is enabled.

Shell: `.zshrc` sources `aliases.zsh` (cc-fable / cc-opus / cc-sonnet, and `ai/bin` on your PATH). Since 0.2.0: `cc-sonnet` runs with an Opus advisor (`cc-sonnet-solo` is the old one), every alias caps subagents at 2 concurrent / depth 1, and `CODEX_REVIEW_MODEL[_RISKY]` pick the Codex tier per review.

Per-project pieces (hook + settings + AGENTS.md block) live in each repo's `.claude/settings.json` and `AGENTS.md`.
State for limit tracking: `~/.local/state/ai-loop/` (`ai-limits` shows it, `ai-limits clear` resets it).

## Limits: fast detection and reset times (0.4.0)

Why: `opencode run` retries a limited provider forever and prints nothing while it does (anomalyco/opencode #40330, #21960), and the scripts used to look for a limit only after the CLI had exited. One exhausted Go window therefore meant an open-ended wait.
Now every lane runs under a watchdog (`run_lane` in `ai/bin/_common.sh`): stderr is read every 2 s while the CLI runs and the lane is killed the moment it reports a hard limit; a lane with no output at all is killed after `AI_STALL_TIMEOUT` (300 s; Codex 600 s; `grunt-run` 600 s) and any lane after `AI_LANE_TIMEOUT` (1200 s; `grunt-run` 2400 s); `codex-review` as a whole ends within `REVIEW_BUDGET` (1500 s; 540 s from the commit hook, under Claude Code's 600 s hook timeout). A heartbeat line goes to stderr every minute. OpenCode runs with `--print-logs` so the provider's error reaches stderr; Codex runs with `--json -o` so errors are separate events and a diff that quotes "usage limit" cannot trip the detector (falls back to plain output if the installed codex refuses the flags; `CODEX_REVIEW_JSON=0` forces that).
Reset times: the lane's own words are parsed (`_limits.py reset`): Codex "try again at Sep 22nd, 2026 9:51 AM" / "in 2 hours 5 minutes", OpenCode Go "Resets in 2h 13m", `resets_at`, `retry-after`. The lane is skipped until that time instead of the fixed 30 minutes, which remains only for a limit that names no time. A lane killed for silence or time is skipped for 15 minutes. Two Go models at their limit in one run mark the whole `opencode-go` provider (anomalyco/opencode #49014). Before spending a Codex call, `codex-review` reads the usage windows Codex writes to `~/.codex/sessions/**/rollout-*.jsonl`; a window at 100 % with a reset in the future skips Codex without a request (`CODEX_PREFLIGHT=0` disables).
`ai-limits` lists every lane with "back Tue 09:51 (in 14h)", how that is known, the lane's own sentence, and Codex's two windows with their percentages. `ai-limits clear [lane]` after buying credits; it also makes the pre-flight ignore older usage snapshots. OpenCode Go has no usage API (anomalyco/opencode #31084), so its reset time is known only after a refusal.
Tested against mock `codex` and `opencode` binaries (limit while running, limit at exit, silence, time-out, flags refused, diff quoting limit words, usage snapshot), not against the live services: the exact wording of a Go limit in `--print-logs` output and the `rate_limits` layout in rollout files are taken from public issues. After the next real limit, check `ai-limits`: "guessed" next to a lane means its message was not parsed — send me the "said:" line.

## Jev triage (0.2.0, optional)

`ai/bin/jev-triage` reads a diff and prints SKIP / REVIEW / ADVERSARIAL from five yes/no questions to TypeSafe's Jev plus local path and credential checks. It fails open to REVIEW, drops lockfiles, env files and generated types, and redacts anything credential-shaped before sending.
The commit hook uses it per clone: `git config ai-loop.jevtriage shadow` logs its verdict next to the real review and changes nothing; `on` lets SKIP skip the review and hands ADVERSARIAL's focus to the reviewer. Off by default, because the diff goes to a third party.
Key: `~/.config/typesafe/api-key` (chmod 600) or `$TYPESAFE_API_KEY`. Log: `~/.local/state/ai-loop/jev-triage.log`; `ai-limits triage` summarises it. Switch a repo to `on` only after the "SKIP but not SHIP" list has stayed empty for a couple of weeks.
The Jev call itself was tested against a mock of the documented API, not the live service.
Since 0.3.0: Jev's scores move a little between identical calls, so a SKIP must hold on two independent calls (`JEV_CONFIRM=0` turns that off); a disagreement or a failed second call means REVIEW. Risk scores within 0.10 of the threshold are logged as `near`. `ai-limits triage` counts those coin flips and ends with a decision line: stay in shadow, keep going, or ready (14 days and 30 compared reviews with no bad SKIP).

## Gotchas files (0.3.0)

Folders where mistakes recur carry a nested `AGENTS.md` of facts (what broke, the check that catches it, the command that proves it), plus a one-line `CLAUDE.md` containing `@AGENTS.md`. Codex reads the nested `AGENTS.md` directly. Claude Code loads the nested `CLAUDE.md` when it reads a file in that folder; it ignores a nested `AGENTS.md` whenever the repo has a root `CLAUDE.md`, which all of yours do. `/ai:loop` reads them while planning and, with `/ai:ship`, proposes a new line when a review finds a repeatable mistake. First set: assigame-next `supabase/`, `supabase/functions/`, `mobile/`.

Cheap lane: `grunt-run` appends a closing quality-pass instruction for the build agent (`GRUNT_QA_PASS=0` turns it off). Keep that kind of line out of prompts for frontier models.

## Models after 22 September 2026 (0.5.0)

Opus 5.5 and GPT-6 Sol/Luna shipped the same day. `opus` now resolves to Opus 5.5 in Claude Code (the Max default), which starts at effort medium and ignores a top-level `effortLevel`: use `/effort high` for a hard plan, or `modelSettings` per model. `cc-opus` is the suggested daily driver; `cc-fable` for what it gets wrong. `reviewer` (opus) picks up 5.5 without a change; `implementer` stays on `sonnet` until Sonnet 5.5 lands, which the alias will also pick up.
Codex tiers are now set in `aliases.zsh`: `gpt-6-sol` at medium for spec reviews and QA, the same model at `xhigh` when a focus marks the diff as risky (`CODEX_REVIEW_EFFORT_RISKY`, new), and `gpt-6-luna` at high for the pre-commit hook (`CODEX_REVIEW_MODEL_COMMIT` / `CODEX_REVIEW_EFFORT_COMMIT`, new, read only by the hook). The ids come from OpenAI's model list; update the Codex CLI so it knows them. Unset the two `_COMMIT` variables to review commits on Sol again. Note for `ai-limits triage`: the "real review" column is now Luna for commits, so compare shadow rows before and after this date separately.
`/ai:loop` and `/ai:ship` no longer poll a running `codex-review`: every check was a main-model turn. Claude Code reports when a background command exits; the 25-minute self-stop is unchanged, and after 26 minutes with no report the skill reads the output once and kills a run still going.
`/ai:loop` also proposes a line for a `## Patterns we do not use` section of the root `AGENTS.md` whenever you turn down an approach at a gate (the tempting choice, the alternative, the reason; added only on your yes). Effort changes mid-session keep the prompt cache since Claude Code v2.1.280, so `/effort high` for the plan and back to medium for the build is free.
`implementer` routes by trust as well as difficulty: chunks touching secrets, env files, auth, payments, migrations or deploy config never go to the cheap lane.
`aliases.zsh` also sets `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` (one background request per turn that re-reads the context; delete the line if you use Tab to accept suggestions).

## Prompt audit (24 September 2026)

Anthropic's `claude-api` skill carries a read-only audit of prompt files against current-model guidance: `/plugin marketplace add anthropics/skills`, then `/plugin install claude-api@anthropic-agent-skills`, then `/claude-api prompt-audit` from `~/devs/dotfiles/claude/ai` (skills, agents and the prompts inside `bin/`) and once from a repo root for its `AGENTS.md` tree. It prints findings (`file:line`, quoted evidence, pattern, confidence) and a proposed diff for the High and Medium ones; apply the hunks by hand. What to keep if it flags them: the waiting rule in `loop` and `ship` (its minutes are the scripts' own timeouts), the `VERDICT:` line pins (the hook and the skills parse them; the verdict comes first in a review, right after the `REVIEWER:` line), and the `never` lines that state their reason (data loss, a third-party lane). Re-run it at each model release: `implementer` (`sonnet`) and `grunt` (`haiku`) will move to 5.5 through their aliases, and the rules that suit Opus 5.5 suit them. A grep pass on 24 September over the plugin, the `bin/` prompts and the nine `AGENTS.md` files found none of the six anti-patterns Anthropic lists (verification rituals, emphasis boosters, mandatory procedures, stale examples, contradictory rules, dated config). The audit itself then found one contradictory rule it had missed: `reviewer` told the model to put both `VERDICT:` and `REVIEWER:` on the first line. `reviewer` now uses `codex-review`'s shape, and `loop` no longer names the implementer's models.
