"use client";

export function ListPagination({ page, pages, total, onPage, label = "列表分页" }: {
  page: number; pages: number; total: number; onPage: (page: number) => void; label?: string;
}) {
  return <nav className="listPagination" aria-label={label}>
    <span role="status">共 {total} 条 · 第 {page} / {pages} 页</span>
    <button type="button" disabled={page <= 1} onClick={() => onPage(page - 1)}>上一页</button>
    <button type="button" disabled={page >= pages} onClick={() => onPage(page + 1)}>下一页</button>
  </nav>;
}
