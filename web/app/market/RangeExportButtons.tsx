"use client";
import { CsvDownloadButton } from "../components/CsvDownloadButton";
export function RangeExportButtons({ products, marketTrend, start, end }: { products: Array<Record<string, unknown>>; marketTrend: Array<Record<string, unknown>>; start: string; end: string }) { return <div className="rangeExportButtons"><CsvDownloadButton filename={`market-products-${start}-${end}.csv`} rows={products}/><CsvDownloadButton filename={`market-trend-${start}-${end}.csv`} rows={marketTrend}/></div>; }
