# YouTube API Calls Mapping

> Observed via Playwright (headed Chrome) network interception on youtube.com (March 2026, logged-out session).
> YouTube uses the **InnerTube** internal API (`/youtubei/v1/`) for all dynamic data fetching.

---

## Architecture Notes

- **Initial page loads are SSR** — the homepage (`/`), search results (`/results`), watch page (`/watch`), and channel pages (`/@handle`) all return fully server-rendered HTML with initial data embedded. No InnerTube `browse` or `search` call is made on first page load.
- **Infinite scroll / pagination** triggers `POST /youtubei/v1/browse` (channel feeds) or `POST /youtubei/v1/search` (search results), passing a `continuation` token in the JSON body.
- **Watch page recommendations and comments** both load via `POST /youtubei/v1/next`, using continuation tokens to page through content.
- **Video streaming** is handled by a separate CDN (`*.googlevideo.com/videoplayback`) using the **SABR** (Server-Adaptive Bitrate) protocol — POST requests carry segment-level feedback, not simple GET byte-range requests.
- **Search typeahead** fires on every keystroke to a separate subdomain: `suggestqueries-clients6.youtube.com`.
- The `guide` (sidebar nav) and `feedback` endpoints reload on every navigation.
- A **JWT/token refresh** service (`/api/jnn/v1/GenerateIT`) is called on each page load to rotate internal session tokens.

---

## Operation → API Call Mapping

### 1. Homepage Load (`youtube.com/`)

The homepage feed content is **embedded in the SSR HTML**. No InnerTube API call fetches the initial feed.

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Sidebar nav | POST | `/youtubei/v1/guide?prettyPrint=false` | Renders left nav (Home, Shorts, Subscriptions, You) |
| Feedback/dismissal | POST | `/youtubei/v1/feedback?prettyPrint=false` | Handles UI feedback actions (e.g. cookie consent) |
| Token rotation | POST | `/api/jnn/v1/GenerateIT` | Rotates internal session/SAPISIDHASH tokens |
| Analytics | POST | `/youtubei/v1/log_event?alt=json` | Client-side event telemetry |

> **Note:** For logged-out users with no history, the homepage shows "Try searching to get started" — no feed to paginate.

---

### 2. Search — Typeahead (Keystroke-by-Keystroke)

Fired on **every character typed** in the search box.

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Autocomplete | GET | `https://suggestqueries-clients6.youtube.com/complete/search?ds=yt&hl=en&gl=us&client=youtube&gs_ri=youtube&h=180&w=320&ytvs=1&gs_id={hex}&q={partial_query}&cp={cursor_position}` | Returns autocomplete suggestions for each keystroke; `gs_id` increments per keystroke (0,1,2…a,b,c…), `q` is the partial query, `cp` is cursor position |

**Key params:**
- `ds=yt` — dataset: YouTube
- `client=youtube` — client identifier
- `gs_id` — monotonically increasing session ID per keystroke (hex: 0–9, then a–z)
- `q` — current partial query string
- `cp` — cursor position (character index)

---

### 3. Search — Submit (Results Page)

Navigating to `/results?search_query={q}` returns SSR HTML with initial results. Scrolling triggers pagination.

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Initial results | *(SSR HTML)* | `GET /results?search_query={q}` | Full server-rendered search results page; initial batch embedded in HTML |
| Sidebar | POST | `/youtubei/v1/guide?prettyPrint=false` | Left nav refresh |
| Token | POST | `/api/jnn/v1/GenerateIT` | Token rotation |

---

### 4. Search Results — Scroll Pagination

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| More results | POST | `/youtubei/v1/search?prettyPrint=false` | Fetches next batch of search results; JSON body contains `{ "continuation": "<token>" }` encoding the page state |

Each scroll near the bottom fires one `search` POST. The continuation token is opaque and base64-encoded. Multiple pages are fetched as user scrolls.

---

### 5. Watch Page — Video Load (`/watch?v={videoId}`)

Initial page data (title, description, channel info, first batch of comments, first batch of recommendations) is **SSR-embedded**. After hydration:

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Recommendations + comments init | POST | `/youtubei/v1/next?prettyPrint=false` | Loads the right-panel "Up next" recommendations and initiates comment thread; body contains `{ "videoId": "..." }` |
| Account settings | POST | `/youtubei/v1/account/get_setting_values?prettyPrint=false` | Fetches user-specific settings (playback prefs, quality defaults) |
| Token | POST | `/api/jnn/v1/GenerateIT` | Token rotation |
| Video stream | POST | `https://{rr-node}.googlevideo.com/videoplayback?expire={ts}&ei={id}&ip={ip}&id={stream_id}&source=youtube&requiressl=yes&sabr=1&...` | Video/audio segment streaming via SABR protocol; POST body carries playback feedback, server adaptively responds with next segment |
| Playback start | GET | `/api/stats/playback?ns=yt&el=detailpage&cpn={id}&ver=2&...` | Reports playback start event (fires once, 204 response) |
| Watch time | GET | `/api/stats/watchtime?ns=yt&el=detailpage&cpn={id}&...&st={start}&et={end}` | Periodic watch-time heartbeat; `st`/`et` = segment start/end seconds |
| Quality of experience | POST | `/api/stats/qoe?fmt={itag}&afmt={audio_itag}&cpn={id}&el=detailpage&...` | Streaming quality telemetry (buffering, bandwidth, bitrate switches) |
| Ad stats | GET | `/api/stats/ads?ver=2&ns=1&event=2&content_v={videoId}&format={ad_format}&...` | Ad impression/view tracking |
| Ad playback | GET | `/api/stats/playback?ns=yt&el=adunit&cpn={ad_cpn}&...&adformat={format}` | Ad playback reporting |
| Ad watch time | GET | `/api/stats/watchtime?ns=yt&el=adunit&...&st={s}&et={e}` | Ad watch-time heartbeat |
| ATR (above fold) | POST | `/api/stats/atr?ns=yt&el=detailpage&cpn={id}&ver=2&...` | Above-the-fold render reporting |

**SABR videoplayback key params:**
- `expire` — token expiry unix timestamp
- `id` — stream object ID
- `source=youtube`
- `sabr=1` — Server-Adaptive Bitrate enabled
- `rqh=1` — request headers flag
- `c=WEB&cver=2.20260310.01.00` — client type and version
- `n` — throttle-bypass token (n-param)
- `sig` — HMAC signature
- `rn` — request number (increments per chunk)

---

### 6. Watch Page — Scroll (More Recommendations & Comments)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| More recommendations | POST | `/youtubei/v1/next?prettyPrint=false` | Loads additional "Up next" video cards; body: `{ "continuation": "<token>" }` |
| More comments | POST | `/youtubei/v1/next?prettyPrint=false` | Same endpoint — loads additional comment threads; distinguished by continuation token type in body |

The `next` endpoint serves **both** recommendations and comments — the response type is determined by the continuation token passed in the body, not a separate endpoint.

---

### 7. Channel Page Load (`/@{handle}` or `/@{handle}/videos`)

Initial channel page content (featured video, about, recent videos grid) is **SSR-rendered**. A channel trailer/featured video autoplays silently.

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Autoplay player | POST | `/youtubei/v1/player?prettyPrint=false` | Fetches player config + stream URLs for the channel's featured/trailer video |
| Account settings | POST | `/youtubei/v1/account/get_setting_values?prettyPrint=false` | User settings |
| Sidebar | POST | `/youtubei/v1/guide?prettyPrint=false` | Left nav |
| Token | POST | `/api/jnn/v1/GenerateIT` | Token rotation |
| Playback | GET | `/api/stats/playback?ns=yt&el=profilepage&...&sdetail=p%3A%2F%40{handle}&sourceid=y` | Autoplay playback report; `el=profilepage` distinguishes channel context |
| Watch time | GET | `/api/stats/watchtime?ns=yt&el=profilepage&...` | Autoplay watch-time heartbeat |
| ATR | POST | `/api/stats/atr?ns=yt&el=profilepage&...` | Above-the-fold report |
| Stream (SABR) | POST | `https://{rr-node}.googlevideo.com/videoplayback?...&sabr=1` | Autoplaying channel video segments |

---

### 8. Channel Videos Tab — Scroll Pagination

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| More videos | POST | `/youtubei/v1/browse?prettyPrint=false` | Fetches next page of channel video grid; body: `{ "continuation": "<token>" }` |

Multiple `browse` POSTs fire as user scrolls through the channel's video list. The same endpoint is used for other channel tabs (Playlists, Community, etc.) with different continuation tokens.

---

## Non-Data / Infrastructure Endpoints (Filtered Out)

These fire on almost every action and carry no primary content:

| Endpoint | Purpose |
|----------|---------|
| `POST /youtubei/v1/log_event?alt=json` | Client-side event telemetry (clicks, impressions, errors) |
| `POST /youtubei/v1/feedback?prettyPrint=false` | UI feedback/dismissal actions |
| `POST /youtubei/v1/guide?prettyPrint=false` | Left sidebar nav refresh on navigation |
| `POST /api/jnn/v1/GenerateIT` | Internal JWT/token rotation per page load |
| `POST /youtube.com/generate_204` | Connectivity check (204 ping) |
| `GET /accounts.google.com/v3/signin/...` | Passive sign-in check (403 for logged-out users) |
| `GET /googleads.g.doubleclick.net/pagead/id` | Ad targeting ID fetch |
| `GET /fonts.gstatic.com/s/i/youtube_*/*.svg` | UI icon sprites |

---

## Key URL Patterns Summary

```
# Search typeahead (per keystroke)
GET https://suggestqueries-clients6.youtube.com/complete/search
    ?ds=yt&client=youtube&q={partial}&cp={cursor_pos}&gs_id={hex_seq}

# Search results pagination (on scroll)
POST /youtubei/v1/search?prettyPrint=false
Body: { "continuation": "<opaque_token>" }

# Watch page — recommendations + comments (initial + on scroll)
POST /youtubei/v1/next?prettyPrint=false
Body: { "videoId": "..." }                    # initial load
Body: { "continuation": "<token>" }           # scroll pagination

# Channel page — player config for autoplay video
POST /youtubei/v1/player?prettyPrint=false
Body: { "videoId": "...", "context": { "client": { "clientName": "WEB", ... } } }

# Channel video grid pagination (on scroll)
POST /youtubei/v1/browse?prettyPrint=false
Body: { "continuation": "<token>" }

# Video streaming (SABR — Server-Adaptive Bitrate)
POST https://{rr-node}---{pop}.googlevideo.com/videoplayback
     ?expire={ts}&id={stream_id}&source=youtube&sabr=1&c=WEB&n={throttle_bypass}&sig={hmac}&rn={chunk_num}

# Playback event (fires once at start)
GET /api/stats/playback?ns=yt&el={detailpage|profilepage|adunit}&cpn={id}&docid={videoId}&...

# Watch-time heartbeat (periodic)
GET /api/stats/watchtime?ns=yt&el={context}&cpn={id}&st={start_sec}&et={end_sec}&...

# Streaming quality telemetry (periodic)
POST /api/stats/qoe?fmt={video_itag}&afmt={audio_itag}&cpn={id}&el=detailpage&seq={n}&...

# Ad impression
GET /api/stats/ads?ver=2&content_v={videoId}&format={ad_format}&...

# Internal token rotation
POST /api/jnn/v1/GenerateIT
```

---

## InnerTube Endpoint Summary

| Endpoint | Trigger | Returns |
|----------|---------|---------|
| `POST /youtubei/v1/guide` | Every page navigation | Left sidebar nav HTML/JSON |
| `POST /youtubei/v1/search` | Search scroll pagination | Next batch of search result cards |
| `POST /youtubei/v1/next` | Watch page load + scroll | Recommendations panel + comment threads |
| `POST /youtubei/v1/browse` | Channel scroll pagination | Next batch of channel video grid items |
| `POST /youtubei/v1/player` | Channel page autoplay | Player config, stream manifest URLs |
| `POST /youtubei/v1/account/get_setting_values` | Watch/channel page load | User playback and UI settings |
| `POST /youtubei/v1/feedback` | UI actions | Acknowledgement of feedback/dismissal |
| `POST /youtubei/v1/log_event` | Continuous | Client telemetry (no content response) |
