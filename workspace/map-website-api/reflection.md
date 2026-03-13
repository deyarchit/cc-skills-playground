# Reflection: Website API Mapping via Browser Automation

This document captures the reasoning, patterns, mistakes, and alternative approaches from API mapping sessions across multiple websites — written as a foundation for building a generic reusable skill.

Sessions covered: multiple sites across SSR MPA, SSR hybrid, and SPA architectures (HN, Reddit, YouTube, GitHub).

---

## What the Task Was

Map which user interactions on a website trigger which backend API/Fetch calls — focusing on data-fetching calls, ignoring analytics noise.

---

## The Core Pattern That Worked

### Baseline → Action → Diff

The fundamental loop was:

```
1. Establish baseline (drain network log)
2. Perform a single, discrete user action
3. Capture new network calls
4. Filter noise, record data endpoints
5. Repeat for next action
```

This is the right mental model. Every action should be atomic — one thing at a time — so the diff is clean and attributable.

### `playwright-cli network` is a draining buffer

**Critical insight discovered mid-session:** `playwright-cli network` does NOT return a cumulative log. Each call returns only requests captured **since the last call**, then resets. This is actually the correct primitive — but I didn't realize it until later, so I wasted effort comparing line counts between files.

**The right pattern is:**
```bash
playwright-cli network   # drain/reset the buffer (discard output)
# ... perform action ...
playwright-cli network   # now this shows ONLY calls from this action
```

If I had used this from the start, every action would have produced a clean, isolated diff automatically.

---

## What Didn't Work (and Why)

### 1. `playwright-cli network` Captures Only XHR/Fetch — Not All Requests

Discovered during the HN session: `playwright-cli network` is **silent on pure SSR sites** because it only intercepts XHR and Fetch calls. Full-page HTML GETs (the dominant request type on SSR MPAs) do not appear in the log at all. The log will be empty even when the browser is actively loading pages.

Additionally, some sites use `new Image().src` as a fire-and-forget side channel for lightweight state mutations (e.g., HN voting, comment collapse). These are real HTTP requests but are **completely invisible** to XHR/Fetch interception.

```
Visible to playwright-cli network:     XHR, fetch()
Invisible to playwright-cli network:   HTML navigations, new Image().src, <form> submits, <a href> links
```

**Lesson:** An empty network log does not mean nothing happened. It may mean the site uses non-XHR request patterns. Read the site's JS source to understand the full picture before concluding there's nothing to capture.

### 2. JS Fetch/XHR Interceptor Injection

I injected a `window.fetch` override into the page to track calls. This failed in practice because:
- Reddit uses **full-page SSR navigation** — clicking a link reloads the page, destroying the injected code
- I didn't know this upfront; it was only revealed by observing the navigation pattern (full `GET` requests for page loads, not just data fetches)
- This approach would only work for true SPAs where JS context persists

**Lesson:** Before injecting interceptors, first determine the rendering model of the site (SSR vs SPA vs hybrid). A quick way: observe whether navigating produces a full HTML request or only data requests.

### 2. `window.scrollTo` vs `mousewheel` — Site-Dependent

`playwright-cli mousewheel 0 3000` didn't scroll the Reddit feed (required `window.scrollTo`). However, on YouTube, `page.mouse.wheel(0, 3000)` via `run-code` worked correctly and triggered infinite scroll pagination.

**Lesson:** Scroll behavior is site-dependent. `mousewheel` is not universally unreliable — it works on sites that use `scroll` event listeners or `IntersectionObserver` on the viewport. It fails on sites that attach listeners to a specific scrollable container element (not the window). Try `mousewheel` first; fall back to `scrollTo` or `scrollIntoView` if pagination isn't triggered.

### 3. Fragile Line-Count Baseline Tracking

I tracked network log state by counting lines in the log file and using `tail -n +N` to extract new entries. This was:
- Fragile (file path changes each call)
- Unnecessary (the buffer-draining behavior already handles this)
- Prone to off-by-one errors

**Lesson:** Use the drain-then-act-then-read pattern instead. No line counting needed.

### 4. Assuming the Interesting API Surface Is on the Main Domain

HN delegates all search to `hn.algolia.com` — a completely separate SPA. If you only observe `news.ycombinator.com`, you'd conclude the site has near-zero API activity and move on. But the Algolia SPA is where all the interesting XHR/Fetch action lives, with a rich query API, live-as-you-type search, and index-per-sort-order patterns.

**Lesson:** Check for third-party or subdomain SPAs that handle major features (search, checkout, dashboards). These are separate architectural units that need to be treated as distinct mapping targets.

### 5. Not Inspecting GraphQL Bodies / Overloaded Endpoints

`POST /svc/shreddit/graphql` was called on almost every page load but I couldn't tell what each call was fetching. The endpoint is overloaded — it serves different queries based on request body.

YouTube confirmed this pattern further: `POST /youtubei/v1/next` serves **both** the recommendations panel and the comment thread — the same URL, same method, different continuation token type in the JSON body. URL alone is completely insufficient to distinguish these two very different operations.

Similarly, YouTube's stats endpoints (`/api/stats/playback`, `/api/stats/watchtime`, `/api/stats/qoe`) use a query param `el=` (e.g., `detailpage`, `profilepage`, `adunit`) to encode context. The URL pattern looks identical across all contexts.

**Lesson:** For overloaded endpoints, document the discriminating signal explicitly:
- GraphQL (POST) → `operationName` in request body
- GraphQL (persisted, GET) → `persistedQueryName` in the `body=` query param (see §9 below)
- InnerTube `next` → continuation token type in body (recommendations vs. comments)
- Stats endpoints → `el=` query param
- Algolia → index name in URL encodes sort order

Request body inspection is necessary. Use either:
- `playwright-cli run-code` with `page.on('request', r => console.log(r.postData()))`
- HAR export which includes request payloads

### 6. Persisted GraphQL via GET (Cache-Friendly GraphQL)

GitHub uses `GET /_graphql?body={...}` rather than `POST /graphql`. The body contains a JSON object with:
- `persistedQueryName` — the operation identifier (human-readable, e.g. `"IssueViewerViewQuery"`)
- `query` — an MD5 hash of the query document (not the query string itself)
- `variables` — the operation variables

This is the **automatic persisted queries (APQ)** pattern — moving GraphQL to GET allows CDN caching. The discriminating signal is `persistedQueryName` in the URL-encoded `body=` param, not `operationName` in a POST body.

**Lesson:** Don't assume GraphQL always uses POST. When you see `GET /_graphql?body=...` or similar, URL-decode and JSON-parse the `body=` param to find the operation name. The query field is usually a hash (not readable) — `persistedQueryName` is what identifies the operation.

### 7. Deferred Section / "Fragment" Loading Pattern

Modern hybrid SSR apps (GitHub, and increasingly common elsewhere) load page sections via **multiple parallel GET requests after the initial SSR paint**, rather than a single API call. Each logical section has its own endpoint:

```
GET /{resource}/{id}/page_data/tab_counts
GET /{resource}/{id}/page_data/diffstat
GET /{resource}/{id}/page_data/merge_box
GET /{resource}/{id}/page_data/status_checks
```

This is distinct from both "one big API call" and "pure SSR" — the page shell is SSR'd but individual sections are independently fetched, cached, and rendered. Each section endpoint is cheap to cache separately (e.g., merge box changes independently of diff stats).

**Lesson:** When you see 5–10 GET requests firing simultaneously after page load, all to sub-paths of the same resource, this is the deferred section pattern. Document each sub-path and its purpose separately — don't collapse them into one entry. The section name in the URL (e.g., `merge_box`, `diffstat`) is usually self-describing.

### 8. Single Endpoint Serving Multiple Nav Menu Types

GitHub loads all four navigation menus from the same URL, distinguished only by a `type=` query param:

```
GET /_global-navigation/payloads.json?type=nav_menu
GET /_global-navigation/payloads.json?type=create_menu
GET /_global-navigation/payloads.json?type=user_menu
GET /_global-navigation/payloads.json?type=account_switch_dialog
```

This fires on every page load. At first glance it looks like "four requests to the same endpoint" — but each returns different JSON. The `type=` param is the discriminator.

**Lesson:** When you see the same URL repeated multiple times in the network log with different query params, look at those params as discriminators before writing it off as duplicate traffic. Log the distinct `type=` values, not just "GET /_global-navigation/payloads.json × 4".

### 9. `run-code` console.log Output Is Unreliable for Request Capture

Tried using `console.log(JSON.stringify(calls))` inside a `run-code` block with a `page.on('request', ...)` listener to capture API calls. The output never surfaced — the listener fires asynchronously while `run-code` executes synchronously and exits before requests complete. Even when it runs correctly, the console output appears in a separate log file and requires an extra read step.

**Lesson:** Don't try to capture network calls via `run-code` + `console.log`. Use `playwright-cli network` directly — it is the right primitive for this. Reserve `run-code` for driving page interactions (navigation, scrolling, clicking), not for observation.

### 7. Auth State Affects Page Content — Plan Around It

On YouTube (logged-out), the homepage shows "Try searching to get started" with zero feed content. This makes the homepage scroll flow unmappable. No amount of scrolling will trigger a `browse` or `next` continuation call because there is no feed to paginate.

**Lesson:** Before planning which flows to map, check what content is actually available in the current auth state. For logged-out sessions, start from search or direct URLs rather than the personalized homepage. Note this as a gap in the mapping rather than wasting time investigating empty pages.

### 8. `--extension` Requires a Specific Chrome Extension — Use `--headed` Instead

Attempted `playwright-cli open --extension` to connect to the user's visible Chrome browser. This requires the "Playwright MCP Bridge" extension to be installed, which it usually isn't. The command errors immediately.

`--headed` (found via `playwright-cli open --help`) opens a new Chromium/Chrome window that is visible to the user. This is the right approach for headed sessions and requires no extensions.

```bash
# Wrong (requires extension installation):
playwright-cli open --extension https://example.com

# Right (opens a visible browser window):
playwright-cli open --browser=chrome --headed https://example.com
```

**Lesson:** Always run `playwright-cli open --help` when unsure of flags. The `--headed` flag is not prominently documented but is essential for visual sessions.

---

## Alternative Approaches (Better in Some Ways)

### Option A: Playwright Tracing (Most Complete)

```bash
playwright-cli tracing-start
# ... perform all actions ...
playwright-cli tracing-stop trace.zip
```

Trace files capture ALL network requests with full headers, bodies, timing, and even screenshots per action. Viewable in Playwright Trace Viewer. Best for thorough audits but requires post-processing to extract the mapping.

**When to use:** When you want the most complete picture, including request/response bodies, headers, and timings.

### Option B: HAR Export via run-code

```bash
playwright-cli run-code "async page => {
  await page.context().tracing.start({ snapshots: true });
  // ... or use CDP to start HAR capture
}"
```

HAR (HTTP Archive) format is the web standard for capturing full network sessions, including request bodies. Most API analysis tools can import HAR files.

**When to use:** When you need to share results with other tools (Postman, Insomnia, Charles Proxy analysis, etc.)

### Option C: Request Listener via run-code (Persists Across Actions)

Playwright's `page.on('request', ...)` listener is set at the browser automation level, not in the JS context, so it survives page navigations. However, `playwright-cli run-code` runs code then exits — the listener doesn't persist.

A workaround:
```bash
playwright-cli run-code "async page => {
  // Log all requests to a file via CDP
  const client = await page.context().newCDPSession(page);
  await client.send('Network.enable');
  client.on('Network.requestWillBeSent', (event) => {
    if (event.request.url.includes('api') || event.request.url.includes('svc')) {
      console.log('[REQ]', event.request.method, event.request.url);
    }
  });
  // Now perform actions...
}"
```

**When to use:** When you need persistent cross-navigation interception with body access, and you want to do it all in one run-code block.

### Option D: Filter-First Shell Helper Script

A reusable helper that wraps every action and automatically filters noise:

```bash
#!/bin/bash
# usage: ./capture_action.sh "action description" <playwright commands...>
ACTION_DESC="$1"
shift

playwright-cli network > /dev/null 2>&1  # drain

"$@"  # run the playwright commands

echo "=== $ACTION_DESC ==="
playwright-cli network 2>/dev/null | grep -v 'shreddit/events' \
  | grep -v 'recaptcha' \
  | grep -v 'w3-reporting' \
  | grep -v 'google.com/ccm' \
  | grep -v 'styling-overrides' \
  | grep -v 'gsi/log'
```

This would have made the entire session much cleaner — each action block would immediately output only the meaningful API calls.

### Option E: Pre-defined Noise Filter List

Build a filter config file (`noise-patterns.txt`) for common tracking/analytics endpoints that appear on most websites:
```
google-analytics
googletagmanager
doubleclick
facebook.com/tr
segment.io
mixpanel
amplitude
sentry.io
recaptcha
w3-reporting
/events
/track
/analytics
/beacon
```

Then filter network output through it automatically. This pattern is reusable across any website.

---

## Reusable Patterns of Thinking

### 1. Identify the Rendering Architecture First

Before anything else, determine how the site renders:

| Signal | Architecture | Implication |
|--------|-------------|-------------|
| Page navigations produce full HTML GET requests | SSR / MPA | JS injection won't persist; rely on playwright network layer |
| Page navigations produce only JSON/API requests | SPA (React/Vue/Angular) | JS injection persists; `window.fetch` override works |
| Mix of both | Hybrid (Next.js, Nuxt, etc.) | Be careful; navigations vary |

Quick test: Navigate to an internal link and watch the network log. Full HTML response = SSR.

**HN lesson:** An empty `playwright-cli network` log after page load is itself a signal — it means pure SSR with no client-side data fetching. Don't spend time looking for endpoints that don't exist; shift to reading the JS source to find hidden request patterns (like `new Image().src`).

### 1a. Check for Key-Feature Subdomains / Third-Party SPAs

Major features like search, checkout, or dashboards may live on a separate subdomain or third-party SPA (e.g., HN search is at `hn.algolia.com`, not `news.ycombinator.com`). These are completely separate mapping targets with their own architecture.

**Checklist before starting:**
- Does the site's search redirect to a different domain?
- Are there `<iframe>` embeds for key features?
- Do auth flows redirect to a separate subdomain (e.g., `auth.example.com`)?

### 2. Enumerate Actions Systematically

Cover all interaction types:
- **Page loads**: Home, listing, detail
- **Pagination**: Scroll-to-load, "Load more" button, numbered pages
- **Sorting/Filtering**: Sort dropdowns, filter toggles
- **Search**: Typeahead, submission, result pagination
- **Expansion**: Nested content (comments, threads, accordions)
- **Navigation**: Links, breadcrumbs, tabs
- **Media**: Video autoplay, image galleries
- **Auth-gated** (if logged in): Voting, posting, subscribing

Missing any of these leaves gaps in the mapping.

### 3. Separate Signal from Noise Immediately

Classify every endpoint on first encounter:
- **Data** (keep): feeds, posts, comments, search, user profiles
- **Noise** (filter): analytics, tracking, ads, recaptcha, CSP reports, styling

Deferring this categorization makes the final mapping messy.

### 4. Name Each Action Before Performing It

Mentally (or in code) label what you're about to do before triggering it. This makes the diff attributable. If you perform multiple actions between network captures, you can't tell which call came from which action.

### 5. Read the Site's JS Source When Network Logs Are Empty

If `playwright-cli network` returns nothing, the site may still have interesting request patterns that are invisible to XHR/Fetch interception. The JS source (`<script src>`) is the ground truth.

Pattern to follow:
```bash
# Find script URL
playwright-cli eval "document.querySelector('script[src]')?.src"
# Fetch and grep it
curl -s "{script_url}" | grep -E "fetch|XMLHttpRequest|new Image|\.src\s*="
```

From this you can find:
- `fetch()` calls and their URL construction logic
- `new Image().src` side-channel requests (voting, tracking, collapse state)
- WebSocket connections
- Any query parameters and auth token patterns

### 6. Check for Over-Loaded Endpoints

Endpoints like `POST /graphql` or `POST /api/query` serve many different operations. Don't stop at the URL — check:
- Request bodies (operationName, query variables)
- Response shapes
- When they fire relative to actions

**Algolia lesson:** The index name itself encodes sort order (`Item_dev` vs `Item_dev_sort_date`). Without inspecting multiple calls, this variation is invisible — the URL looks the same at a glance.

### 7. Scroll Triggering — Try Both Approaches

For infinite scroll / lazy loading (behavior is site-dependent):
```bash
# Works on many sites (YouTube, etc.) — use first:
playwright-cli run-code "async page => {
  await page.mouse.wheel(0, 3000);
  await page.waitForTimeout(1500);
}"

# Fallback if mousewheel doesn't trigger pagination (Reddit, container-scroll sites):
playwright-cli eval "window.scrollTo(0, document.body.scrollHeight)"

# For specific element lazy loading:
playwright-cli eval "document.querySelector('last-item-selector').scrollIntoView()"
```

Repeat scroll + wait 3–5 times with pauses between to give intersection observers time to fire and network requests time to complete.

---

## Generic Skill Blueprint (for future implementation)

```
SKILL: map-website-api

INPUTS:
  - target_url: starting URL
  - actions: list of (label, playwright_commands) pairs
  - noise_patterns: list of URL substrings to filter out (has sane defaults)

STEPS:
  0. Open browser:
     playwright-cli open --browser=chrome --headed {target_url}
     (ALWAYS headed; --extension requires an uninstalled Chrome extension, avoid it)

  1. Pre-flight checks (do these BEFORE starting action enumeration):
     a. Check auth state: is there actual content on the page, or a "log in" / empty
        state? If empty (e.g. YouTube logged-out homepage), skip personalized flows
        and start from search or direct content URLs instead.
     b. Detect rendering architecture (SSR vs SPA): drain network buffer, navigate
        to an internal link, check if log is empty → SSR, or has JSON/XHR → SPA
     c. If empty log (SSR): fetch the site's main JS file and grep for fetch/XHR/Image
        patterns to find hidden request mechanisms
     d. Scan HTML for feature subdomains (search forms, iframes, auth redirects)
        that need to be treated as separate mapping targets

  2. Set up noise filter alias:
     FILTER="log_event|analytics|tracking|events|recaptcha|reporting|styling|feedback|guide|generate_204|jnn/v1/GenerateIT|doubleclick|fonts.gstatic"
     # Use: playwright-cli network 2>/dev/null | grep -vE "$FILTER"

  3. For each action in actions:
     a. Drain network buffer:  playwright-cli network > /dev/null
     b. Execute action (use run-code for interactions, NOT for network observation)
     c. Wait for network idle
     d. Capture: playwright-cli network 2>/dev/null | grep -vE "$FILTER"
     e. If log is empty, note "SSR full-page load" rather than leaving blank
     f. For any endpoint that fires repeatedly or in multiple contexts, check discriminators:
        - POST GraphQL → `operationName` in body
        - GET persisted GraphQL → `persistedQueryName` in URL-decoded `body=` param
        - Shared nav endpoint → `type=` query param
        - InnerTube → continuation token type in body
        - Stats → `el=` query param
        - Algolia → index name in URL (encodes sort order)
     g. If you see 5–10 GETs to sub-paths of the same resource firing in parallel after
        page load (e.g., /page_data/diffstat, /page_data/merge_box), this is the
        deferred section pattern — document each sub-path individually
     g. Store: { action_label -> [filtered_endpoints + discriminator notes] }

  4. Scroll triggering — try in order:
     a. page.mouse.wheel(0, 3000) via run-code, repeat 4-5× with 1-2s pauses
     b. If no pagination: window.scrollTo(0, document.body.scrollHeight)
     c. If still nothing: element.scrollIntoView() on the last visible item

  5. Deduplicate and normalize URL patterns (replace IDs/cursors with {id}, {cursor})

  6. Output structured mapping document

OUTPUT:
  - Architecture note: SSR vs SPA vs hybrid; auth-state dependency
  - Markdown table per flow: Operation | Method | Endpoint Pattern | Discriminator | Notes
  - Grouped by: data endpoints vs infrastructure/noise
  - Invisible patterns (new Image, form submits) in a separate section
  - Subdomain SPAs listed as separate sections
  - Key URL pattern summary block at the bottom (copy-paste ready)
```

---

## What I Would Do Differently Next Time

1. **Always open headed** — `playwright-cli open --browser=chrome --headed {url}`. Never run headless for these sessions; the user can't see and verify what's happening.

2. **Start with the drain pattern** — call `playwright-cli network` once before any action to clear the buffer, then every subsequent call gives a clean diff.

3. **Write a noise-filter one-liner** at the start:
   ```bash
   FILTER="events|recaptcha|analytics|tracking|reporting|styling|gsi|ccm|collect|play.google|log_event|generate_204|feedback|guide|jnn"
   alias clean_net="playwright-cli network 2>/dev/null | grep -vE '$FILTER'"
   ```
   Then every action is just: `clean_net` and you only see meaningful calls.

4. **Check auth state first** — if the target page is personalized (homepage feeds, dashboards), verify there's actual content before trying to map scroll/pagination flows. If logged out produces an empty page, skip to flows that work without auth (search, direct URLs).

5. **Check overloaded endpoint discriminators** — for any endpoint that fires repeatedly or in multiple contexts, check what distinguishes calls: body params (`operationName`, `persistedQueryName`), query params (`type=`, `el=`), or continuation token type. Don't just record the URL. This applies to both POST and GET endpoints.

6. **Detect SSR vs SPA first** — one quick navigation would have told me not to bother with the JS interceptor.

7. **Parameterize URL patterns** immediately — replace actual IDs/cursors with `{id}`, `{cursor}` etc. as you build the mapping, so the patterns are immediately reusable.

11. **Watch for deferred section loading** — if you see 5–10 GETs firing simultaneously to sub-paths of the same resource after page load (e.g., `/pull/123/page_data/diffstat`, `/pull/123/page_data/merge_box`), document each section separately. This is the "deferred fragment" pattern — don't collapse them into one entry.

12. **Check for GET-based persisted GraphQL** — not all GraphQL is `POST /graphql`. Some sites move to `GET /_graphql?body={...}` for CDN cacheability. URL-decode the `body=` param and parse the JSON to find the `persistedQueryName` field.

13. **Look for `type=` or similar query-param dispatching on shared nav endpoints** — global navigation often loads lazily from a single URL with a `type=` param distinguishing each menu. Note the distinct values, not just the URL.

8. **When the network log is empty, read the JS source** — `curl -s {script_url} | grep -E "fetch|new Image"` takes 10 seconds and reveals all hidden request patterns. HN's voting and collapse state mutations would have been missed entirely without this step.

9. **Check for subdomain SPAs upfront** — look at where links go before starting. HN's search form `action="//hn.algolia.com/"` is visible in the HTML; spotting it early would have set the right scope immediately.

10. **Don't use `run-code` for network observation** — use it only for driving interactions. `playwright-cli network` is the correct tool for capturing requests; `run-code` + `console.log` is async and unreliable for this purpose.

