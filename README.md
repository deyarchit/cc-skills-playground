# Claude Code Skills Playground

A workbench for building, refining, and composing [Claude Code](https://claude.ai/code) skills.

## Skills

| Name | Description |
|------|-------------|
| `map-website-api` | Maps which user interactions on a website trigger which backend API calls, producing a structured report of the site's API surface. [How it was built](workspace/map-website-api/how-it-was-built.md) |

## Setup

**1. Enable the `skill-creator` plugin**

The `skill-creator` Claude Code plugin is required for building and refining skills in this repo. Enable it in your Claude Code settings before working on skills.

**2. Install Playwright CLI:**

```bash
npm install -g @playwright/cli@latest
playwright-cli --help
playwright-cli install --skills
```
