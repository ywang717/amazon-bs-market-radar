import fs from 'node:fs';

const root = new URL('../var/amazon-bestsellers/', import.meta.url);
const template = JSON.parse(fs.readFileSync(new URL('2026-09-10/dashboard-sync-bundle.json', root), 'utf8'));
const categories = ['pressure_washers', 'sump_pumps', 'pressure_washer_accessories'];

for (const marketDate of ['2026-09-12', '2026-09-13']) {
  const dir = new URL(`${marketDate}/`, root);
  const snapshot = JSON.parse(fs.readFileSync(new URL('amazon-bestsellers.json', dir), 'utf8'));
  const receipt = JSON.parse(fs.readFileSync(new URL('best-sellers-capture-receipt.json', dir), 'utf8'));
  const observedAt = new Date(snapshot.observed_at).toISOString();
  const metadata = template.productMetadata.map((row) => ({ ...row, lastSeenMarketDate: marketDate }));
  const bundle = {
    schemaVersion: 'amazon-bs-dashboard-bundle-v2',
    marketDate,
    observedAt,
    receiptSha256: receipt.snapshot_sha256,
    categories: categories.map((key) => ({
      key,
      sourceUrl: snapshot.sources[key],
      observations: snapshot[key].map((row) => ({
        ...row,
        price: typeof row.price === 'string' ? Number.parseFloat(row.price.replace(/[^0-9.,+-]/g, '').replace(',', '')) : row.price,
        rating: row.rating === null || row.rating === undefined ? null : Number(row.rating),
        reviews: row.reviews === null || row.reviews === undefined ? null : Number(row.reviews),
        has_discount: row.has_discount ?? null,
        discounts: row.discounts ?? [],
      })),
    })),
    productMetadata: metadata,
    reports: [],
  };
  fs.writeFileSync(new URL('dashboard-sync-bundle.json', dir), JSON.stringify(bundle, null, 2) + '\n');
  console.log(`${marketDate}: ${bundle.categories.reduce((n, c) => n + c.observations.length, 0)} observations, ${metadata.length} metadata`);
}
