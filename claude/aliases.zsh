# ai-loop — sourced from ~/.zshrc. Launch aliases pair the main model with the subagent default.
export PATH="$HOME/devs/dotfiles/claude/ai/bin:$PATH"   # grunt-run, codex-review, jev-triage, ai-limits usable from your own shell too

# Subagent caps (docs: sub-agents; defaults are 20 concurrent, depth 3). Depth 1 = subagents can't spawn subagents.
# /ai:loop only needs main → implementer / grunt; grunt-run and codex-review are Bash calls, not subagents. Nesting agents? Set depth 2.
_cc_caps='CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=5 CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1'   # 5 since 0.12.0: /ai:preship sends five checkers at once; the loop runs one agent at a time

# Next-prompt suggestions (grey text after each reply) are a background request that re-reads the whole context from cache.
# Cheap per call per the docs, but it is one extra request per turn on 1M-context sessions. Delete this line if you use Tab to accept them.
export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false

# Since 22 Sep 2026 the `opus` alias is Opus 5.5 (Fable-level on most tasks, ahead of Fable 5.1 on Anthropic's Terminal-Bench and FrontierCode,
# cheaper than Opus 5). cc-opus is the daily driver; cc-fable is for what cc-opus gets wrong.
#
# Effort (plugin 0.5.3, 24 Sep 2026; code.claude.com/docs/en/model-config): each alias now pins it with --effort, which applies to that
# session only and beats a default you once saved with /effort + Enter, so a launch always starts where the alias says. /effort still
# works mid-session. CLAUDE_CODE_EFFORT_LEVEL is deliberately not exported: it overrides /effort, which would lock the level for the session.
# Opus 5.5 ignores a top-level "effortLevel" in settings.json (its own default is medium); cc-opus starts it at high by choice.
# Climb effort before you switch models: cc-opus high → /effort xhigh (high got it wrong) → only then cc-fable. /effort medium for rote stretches.
# (@SKatalystAI's rule of thumb: Opus 5.5 medium ≈ Fable 5.1 high, Opus 5.5 high ≈ Fable 5.1 max.) Since Claude Code v2.1.280 a
# mid-session /effort change keeps the prompt cache (Anthropic's Lydia Hallie), so dropping to medium for a rote stretch and back is free.
# /effort ultracode = xhigh + dynamic workflows: many agents, large spend — only when you mean it.
# Subagents inherit the session's effort unless their definition says otherwise. The ai plugin pins them: implementer opus/medium,
# reviewer opus/high, grunt sonnet/medium (a relay to the OpenCode lane; does the work itself when the lane is off). So an xhigh main session no longer drags the build up with it.
#
# Subagent model (0.7.0, 26 Sep 2026): Sonnet builds took too many implementer ↔ Codex review rounds (snowlan), so the implementer
# is Opus 5.5 at medium. cc-opus and cc-fable no longer set CLAUDE_CODE_SUBAGENT_MODEL_FORCE: with it on, Claude Code ignores every
# agent's `model:` line (grunt's relay ran on the forced model too). Without it the agent files decide; CLAUDE_CODE_SUBAGENT_MODEL=opus
# only fills in for agents that name no model. Built-in Explore keeps its own (Haiku). Rote chunks and small updates: the free /
# OpenCode lane through grunt, or a cc-sonnet session, whose subagents are all forced to Sonnet (was Haiku: not worth the quality loss).
# Subagent effort: only an agent's `effort:` line sets it (no env var for subagents alone; CLAUDE_CODE_EFFORT_LEVEL would override
# main and subagents together and lock /effort). Agents without one inherit the session's level.

alias cc-fable="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL=opus claude --model fable --effort high"      # no advisor: a Fable main only accepts a Fable advisor
alias cc-opus="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL=opus claude --model 'opus[1m]' --effort high --autocompact 400k --advisor fable"  # 1M context (included on Max); quoted because zsh reads [1m] as a glob. --autocompact 400k (9 Oct 2026): compact at 400k, not near 967k — every call re-reads the whole context, and one replay of a week measured about 29% less weekly usage; /autocompact auto for one session that needs the full window. Fable advisor on by default since 5 Oct 2026, on trial for a few days: Fable reads the session and weighs in before a plan, on a repeated error and before done, while Opus keeps building. Fable has its own limit (two sessions stopped on it, 4 Oct 03:11 UTC): /advisor off mid-session, or remove the flag if the trial ends
# Sonnet drives, Opus is consulted at decision points (before an approach, on a recurring error, before "done").
# Counts toward the Max window; each consult re-reads the whole transcript uncached, so keep these sessions short.
# Mid-session: /advisor off · /advisor opus. Stays off if DISABLE_TELEMETRY (or anything blocking feature flags) is set.
alias cc-sonnet="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=sonnet claude --model sonnet --effort high --advisor opus"
alias cc-sonnet-solo="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=sonnet claude --model sonnet --effort high"   # the old cc-sonnet, for comparing /usage

# Codex review tiers (read by codex-review, so also by the commit hook, /ai:loop and /ai:ship). Plus quota is the scarce budget.
# Ids from OpenAI's model list (22 Sep 2026: GPT-6 Sol and Luna on Plus, half the price of the 5.6 pair). Needs a Codex CLI that lists them
# under /model — update Codex first. Astra is left out: OpenAI puts Sol at Astra-level reliability; set the risky tier to gpt-6-astra if you disagree.
export CODEX_REVIEW_MODEL="gpt-6.1-sol"        # spec reviews and /ai:loop, /ai:ship QA (6.1 since 1 Oct: better than 6 at the same price, cached input halved)
export CODEX_REVIEW_EFFORT="medium"            # OpenAI's suggested start for Sol
export CODEX_REVIEW_MODEL_RISKY="gpt-6.1-sol"  # a focus (auth, payments, schema…) keeps the model and raises the effort
export CODEX_REVIEW_EFFORT_RISKY="xhigh"
export CODEX_REVIEW_MODEL_COMMIT="gpt-6-luna"  # the pre-commit hook: small diffs, many calls. Unset both to review commits on Sol.
export CODEX_REVIEW_EFFORT_COMMIT="high"       # max is Luna's best mode but slower; the hook has 540 s
export CODEX_REVIEW_EFFORT_CHEAP="max"         # the weekly-budget downgrade tier (Luna): loop reviews have 35 min, so use Luna's best mode (0.5.3; was high)
# Trial (batch 14, live since the 7 Oct 2026 weekly reset): spec reviews on Astra at low effort ("Astra Light"). Compare the weekly %
# per spec review in `ai-limits log` with Sol's (~1.5 % at medium) and the findings with Sol's. Comment both out again to end the trial.
export CODEX_REVIEW_MODEL_SPEC="gpt-6-astra"
export CODEX_REVIEW_EFFORT_SPEC="low"
# Weekly budget (plugin 0.5.1, after the 21–24 Sep week: Astra/Sol reviews spent a Plus week in 2.5 days, Luna reviews did not move the counter):
# once Codex's last usage snapshot shows the 7-day window at 80 % or more, codex-review runs every review on gpt-6-luna high and says so in its
# REVIEWER line. Tune with CODEX_WEEKLY_DOWNGRADE_AT (0 = off), CODEX_REVIEW_MODEL_CHEAP, CODEX_REVIEW_EFFORT_CHEAP. The commit hook keeps the
# _COMMIT model even when jev-triage says ADVERSARIAL (CODEX_REVIEW_MODEL_COMMIT_RISKY overrides). `ai-limits` shows the week, `ai-limits log` the calls.
# 0.5.2: a stored Codex limit (or a snapshot that would downgrade) older than CODEX_RECHECK_EVERY (1800 s) is re-checked with a one-word Luna turn
# before it is believed — limits get reset, credits get bought. CODEX_RECHECK=0 trusts the stored date instead.

# Free OpenCode models (plugin 0.6.0). When OpenCode Zen runs a model for free, list it in ~/.zshrc.local (untracked, so the lists
# — OPENCODE_FREE_MODELS, GRUNT_MODELS, GRUNT_VARIANT, REVIEW_FALLBACK_MODELS — change without touching this repo): grunt-run tries it before GRUNT_MODELS,
# codex-review asks it before the paid Go fallbacks (after Codex), and the agents send it more than the rote parts while `grunt-run --free-status`
# exits 0. Ids end in -free (opencode.ai/docs/zen; `/models` in the OpenCode TUI). Free periods end without notice: a model that errors is skipped
# for 15 min, then retried. Mind the data terms: most free models may train on what they are sent (Space Bunny Free is zero-retention; the
# Nemotron trials say no confidential data). Per repo opt-out: `git config ai-loop.freelane off`. Reviews only: REVIEW_FREE=0.
# export OPENCODE_FREE_MODELS="opencode-go/space-bunny-free opencode-go/longcat-2.5-preview-free"
# NVIDIA build.nvidia.com (batch 7, 26 Sep 2026): free endpoints for DeepSeek V4.1 Flash, GLM 5.3, GLM 5.3 Flash, Kimi K3 — OpenAI-compatible,
# https://integrate.api.nvidia.com/v1, key in NVIDIA_API_KEY. Free tier = development/testing/evaluation only, per-model rate limits unpublished,
# data terms not checked: treat like the training free models (opt-out repos stay out). To try: add the provider in OpenCode, `opencode models`
# to get the exact ids, then append e.g. the Kimi K3 and GLM 5.3 ids to OPENCODE_FREE_MODELS (is_free matches the id as written).

# Cheap lane off (0.12.0): `ai-lane off` per clone, `ai-lane off --global`, or for one shell `export AI_CHEAP_LANE=off` — grunt does the work
# itself on Sonnet, the implementer's rote chunks run in a headless Sonnet session (0.14.2: GRUNT_CLAUDE_EFFORT=medium; low is
# cheaper for pure renames), codex-review has no OpenCode fallback. `ai-lane` shows what applies.

# Jev triage key: keep it out of every repo. jev-triage reads $TYPESAFE_API_KEY, else this file (chmod 600):
#   mkdir -p ~/.config/typesafe && pbpaste > ~/.config/typesafe/api-key && chmod 600 ~/.config/typesafe/api-key
# Enable per clone: git config ai-loop.jevtriage shadow   (see hook-scripts/review-before-commit.sh) · compare: ai-limits triage
