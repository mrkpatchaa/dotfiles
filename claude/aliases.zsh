# ai-loop — sourced from ~/.zshrc. Launch aliases pair the main model with the subagent default.
export PATH="$HOME/devs/dotfiles/claude/ai/bin:$PATH"   # grunt-run, codex-review, jev-triage, ai-limits usable from your own shell too

# Subagent caps (docs: sub-agents; defaults are 20 concurrent, depth 3). Depth 1 = subagents can't spawn subagents.
# /ai:loop only needs main → implementer / grunt; grunt-run and codex-review are Bash calls, not subagents. Nesting agents? Set depth 2.
_cc_caps='CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=2 CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1'

# Next-prompt suggestions (grey text after each reply) are a background request that re-reads the whole context from cache.
# Cheap per call per the docs, but it is one extra request per turn on 1M-context sessions. Delete this line if you use Tab to accept them.
export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false

# Since 22 Sep 2026 the `opus` alias is Opus 5.5 (Fable-level on most tasks, ahead of Fable 5.1 on Anthropic's Terminal-Bench and FrontierCode,
# cheaper than Opus 5). It starts at effort medium and ignores a top-level "effortLevel"; use /effort high for a hard plan, or
# "modelSettings" per model in ~/.claude/settings.json. Since Claude Code v2.1.280, changing effort mid-session keeps the prompt cache
# (Anthropic's Lydia Hallie), so /effort high for the plan and /effort medium for the build costs no re-read.
# cc-opus is the daily driver; cc-fable is for what cc-opus gets wrong.

alias cc-fable="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=opus claude --model fable"      # no advisor: a Fable main only accepts a Fable advisor
alias cc-opus="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=sonnet claude --model 'opus[1m]'"  # 1M context (included on Max); quoted because zsh reads [1m] as a glob. --advisor opus by hand for high-stakes work only
# Sonnet drives, Opus is consulted at decision points (before an approach, on a recurring error, before "done").
# Counts toward the Max window; each consult re-reads the whole transcript uncached, so keep these sessions short.
# Mid-session: /advisor off · /advisor opus. Stays off if DISABLE_TELEMETRY (or anything blocking feature flags) is set.
alias cc-sonnet="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=haiku claude --model sonnet --advisor opus"
alias cc-sonnet-solo="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=haiku claude --model sonnet"   # the old cc-sonnet, for comparing /usage

# Codex review tiers (read by codex-review, so also by the commit hook, /ai:loop and /ai:ship). Plus quota is the scarce budget.
# Ids from OpenAI's model list (22 Sep 2026: GPT-6 Sol and Luna on Plus, half the price of the 5.6 pair). Needs a Codex CLI that lists them
# under /model — update Codex first. Astra is left out: OpenAI puts Sol at Astra-level reliability; set the risky tier to gpt-6-astra if you disagree.
export CODEX_REVIEW_MODEL="gpt-6-sol"          # spec reviews and /ai:loop, /ai:ship QA
export CODEX_REVIEW_EFFORT="medium"            # OpenAI's suggested start for Sol
export CODEX_REVIEW_MODEL_RISKY="gpt-6-sol"    # a focus (auth, payments, schema…) keeps the model and raises the effort
export CODEX_REVIEW_EFFORT_RISKY="xhigh"
export CODEX_REVIEW_MODEL_COMMIT="gpt-6-luna"  # the pre-commit hook: small diffs, many calls. Unset both to review commits on Sol.
export CODEX_REVIEW_EFFORT_COMMIT="high"       # max is Luna's best mode but slower; the hook has 540 s
# Weekly budget (plugin 0.5.1, after the 21–24 Sep week: Astra/Sol reviews spent a Plus week in 2.5 days, Luna reviews did not move the counter):
# once Codex's last usage snapshot shows the 7-day window at 80 % or more, codex-review runs every review on gpt-6-luna high and says so in its
# REVIEWER line. Tune with CODEX_WEEKLY_DOWNGRADE_AT (0 = off), CODEX_REVIEW_MODEL_CHEAP, CODEX_REVIEW_EFFORT_CHEAP. The commit hook keeps the
# _COMMIT model even when jev-triage says ADVERSARIAL (CODEX_REVIEW_MODEL_COMMIT_RISKY overrides). `ai-limits` shows the week, `ai-limits log` the calls.
# 0.5.2: a stored Codex limit (or a snapshot that would downgrade) older than CODEX_RECHECK_EVERY (1800 s) is re-checked with a one-word Luna turn
# before it is believed — limits get reset, credits get bought. CODEX_RECHECK=0 trusts the stored date instead.

# Jev triage key: keep it out of every repo. jev-triage reads $TYPESAFE_API_KEY, else this file (chmod 600):
#   mkdir -p ~/.config/typesafe && pbpaste > ~/.config/typesafe/api-key && chmod 600 ~/.config/typesafe/api-key
# Enable per clone: git config ai-loop.jevtriage shadow   (see hook-scripts/review-before-commit.sh) · compare: ai-limits triage
