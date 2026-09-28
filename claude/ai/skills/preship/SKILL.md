---
name: preship
description: Use before launching or publicly sharing a web app or site. Five read-only checkers (design, mobile, states, real-user flows, launch basics) report issues with evidence; after my yes, one writer fixes them in one pass and shows before/after screenshots.
disable-model-invocation: true
---
Pre-ship check for: $ARGUMENTS (default: the web app in this repo). Adapted from @Voxyz_ai's 20-point list (26 September 2026).

Read the root and nested `AGENTS.md` first, then the repo's design source of truth — `docs/STYLE-GUIDE.md`, `DESIGN.md`, or whatever `AGENTS.md` names. If none exists, say so and propose writing one before anything else; the design check has nothing to measure against without it.

Stage 1 — Check (read-only). Start the app the way `AGENTS.md` says. Send one subagent per group below, in parallel, each told not to edit any file. Each returns a list: page or file, what is wrong, evidence (screenshot path, selector, or file:line), and a suggested fix. Browser checks use the `agent-browser` skill; the installed impeccable skills (`audit`, `adapt`, `polish`, `clarify`) may be used for their group. Static greps (placeholder text, missing titles) can go to the `grunt` agent when `grunt-run --free-status` exits 0.
1. Design consistency: every colour, font size, spacing and radius comes from the style guide; restrained palette and a clear type hierarchy; same-kind buttons, cards and inputs look alike; readable text on light and dark surfaces.
2. Mobile (375 px and 768 px): no sideways scroll or overflow; a working mobile menu; tap targets at least 44 px; layout holds at 200 % text size.
3. Every state: loading, empty and error screens; hover, pressed, focus and disabled looks on every button; form errors next to the field plus submitting, success and failure messages; transitions on modals, dropdowns and tabs (short and purposeful — one focal point, no effects for their own sake).
4. Real use: click through the core flows end to end (sign-up, posting, checkout or contact — whatever the product's main path is); buttons that do nothing and broken links; the whole flow with a keyboard only.
5. Launch basics: the home page says what the product does in one line; each page has one primary action; every page has a title, a meta description and a favicon; no placeholder or lorem text.

Stage 2 — Gate. Merge the five lists, drop duplicates, and show me one table grouped by severity (broken, confusing, polish). Change nothing until I answer; I may strike items.

Stage 3 — Fix. Fix the approved items yourself, one writer for every file (or delegate to the `implementer` with the table as its brief when the list is long). Run the repo's gates. Take after screenshots of every page you changed, next to the before shots from Stage 1.

Report: items fixed, items left and why, gates run with exit status, and the before/after screenshot paths.
