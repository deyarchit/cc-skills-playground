# GitHub API Calls Mapping

> Observed via Playwright network interception on github.com (March 2026, logged-in session).
> Tested against `microsoft/vscode` as representative repository.

---

## Architecture Notes

- GitHub uses **hybrid SSR + deferred lazy-loading**: full-page HTML is server-rendered, dynamic sections are fetched in parallel after paint.
- Deferred content uses path-based REST-style JSON endpoints under `/{owner}/{repo}/` — not a public REST API, these are internal fragment/partial endpoints.
- **Persisted GraphQL** (`GET /_graphql?body={...}`) is the primary query mechanism for Issues and PRs, using MD5 query hashes (not query strings).
- Navigation menus are lazy-loaded via `/_global-navigation/payloads.json?type=...` — the same URL pattern for all four menu types.
- The logged-in dashboard feed runs through a separate **Conduit service** (`/conduit/`).
- Analytics/telemetry endpoints (`collector.github.com`, `api.github.com/_private/browser/stats`) fire on nearly every page and are filtered out below.

---

## Operation → API Call Mapping

### 1. Dashboard (Logged-in Homepage — `github.com/`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| For You feed | GET | `/conduit/for_you_feed` | Main activity feed content (repos, PRs, releases followed users/orgs post) |
| Feed filters | GET | `/conduit/filter` | Available filter options for the feed (e.g. All Activity, Releases, PRs) |
| Left sidebar repos | GET | `/dashboard/my_top_repositories?location=left` | Top repositories list for left sidebar |
| Center repos (mobile) | GET | `/dashboard/my_top_repositories?location=center&mobile=true` | Repository list for center column (mobile-targeted) |
| Notification count | GET | `/notifications/indicator` | Unread notification bell count |
| Login fragment | GET | `/u2f/login_fragment?disable_signup=false&is_emu_login=false` | Security key login state fragment |

---

### 2. Repository Home (`/{owner}/{repo}`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Latest commit | GET | `/{owner}/{repo}/latest-commit` | Most recent commit metadata for the default branch header |
| File tree commit info | GET | `/{owner}/{repo}/tree-commit-info` | Last-commit message + author per file/folder in the file tree |
| Recent branches | GET | `/{owner}/{repo}/recently-touched-branches` | Recently active branches for the branch switcher dropdown |
| Branch & tag counts | GET | `/{owner}/{repo}/branch-and-tag-count` | Total number of branches and tags |
| Overview files | GET | `/{owner}/{repo}/overview-files/{branch}` | README, LICENSE, CODEOWNERS content for the repo overview panel |
| Used by | GET | `/{owner}/{repo}/used_by_list` | "Used by N repositories" section |
| Contributors | GET | `/{owner}/{repo}/contributors_list?current_repository={repo}&deferred=true` | Contributor avatars list |
| Branch refs | GET | `/{owner}/{repo}/refs?type=branch` | Full branch list for the branch/tag switcher |
| Watch subscription | GET | `/notifications/{repo_id}/watch_subscription?...` | Current user's watch/subscribe state for the repo |
| Deployment status | GET | `/{owner}/{repo}/environment_status?environment=main` | Latest deployment badge |
| Citation sidebar | GET | `/{owner}/{repo}/hovercards/citation/sidebar_partial?tree_name={branch}` | Academic citation metadata (204 if none) |

---

### 3. Issues List (`/{owner}/{repo}/issues`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Open/closed counts | GET | `/_graphql?body={persistedQueryName: "OpenClosedTabsQuery", variables: {name, owner, query}}` | Issue counts for the Open / Closed tabs |
| Issue hover previews | GET | `/_graphql?body={persistedQueryName: "IssueViewerViewQuery", variables: {number, owner, repo, count: 15}}` | Full data for each issue row (repeated per visible issue for hover cards) |
| Filter fields | GET | `/_filter/issue_fields/dashboard` | Available filter options (label, assignee, milestone, etc.) |
| Contribution guidelines | GET | `/_graphql?body={persistedQueryName: "FirstTimeContributionBannerContributingGuidelinesQuery", ...}` | Whether to show first-time contributor banner |

---

### 4. Single Issue (`/{owner}/{repo}/issues/{number}`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Issue data | GET | `/_graphql?body={persistedQueryName: "IssueViewerViewQuery", variables: {number, owner, repo, count: 15, hideTimeline: false}}` | Full issue content: title, body, comments, labels, assignees, timeline |
| Viewer settings | GET | `/settings/appearance/viewer-settings` | Theme/display preferences for rendering the issue |

---

### 5. Pull Requests List (`/{owner}/{repo}/pulls`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Recent branches partial | GET | `/{owner}/{repo}/show_partial?partial=tree%2Frecently_touched_branches_list` | Recently touched branches section |
| CI status rollups | POST | `/{owner}/{repo}/commits/checks-statuses-rollups` | Aggregated CI check status (pass/fail/pending) per PR head commit |
| Review decisions | POST | `/pull_request_review_decisions` | Review approval/changes-requested state per PR |

---

### 6. Single PR — Conversation Tab (`/{owner}/{repo}/pull/{number}`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Tab counts | GET | `/{owner}/{repo}/pull/{number}/page_data/tab_counts` | Conversation / Commits / Files Changed counts |
| Diff stat | GET | `/{owner}/{repo}/pull/{number}/page_data/diffstat` | Summary line/file change counts (+N −N) |
| Merge box | GET | `/{owner}/{repo}/pull/{number}/page_data/merge_box?merge_method=MERGE&bypass_requirements=false` | Mergeable state, merge button, required checks status |
| Status checks | GET | `/{owner}/{repo}/pull/{number}/page_data/status_checks` | CI check results list |
| Related links | GET | `/{owner}/{repo}/pull/{number}/partials/links?has_github_issues=false` | Linked issues, linked PRs |
| Syntax-highlighted diff | POST | `/{owner}/{repo}/pull/{number}/review_thread_syntax_highlighted_diff_lines` | Highlighted diff lines for inline review threads |
| Commit badges | POST | `/commits/badges` | Verification badges (signed, verified) for listed commits |
| CI rollups | POST | `/{owner}/{repo}/commits/checks-statuses-rollups` | CI check roll-up per commit in the PR |

---

### 7. PR Files Changed Tab (`/{owner}/{repo}/pull/{number}/files`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Tab counts | GET | `/{owner}/{repo}/pull/{number}/page_data/tab_counts` | Same as Conversation tab |
| Diff stat | GET | `/{owner}/{repo}/pull/{number}/page_data/diffstat` | Diff summary for the stat bar |
| PR description | GET | `/{owner}/{repo}/pull/{number}/page_data/description` | PR title and body for the sticky description header |
| CODEOWNERS | GET | `/{owner}/{repo}/pull/{number}/page_data/codeowners` | CODEOWNERS assignments per changed file |

---

### 8. Commits List (`/{owner}/{repo}/commits/{branch}`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Branch refs | GET | `/{owner}/{repo}/refs?type=branch` | Branch switcher dropdown |
| Deferred commit data | GET | `/{owner}/{repo}/commits/deferred_commit_data/{branch}?original_branch={branch}` | Grouped commit rows with dates and messages |
| Commit contributors | GET | `/{owner}/{repo}/commits/deferred_commit_contributors` | Author avatars for the commit list |

---

### 9. Single Commit (`/{owner}/{repo}/commit/{sha}`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Deferred commit data | GET | `/{owner}/{repo}/commit/{sha}/deferred_commit_data` | Metadata: stats, parent SHA, author, GPG verification |
| Branch membership | GET | `/{owner}/{repo}/branch_commits/{sha}` | Which branches and tags contain this commit |
| Comment data | GET | `/{owner}/{repo}/commit/{sha}/deferred_comment_data` | Inline and top-level comments on the commit |
| Diff content (paginated) | GET | `/{owner}/{repo}/diffs?commit={sha}&sha2={sha}&sha1={parent_sha}&start_entry={n}&bytes={n}&lines={n}` | Paginated diff content; large diffs split into chunks by byte/line count |

---

### 10. File View — Blob (`/{owner}/{repo}/blob/{branch}/{path}`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| File metadata | GET | `/{owner}/{repo}/deferred-metadata/{branch}/{path}` | File size, language, encoding, raw URL |
| Last commit for file | GET | `/{owner}/{repo}/latest-commit/{branch}/{path}` | Most recent commit that touched this specific file |
| Syntax / symbol AST | GET | `/{owner}/{repo}/deferred-ast/{branch}/{path}` | Parsed symbol tree for the code navigation sidebar and syntax tokens |
| User preferences | PUT | `/repos/preferences` | Saves display preferences (e.g. line wrap toggle) |

---

### 11. Notifications (`/notifications`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Recent alerts | GET | `/notifications/beta/recent_notifications_alert?query=&since={unix_timestamp}` | Notifications newer than the given timestamp (polled for real-time updates) |

---

### 12. Search (`/search?q={query}&type={type}`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Total count | GET | `/search/blackbird_count?saved_searches=&q={query}` | Aggregate result count across all types |
| Per-type counts | GET | `/search/count?q={query}&type={issues\|pullrequests\|discussions\|users\|commits\|registrypackages\|wikis\|topics\|marketplace}` | Result count badge per tab (one request per type) |
| Custom scopes | GET | `/search/custom_scopes` | User's saved search scope filters |
| Suggestions | GET | `/search/suggestions?query={q}&saved_searches=[]` | Autocomplete/typeahead suggestions while typing |
| Cache warm | GET | `/search/warm_blackbird_caches` | Pre-warms search backend caches |
| Sponsor buttons | POST | `/sponsors/batch_deferred_sponsor_buttons` | Renders sponsor buttons for result repos in bulk |
| Funding links | GET | `/{owner}/{repo}/funding_links?fragment=1` | Per-repo funding/sponsor links in search results |

---

### 13. User / Org Profile (`/{username}`)

| Call | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| Contribution graph | GET | `/{username}?action=show&controller=profiles&tab=contributions&user_id={username}` | Contribution heatmap calendar data (deferred fragment) |

---

## Global Navigation (present on every page)

These fire on every route change and populate the shared navigation chrome:

| Endpoint | Type | Purpose |
|----------|------|---------|
| `GET /_global-navigation/payloads.json?type=nav_menu&return_to={url}` | GET | Main nav bar links (contextual: adds repo/org params when in a repo) |
| `GET /_global-navigation/payloads.json?type=create_menu&...` | GET | "+" Create dropdown menu items |
| `GET /_global-navigation/payloads.json?type=user_menu&...` | GET | User avatar dropdown (profile, settings, sign out) |
| `GET /_global-navigation/payloads.json?type=account_switch_dialog&...` | GET | Multi-account switcher dialog |
| `GET /notifications/indicator` | GET | Notification bell unread count |
| `GET /_side-panels/user.json` | GET | Left side-panel user context data |
| `GET /github-copilot/chat/entitlement` | GET | Whether Copilot Chat is enabled for the user |
| `GET /github-copilot/chat?skip_anchor=true` | GET | Copilot Chat panel initial state |
| `POST /github-copilot/chat/token` | POST | Copilot Chat authentication token |
| `GET https://api.individual.githubcopilot.com/models` | GET | Available Copilot AI models |
| `GET /github-copilot/chat/repositories_search?limit=10` | GET | Repos available for Copilot context |
| `GET /in-product-messaging/organization-new-tasks-indicator.json` | GET | Badge for new org-level tasks |
| `GET /in-product-messaging/enterprise-new-tasks-indicator.json` | GET | Badge for new enterprise-level tasks |

---

## Non-Data / Infrastructure Endpoints (Filtered Out)

These fire on almost every action and carry no page content:

| Endpoint | Purpose |
|----------|---------|
| `POST https://collector.github.com/github/collect` | Client-side analytics / event collection |
| `POST https://api.github.com/_private/browser/stats` | Browser performance and error telemetry |
| `GET https://github.com/assets-cdn/worker/socket-worker-{hash}.js` | WebSocket worker script (live updates) |

---

## Key URL Patterns Summary

```
# Dashboard feed
GET /conduit/for_you_feed
GET /conduit/filter
GET /dashboard/my_top_repositories?location={left|center}&mobile={true}

# Repository deferred sections
GET /{owner}/{repo}/latest-commit[/{branch}/{path}]
GET /{owner}/{repo}/tree-commit-info
GET /{owner}/{repo}/overview-files/{branch}
GET /{owner}/{repo}/used_by_list
GET /{owner}/{repo}/contributors_list?deferred=true
GET /{owner}/{repo}/refs?type=branch

# PR page_data fragments (one request per section)
GET /{owner}/{repo}/pull/{number}/page_data/{tab_counts|diffstat|merge_box|status_checks|description|codeowners}

# Commit diff (paginated)
GET /{owner}/{repo}/diffs?commit={sha}&sha2={sha}&sha1={parent_sha}&start_entry={n}&bytes={n}&lines={n}

# File view
GET /{owner}/{repo}/deferred-metadata/{branch}/{path}
GET /{owner}/{repo}/deferred-ast/{branch}/{path}

# Persisted GraphQL (Issues & PRs)
GET /_graphql?body={"persistedQueryName":"{QueryName}","query":"{md5hash}","variables":{...}}

# Global nav (four lazy-loaded menus, same URL with type param)
GET /_global-navigation/payloads.json?type={nav_menu|create_menu|user_menu|account_switch_dialog}&return_to={url}[&current_repo_nwo={owner/repo}&org={org}&repository={repo}]

# Search counts (one per category)
GET /search/count?q={query}&type={type}
GET /search/blackbird_count?q={query}

# Notifications polling
GET /notifications/beta/recent_notifications_alert?query=&since={unix_timestamp}
```
