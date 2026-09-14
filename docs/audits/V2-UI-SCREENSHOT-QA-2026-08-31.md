# Amazon BS Market Radar V2.0 — Screenshot QA

Date: 2026-08-31  
Scope: local production-equivalent UI preview, verified seed fallback when D1 is unavailable locally

## Desktop viewport checks

| Route | Viewport | Result |
| --- | --- | --- |
| Overview | 1366 × 768 | Pass — navigation, market context, summary, four KPIs and the first complete Signal Card are visible. First signal bottom: 688 px. |
| Overview | 1440 × 900 | Pass — complete overview hierarchy visible without horizontal overflow. |
| Overview | 1920 × 1080 | Pass — content remains centered and capped at 1520 px. |
| Rankings | 1440 × 900 | Pass — 60 px rows, sticky header, compact product identity, no page-level horizontal overflow. |
| Products | 1440 × 900 | Pass — search, filters and 60 px product rows are visible and aligned. |
| Product detail | 1440 × 900 | Pass — reverse rank axis (#1 to #30), Top10 zone, current status and timeline event are visible. |
| Market | 1440 × 900 | Pass — market state and prioritized activity are visually dominant. |
| Brands | 1440 × 900 | Pass — presence visualization precedes the brand table. |
| Seller analysis | 1440 × 900 | Pass — controls, report text and evidence disclosure use the V2 dark surface and readable text tokens. |
| Reports | 1440 × 900 | Pass — report entry cards and archive state share the primary dark surface system. |

## Responsive checks

| Check | Result |
| --- | --- |
| 390 × 844 overview | Pass — two-column KPI stack, readable Signal Card and usable compact header. |
| Mobile navigation | Pass — menu button remains visible and exposes the six primary destinations. |
| Mobile Data Status drawer | Pass — 359 px wide in a 390 px viewport; full 844 px height; close control accessible. |
| Mobile ranking table | Pass — page remains viewport-bound; the 1009 px table scrolls inside a 373 px container. |
| Page overflow | Pass — document width remains viewport-bound; only tables use intentional internal horizontal scrolling. |

## Accessibility and state checks

- Keyboard focus uses a visible 2 px primary-accent outline.
- Icon-only controls have accessible names.
- Drawer closes through its named close button and Escape.
- Drawer moves focus to its close control, traps Tab navigation and restores focus to the triggering control when closed.
- Rank movement includes arrows and numeric values; signal priority includes text badges.
- Product rank history points are focusable, labelled with date and rank, and backed by a non-visual ordered data list.
- Ranking market context updates with the selected category; verified interactively with Sump Pumps / All Best Sellers.
- Loading uses skeleton rows; no-data and loading-error states are distinct.
- Reduced-motion preference disables non-essential transitions and drawer animation.
- Product titles expose the full original title through the native title tooltip while keeping the row compact.

## Evidence artifacts

- `docs/screenshots/v2-ui/overview-1366x768.png`
- `docs/screenshots/v2-ui/overview-1440x900.png`
- `docs/screenshots/v2-ui/overview-1920x1080.png`
- `docs/screenshots/v2-ui/rankings-1440x900.png`
- `docs/screenshots/v2-ui/products-1440x900.png`
- `docs/screenshots/v2-ui/product-detail-1440x900.png`
- `docs/screenshots/v2-ui/market-1440x900.png`
- `docs/screenshots/v2-ui/brands-1440x900.png`
- `docs/screenshots/v2-ui/overview-mobile-390x844.png`
- `docs/screenshots/v2-ui/analysis-1440x900.png`
- `docs/screenshots/v2-ui/reports-1440x900.png`

## Local-preview limitation

The local runtime does not contain the production D1 binding, so screenshots use the repository's verified fallback snapshot. The UI explicitly labels that state. Production QA must repeat the key routes against the deployed D1-backed site and confirm that the fallback notice is absent.
