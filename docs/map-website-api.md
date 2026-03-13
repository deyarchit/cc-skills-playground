## Skill Building Process

### Teaching Sessions

Goal: Perform analysis sessions using the playwright-cli skill and capture learnings.

Run this for a few websites, e.g. www.youtube.com, news.ycombinator.com

1. Start a new session with a prompt
```
Open a headed Chrome browser using the playwright-cli skill.

  Go to <website>

  1. Focus on the most important navigation flows
  2. For each flow, capture the API calls that are bringing data to populate the page
  3. Create a markdown summarizing the findings
```

2. Capture learnings (first time)

```
Reflect on how you approached this problem. Think about the reusable patterns of thinking or problem-solving
  that can be applied to other websites.

  Think about what worked and what didn't. Think about alternative approaches you could have taken, e.g.
  creating helper scripts.

  Capture all your thoughts in a document. I will later use that document to create a generic skill that
  can be used to perform this kind of analysis on other websites.

  Create network-interception-reflection.md
```

3. Refine learnings
```
Update @network-interception-reflection.md with your learnings from this session working with
  Hacker News.

  Stay focused on reusable knowledge — we don't want to bloat this guide with site-specific patterns.

  The goal of this doc is to serve as a detailed dump of highly valuable knowledge and learnings for building
  skills later.
```

### Building the Skill

Goal: Using the learnings from previous sessions, build the new skill called map-website-api which will use playwright-cli skill to perform website api analysis for most commonly used flows.

```
/skill-creator Using the knowledge captured in @network-interception-reflection.md, create a skill that can be used to:

  Given a website:
  1. Capture API calls triggered during the most common navigational flows
  2. Capture relevant API calls that bring data to the website; we are not interested in other asset-related calls
  3. Output the findings in a markdown
```

### Refining the Skill

Now using the skill, perform the analysis.
```
/map-website-api Analyze <website> in a headed browser.
```

Then refine the skill:
```
Using /skill-creator

  1. Review the overall effectiveness of the @.claude/skills/map-website-api/ skill at performing the given user task.
  2. Review the effectiveness of the scripts — can we optimize anything?
  3. The goal is to capture the most commonly used flows and identify their corresponding API calls for fetching
  data. Was the analysis thorough enough, or was it excessive?
```
