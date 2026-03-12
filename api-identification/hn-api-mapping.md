# Hacker News API Calls Mapping

> Observed via Playwright network interception on news.ycombinator.com and hn.algolia.com (March 2026, logged-out session).
> HN core is a classic SSR MPA; search is powered by a separate Algolia-backed SPA.

---

## Architecture Notes

- **news.ycombinator.com** is a **pure SSR Multi-Page Application**. Every navigation produces a full HTML page reload. There are no XHR or Fetch calls for loading page content.
- **hn.algolia.com** is a **SPA** (React + InstantSearch.js). All search queries go through a single Algolia endpoint via `POST` with parameters in the request body.
- Voting and comment collapsing on the core site use `new Image().src` as a fire-and-forget side channel — not XHR/Fetch, and thus **not captured by `playwright-cli network`**.
- The only real `fetch()` call on the core site (`/snip-story`) requires the user to be logged in.

---

## Part 1: news.ycombinator.com

### Navigation Flows (SSR — No XHR/Fetch)

All the flows below produce **full-page HTML GET requests**. There are no client-side data fetches involved.

| Operation | URL Pattern | Notes |
|-----------|-------------|-------|
| Homepage load | `GET /` | Returns 30 top stories |
| New submissions | `GET /newest` | Latest submissions, reverse chronological |
| Past front pages | `GET /front?day=YYYY-MM-DD` | Front page for a specific day |
| Ask HN | `GET /ask` | Ask HN posts only |
| Show HN | `GET /show` | Show HN posts only |
| Jobs | `GET /jobs` | Job listings |
| Comments feed | `GET /newcomments` | Latest comments across all posts |
| Post + comments | `GET /item?id={id}` | Full post with nested comment thread |
| User profile | `GET /user?id={username}` | User profile and submitted links |
| Submitted by user | `GET /submitted?id={username}` | All stories submitted by a user |
| More (pagination) | `GET /?p={page}` or `GET /newest?next={id}&n={rank}` | Numbered pages for top; cursor-based for newest |
| Source domain filter | `GET /from?site={domain}` | All stories from a given domain |

### JavaScript-Driven Interactions (non-XHR side channels)

These are triggered by JS but use `new Image().src` rather than `fetch()` — they fire a GET request as a side effect but are **not detectable via XHR/Fetch interception**:

| Operation | URL Pattern | Mechanism |
|-----------|-------------|-----------|
| Upvote / unvote | `GET /vote?id={id}&how={up\|un}&auth={token}&goto={page}&js=t` | `new Image().src` |
| Comment collapse / expand | `GET /collapse?id={commentId}&un=true` | `new Image().src` (logged-in only) |

### The One Real Fetch Call

This is the **only `fetch()` call** on the core site, and it only fires when logged in:

| Operation | Method | Endpoint | Purpose |
|-----------|--------|----------|---------|
| Hide story (on "newest" page) | GET via `fetch()` | `/snip-story?id={id}&onop=newest&next={nextId}` | Removes hidden story from DOM; server returns JSON `[html_snippet, next_story_id]` to fill in the gap |

The JS source (`hn.js`) shows:
```js
function hidestory(el, id) {
  var url = el.href.replace('hide', 'snip-story').replace('goto', 'onop');
  fetch(url + next).then(r => r.json()).then(newstory);
}
```

The response is a JSON array: `[htmlString, nextStoryId]`. The HTML string is inserted into the DOM and the "More" link cursor is updated.

---

## Part 2: hn.algolia.com (HN Search)

HN search is a separate Algolia-powered SPA at `hn.algolia.com`. All search queries go through a single endpoint with parameters in the POST body.

### Core Search Endpoint

```
POST https://uj5wyc0l7x-dsn.algolia.net/1/indexes/{index}/query
  ?x-algolia-api-key=28f0e1ec37a5e792e6845e67da5f20dd
  &x-algolia-application-id=UJ5WYC0L7X
```

The **index name** encodes the sort order:

| Sort | Index Name |
|------|-----------|
| Popularity (default) | `Item_dev` |
| Date (newest first) | `Item_dev_sort_date` |

All other parameters (query text, type filter, page, date range) are in the **POST request body** — not in the URL.

### URL State (Client-Side Routing)

The Algolia SPA reflects all search state in the URL:

```
https://hn.algolia.com/?q={query}&type={type}&sort={sort}&page={n}&dateRange={range}
```

| Parameter | Values |
|-----------|--------|
| `type` | `story`, `comment`, `ask_hn`, `show_hn`, `launch_hn`, `job`, `poll` (or omit for all) |
| `sort` | `byPopularity` → index `Item_dev`; `byDate` → index `Item_dev_sort_date` |
| `page` | 0-indexed page number (in POST body, not Algolia index) |
| `dateRange` | `all`, `last24h`, `pastWeek`, `pastMonth`, `pastYear` |

### Operation → API Call Mapping

| Operation | Endpoint | Notes |
|-----------|----------|-------|
| Initial search page load | `POST /1/indexes/Item_dev/query` | One query on page load |
| Typing (live search) | `POST /1/indexes/{index}/query` | Fires on **every keystroke** (debounced); returns matching stories/comments |
| Change type filter (e.g. Stories → Comments) | `POST /1/indexes/{index}/query` | Type constraint goes in POST body |
| Change sort (Popularity → Date) | `POST /1/indexes/Item_dev_sort_date/query` | Index name switches; POST body updated |
| Change date range | `POST /1/indexes/{index}/query` | `numericFilters` param in POST body changes |
| Pagination (click page N) | `POST /1/indexes/{index}/query` | `page` param in POST body increments |

### Supporting Endpoint

| Endpoint | Purpose |
|----------|---------|
| `GET https://hn.algolia.com/popular.json` | Fetches popular/trending search queries (loaded periodically for suggestions display) |

### Infrastructure / Noise Endpoints (Filter Out)

| Endpoint | Purpose |
|----------|---------|
| `GET https://telemetry.algolia.com/1/settings?applications=...` | Algolia client telemetry / SDK settings |
| `GET https://{node}.algolia.net/1/isalive?probe=1` | DSN health probes — Algolia client checks multiple regional nodes (USW, EU, IN) to find the fastest |
| `POST https://www.google-analytics.com/...` | Google Analytics pageview tracking |

---

## Key URL / Endpoint Summary

```
# HN core — all SSR, full-page HTML GETs
GET https://news.ycombinator.com/
GET https://news.ycombinator.com/newest
GET https://news.ycombinator.com/item?id={id}
GET https://news.ycombinator.com/user?id={username}
GET https://news.ycombinator.com/?p={page}
GET https://news.ycombinator.com/newest?next={id}&n={rank}

# HN core — side-channel fire-and-forget (new Image(), not XHR/Fetch)
GET https://news.ycombinator.com/vote?id={id}&how={up|un}&auth={token}&goto={page}&js=t
GET https://news.ycombinator.com/collapse?id={commentId}&un=true

# HN core — the one real Fetch (logged-in only)
GET https://news.ycombinator.com/snip-story?id={id}&onop={page}&next={nextId}
  → returns JSON: [htmlString, nextStoryId]

# HN Algolia search — all via POST body, no URL params for query
POST https://uj5wyc0l7x-dsn.algolia.net/1/indexes/Item_dev/query          # Popularity sort
POST https://uj5wyc0l7x-dsn.algolia.net/1/indexes/Item_dev_sort_date/query # Date sort

# HN Algolia — popular queries
GET https://hn.algolia.com/popular.json
```

---

## Key Findings vs Reddit

| Dimension | HN (news.ycombinator.com) | Reddit (shreddit) |
|-----------|--------------------------|-------------------|
| Architecture | Pure SSR MPA | SSR + partial hydration (hybrid) |
| XHR/Fetch for navigation | None | None (full HTML GETs) |
| XHR/Fetch for dynamic content | 1 (hide story, logged-in only) | Many (`/svc/shreddit/` partials, more-comments, feed pagination) |
| Comment loading | Full page reload | Incremental fetch via `POST /svc/shreddit/more-comments/...` |
| Search | Separate SPA at hn.algolia.com | Partial (`GET /svc/shreddit/r/{sub}/search/`) embedded in main site |
| Vote mechanism | `new Image().src` (side channel) | Full redirect (logged-out); likely AJAX when logged in |
| API style | No public-facing data API on the main site | `/svc/shreddit/` REST-style partial-render endpoints + GraphQL |

HN is deliberately minimal — the site has barely changed in a decade, and almost everything is server-rendered. The search is entirely delegated to a third-party Algolia SPA.
