# claude/ — the `ai` plugin (skills, agents, fallback scripts) and shell aliases

Install once, in Claude Code:

    /plugin marketplace add /Users/user/devs/dotfiles/claude
    /plugin install ai@mrk

(or from a shell: `claude plugin marketplace add /Users/user/devs/dotfiles/claude && claude plugin install ai@mrk`)

The marketplace is a local directory, so the plugin loads in place: edit anything under `ai/` and run `/reload-plugins`.
Skills are namespaced: `/ai:loop`, `/ai:ship`. Agents: `implementer`, `grunt`, `reviewer`. `ai/bin/` is on the Bash tool's PATH while the plugin is enabled.

Shell: `.zshrc` sources `aliases.zsh` (cc-fable / cc-opus / cc-sonnet, and `ai/bin` on your PATH).

Per-project pieces (hook + settings + AGENTS.md block) live in each repo's `.claude/settings.json` and `AGENTS.md`.
State for limit tracking: `~/.local/state/ai-loop/` (`ai-limits` shows it, `ai-limits clear` resets it).
