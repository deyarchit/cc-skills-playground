---
name: map-website-api
description: Maps which user interactions on a website trigger which backend API/data-fetch calls, then produces a structured markdown report. Use this skill whenever the user wants to understand a website's API surface, explore what network calls a page makes, reverse-engineer a site's data-fetching patterns, or capture API endpoints from navigational flows. Trigger on phrases like "map the API calls", "capture network requests", "what endpoints does this site use", "intercept API calls", "find the data APIs for this website", or any task involving discovering/documenting backend calls for a given URL.
allowed-tools: Bash(playwright-cli:*), Bash(bash:*)
---

# map-website-api

> **Builds on:** `@.claude/skills/playwright-cli/SKILL.md` — read it for the full
> playwright-cli command reference. This skill covers *when and why* to use those
> commands; playwright-cli covers *what* each command does.

Given a target website URL, systematically capture the data-fetching API calls triggered by the most common navigational flows, then output a clean markdown report. Focus exclusively on calls that bring content/data to the page — ignore assets (fonts, images, CSS, JS bundles).

## Before you start — headed or headless?

If the user's request already specifies headed or headless (e.g. "in a headed browser", "headless"), skip this question and use that preference directly.

Otherwise ask:

> "Should I run this with a visible browser window (headed) or in the background (headless)?
> Headed is recommended — you can watch what's happening and verify the interactions are correct.
> Headless is faster if you just want the output."

Default to **headed** if the user doesn't have a preference or says "up to you".

Use the answer to set the open command for the entire session:

```bash
# Headed (recommended — user can see and verify interactions):
playwright-cli open --browser=chrome --headed {target_url}

# Headless (faster, no visible window):
playwright-cli open --browser=chrome {target_url}
```

Headed is strongly preferred for this type of analysis because:
- Many sites behave differently (bot detection, lazy features) when headless
- The user can spot when an interaction didn't work as intended
- It makes the session auditable — the user sees exactly what was clicked

## Bundled scripts

All scripts live in `.claude/skills/map-website-api/scripts/`. Use them via `bash <script>`.

| Script | Purpose |
|--------|---------|
| `drain.sh` | Drain the network buffer before an action |
| `capture.sh [label]` | Capture and filter network calls after an action |
| `filter_noise.sh` | Pipeable noise filter (used internally by capture.sh) |
| `fetch_blocklist.sh` | One-time setup: download HaGeZi ad domain list to `~/.claude/cache/` |
| `detect_architecture.sh <url>` | Auto-detect SSR vs SPA + scan for subdomain SPAs |
| `inspect_ssr_requests.sh` | SSR fallback: find fetch/Image/XHR patterns in the JS bundle |
| `inspect_post_bodies.js` | run-code template for capturing GraphQL operationName etc. |

> **One-time setup for best ad filtering:** Run `bash $S/fetch_blocklist.sh` once before your first session. This downloads the HaGeZi Pro blocklist (~300k community-maintained ad domains) to `~/.claude/cache/` and enables pass-2 filtering in `filter_noise.sh`. The cache auto-refreshes after 7 days. Completely optional — the skill works without it using the built-in regex patterns.

Reference path shorthand used below: `$S` = `.claude/skills/map-website-api/scripts`

---

## Phase 1: Setup

Open the browser using whichever mode the user chose (see above), then set the script path shorthand:

```bash
# headed (if user chose visible):
playwright-cli open --browser=chrome --headed {target_url}

# headless (if user chose background):
playwright-cli open --browser=chrome {target_url}

S=.claude/skills/map-website-api/scripts
```

---

## Phase 2: Pre-flight checks

Do these before enumerating actions — they save you from pursuing patterns that don't apply.

### 2a. Architecture detection

```bash
bash $S/detect_architecture.sh {any_internal_url}
```

- **Empty log → SSR/MPA.** Jump to Phase 2b.
- **Non-empty log → SPA or hybrid.** Proceed to Phase 3.

The script also scans the DOM for form actions, iframes, and auth links pointing to other domains — these are subdomain SPAs that need separate treatment.

**Mostly-SSR with interactive islands** — many sites (MediaWiki/Wikipedia, traditional CMS, government portals) are SSR for all navigations but still have client-side API calls in specific interactive widgets. If you confirm SSR via empty page-load logs, **skip navigation-heavy flows entirely** and focus exclusively on in-page interactions:

| Widget type | Trigger | Likely API |
|-------------|---------|------------|
| Search box | Type characters | Autocomplete/typeahead endpoint |
| Internal link hover | Hover and wait 1–2s | Page preview/summary endpoint |
| Image / media click | Click thumbnail | Media metadata endpoint |
| Language / locale switcher | Open and type | Language search endpoint |
| Comment threads | Expand or load more | Thread/comment pagination endpoint |
| Dynamic filters | Toggle sort or filter | Filtered results endpoint |

Exhausting navigation flows on an SSR site wastes cycles — each `goto` will produce `[empty]`. Once you've confirmed the architecture, shift strategy immediately.

### 2b. SSR fallback (only if network log is empty)

When the site uses server-side rendering, all content arrives as full HTML GETs — invisible to XHR/Fetch interception. Find hidden request patterns in the JS source instead:

```bash
bash $S/inspect_ssr_requests.sh
```

This fetches the main JS bundle and greps for `fetch()`, `new Image().src`, `XMLHttpRequest`, `WebSocket`, and URL string literals. These are the patterns that would be completely missed by network interception alone — especially `new Image().src` side-channels used for voting, flagging, and state mutations.

### 2c. Auth state check

Look at the page snapshot. If the page is empty or shows a "log in" prompt for personalized content (e.g. YouTube homepage logged out), skip those flows and start from search or direct content URLs. Note the gap in the output.

---

## Phase 3: Action enumeration

The fundamental loop for each action:

```bash
bash $S/drain.sh                         # 1. reset the buffer
# ... perform one atomic action ...      # 2. act
bash $S/capture.sh "Flow: description"   # 3. capture — shows only calls from this action
```

**Keep each action atomic.** One thing at a time so the diff is clean and attributable.

### Standard flows to cover

| Flow | How to trigger |
|------|---------------|
| Home / landing page load | `playwright-cli goto {base_url}` |
| Listing / category page | Navigate to a browse or listing page |
| Detail page | Navigate to a single item/post/video |
| Pagination | Scroll, or click "next page" / "load more" |
| Sort / filter | Toggle a sort dropdown or filter control |
| Search typeahead | Type into search box, don't submit |
| Search submit | Press Enter or click search button |
| Nested expansion | Expand comments, accordions, threads |
| Navigation tabs | Click tabs or nav links within a page |
| Auth-gated actions (if logged in) | Vote, post, subscribe, follow |

For **infinite scroll / lazy loading** — try in order, stop when pagination fires:

```bash
# Option 1 — most SPAs (YouTube, etc.):
playwright-cli run-code "async page => { await page.mouse.wheel(0, 3000); await page.waitForTimeout(1500); }"
# Repeat 4-5× with pauses

# Option 2 — fallback for container-scroll sites (Reddit, etc.):
playwright-cli eval "window.scrollTo(0, document.body.scrollHeight)"

# Option 3 — scroll last item into view:
playwright-cli eval "document.querySelector('{last-item-selector}').scrollIntoView()"
```

---

## Phase 4: Discriminator inspection

When an endpoint fires repeatedly across different actions, identify its discriminating signal before recording it. Same URL ≠ same operation.

> **Trigger rule:** If you see 3+ POSTs to the same URL (e.g. `POST /graphql` or `POST nexus-gateway-prod.media.yahoo.com/`) across any single capture window, stop and use `inspect_post_bodies.js` to find the operationName before continuing. Recording "POST /graphql — various" without the discriminator is the most common way this analysis goes wrong.

| Endpoint type | What to check | Signal field |
|---------------|--------------|-------------|
| POST GraphQL | Request body | `operationName` |
| GET persisted GraphQL (`?body=...`) | URL-decode `body=` param, parse JSON | `persistedQueryName` |
| InnerTube `POST /next` | Request body | continuation token type |
| Shared nav endpoint | Query params | `type=` param |
| Stats/context endpoint | Query params | `el=` param |
| Algolia search | URL | index name encodes sort order |

To capture POST bodies and extract `operationName`:

```bash
# Edit the ACTION STEPS section in the template, then:
playwright-cli run-code "$(cat $S/inspect_post_bodies.js)"
playwright-cli console   # read the output
```

### Deferred fragment pattern

If 5–15 GET requests fire simultaneously after page load, all to sub-paths of the same resource (e.g. `/pull/123/page_data/diffstat`, `/pull/123/page_data/merge_box`), this is the **deferred fragment pattern** — the page shell is SSR'd but each section is independently fetched. Document each sub-path separately; don't collapse them.

---

## Phase 5: Output

### URL normalization

Replace concrete IDs, cursors, and hashes with placeholders before writing the report:
- `/posts/12345` → `/posts/{id}`
- `?cursor=eyJ...` → `?cursor={cursor}`
- `/users/johndoe` → `/users/{username}`

### Markdown report template

```markdown
# API Map: {Site Name}

**URL:** {base_url}
**Rendering architecture:** {SSR / SPA / Hybrid}
**Auth state:** {Logged in / Logged out — affects: {list affected flows}}
**Date captured:** {date}

---

## Data Endpoints

### {Flow name}

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/api/feed` | — | Main feed items |
| POST | `/graphql` | `operationName: FeedQuery` | Feed via GraphQL |

### {Next flow...}

---

## Invisible / Non-XHR Patterns

| Pattern | Trigger | Notes |
|---------|---------|-------|
| `GET /vote?id={id}&how=up` via `new Image().src` | Upvote click | Fire-and-forget, no response body |

---

## Subdomain / Third-Party SPAs

| Domain | Feature | Architecture |
|--------|---------|--------------|
| `search.example.com` | Search | SPA — separate mapping needed |

---

## URL Pattern Summary

\`\`\`
GET  /api/v1/posts             # listing
GET  /api/v1/posts/{id}        # detail
POST /graphql                  # various — see operationName
\`\`\`

---

## Gaps & Notes

- {Flows skipped due to auth state}
- {Overloaded endpoints where discriminator wasn't fully identified}
- {SSR flows — captured via JS source inspection, not live network}
```

---

## Cleanup

```bash
playwright-cli close
```

---

## Common mistakes

- **Empty log ≠ no requests.** SSR produces HTML GETs invisible to interception. Run `inspect_ssr_requests.sh` before concluding there's nothing to capture.
- **Don't call `playwright-cli network` directly and read stdout.** Its stdout is just a markdown pointer (`### Result\n- [Network](...)`), not the actual log entries. Always use `capture.sh` — it reads the `.log` file correctly.
- **Don't use `run-code` for network observation.** It exits before async requests complete. Use `capture.sh` instead. Reserve `run-code` for driving interactions — or for `inspect_post_bodies.js` where the action and listener are in the same block.
- **One action per capture cycle.** Multiple actions between drains make the diff unattributable.
- **Run `detect_architecture.sh` first.** It tells you which subsequent steps apply and spots subdomain SPAs before you waste time on the wrong domain.
- **On SSR sites, don't keep navigating — interact instead.** Once you see `[empty]` for page loads, stop navigating and switch to in-page interactions (search box, hover, media click, filters).
- **Don't stop at the URL for overloaded endpoints.** Record the discriminating signal or the mapping is misleading.
- **When capture output is still large after filtering, grep for signal.** Even with noise filtering, high-traffic sites accumulate telemetry and ad calls. Rather than reading the full output, grep for what matters: `bash $S/capture.sh "label" 2>&1 | grep -E "your-domain|api|query|graphql"`. The filter already removes most ad noise; this final grep narrows to data APIs on the domains you care about.
- **Some endpoints appear in every capture — that's expected, not a bug.** Sites with real-time widgets (config resolvers, weather sidebars, finance tickers, user-profile pings) poll on every page. These will show up in every flow's capture regardless of what you triggered. Don't document them as specific to a single flow — put them in a "Shared / Cross-page" section instead. If they're cluttering a per-flow capture, use grep to focus: `bash $S/capture.sh "label" 2>&1 | grep -vE "config.*resolver|recoitems/weather|finance/charts|service/msn/user"`.
- **`playwright-cli eval` serialization rules — three things that will burn you:**

  1. **No IIFEs.** `playwright-cli eval "(() => { ... })()"` always fails.
  2. **No nested arrow functions.** Even inside a valid `() => {}` wrapper, using `.filter(a => ...)`, `.map(x => ...)`, or any callback expressed as an arrow function triggers `Error: page._evaluateFunction: Passed function is not well-serializable!`. The outer arrow wrapper is fine; the inner ones are not.
  3. **No complex top-level expressions.** `JSON.stringify(Array.from(...).map(i => ...))` as the whole argument fails — put it inside a wrapper body instead.

  **Working patterns:**
  - ✅ Simple property: `playwright-cli eval "document.querySelectorAll('input').length"`
  - ✅ String concat: `playwright-cli eval "document.querySelector('input').name + '|' + document.querySelector('input').type"`
  - ✅ Arrow wrapper, no inner arrows: `playwright-cli eval "() => { const items = Array.from(document.querySelectorAll('input')); return items.map(i => i.name).join(','); }"`
  - ✅ Use a `for` loop when you need filtering: see example below

  **Broken pattern and its fix:**
  ```bash
  # ❌ Fails — .filter() callback is a nested arrow function:
  playwright-cli eval "() => { const links = Array.from(document.querySelectorAll('a')); return links.filter(a => a.href.includes('/news/')).map(a => a.href).join('\n'); }"
  # Error: page._evaluateFunction: Passed function is not well-serializable!

  # ✅ Fix — replace .filter()/.map() chains with a for-loop:
  playwright-cli eval "() => { var out = []; var links = document.querySelectorAll('a'); for (var i = 0; i < links.length && out.length < 5; i++) { if (links[i].href.indexOf('/news/') > -1) out.push(links[i].href); } return out.join('\n'); }"

  # ✅ Alternative fix — grep the snapshot file instead (often simpler):
  grep "url:" .playwright-cli/page-*.yml | grep "/news/" | head -5
  ```

  The simplest fallback when you need to find links is always **grep the snapshot .yml** — it's faster than eval and has no serialization constraints.
