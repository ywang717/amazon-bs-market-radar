import Link from "next/link";
import type { Metadata } from "next";
import { GardenNavigation } from "./navigation";
import "./garden.css";

export const metadata: Metadata = { title: "庭院与花园" };
export default function GardenLayout({ children }: { children: React.ReactNode }) {
  return <div className="garden"><header className="gardenHeader"><p>AMAZON US · PATIO, LAWN & GARDEN</p><h1>庭院与花园</h1><p>观察榜单样本，积累市场证据，谨慎发现选品线索。</p></header><GardenNavigation />{children}<footer className="gardenFoot">排名与评论变化不等于销量。商机线索不代表已证明盈利。<Link href="/methodology">查看方法说明</Link></footer></div>;
}
