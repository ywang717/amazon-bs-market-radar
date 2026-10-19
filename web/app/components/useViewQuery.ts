"use client";

import { useSyncExternalStore } from "react";
import { useSearchParams } from "next/navigation";
import { patchViewQuery } from "@/lib/view-state";

function subscribe(listener: () => void) {
  window.addEventListener("popstate", listener);
  window.addEventListener("market-radar:navigation", listener);
  return () => {
    window.removeEventListener("popstate", listener);
    window.removeEventListener("market-radar:navigation", listener);
  };
}
const browserSearch = () => window.location.search.slice(1);

export function useViewQuery() {
  const serverSearch = useSearchParams().toString();
  const search = useSyncExternalStore(subscribe, browserSearch, () => serverSearch);
  function update(changes: Record<string, string | number | null>, replace = false) {
    const next = patchViewQuery(browserSearch(), changes);
    if (next === browserSearch()) return;
    const href = `${window.location.pathname}${next ? `?${next}` : ""}${window.location.hash}`;
    window.history[replace ? "replaceState" : "pushState"](window.history.state, "", href);
    window.dispatchEvent(new CustomEvent("market-radar:navigation", { detail: { search: next } }));
  }
  return { params: new URLSearchParams(search), update };
}
