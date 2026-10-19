import type { CategoryKey } from "@/lib/catalog";
import { ensureSchema, getD1 } from "@/lib/d1";
import { createD1DashboardStore } from "@/lib/dashboard-store";
import { loadLiveDashboard } from "@/lib/live-dashboard-data";
import { createMarketContextResolver, productionMarketContextResolver, resolvePublicMarketQuery } from "@/lib/market-context";
import { isValidMarketDate } from "@/lib/public-validation";
import { compareRankings, validateCategory } from "@/lib/analytics";
import { previousValidMarketDate, selectValidCategoryDays } from "@/lib/valid-market-days";

import { productionCategoryRegistry } from "@/lib/category-registry";

const json = (body: unknown, init: ResponseInit = {}) => Response.json(body, init);
const rankingMarketContextResolver = createMarketContextResolver(productionCategoryRegistry);

export async function GET(request: Request) {
  const url = new URL(request.url);
  const parsed = resolvePublicMarketQuery({
    marketplace: url.searchParams.get("marketplace"),
    category: url.searchParams.get("category"),
    segment: url.searchParams.get("segment"),
    page: "rankings",
  }, rankingMarketContextResolver);
  if (!parsed.ok) return json({ error: parsed.error }, { status: 400 });
  const category = parsed.context.category as CategoryKey;
  let date = url.searchParams.get("date");
  if (date !== null && !isValidMarketDate(date)) return json({ error: "invalid_date" }, { status: 400 });

  if (!date && productionMarketContextResolver.enabled.some(({ categoryKey }) => categoryKey === category)) {
    const dashboard = await loadLiveDashboard({ preferLatestSnapshot: true });
    const row = dashboard.categoryRows.find(({ key }) => key === category)!;
    if (dashboard.source === "d1" && row.categoryDayPresent !== true) {
      return json({ error: "unavailable" }, { status: 503 });
    }
    return json(
      { marketDate: dashboard.marketDate, category, scope: "raw_ranking", observations: row.observations, quality: row.quality, comparison: row.comparison },
      { headers: { "cache-control": `public, max-age=${dashboard.source === "d1" ? 300 : 60}` } },
    );
  }

  try {
    const db = getD1();
    await ensureSchema(db);
    const store = createD1DashboardStore(db);
    const [snapshots, categoryDays, allObservations] = await Promise.all([
      store.listSnapshots(),
      store.listCategoryDays(),
      store.listObservations(),
    ]);
    if (!date) {
      date = categoryDays.filter((day) => day.category_key === category && snapshots.some(({ market_date }) => market_date === day.market_date))
        .map(({ market_date }) => market_date).toSorted().at(-1) ?? null;
      if (!date) return json({ error: "unavailable" }, { status: 503 });
    }
    if (!snapshots.some(({ market_date }) => market_date === date)) return json({ error: "not_found" }, { status: 404 });
    const observations = await store.listCategoryObservations(date, category);
    const checked = validateCategory(observations);
    const persisted = categoryDays.find((day) => day.market_date === date && day.category_key === category);
    if (!persisted) return json({ error: "not_found" }, { status: 404 });
    const quality = { ...checked, complete: Boolean(persisted && persisted.complete === 1 && checked.complete) };
    const validDates = selectValidCategoryDays({ categoryKey: category, categoryDays, observations: allObservations });
    const baselineDate = validDates.includes(date) ? previousValidMarketDate(validDates, date) : null;
    const previousObservations = baselineDate
      ? await store.listCategoryObservations(baselineDate, category as CategoryKey)
      : [];
    const comparison = compareRankings(baselineDate ? previousObservations : [], observations);
    return json({ marketDate: date, category, scope: "raw_ranking", observations, quality, comparison: { ...comparison, baselineDate } }, { headers: { "cache-control": "public, max-age=300" } });
  } catch {
    return json({ error: "unavailable" }, { status: 503 });
  }
}
