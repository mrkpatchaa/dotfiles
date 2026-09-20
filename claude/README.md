# claude/ — the `ai` plugin (skills, agents, fallback scripts) and shell aliases

Install once, in Claude Code:

    /plugin marketplace add /Users/user/devs/dotfiles/claude
    /plugin install ai@mrk

(or from a shell: `claude plugin marketplace add /Users/user/devs/dotfiles/claude && claude plugin install ai@mrk`)

The marketplace is a local directory, so the plugin loads in place: edit anything under `ai/` and run `/reload-plugins`.
Skills are namespaced: `/ai:loop`, `/ai:ship`. Agents: `implementer`, `grunt`, `reviewer`. `ai/bin/` is on the Bash tool's PATH while the plugin is enabled.

Shell: `.zshrc` sources `aliases.zsh` (cc-fable / cc-opus / cc-sonnet, and `ai/bin` on your PATH). Since 0.2.0: `cc-sonnet` runs with an Opus advisor (`cc-sonnet-solo` is the old one), every alias caps subagents at 2 concurrent / depth 1, and `CODEX_REVIEW_MODEL[_RISKY]` pick the Codex tier per review.

Per-project pieces (hook + settings + AGENTS.md block) live in each repo's `.claude/settings.json` and `AGENTS.md`.
State for limit tracking: `~/.local/state/ai-loop/` (`ai-limits` shows it, `ai-limits clear` resets it).

## Jev triage (0.2.0, optional)

`ai/bin/jev-triage` reads a diff and prints SKIP / REVIEW / ADVERSARIAL from five yes/no questions to TypeSafe's Jev plus local path and credential checks. It fails open to REVIEW, drops lockfiles, env files and generated types, and redacts anything credential-shaped before sending.
The commit hook uses it per clone: `git config ai-loop.jevtriage shadow` logs its verdict next to the real review and changes nothing; `on` lets SKIP skip the review and hands ADVERSARIAL's focus to the reviewer. Off by default, because the diff goes to a third party.
Key: `~/.config/typesafe/api-key` (chmod 600) or `$TYPESAFE_API_KEY`. Log: `~/.local/state/ai-loop/jev-triage.log`; `ai-limits triage` summarises it. Switch a repo to `on` only after the "SKIP but not SHIP" list has stayed empty for a couple of weeks.
The Jev call itself was tested against a mock of the documented API, not the live service.

Cheap lane: `grunt-run` appends a closing quality-pass instruction for the build agent (`GRUNT_QA_PASS=0` turns it off). Keep that kind of line out of prompts for frontier models.
