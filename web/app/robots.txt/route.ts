export function GET() {
  const body = [
    "User-agent: *",
    "Allow: /",
    "Disallow: /api/",
    "Disallow: /_next/",
    "Sitemap: https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/sitemap.xml",
    "",
    "# AI-readable site context",
    "LLMS: https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/llms.txt",
    "LLMS-FULL: https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/llms-full.txt",
    "",
  ].join("\n");
  return new Response(body, {
    headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "public, max-age=3600" },
  });
}
