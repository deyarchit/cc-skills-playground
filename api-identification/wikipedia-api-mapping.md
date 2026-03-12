# API Map: Wikipedia (Wikimedia)

**URL:** https://en.wikipedia.org
**Rendering architecture:** SSR/MPA (MediaWiki) with client-side enhancements
**Auth state:** Logged out — auth-gated flows (watchlist, notifications, edit-with-account) skipped
**Date captured:** 2026-03-11
**Subdomains covered:** en.wikipedia.org, www.wikidata.org, commons.wikimedia.org

---

## Overview

Wikipedia is built on MediaWiki, a server-side rendered PHP application. Nearly all page navigations (article loads, history, categories, talk pages, search results) are full HTML GETs — invisible to XHR/Fetch interception. Client-side API calls are limited to specific interactive widgets layered on top of the SSR page: search typeahead, page-preview popups, the media viewer, and the language switcher.

Wikipedia exposes two distinct API surfaces:
- **MediaWiki Action API** (`/w/api.php?action=...`) — the legacy PHP API, used by media viewer, language search, Commons annotations
- **Wikimedia REST API** (`/w/rest.php/v1/...` and `/api/rest_v1/...`) — newer REST API, used by search typeahead and page summaries

---

## Data Endpoints

### Search Typeahead

Triggered when the user types in the search box (header search, any Wikipedia page).

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/w/rest.php/v1/search/title?q={query}&limit=10` | — | Autocomplete article title suggestions (up to 10 results with descriptions) |
| GET | `/w/api.php?action=cirrus-config-dump&format=json&formatversion=2&prop=usertesting` | — | Fetch CirrusSearch A/B test configuration on first search interaction |

**Notes:**
- `cirrus-config-dump` fires once on the first search session, not on every keystroke.
- The typeahead shows article titles, short descriptions, and thumbnail images — all from the `search/title` endpoint.
- "Search for pages containing X" (full-text search) navigates to `Special:Search` — which is a full HTML GET, not an XHR/Fetch.

---

### Page Preview Popups

Triggered when the user hovers over any internal wiki link (after a brief delay).

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/api/rest_v1/page/summary/{title}` | — | Fetch article summary (extract, thumbnail, description) for hover popup card |

**Examples:**
- Hovering over "Machine learning" → `GET /api/rest_v1/page/summary/Machine_learning`
- Hovering over "Guido van Rossum" → `GET /api/rest_v1/page/summary/Guido_van_Rossum`
- Hovering over "Unsupervised learning" → `GET /api/rest_v1/page/summary/Unsupervised_learning`

**Notes:**
- Only triggers on internal wiki links (`/wiki/...`), not on anchor links or external links.
- The popup is provided by the `mw.popups` MediaWiki extension module.

---

### Media Viewer

Triggered when the user clicks on an image/media thumbnail in an article.

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/w/api.php?action=query&format=json&formatversion=2&prop=imageinfo&titles=File%3A{filename}&iiprop=timestamp\|url\|size\|mime\|mediatype\|extmetadata&iiextmetadatafilter={fields}&iiextmetadatalanguage=en&uselang=content&smaxage=300&maxage=300` | — | Fetch full image metadata, license info, attribution, GPS for media viewer lightbox |

**Behavior:**
- On opening an image, fires for the clicked image.
- Prefetches metadata for adjacent images (next/previous in the article) proactively.
- `iiextmetadatafilter` includes: `DateTime`, `DateTimeOriginal`, `ObjectName`, `ImageDescription`, `License`, `LicenseShortName`, `UsageTerms`, `LicenseUrl`, `Credit`, `Artist`, `AuthorCount`, `GPSLatitude`, `GPSLongitude`, `Permission`, `Attribution`, `AttributionRequired`, `NonFree`, `Restrictions`, `DeletionReason`

---

### Language Switcher

Triggered when the user opens the "Available in N languages" panel and types in the search box.

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/w/api.php?action=languagesearch&format=json&formatversion=2&search={query}` | — | Autocomplete language names in the interwiki language switcher panel |

**Notes:**
- The language switcher button opens a panel that already has language links pre-rendered (SSR).
- The search input inside the panel triggers `languagesearch` to filter by language name.
- Navigating to another language version of the article is a full HTML GET to the target wiki domain (e.g., `fr.wikipedia.org`).

---

### SSR Flows (No XHR/Fetch — Full HTML GETs)

All of the following are server-rendered and produce no observable XHR/Fetch calls:

| Flow | URL Pattern | Notes |
|------|------------|-------|
| Article page load | `/wiki/{title}` | Full HTML GET, no client-side fetch |
| Search results page | `/w/index.php?title=Special:Search&search={query}` | SSR; often redirects directly to matching article |
| Full-text search | `/w/index.php?title=Special:Search&fulltext=1&search={query}` | SSR search results, no XHR pagination |
| Article history | `/w/index.php?title={title}&action=history` | SSR |
| Talk page | `/wiki/Talk:{title}` | SSR |
| Category page | `/wiki/Category:{name}` | SSR |
| "What links here" | `/w/index.php?title=Special:WhatLinksHere/{title}` | SSR |
| Recent changes | `/wiki/Special:RecentChanges` | SSR, no live refresh |
| Random article | `/wiki/Special:Random` → redirect | SSR redirect |

---

## Wikidata (wikidata.org) — Subdomain SPA

Wikidata entity pages fire multiple XHR calls on load. It is a **hybrid** — the base page shell is SSR, but structured data and constraint checks are loaded client-side.

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/wiki/Special:EntityData/{entity_id}.json?revision={rev_id}` | — | Full entity data as Wikibase JSON-LD (all statements, labels, descriptions, aliases) |
| GET | `/w/api.php?action=wbgetentities&format=json&ids={prop_ids}&props=claims&errorformat=plaintext` | — | Fetch property metadata for entity display |
| GET | `/w/api.php?action=wbcheckconstraints&format=json&formatversion=2&uselang=en&id={entity_id}&status=violation\|warning\|suggestion\|bad-parameters` | — | Constraint checker: fetch violations/warnings for entity |
| GET | `/w/api.php?action=wbformatvalue&format=json&datavalue={json}&generate=text%2Fplain&options={opts}` | — | Format a Wikibase value (e.g., entity reference → readable label) |

**Notes:**
- All three load calls fire simultaneously on every Wikidata entity page view.
- `entity_id` format: `Q{id}` for items (e.g., `Q10884`), `P{id}` for properties.
- `wbgetentities` is called with a batch of property IDs (separator `%1F`) to fetch their labels/descriptions in bulk.

---

## Wikimedia Commons (commons.wikimedia.org) — Subdomain

Commons file pages trigger structured data and image annotation API calls.

| Method | Endpoint Pattern | Discriminator | Purpose |
|--------|-----------------|---------------|---------|
| GET | `/wiki/Special:EntityData/M{media_id}.json?revision={rev_id}` | — | Structured Data on Commons (SDC) — file's structured metadata as Wikibase JSON |
| GET | `/w/api.php?action=parse&pst&text={wikitext}&title=API&prop=text&uselang=en&maxage=14400&smaxage=14400&format=json` | — | Render ImageAnnotator UI text from MediaWiki template |
| GET | `/w/api.php?action=query&titles={filename}&prop=info\|imageinfo&inprop=protection&iiprop=size&format=json` | — | Fetch basic image metadata and protection status |

---

## Analytics / Instrumentation (Noise)

These fire on most user interactions but carry no content — filter out in analysis.

| Method | Endpoint | Trigger | Notes |
|--------|---------|---------|-------|
| POST | `https://intake-analytics.wikimedia.org/v1/events?hasty=true` | Nearly all interactions | Wikimedia Event Platform event collection; all requests fail with `ERR_ABORTED` in test environment |
| POST | `/beacon/statsv?Search.FullTextResults={ms}ms` | After search redirects to article | CirrusSearch result load time metric beacon |
| POST | `/beacon/statsv?mediawiki_WikimediaEvents_Search_FullTextResults_seconds:{ms}\|ms` | Same | StatsD timing metric for search result load |

---

## URL Pattern Summary

```
# Wikipedia (en.wikipedia.org)
GET  /w/rest.php/v1/search/title?q={query}&limit=10     # search typeahead
GET  /api/rest_v1/page/summary/{title}                   # page hover preview
GET  /w/api.php?action=cirrus-config-dump&...            # search A/B config (once per session)
GET  /w/api.php?action=languagesearch&search={query}     # language switcher search
GET  /w/api.php?action=query&prop=imageinfo&titles=File%3A{filename}&iiprop=...  # media viewer

# Wikidata (wikidata.org)
GET  /wiki/Special:EntityData/{Q_or_P_id}.json?revision={rev}  # entity data
GET  /w/api.php?action=wbgetentities&ids={prop_ids}&props=claims  # property metadata
GET  /w/api.php?action=wbcheckconstraints&id={entity_id}&status=...  # constraint checker
GET  /w/api.php?action=wbformatvalue&datavalue={json}   # value formatter

# Commons (commons.wikimedia.org)
GET  /wiki/Special:EntityData/M{media_id}.json?revision={rev}  # SDC metadata
GET  /w/api.php?action=parse&pst&text={wikitext}&prop=text     # image annotator UI
GET  /w/api.php?action=query&titles={file}&prop=info|imageinfo  # image file info
```

---

## Subdomain / Third-Party Properties

| Domain | Feature | Architecture |
|--------|---------|--------------|
| `wikidata.org` | Structured knowledge graph (entities, properties) | SSR shell + client-side XHR for entity data and constraints |
| `commons.wikimedia.org` | Shared media repository | SSR + client-side SDC and image annotation APIs |
| `intake-analytics.wikimedia.org` | Event analytics pipeline | Receive-only; all requests fail outside Wikimedia infra |
| `auth.wikimedia.org` | Centralized login (SUL3) | Redirects here when accessing auth-gated pages |

---

## Gaps & Notes

- **Auth-gated flows skipped:** Watchlist, notification bell, edit tools, user preferences, and login-required API calls (e.g., `action=watch`, `action=edit`, Echo notifications) were not captured.
- **SSR dominance:** The vast majority of Wikipedia's functionality is server-rendered — article reads, search results, and most special pages produce zero client-side API calls.
- **Full-text search is SSR:** Unlike modern SPAs, Wikipedia's search results page (`Special:Search`) is fully server-rendered with no client-side result fetching or infinite scroll.
- **Mobile site (`en.m.wikipedia.org`)** redirects to the desktop site in this browser environment — mobile-specific API patterns were not captured separately.
- **`mw.popups` scope:** Page previews only fire for `title` links pointing to existing articles. Red links and anchor-only links do not trigger preview fetches.
- **Media Viewer prefetching:** The viewer proactively fetches `imageinfo` for neighboring images (adjacent in article order) in addition to the currently viewed image.
- **Wikidata constraint checker** (`wbcheckconstraints`) fires on every entity page load — it is a significant background call that always runs regardless of whether violations exist.
