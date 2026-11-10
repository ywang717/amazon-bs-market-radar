import type { Metadata } from "next";
import "./globals.css";
import "./enhancements.css";
import "./v2.css";
import { SiteShell } from "./components/SiteShell";

export const metadata: Metadata = {
  title: { default: "Amazon BS 市场雷达", template: "%s · Amazon BS 市场雷达" },
  description: "Amazon 美国站三个家居设备畅销榜 Top 30 的中文市场情报看板。",
  metadataBase: new URL("https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site"),
  alternates: { canonical: "/" },
  robots: { index: true, follow: true },
  icons: { icon: "/favicon.svg", shortcut: "/favicon.svg" },
  openGraph: { title: "Amazon BS 市场雷达", description: "证据优先的畅销榜市场情报", type: "website", images: [{ url: "/og.png", width: 1200, height: 630, alt: "Amazon BS 市场雷达" }] },
  twitter: { card: "summary_large_image", title: "Amazon BS 市场雷达", description: "证据优先的畅销榜市场情报", images: ["/og.png"] },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const structuredData = [
    {
      "@context": "https://schema.org",
      "@type": "WebSite",
      name: "Amazon BS 市场雷达",
      url: "https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/",
      description: "证据优先的 Amazon 美国站畅销榜市场情报看板。",
      inLanguage: "zh-CN",
      isAccessibleForFree: true,
      keywords: "Amazon 美国站,畅销榜,市场趋势,产品排名,品牌席位",
      publisher: { "@id": "https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/#organization" },
      potentialAction: { "@type": "SearchAction", target: "https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/products?q={search_term_string}", "query-input": "required name=search_term_string" },
    },
    {
      "@context": "https://schema.org",
      "@type": "Organization",
      "@id": "https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/#organization",
      name: "Amazon BS 市场雷达",
      url: "https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/",
      sameAs: ["https://github.com/ywang717/amazon-bs-market-radar"],
    },
    {
      "@context": "https://schema.org",
      "@type": "Dataset",
      name: "Amazon 美国站畅销榜市场快照",
      description: "经过完整度校验的 Amazon 美国站公开畅销榜排名、价格、评分、评论数和趋势观察。",
      url: "https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/insights",
      isAccessibleForFree: true,
      inLanguage: "zh-CN",
      creator: { "@id": "https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/#organization" },
      includedInDataCatalog: { "@type": "DataCatalog", name: "Amazon BS 市场雷达" },
      license: "https://creativecommons.org/licenses/by/4.0/",
    },
  ];
  return <html lang="zh-CN"><body><script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }} /><SiteShell>{children}</SiteShell></body></html>;
}
