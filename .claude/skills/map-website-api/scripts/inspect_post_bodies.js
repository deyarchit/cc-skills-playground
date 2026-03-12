// Template for capturing POST request bodies within a run-code block.
// Useful for identifying GraphQL operationName, persistedQueryName, and other
// overloaded endpoint discriminators.
//
// IMPORTANT: The action you want to inspect MUST happen inside this same async block.
// run-code exits synchronously — a listener set up in one run-code block cannot
// observe actions triggered by a separate playwright-cli command.
//
// Usage:
//   playwright-cli run-code "$(cat .claude/skills/map-website-api/scripts/inspect_post_bodies.js)"
//
// Then: playwright-cli console   (to see the [POST BODY] output)
//
// ─── HOW TO USE ─────────────────────────────────────────────────────────────
// Replace the ACTION STEPS section below with the interaction you want to
// observe (click, goto, fill, etc.). The listener will capture all POST bodies
// fired during the wait window.
// ────────────────────────────────────────────────────────────────────────────

async page => {
  const captured = [];

  page.on('request', r => {
    if (r.method() !== 'POST') return;
    const url = r.url();
    const body = r.postData();
    if (!body) return;

    let entry = { url, raw: body.slice(0, 600) };

    // Try to parse as JSON and extract discriminating fields
    try {
      const parsed = JSON.parse(body);
      entry.operationName      = parsed.operationName      || null;
      entry.persistedQueryName = parsed.persistedQueryName || null;
      entry.query_hash         = parsed.query              || null;  // often an MD5 in persisted queries
      entry.variables          = parsed.variables          ? JSON.stringify(parsed.variables).slice(0, 300) : null;
      // Clean up nulls
      Object.keys(entry).forEach(k => entry[k] === null && delete entry[k]);
    } catch {
      // not JSON — keep raw
    }

    captured.push(entry);
  });

  // ─── ACTION STEPS ──────────────────────────────────────────────────────────
  // Replace this block with the interaction you want to observe. Examples:
  //
  //   await page.click('text=Load more');
  //   await page.goto('https://example.com/feed');
  //   await page.fill('input[name=q]', 'search term');
  //
  // Then wait long enough for the requests to fire:
  await page.waitForTimeout(3000);
  // ──────────────────────────────────────────────────────────────────────────

  // Output results — readable by playwright-cli console
  if (captured.length === 0) {
    console.log('[POST BODY INSPECTOR] No POST requests captured in this window.');
  } else {
    console.log(`[POST BODY INSPECTOR] Captured ${captured.length} POST request(s):`);
    captured.forEach((entry, i) => {
      console.log(`\n--- Request ${i + 1} ---`);
      console.log(JSON.stringify(entry, null, 2));
    });
  }
}
