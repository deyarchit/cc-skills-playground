# API Map: MSN

**URL:** https://www.msn.com
**Rendering architecture:** Hybrid (SPA shell with SSR-assisted content)
**Auth state:** Logged out (anonymous) — signed-in flows (personalized feed, saved content, following topics/stocks) have anonymous fallbacks that 404 or return empty
**Date captured:** 2026-03-13

---

## Shared Infrastructure (fires on every page)

| Method | Endpoint Pattern | Purpose |
|--------|-----------------|---------|
| GET | `assets.msn.com/resolver/api/resolve/v3/config/?expType=AppConfig&apptype={page_type}` | Per-page A/B experiment config and feature flags |
| GET | `assets.msn.com/service/msn/user?user={user_id}` | User profile fetch (→ 404 for anonymous) |
| GET | `assets.msn.com/content/v1/cms/api/amp/Document/{doc_id}` | CMS document (promo banners, editorial config) |
| GET | `assets.msn.com/service/segments/recoitems/weather?days={n}&pageOcid={page}` | Weather widget card data (appears in sidebar of every page) |
| POST | `ib.msn.com/ut/v3` | Identity/audience matching (Universal Tag) |
| POST | `browser.events.data.microsoft.com/OneCollector/1.0/` | Client telemetry / diagnostics |
| POST | `login.microsoftonline.com/common/instrumentation/reportstaticmecontroltelemetry` | Azure AD login control telemetry |

---

## Data Endpoints by Flow

### Home Page Load

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `assets.msn.com/service/news/feed/pages/weblayout?newsSkip=0&newsTop=48&column=c3` | `newsSkip=0` (initial) | Homepage news feed with ad-layout metadata |
| GET | `assets.msn.com/service/news/feed?query=topstories&$top=1` | `query=topstories` | Headline ticker feed (top 1 story, used in header bar) |
| GET | `assets.msn.com/service/Finance/Charts?ids={ids}&type=1D1M` | — | Intraday + 1-month chart data for homepage market tickers |
| GET | `assets.msn.com/service/Finance/ExchangeStatistics?ids={exchange_ids}` | — | Exchange-level market statistics (e.g. NASDAQ) |
| GET | `prod-streaming-video-msn-com.akamaized.net/v1/{region}/{session_id}/{file_id}_650.mp4` | — | Auto-playing hero video (Akamai CDN, range requests) |

---

### Home Feed — Infinite Scroll (Pagination)

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `assets.msn.com/service/news/feed/pages/weblayout?$skip={page}&newsSkip={offset}` | `$skip` + `newsSkip` | Subsequent pages of home feed; first scroll → `$skip=1&newsSkip=37` |

**Key pagination params:**
- `$skip`: page number (0-indexed, first fetch omits it)
- `newsSkip`: article offset cursor from prior response
- `cardsServed`, `lastcardrank`: client-state bookkeeping sent back on scroll

---

### Search

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `assets.msn.com/service/news/feed/segments/autosuggest?q={query}&market=en-us` | `q=` | MSN news-aware search autosuggest (fires per-keystroke) |
| GET | `www.bing.com/AS/Suggestions/v2?qry={query}&cp={cursor_pos}&pt=msnedgentp` | `qry=` | Bing web-search suggestions (fires per-keystroke in parallel) |
| — | `www.bing.com/search?q={query}&form=MSNSB1` | — | **Submit redirects to bing.com** — search results are served by Bing, not MSN |

**Post-redirect (bing.com):**
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `www.bing.com/instantsearch/getquerylist?query={query}` | Inline answer / entity card |
| GET | `www.bing.com/geolocation/write` | Write detected geo to Bing session |
| POST | `www.bing.com/rewardsapp/reportActivity` | Log search for Bing Rewards |
| POST | `www.bing.com/mysaves/collections/get` | Load saved video/content collections |

---

### News Topic / Channel Page (`/en-us/channel/topic/{name}/tp-{id}`)

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `assets.msn.com/service/msn/topics?ids={topic_id}&followersCount=true` | `ids=` | Topic metadata (name, follower count, card config) |
| GET | `assets.msn.com/service/news/feed/pages/fullchannelpage?TopicId={topic_id}` | `TopicId=` | Full topic feed with promoted and organic articles |
| GET | `assets.msn.com/service/segments/recoitems/weather?pageOcid=peregrine&source=channel_csr` | `source=channel_csr` | Weather sidebar for channel pages |

---

### News Article Detail (`/en-us/news/{category}/{slug}/ar-{id}` or `vi-{id}`)

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `assets.msn.com/content/view/v2/Detail/en-us/{article_id}` | — | Full article content payload |
| GET | `assets.msn.com/service/news/feed/pages/viewsfullpage?contentId={id}&pageIndex={n}` | `pageIndex=` | Related articles feed (infinite scroll on article page; `pageIndex` increments) |
| GET | `assets.msn.com/content/view/v2/provider/en-us/{provider_id}` | — | Publisher/provider card metadata |
| GET | `assets.msn.com/service/community/users/{user_vid}?profile=social` | — | Community user avatar + display name |
| GET | `assets.msn.com/service/community/urls/?cmsid={article_id}&cmsUpdate={timestamp}` | — | Comment count + social share stats for article |
| GET | `assets.msn.com/service/Graph/Actions?$filter=actionType eq 'More' and targetId eq '{provider_id}'` | `actionType=More` | Whether user follows this publisher |

---

### Sports Section (`/en-us/sports`)

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `assets.msn.com/resolver/api/resolve/v3/config/?expType=SportsLayoutRenderer&apptype=sports` | `expType=SportsLayoutRenderer` | Sports page layout config |
| GET | `assets.msn.com/service/graph/actions?$filter=actionType eq 'Follow'&ocid=sports-league-landing` | `ocid=sports-league-landing` | User's followed sports/leagues |
| GET | `assets.msn.com/service/news/feed?ids={interest_id}&query=myFeed&queryType=myFeed&contentType=article,video` | `query=myFeed` | Initial sports articles (top 8) |
| GET | `assets.msn.com/service/news/feed/pages/ntpxfeed?InterestIds={interest_id}&newsSkip=8` | `InterestIds=` | Sports NTP extended feed (pagination from 8 onwards) |

---

### Weather Section (`/en-us/weather`)

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `assets.msn.com/service/weather/overview?days=10&lifeDays=2&insights=65536` | — | Full weather overview: 10-day forecast, life tips, storm alerts |
| GET | `assets.msn.com/service/weather/locations/search?lat={lat}&lon={lon}&locale=en-us` | — | Reverse-geocode device location to weather location name |
| GET | `assets.msn.com/weathermapdata/1/nowcastmap/{timestamp}/Sbn/{zoom}/{x}_{y}_{zoom}_{timestamp}.blc` | — | Radar nowcast map tiles (binary format, tiled by x/y/zoom) |
| POST | `assets.msn.com/service/msn/user` | — | Persist location preference to user profile |

---

### Finance / Money Section (`/en-us/money`)

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `assets.msn.com/service/Finance/Quotes?ids={comma_sep_ids}` | `ids=` | Real-time quotes for multiple tickers (batched) |
| GET | `assets.msn.com/service/Finance/QuoteSummary?ids={id}&intents=Charts,Exchanges&type=1D1M` | `intents=` | Quote detail with chart + exchange context |
| GET | `assets.msn.com/service/Finance/Exchanges?ids={exchange_ids}` | — | Exchange-level market data (open/close, status) |
| GET | `assets.msn.com/service/Finance/Charts?ids={id}&type=1D1M&chartflag=7` | `type=` | Price chart time-series data |
| GET | `assets.msn.com/service/Finance/ExchangeStatistics?ids={ids}` | — | Market-wide statistics per exchange |
| GET | `assets.msn.com/service/Finance/Calculator/CurrenciesStaticData?localizeFor=en-us` | — | Currency list for converter widget |
| GET | `assets.msn.com/service/MSN/Feed/me?query=marketbrief&ocid=finance-data-feeds` | `query=marketbrief` | Curated market brief news (top 12) |
| GET | `assets.msn.com/service/MSN/Feed/me?query=finance_latest&ocid=finance-verthp-feeds` | `query=finance_latest` | Latest finance news (top 30) |
| GET | `assets.msn.com/service/MSN/Feed/me?query=finance_news&ocid=finance-verthp-feeds` | `query=finance_news` | Finance news with info-pane cards |
| GET | `assets.msn.com/service/graph/actions?$filter=actionType eq 'Follow' and targetType eq 'Finance'` | `targetType=Finance` | User's followed stocks/companies |

---

### Video / Watch Section (`/en-us/video`)

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `assets.msn.com/service/MSN/Feed/me?query=WATCH&contentType=video&ocid=watch` | `query=WATCH` | Video feed (top 5 autoplay queue) |
| GET | `assets.msn.com/content/view/v2/Detail/en-us/{video_id}` | — | Video detail payload (same endpoint as articles) |
| GET | `assets.msn.com/service/MSN/User/me/SavedContent?$top=200&$select=title,id,url,images,...` | — | User's saved/bookmarked content (videos + articles) |
| GET | `assets.msn.com/service/community/users/{user_vid}?profile=social` | — | Publisher/user social card for video attribution |

---

## URL Pattern Summary

```
# Config / A/B
GET  assets.msn.com/resolver/api/resolve/v3/config/          # page config + feature flags

# News feeds
GET  assets.msn.com/service/news/feed                        # top stories, sports feed
GET  assets.msn.com/service/news/feed/pages/weblayout        # homepage feed (paginated)
GET  assets.msn.com/service/news/feed/pages/fullchannelpage  # topic/channel feed
GET  assets.msn.com/service/news/feed/pages/ntpxfeed         # NTP extended feed
GET  assets.msn.com/service/news/feed/pages/viewsfullpage    # article related feed
GET  assets.msn.com/service/news/feed/segments/autosuggest   # search autocomplete

# Content
GET  assets.msn.com/content/view/v2/Detail/en-us/{id}        # article or video detail
GET  assets.msn.com/content/view/v2/provider/en-us/{id}      # publisher card
GET  assets.msn.com/content/v1/cms/api/amp/Document/{id}     # CMS editorial document

# Finance
GET  assets.msn.com/service/Finance/Quotes                   # real-time quotes (batched)
GET  assets.msn.com/service/Finance/QuoteSummary             # quote + chart + exchange
GET  assets.msn.com/service/Finance/Charts                   # price chart time-series
GET  assets.msn.com/service/Finance/Exchanges                # exchange market data
GET  assets.msn.com/service/Finance/ExchangeStatistics       # exchange-level stats
GET  assets.msn.com/service/Finance/Calculator/CurrenciesStaticData

# Weather
GET  assets.msn.com/service/weather/overview                 # 10-day forecast
GET  assets.msn.com/service/weather/locations/search         # reverse-geocode
GET  assets.msn.com/weathermapdata/1/nowcastmap/...          # radar map tiles

# Personalisation / social graph
GET  assets.msn.com/service/msn/topics                       # topic metadata
GET  assets.msn.com/service/msn/user                         # user profile
POST assets.msn.com/service/msn/user                         # persist user prefs
GET  assets.msn.com/service/graph/actions                    # follows (topics, stocks, publishers)
GET  assets.msn.com/service/Graph/Actions                    # same, different casing variant
GET  assets.msn.com/service/MSN/Feed/me                      # personalised content feed
GET  assets.msn.com/service/MSN/User/me/SavedContent         # saved/bookmarked content

# Community / social
GET  assets.msn.com/service/community/users/{vid}            # community user profile
GET  assets.msn.com/service/community/urls/                  # comment count + share stats

# Segments / reco
GET  assets.msn.com/service/segments/recoitems/weather       # weather sidebar widget

# Telemetry (not content)
POST ib.msn.com/ut/v3                                        # identity / audience matching
POST browser.events.data.microsoft.com/OneCollector/1.0/     # telemetry
```

---

## Subdomain / Third-Party SPAs

| Domain | Feature | Notes |
|--------|---------|-------|
| `www.bing.com` | Search results | Full SPA — search submit navigates to bing.com; separate mapping needed for SERP flows |
| `prod-streaming-video-msn-com.akamaized.net` | Video CDN | Akamai CDN for .mp4 delivery (range requests) |
| `acdn.adnxs.com` | Ad sync | AppNexus/Xandr DMP iframe for user ID syncing |

---

## Gaps & Notes

- **Auth-gated flows not captured:** Follow/unfollow topic, save article, personalized feed differences for signed-in users. The `service/msn/user` endpoint returned 404 for anonymous users, but a 201 POST response was observed on the weather page (suggesting the session was partially initialised mid-session).
- **Finance stock detail page not captured separately:** `QuoteSummary` and `Charts` endpoints were observed from the Money landing page; clicking a specific ticker would likely add `/en-us/money/stocks/stock-price/{ticker}` page and may fire additional `QuoteSummary` calls with different `intents=` values.
- **Comments thread not loaded:** `service/community/urls/` returns comment counts; the full comment thread likely loads from a different endpoint (possibly Livefyre or similar) on article detail expansion — not triggered in this session.
- **Streaming video metadata:** The `.mp4` requests go directly to Akamai CDN. No separate manifest/HLS endpoint was observed (no `.m3u8`); MSN uses progressive MP4 download for short hero videos.
- **`ib.msn.com/ut/v3` POST body not inspected** — this is the Universal Tag endpoint used for audience matching; body likely contains user segment data.
