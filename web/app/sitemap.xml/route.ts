const origin = "https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site";
const paths = ["/", "/market", "/rankings", "/products", "/brands", "/reports", "/analysis", "/garden", "/garden/products", "/garden/opportunities", "/methodology", "/insights", "/llms.txt", "/llms-full.txt"];

export function GET() {
  const urls = paths.map((path) => `<url><loc>${origin}${path}</loc></url>`).join("");
  return new Response(`<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls}</urlset>`, {
    headers: { "content-type": "application/xml; charset=utf-8", "cache-control": "public, max-age=3600" },
  });
}
