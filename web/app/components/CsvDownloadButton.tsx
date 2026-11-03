"use client";
export function CsvDownloadButton({ filename, rows }: { filename: string; rows: Array<Record<string, unknown>> }) {
  const download = () => { const keys = rows.length ? Object.keys(rows[0]) : []; const esc = (value: unknown) => { let text = value == null ? "" : String(value); if (/^[=+\-@]/.test(text)) text = `'${text}`; return `"${text.replaceAll('"', '""')}"`; }; const csv = `\ufeff${[keys, ...rows.map((row) => keys.map((key) => row[key]))].map((line) => line.map(esc).join(",")).join("\r\n")}`; const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" })); const link = document.createElement("a"); link.href = url; link.download = filename; link.click(); URL.revokeObjectURL(url); };
  return <button type="button" className="downloadButton" onClick={download}>导出 CSV</button>;
}
