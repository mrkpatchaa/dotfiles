# ai-loop — sourced from ~/.zshrc. Launch aliases pair the main model with the subagent default.
export PATH="$HOME/devs/dotfiles/claude/ai/bin:$PATH"   # grunt-run, codex-review, ai-limits usable from your own shell too
alias cc-fable='CLAUDE_CODE_SUBAGENT_MODEL=opus claude --model fable'
alias cc-opus='CLAUDE_CODE_SUBAGENT_MODEL=sonnet claude --model opus'
alias cc-sonnet='CLAUDE_CODE_SUBAGENT_MODEL=haiku claude --model sonnet'
