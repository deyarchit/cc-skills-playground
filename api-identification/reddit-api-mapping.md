# Reddit API Calls Mapping

> Observed via Playwright network interception on reddit.com (March 2026, logged-out session).
> Reddit uses the `shreddit` frontend (custom web components, SSR + partial hydration).

---

## Architecture Notes

- Reddit navigation is **full-page SSR** for most route changes (not pure SPA client-side routing).
- After SSR load, dynamic content (pagination, comments expansion) is fetched via dedicated partial-render endpoints under `/svc/shreddit/`.
- GraphQL (`POST /svc/shreddit/graphql`) is used for supplemental data (e.g. user identity, community metadata).
- Video is served from a separate CDN (`v.redd.it`) using HLS/CMAF streaming.

---

## Operation → API Call Mapping

### 1. Homepage Load (`reddit.com/`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Feed data | GET | `/svc/shreddit/feeds/popular-feed?after=...&distance=4&adDistance=2&navigationSessionId=...&sort=BEST` | Fetches additional post cards for the popular feed (triggered on scroll) |
| Left nav | GET | `/svc/shreddit/partial/J7VVLM/common-left-nav?data={"selectedPageType":"popular"}` | Fetches rendered HTML for left sidebar navigation |
| GraphQL | POST | `/svc/shreddit/graphql` | Supplemental data (user state, community info) |

---

### 2. Homepage Scroll (Feed Pagination)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Load more posts | GET | `/svc/shreddit/feeds/popular-feed?after={cursor}&distance=33&adDistance=3&cursor={cursor}&sort=BEST` | Fetches next batch of posts; `after` is a base64 cursor |

---

### 3. Open a Post (`/r/{subreddit}/comments/{id}/{slug}/`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Full page | GET | `/r/{subreddit}/comments/{id}/{slug}/` | Full SSR HTML for the post + initial comments |
| Left nav partial | GET | `/svc/shreddit/partial/J7VVLM/common-left-nav?data={"selectedPageType":"post_detail"}&params=prefix%3Dr%26subreddit%3D{sub}%26postId%3D{id}` | Left sidebar for post detail context |
| GraphQL | POST | `/svc/shreddit/graphql` | Supplemental post/community metadata |

---

### 4. Scroll in Post (Load More Top-Level Comments)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| More comments | POST | `/svc/shreddit/more-comments/{subreddit}/t3_{postId}?seeker-session=false&render-mode=partial&referer=...&top-level=1&comments-remaining={N}` | Fetches the next batch of top-level comment HTML; returns partial rendered HTML |

---

### 5. Expand Nested Replies ("N more replies" button)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| More replies | POST | `/svc/shreddit/more-comments/{subreddit}/t3_{postId}?sort=CONFIDENCE&startingDepth={depth}` | Fetches nested reply HTML at a given thread depth |

---

### 6. Navigate to a Subreddit (`/r/{subreddit}/`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Subreddit page | GET | `/r/{subreddit}/` | Full SSR HTML for subreddit feed (default sort) |
| GraphQL | POST | `/svc/shreddit/graphql` | Community metadata, user subscription status |
| Video autoplay | GET | `https://v.redd.it/{videoId}/HLSPlaylist.m3u8` | HLS manifest for autoplaying video posts |
| Video segments | GET | `https://v.redd.it/{videoId}/CMAF_{quality}.mp4` | Video/audio segments streamed via byte-range requests (206) |

---

### 7. Change Sort Order (e.g. Best → New)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Sorted page | GET | `/r/{subreddit}/{sort}/` | Full SSR HTML for subreddit with new sort (e.g. `/new/`, `/hot/`, `/top/`, `/rising/`) |
| Community more posts | GET | `/svc/shreddit/community-more-posts/{sort}/?after={cursor}&t=DAY&name={subreddit}&adDistance=1&ad_posts_served=N&navigationSessionId=...&feedLength=N` | Pagination for community feed posts under a sort |

---

### 8. Search (Typing in Search Box → Submit)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Typeahead suggestions | GET | `/svc/shreddit/r/{subreddit}/search-typeahead?query={query}&cId={sessionId}` | Autocomplete/suggestion results while typing |
| Search results page | GET | `/r/{subreddit}/search/?q={query}&cId=...&iId=...` | Full SSR HTML for search results page |
| GraphQL | POST | `/svc/shreddit/graphql` | Supplemental data for search context |

---

### 9. Scroll Search Results (Search Pagination)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| More results | GET | `/svc/shreddit/r/{subreddit}/search/?q={query}&cursor={base64cursor}&cId=...&iId=...` | Next page of search results; `cursor` encodes pipeline state |

---

## Non-Data / Infrastructure Endpoints (Filtered Out)

These fire on almost every action and are not content-fetching:

| Endpoint | Purpose |
|----------|---------|
| `POST /svc/shreddit/events` | Client-side analytics / event tracking |
| `POST /alb.reddit.com/track` | Additional analytics tracking |
| `GET /svc/shreddit/update-recaptcha?k=...` | reCAPTCHA token refresh (key contains page context) |
| `GET /svc/shreddit/styling-overrides/?v=0` | Per-subreddit CSS overrides |
| `GET /svc/shreddit/data-protection-consent` | GDPR / consent state |
| `POST /w3-reporting.reddit.com/reports` | Browser CSP violation reports |
| `GET /w3-reporting.reddit.com/policy` | CSP reporting policy endpoint |
| `POST /*.google.com/recaptcha/...` | Google reCAPTCHA enterprise |
| `POST /*.google.com/ccm/collect` | Google Analytics page view |

---

## Key URL Patterns Summary

```
# Feed pagination
GET /svc/shreddit/feeds/popular-feed?after={cursor}&sort={BEST|HOT|NEW|TOP}&...

# Subreddit feed pagination (within a community)
GET /svc/shreddit/community-more-posts/{sort}/?after={cursor}&name={subreddit}&...

# Comments (top-level, on scroll)
POST /svc/shreddit/more-comments/{subreddit}/t3_{postId}?top-level=1&comments-remaining={N}&...

# Comments (nested replies, on click)
POST /svc/shreddit/more-comments/{subreddit}/t3_{postId}?sort=CONFIDENCE&startingDepth={N}

# Search typeahead
GET /svc/shreddit/r/{subreddit}/search-typeahead?query={q}&cId={id}

# Search results pagination
GET /svc/shreddit/r/{subreddit}/search/?q={q}&cursor={base64}&cId={id}&iId={id}

# Left nav partial (context-aware)
GET /svc/shreddit/partial/J7VVLM/common-left-nav?data={json}&params={urlencoded}&sig={hmac}

# GraphQL (multi-purpose)
POST /svc/shreddit/graphql

# Video (HLS)
GET https://v.redd.it/{videoId}/HLSPlaylist.m3u8
GET https://v.redd.it/{videoId}/CMAF_{480|720|1080}.m3u8
GET https://v.redd.it/{videoId}/CMAF_AUDIO_128.m3u8
GET https://v.redd.it/{videoId}/CMAF_{quality}.mp4  (byte-range 206)
```
