# API Map: Reddit

**URL:** https://www.reddit.com
**Rendering architecture:** Hybrid — SSR full-page loads + Shreddit partial hydration via `/svc/shreddit/` endpoints
**Auth state:** Logged out — auth-gated flows (vote, post, subscribe, awards) not captured
**Date captured:** 2026-03-13

---

## Data Endpoints

### Home Page Load

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/svc/shreddit/feeds/popular-feed?after={cursor}&distance={n}&adDistance={n}&navigationSessionId={uuid}&ad_posts_served={n}&cursor={cursor}&sort=BEST` | `sort=BEST` | Popular feed post cards; fires on initial load and scroll |
| GET | `/svc/shreddit/partial/{partialId}/common-left-nav?data={"selectedPageType":"popular"}` | `selectedPageType: popular` | Left sidebar HTML partial |

---

### Subreddit Listing Page

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/svc/shreddit/community-more-posts/{sort}/?after={cursor}&t={timeframe}&name={subreddit}&adDistance={n}&ad_posts_served={n}&navigationSessionId={uuid}&feedLength={n}` | path `{sort}` | Subreddit feed post cards; `sort` = `best`, `new`, `hot`, `top`; `t` = `DAY`, `WEEK`, `MONTH`, `YEAR`, `ALL` (only on `top`) |
| GET | `/svc/shreddit/partial/{partialId}/common-left-nav?data={"selectedPageType":"community"}&params=prefix%3Dr%26subredditName%3D{subreddit}%26sort%3D{sort}` | `selectedPageType: community` | Left sidebar HTML partial |

---

### Post Detail Page

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/svc/shreddit/partial/{partialId}/common-left-nav?data={"selectedPageType":"post_detail"}&params=prefix%3Dr%26subreddit%3D{subreddit}%26postId%3D{postId}%26slug%3D{slug}` | `selectedPageType: post_detail` | Left sidebar HTML partial with post context |

> Initial post content and comments are SSR'd — no client fetch for the post body or first comment batch.

---

### Comments — Load More Replies ("N more replies" button)

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| POST | `/svc/shreddit/more-comments/{subreddit}/t3_{postId}?sort=CONFIDENCE&startingDepth={depth}&seeker-session=true` | `startingDepth={n}` | Loads nested reply thread at the given depth; returns partial HTML |

---

### Subreddit Feed Pagination (Infinite Scroll)

Reuses the same `community-more-posts` endpoint as listing load (see above); subsequent scroll batches add `distance={n}` and increment `feedLength`.

---

### Search — Typeahead

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/svc/shreddit/r/{subreddit}/search-typeahead?query={q}&cId={uuid}` | scoped to subreddit | Autocomplete suggestions while typing in search box within a subreddit |

---

### Search — In-Subreddit Results

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/r/{subreddit}/search/?q={query}&cId={uuid}&iId={uuid}` | — | Full-page SSR HTML for initial subreddit search results |
| GET | `/svc/shreddit/r/{subreddit}/search/?q={query}&cursor={cursor}&cId={uuid}&iId={uuid}` | — | Paginated search results data; `cursor` is base64-encoded pipeline state JSON |

---

### Search — Global (All of Reddit)

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/search/?q={query}` | — | Full-page SSR HTML for initial global search results |
| GET | `/svc/shreddit/search/?q={query}&cursor={cursor}` | — | Paginated global search results (triggered on scroll) |
| GET | `/svc/shreddit/partial/{partialId}/common-left-nav?data={"selectedPageType":"search_results"}&query={"q":"{query}"}` | `selectedPageType: search_results` | Left sidebar HTML partial for search context |

---

### User Profile Page

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/svc/shreddit/verification-hover-card/{username}` | — | User identity/verification card (fires multiple times for each username mention on page) |
| GET | `/svc/shreddit/partial/{partialId}/profile-left-nav?params=username%3D{username}&sig={sig}` | — | Profile-specific left nav partial |
| GET | `/svc/shreddit/profiles/profile_overview-more-posts/new/?after={cursor}&name={username}&navigationSessionId={uuid}&feedLength={n}` | — | User post/comment feed |

---

### Shared / Cross-Page (GraphQL)

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| POST | `/svc/shreddit/graphql` | `operation: ExposeVariant` | A/B experiment variant exposure; fires once on home page load |
| POST | `/svc/shreddit/graphql` | `operation: CreateCaptchaToken` | Per-page reCAPTCHA token refresh; fires on every navigation |

> Reddit uses `operation` (not the standard `operationName`) as the discriminator field in GraphQL POST bodies.

---

### Video Streaming (v.redd.it)

| Method | Endpoint Pattern | Purpose |
|--------|-----------------|---------|
| GET | `https://v.redd.it/{videoId}/HLSPlaylist.m3u8?f={flags}&v=1&a={token}` | HLS manifest for autoplaying video posts |
| GET | `https://v.redd.it/{videoId}/CMAF_{quality}.m3u8` | Video quality stream playlist |
| GET | `https://v.redd.it/{videoId}/CMAF_AUDIO_{bitrate}.m3u8` | Audio stream playlist |
| GET | `https://v.redd.it/{videoId}/CMAF_{quality}.mp4` | Video segment (HTTP 206 byte-range) |
| GET | `https://v.redd.it/{videoId}/CMAF_AUDIO_{bitrate}.mp4` | Audio segment (HTTP 206 byte-range) |

---

## Infrastructure / Non-Data Endpoints

These fire on almost every navigation and are not content-fetching:

| Endpoint | Purpose |
|----------|---------|
| `POST /svc/shreddit/events` | Client-side analytics / interaction tracking |
| `POST alb.reddit.com/track` | Additional analytics pipeline |
| `GET /svc/shreddit/update-recaptcha?k={base64}` | reCAPTCHA token refresh; base64 key encodes page context |
| `GET /svc/shreddit/styling-overrides/?v=0` | Per-subreddit CSS theme overrides |
| `GET /svc/shreddit/data-protection-consent` | GDPR / consent check |
| `POST w3-reporting.reddit.com/reports` | Browser CSP violation reports |
| `GET w3-reporting.reddit.com/policy` | CSP reporting policy |
| `POST *.google.com/recaptcha/enterprise/...` | Google reCAPTCHA enterprise |
| `POST *.google.com/ccm/collect` | Google Analytics page view |
| `POST m.stripe.com/6` | Stripe telemetry (seen on profile pages) |

---

## URL Pattern Summary

```
# Popular feed (home)
GET  /svc/shreddit/feeds/popular-feed?after={cursor}&sort={BEST|HOT|NEW|TOP}&...

# Subreddit feed + pagination
GET  /svc/shreddit/community-more-posts/{best|new|hot|top}/?after={cursor}&name={subreddit}&t={DAY|WEEK|...}&...

# Comments (nested replies, click)
POST /svc/shreddit/more-comments/{subreddit}/t3_{postId}?sort=CONFIDENCE&startingDepth={n}&seeker-session=true

# Search typeahead (in-subreddit)
GET  /svc/shreddit/r/{subreddit}/search-typeahead?query={q}&cId={uuid}

# Search results data (in-subreddit, paginated)
GET  /svc/shreddit/r/{subreddit}/search/?q={q}&cursor={base64}&cId={uuid}&iId={uuid}

# Search results data (global, paginated)
GET  /svc/shreddit/search/?q={q}&cursor={base64}

# Left nav partial (context-aware across all page types)
GET  /svc/shreddit/partial/{partialId}/common-left-nav?data={json}&params={urlencoded}&sig={hmac}

# Profile feed
GET  /svc/shreddit/profiles/profile_overview-more-posts/new/?after={cursor}&name={username}&...

# GraphQL (infrastructure only — no content data)
POST /svc/shreddit/graphql  { operation: "ExposeVariant" | "CreateCaptchaToken" }

# Video (HLS/CMAF from v.redd.it CDN)
GET  https://v.redd.it/{videoId}/HLSPlaylist.m3u8
GET  https://v.redd.it/{videoId}/CMAF_{quality}.mp4   (206 byte-range)
GET  https://v.redd.it/{videoId}/CMAF_AUDIO_{bitrate}.mp4  (206 byte-range)
```

---

## Gaps & Notes

- **Auth-gated flows not captured**: vote, post submission, subscribe/join community, DMs, awards — all require a logged-in session.
- **Top-level comment scroll**: v1 documented `POST more-comments?top-level=1&comments-remaining={N}` for scrolling within a post. Not re-observed in this session (post had enough initial comments). Params may vary by comment count.
- **Global search typeahead**: only in-subreddit typeahead was observed (`/svc/shreddit/r/{subreddit}/search-typeahead`). Global search bar typeahead endpoint not confirmed.
- **`partialId` in left nav URL** (`J7VVLM`, `wgdQP7`, etc.) appears to be a static build hash, not a dynamic ID — same value reused across sessions on the same build.
