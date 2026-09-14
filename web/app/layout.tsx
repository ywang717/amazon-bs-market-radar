import type { Metadata } from "next";
import "./globals.css";
import "./enhancements.css";
import "./v2.css";
import { SiteShell } from "./components/SiteShell";

export const metadata: Metadata = {
  title: { default: "Amazon BS 市场雷达", template: "%s · Amazon BS 市场雷达" },
  description: "Amazon 美国站三个家居设备畅销榜 Top 30 的中文市场情报看板。",
  icons: { icon: "/favicon.svg", shortcut: "/favicon.svg" },
  openGraph: { title: "Amazon BS 市场雷达", description: "证据优先的畅销榜市场情报", type: "website", images: [{ url: "/og.png", width: 1200, height: 630, alt: "Amazon BS 市场雷达" }] },
  twitter: { card: "summary_large_image", title: "Amazon BS 市场雷达", description: "证据优先的畅销榜市场情报", images: ["/og.png"] },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="zh-CN"><body><SiteShell>{children}</SiteShell></body></html>;
}
