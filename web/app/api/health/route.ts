import { ensureSchema, getD1 } from "@/lib/d1";

export async function GET() {
  try {
    const db = getD1();
    await ensureSchema(db);
    const row = await db
      .prepare("SELECT MAX(market_date) AS latest_data_date FROM snapshots")
      .first<{ latest_data_date: string | null }>();

    return Response.json({
      ok: true,
      database: true,
      latest_data_date: row?.latest_data_date ?? null,
    });
  } catch {
    return Response.json({ ok: false, database: false }, { status: 503 });
  }
}
