# API Map: Yahoo

**URL:** https://www.yahoo.com
**Rendering architecture:** Hybrid SPA (Next.js React Server Components + client-side data fetching)
**Auth state:** Logged out — personalized flows (My Teams, My Portfolio, notifications) may differ when logged in
**Date captured:** 2026-03-12

---

## Data Endpoints

### Homepage: Initial Page Load

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `ncp-gw-frontpage.media.yahoo.com/api/v1/gql/stream_view?count=1&id=ntk-assetlist-stream&listId={listId}&namespace=media&site=news&version=v1` | `id=ntk-assetlist-stream` | Need-to-Know (NTK) asset list — initial 1-item check |
| GET | `ncp-gw-frontpage.media.yahoo.com/api/v1/gql/stream_view?count=20&id=ntk-assetlist-stream&listId={listId}&namespace=media&site=frontpage&version=v1` | `id=ntk-assetlist-stream`, `count=20` | NTK widget top stories |
| POST | `ncp-gw-frontpage.media.yahoo.com/api/v1/gql/stream_view?id=ntk-main-stream&namespace=frontpage&count=170&version=v2` | `id=ntk-main-stream` | Main homepage feed (large initial batch, includes `bucketId` A/B test params) |
| GET | `ncp-gw-frontpage.media.yahoo.com/api/v1/gql/stream_view?id=shopping-list&namespace=news&count=6&version=v1` | `id=shopping-list` | Shopping/product carousel |
| POST | `nexus-gateway-prod.media.yahoo.com/` | (GraphQL — body not captured) | GraphQL gateway — fires multiple times on load for various modules |
| POST | `signal-service.pbs.yahoo.com/v1/signal/refresh` | — | Prebid user signal refresh |
| GET | `s.yimg.com/eh/prebid-config/bp-fp.json` | — | Prebid ad configuration |

### Homepage: Feed Pagination (Scroll)

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| POST | `ncp-gw-frontpage.media.yahoo.com/api/v1/gql/stream_view?id=ntk-main-stream&pageIndex=0&listStartIndex=11&count=170&version=v2` | `pageIndex`, `listStartIndex` | Paginated feed load — `pageIndex` and `listStartIndex` are the pagination cursors |
| GET | `ncp-gw-frontpage.media.yahoo.com/api/v1/gql/stream_view?configId=breaking-news&id=breakingnews&count=1` | `id=breakingnews` | Breaking news banner widget refresh |

### Homepage: RSC Article Prefetch

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `www.yahoo.com/{section}/articles/{slug}?_rsc={hash}` | `_rsc` query param | React Server Component prefetch — fires for visible feed articles; returns RSC payload (not full HTML) |

---

### Search: Typeahead

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `search.yahoo.com/sugg/gossip/gossip-us-fastbreak?command={query}&appid=yfp-t&output=sd1&f=1&.crumb={crumb}&t_stmp={ts}` | `command` param increments per keystroke | Search autocomplete suggestions — fires per keystroke with debounce; early keystrokes return `net::ERR_ABORTED` (race-cancelled) |

### Search: Submit

| Method | Endpoint Pattern | Purpose |
|--------|-----------------|---------|
| GET | `search.yahoo.com/search?p={query}&fr=yfp-t&fr2=p%3Afp%2Cm%3Asb&fp=1` | Full search results page (new tab navigation — `search.yahoo.com` is a separate SPA) |

---

### News: Article Page

| Method | Endpoint Pattern | Purpose |
|--------|-----------------|---------|
| GET | `www.yahoo.com/caas/content/article/commentsCount/?features=enableCommentsCountRouteViaOpenweb&uuid={uuid}` | Article comment count (OpenWeb integration) |
| GET | `ncp-gw-frontpage.media.yahoo.com/api/v1/gql/stream_view?configId=breaking-news&id=breakingnews&count=1` | Breaking news ticker on article pages |
| POST | `nexus-gateway-prod.media.yahoo.com/` | GraphQL — article-related modules (related stories, etc.) |
| GET | `manifest.prod.boltdns.net/manifest/v1/hls/v5/clear/{accountId}/{videoId}/{renditionId}/6s/rendition.m3u8?fastly_token={token}` | Brightcove HLS video rendition manifest |
| GET | `edge.api.brightcove.com/playback/v1/accounts/{accountId}/videos/{videoId}/master.m3u8?bcov_auth={jwt}` | Brightcove master video manifest (JWT-authenticated) |

---

### Finance: Homepage

| Method | Endpoint Pattern | Purpose |
|--------|-----------------|---------|
| GET | `query1.finance.yahoo.com/v1/test/getcrumb` | Fetch auth crumb (required for all subsequent Finance API calls) |
| GET | `finance.yahoo.com/xhr/i18n?pages=common,home&lang=en-US&v={buildTs}` | i18n strings for Finance UI |
| GET | `query1.finance.yahoo.com/v1/finance/screener/predefined/saved?scrIds=MOST_ACTIVES&count=200&fields=symbol,shortName` | Most Active stocks screener |
| GET | `query1.finance.yahoo.com/v7/finance/quote?symbols={symbols}&fields={fields}&crumb={crumb}&region=US&lang=en-US` | Multi-symbol real-time quote data (markets bar, tickers) |
| POST | `query1.finance.yahoo.com/v1/finance/visualization?lang=en-US&region=US&crumb={crumb}` | Finance visualization / chart config data |
| POST | `finance.yahoo.com/nimbus_ms/remote?ctrl=notification-panel&m_id=nimbus` | Notification panel data (server-side micro-service) |

### Finance: Stock Quote Page (`/quote/{symbol}`)

| Method | Endpoint Pattern | Purpose |
|--------|-----------------|---------|
| GET | `query2.finance.yahoo.com/v8/finance/chart/{symbol}?period1={ts}&period2={ts}&interval=1m&includePrePost=true&events=div\|split\|earn` | Intraday price chart data (OHLCV + events) |
| GET | `query2.finance.yahoo.com/v1/finance/quoteType/?symbol={symbol}&enablePrivateCompany=true` | Quote type metadata (equity/ETF/crypto/etc.) |
| GET | `query1.finance.yahoo.com/v7/finance/quote?symbols={symbol}&fields={fields}&crumb={crumb}` | Real-time quote fields for the symbol |
| GET | `query1.finance.yahoo.com/v2/ratings/top/{symbol}?exclude_noncurrent=true` | Analyst consensus ratings |
| GET | `query1.finance.yahoo.com/ws/insights/v3/finance/insights?symbols={symbol}&getAllResearchReports=true&reportsCount=4` | Research reports and AI insights |
| GET | `query1.finance.yahoo.com/ws/fundamentals-timeseries/v1/finance/timeseries/{symbol}?type=spEarningsReleaseEvents,analystRatings,economicEvents&period1={ts}&period2={ts}` | Earnings calendar & fundamentals timeseries |
| GET | `query1.finance.yahoo.com/ws/screeners/v1/finance/calendar-events?tickersFilter={symbol}&modules=earnings&startDate={ts}&endDate={ts}` | Upcoming earnings dates |
| POST | `finance.yahoo.com/xhr/ncp?queryRef=qsp&serviceKey=ncp_fin&symbols={symbol}&lang=en-US&region=US` | NCP content — news & analysis for this ticker |
| POST | `finance.yahoo.com/xhr/ncp?queryRef=qspVideos&serviceKey=ncp_fin&lang=en-US&region=US` | NCP video content for Finance |
| GET | `yfc-server-query.finance.yahoo.com/?query={graphql}&operationName=GetPostsForQsp&variables={"symbol":"{symbol}"}` | GraphQL — community posts for stock symbol (pagination via `cursor`) |
| GET | `finance.yahoo.com/xhr/i18n?pages=common,quote,leaf-chart&lang=en-US&v={buildTs}` | i18n strings for quote page UI |

---

### Sports: Homepage

| Method | Endpoint Pattern | Purpose |
|--------|-----------------|---------|
| GET | `graphite.sports.yahoo.com/v1/query/shangrila/navDropdownTray?lang=en-US&region=US&getSoccerData=true&soccerLeagueIds={ids}` | Navigation dropdown tray data (all sport leagues) |
| GET | `graphite.sports.yahoo.com/v1/query/shangrila/trendingGameIds?lang=en-US&region=US` | Trending game IDs |
| GET | `graphite.sports.yahoo.com/v1/query/shangrila/featuredGameIds?lang=en-US&region=US` | Featured / promoted game IDs |
| GET | `graphite.sports.yahoo.com/v1/query/shangrila/moduleGame?gameId={gameId}&lang=en-US&region=US` | Individual game module data (scores, status) — fires in parallel for each game |
| GET | `graphite.sports.yahoo.com/v1/query/shangrila/teamsBasic?teamIds={teamIds}&imageHeight=160&imageWidth=160` | Team info (logo, name, record) for multiple teams |
| GET | `graphite.sports.yahoo.com/v1/query/shangrila/nc/myTeams?imageWidth=48&imageHeight=48` | My Teams personalization data |
| GET | `sports.yahoo.com/api/watch/` | Watch tab — live/upcoming video content |
| POST | `sports.yahoo.com/api/content/` | Main sports content feed |
| GET | `mrest.sports.yahoo.com/api/v8/common/pills?teamIds={teamIds}&addTeamLogos=true` | Sport/league navigation pills |
| GET | `s.yimg.com/ba/sports:trending-teams_sports_US_en-US` | Trending teams static config (CDN-served) |
| GET | `s.yimg.com/ba/sports:trending-items_sports_US_en-US` | Trending items static config (CDN-served) |

---

## Telemetry & Analytics (Fire-and-Forget)

| Method | Endpoint | Purpose |
|--------|---------|---------|
| POST | `udc.yahoo.com/v2/public/yql?yhlClient=rapid&yhlS={spaceId}` | Yahoo UDC (Universal Data Collector) — page view and interaction events; fires on nearly every action; compressed payload (`yhlCompressed=3`) |
| POST | `trc.taboola.com/yahoo-home/trc/3/json` | Taboola recommendations engine — sends viewport/session state, receives recommendation config |
| POST | `pbd.yahoo.com/data/logs/taboola` | Yahoo proxy for Taboola logging events |

---

## Invisible / Non-XHR Patterns

| Pattern | Trigger | Notes |
|---------|---------|-------|
| `GET scorecardresearch.com/p?...&ns_st_ev=end` | Video play/pause | Comscore streaming tag — fire-and-forget video analytics beacon |

---

## Subdomain / Third-Party SPAs

| Domain | Feature | Architecture | Notes |
|--------|---------|--------------|-------|
| `search.yahoo.com` | Search results | Separate SPA | Opened in new tab on submit; requires separate mapping |
| `finance.yahoo.com` | Finance | Separate SPA | Own routing, crumb auth, uses `query1`/`query2` data APIs |
| `sports.yahoo.com` | Sports | Separate SPA | Dedicated `graphite.sports.yahoo.com` Shangrila API |
| `yfc-server-query.finance.yahoo.com` | Finance community | GraphQL | Used for community posts on quote pages; operationName-discriminated |

---

## URL Pattern Summary

```
# Homepage feed
GET  ncp-gw-frontpage.media.yahoo.com/api/v1/gql/stream_view   # GET variant: initial/widget loads
POST ncp-gw-frontpage.media.yahoo.com/api/v1/gql/stream_view   # POST variant: main feed + pagination
POST nexus-gateway-prod.media.yahoo.com/                        # GraphQL gateway (operationName in body)

# Article
GET  /caas/content/article/commentsCount/?uuid={uuid}           # Comment count
GET  /{section}/articles/{slug}?_rsc={hash}                     # RSC prefetch (Next.js)

# Search autocomplete
GET  search.yahoo.com/sugg/gossip/gossip-us-fastbreak?command={query}&appid=yfp-t

# Finance — auth
GET  query1.finance.yahoo.com/v1/test/getcrumb                  # Must call first to get crumb

# Finance — market data
GET  query{1,2}.finance.yahoo.com/v7/finance/quote?symbols={symbols}&crumb={crumb}
GET  query{1,2}.finance.yahoo.com/v8/finance/chart/{symbol}?interval=1m&period1={ts}&period2={ts}
GET  query1.finance.yahoo.com/v2/ratings/top/{symbol}
GET  query1.finance.yahoo.com/ws/insights/v3/finance/insights?symbols={symbol}
GET  query1.finance.yahoo.com/ws/fundamentals-timeseries/v1/finance/timeseries/{symbol}
GET  query1.finance.yahoo.com/ws/screeners/v1/finance/calendar-events?tickersFilter={symbol}
GET  query1.finance.yahoo.com/v1/finance/screener/predefined/saved?scrIds=MOST_ACTIVES
POST query1.finance.yahoo.com/v1/finance/visualization
POST finance.yahoo.com/xhr/ncp?queryRef={qsp|qspVideos}&serviceKey=ncp_fin&symbols={symbol}
GET  yfc-server-query.finance.yahoo.com/?operationName=GetPostsForQsp&variables={"symbol":"{symbol}"}

# Sports — Shangrila API
GET  graphite.sports.yahoo.com/v1/query/shangrila/navDropdownTray
GET  graphite.sports.yahoo.com/v1/query/shangrila/trendingGameIds
GET  graphite.sports.yahoo.com/v1/query/shangrila/featuredGameIds
GET  graphite.sports.yahoo.com/v1/query/shangrila/moduleGame?gameId={gameId}
GET  graphite.sports.yahoo.com/v1/query/shangrila/teamsBasic?teamIds={ids}
GET  graphite.sports.yahoo.com/v1/query/shangrila/nc/myTeams
POST sports.yahoo.com/api/content/
GET  sports.yahoo.com/api/watch/
GET  mrest.sports.yahoo.com/api/v8/common/pills?teamIds={ids}

# Video
GET  edge.api.brightcove.com/playback/v1/accounts/{accountId}/videos/{videoId}/master.m3u8?bcov_auth={jwt}
GET  manifest.prod.boltdns.net/manifest/v1/hls/v5/clear/{accountId}/{videoId}/{renditionId}/6s/rendition.m3u8

# Telemetry
POST udc.yahoo.com/v2/public/yql                                # Fires on nearly every action
```

---

## Gaps & Notes

- **Auth-gated flows not captured**: My Portfolio, My Teams customization, Fantasy Sports, Mail, and notification interactions all require a logged-in session. The `nc/myTeams` endpoint returned an empty/default response logged-out.
- **`nexus-gateway-prod.media.yahoo.com/` operationNames not fully identified**: This GraphQL gateway fires 4–6 POSTs on every page load. POST bodies were not captured in this session — a follow-up `inspect_post_bodies.js` run would reveal the `operationName` for each.
- **`ncp-gw-frontpage.media.yahoo.com/api/v1/gql/stream_view` discriminator**: Despite "gql" in the path, this is a parameterized REST endpoint. The `id` param (`ntk-main-stream`, `ntk-assetlist-stream`, `breakingnews`, `shopping-list`) is the key discriminator. The `version=v2` variant (main feed) uses POST; widget variants use GET.
- **Search results page** (`search.yahoo.com`) is a separate SPA and was not mapped — would require a dedicated session.
- **Finance crumb**: `query{1,2}.finance.yahoo.com` calls require a valid `crumb` token obtained from `GET /v1/test/getcrumb`. Crumbs appear session-scoped. `query1` and `query2` are load-balanced mirrors of the same API.
- **Sports Shangrila API** fires `moduleGame` in parallel for all visible game IDs — this is the deferred fragment pattern applied to game cards.
- **`_rsc` prefetch pattern**: Yahoo homepage prefetches article RSC payloads for visible cards using Next.js RSC. The hash in `?_rsc={hash}` is a build ID (constant per deploy), not a per-request token.
- **Taboola**: `trc.taboola.com` handles the recommendation engine; Yahoo proxies Taboola logging through `pbd.yahoo.com/data/logs/taboola` (likely to avoid ad-blocker interference).
