# ai-loop — sourced from ~/.zshrc. Launch aliases pair the main model with the subagent default.
export PATH="$HOME/devs/dotfiles/claude/ai/bin:$PATH"   # grunt-run, codex-review, jev-triage, ai-limits usable from your own shell too

# Subagent caps (docs: sub-agents; defaults are 20 concurrent, depth 3). Depth 1 = subagents can't spawn subagents.
# /ai:loop only needs main → implementer / grunt; grunt-run and codex-review are Bash calls, not subagents. Nesting agents? Set depth 2.
_cc_caps='CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=2 CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1'

alias cc-fable="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=opus claude --model fable"      # no advisor: a Fable main only accepts a Fable advisor
alias cc-opus="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=sonnet claude --model opus"       # add --advisor opus by hand for high-stakes work only
# Sonnet drives, Opus is consulted at decision points (before an approach, on a recurring error, before "done").
# Counts toward the Max window; each consult re-reads the whole transcript uncached, so keep these sessions short.
# Mid-session: /advisor off · /advisor opus. Stays off if DISABLE_TELEMETRY (or anything blocking feature flags) is set.
alias cc-sonnet="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=haiku claude --model sonnet --advisor opus"
alias cc-sonnet-solo="$_cc_caps CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=haiku claude --model sonnet"   # the old cc-sonnet, for comparing /usage

# Codex review tiers (read by codex-review, so also by the commit hook, /ai:loop and /ai:ship). Plus quota is the scarce budget:
# a mid model for spec reviews and ordinary diffs, the strong one only when a focus marks the diff as risky.
# Use ids your account lists under /model in the Codex TUI, then uncomment:
# export CODEX_REVIEW_MODEL="gpt-5.5"
# export CODEX_REVIEW_MODEL_RISKY="gpt-6-astra"
# export CODEX_REVIEW_EFFORT="high"

# Jev triage key: keep it out of every repo. jev-triage reads $TYPESAFE_API_KEY, else this file (chmod 600):
#   mkdir -p ~/.config/typesafe && pbpaste > ~/.config/typesafe/api-key && chmod 600 ~/.config/typesafe/api-key
# Enable per clone: git config ai-loop.jevtriage shadow   (see hook-scripts/review-before-commit.sh) · compare: ai-limits triage
