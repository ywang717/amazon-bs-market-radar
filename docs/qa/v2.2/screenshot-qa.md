# V2.2 Screenshot QA

Production site: https://amazon-bs-market-radar.warrenwangyihao.chatgpt.site

Result: PASS. All screenshots below were recaptured from production after version 32 deployed successfully. Representative images were visually inspected for current market date, market isolation, readable hierarchy, non-overlapping controls, signal evidence, and absence of 404/error states.

## 1366×768

- PASS — Overview — Pressure Washers / Machines
- PASS — Products — Sump Pumps / All
- PASS — Rankings — Pressure Washer Accessories / All
- PASS — Reports — Pressure Washers / Machines

## 1440×900

- PASS — Overview — Sump Pumps / All
- PASS — Market — Pressure Washer Accessories / All
- PASS — Brands — Pressure Washers / Machines
- PASS — Alerts — Sump Pumps / All; default filter is High + Watch

## 1920×1080

- PASS — Overview — Pressure Washer Accessories / All
- PASS — Reports — Sump Pumps / All

## Browser state

- PASS — Refresh preserves market context and date.
- PASS — Back restores the previous page and market query.
- PASS — Forward restores the next page and market query.
- PASS — Deep links resolve the requested category, segment, and valid date.
- PASS — Category changes clear a stale explicit date and resolve the new market's date.
- PASS — Two tabs retain independent market contexts.

Automation evidence: `run-browser-qa.mjs` completed with refresh, back, forward, deepLink, categoryDateReset, multiTab, alertsScreenshot, and 10 production screenshot captures passing.
