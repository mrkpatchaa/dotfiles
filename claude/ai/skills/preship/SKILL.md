---
name: preship
description: Use before launching or publicly sharing a web app or site. Five read-only checkers (design, mobile, states, real-user flows, launch basics) report issues with evidence; `break` sends four read-only breakers (security, data, flows under stress, environment) instead, `all` runs both. After my yes, one writer fixes the polish items and security or data items go through /ai:loop.
disable-model-invocation: true
---
Pre-ship check for: $ARGUMENTS (default: the web app in this repo). Adapted from @Voxyz_ai's 20-point list (26 September 2026) and 16 break questions (27 September 2026).

Mode: if the first word of the arguments is `break`, run groups 6–9 only; if it is `all`, run 1–9; otherwise run 1–5. The rest of the arguments name the app.

Read the root and nested `AGENTS.md` first, then the repo's design source of truth — `docs/STYLE-GUIDE.md`, `DESIGN.md`, or whatever `AGENTS.md` names. If none exists, say so and propose writing one before anything else; the design check has nothing to measure against without it.

Stage 1 — Check (read-only). Start the app the way `AGENTS.md` says. Send one subagent per group below, in parallel, each told not to edit any file. Each returns a list: page or file, what is wrong, evidence (screenshot path, selector, or file:line), and a suggested fix. Browser checks use the `agent-browser` skill; the installed impeccable skills (`audit`, `adapt`, `polish`, `clarify`) may be used for their group. Static greps (placeholder text, missing titles) can go to the `grunt` agent when `grunt-run --free-status` exits 0.
1. Design consistency: every colour, font size, spacing and radius comes from the style guide; restrained palette and a clear type hierarchy; same-kind buttons, cards and inputs look alike; readable text on light and dark surfaces.
2. Mobile (375 px and 768 px): no sideways scroll or overflow; a working mobile menu; tap targets at least 44 px; layout holds at 200 % text size.
3. Every state: loading, empty and error screens; hover, pressed, focus and disabled looks on every button; form errors next to the field plus submitting, success and failure messages; transitions on modals, dropdowns and tabs (short and purposeful — one focal point, no effects for their own sake).
4. Real use: click through the core flows end to end (sign-up, posting, checkout or contact — whatever the product's main path is); buttons that do nothing and broken links; the whole flow with a keyboard only.
5. Launch basics: the home page says what the product does in one line; each page has one primary action; every page has a title, a meta description and a favicon; no placeholder or lorem text.

Break groups (6–9). Before sending them, confirm with me that the target is local or a test environment, and get two test accounts (unless `AGENTS.md` names seeded ones). Payments in test mode only; AI APIs mocked or on a capped test key; test data only in the test database, removed afterwards. Send one `breaker` agent per group, in parallel, with the group's questions, the app URL and the accounts. They stop and report if they find production keys or a live domain.
6. Security: private keys in the built frontend bundle or git history (`sk_`, `service_role`, the Supabase service key); API, RPC and edge-function calls made directly, logged out and as the other account (row-level security must refuse them); price, quantity or role changed in a request and replayed; 100 quick requests to one endpoint (is there a limit per user and per IP); a script hidden in Markdown, rich text or an uploaded SVG, opened by the other account.
7. Data: 10,000 records seeded in the test database (does the page still open); a 200-character name with emoji and French or Kabiyè diacritics (does the layout hold); the same email in different capitalisation (one account, not two); an empty form submitted (no blank row).
8. Flows under stress: the same order or post submitted twice at once, and the same webhook replayed (one record); refresh or Back halfway through a form (is the input kept, or is the loss clear); saving while offline (no false "saved"); a 50 MB image upload (rejected or handled without freezing).
9. Environment: a small phone at 200 % zoom (every control tappable; skip when group 2 ran in the same pass); the WebKit engine (Playwright `webkit`); users in other time zones, for example America/Los_Angeles and Pacific/Auckland next to Africa/Casablanca (dates, deadlines and "today" not off by a day).

Stage 2 — Gate. Merge the lists, drop duplicates, and show me one table grouped by severity (critical, broken, confusing, polish), then the items each breaker marked untested, with the reason. Change nothing until I answer; I may strike items.

Stage 3 — Fix. Fix the approved items yourself, one writer for every file (or delegate to the `implementer` with the table as its brief when the list is long). Run the repo's gates. Take after screenshots of every page you changed, next to the before shots from Stage 1. Critical items and anything from groups 6–8 that touches auth, money or stored data go through `/ai:loop` instead (one run per item or per related group), so they get the verifier and the independent review; list them in the report as handed over. After fixes, re-ask the breaker questions that were broken.

Report: items fixed, items handed to `/ai:loop`, items left and why, untested items, test data the breakers could not remove, gates run with exit status, and the before/after screenshot paths.
