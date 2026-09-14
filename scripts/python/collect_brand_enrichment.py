"""Collect conservative, auditable Amazon brand evidence for a fixed ASIN set."""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ARTIFACT_SCHEMA = "amazon-brand-enrichment-v1"
MARKETPLACE = "AMAZON_US"
AMAZON_ORIGIN = "https://www.amazon.com"


def _load_local_module(name: str):
    path = Path(__file__).with_name(f"{name}.py")
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


try:
    from collect_best_sellers import _extract_detail_page
except ModuleNotFoundError:
    _extract_detail_page = _load_local_module("collect_best_sellers")._extract_detail_page

try:
    from brand_evidence import classify_brand_evidence
except ModuleNotFoundError:
    classify_brand_evidence = _load_local_module("brand_evidence").classify_brand_evidence


def _canonical_asins(asins: list[str]) -> list[str]:
    unique: set[str] = set()
    for value in asins:
        asin = str(value).strip().upper()
        if re.fullmatch(r"[A-Z0-9]{10}", asin) is None:
            raise ValueError(f"Invalid ASIN: {value}")
        unique.add(asin)
    return sorted(unique)


def _detail_url(asin: str) -> str:
    return f"{AMAZON_ORIGIN}/dp/{asin}"


def _unknown_result(asin: str, status: str) -> dict[str, str | None]:
    return {
        "asin": asin,
        "detail_url": _detail_url(asin),
        "verification_status": status,
        "raw_brand": None,
        "brand_source": "unknown",
        "evidence_source": None,
    }


def collect_brand_enrichment(
    asins: list[str], *, context: Any, generated_at: str | None = None
) -> dict[str, Any]:
    """Visit each canonical ASIN once and return a sorted enrichment artifact."""
    products: list[dict[str, str | None]] = []
    for asin in _canonical_asins(asins):
        page = None
        try:
            page = context.new_page()
            page.goto(_detail_url(asin), wait_until="domcontentloaded", timeout=60000)
            classification = classify_brand_evidence(_extract_detail_page(page), asin)
            products.append({
                "asin": asin,
                "detail_url": _detail_url(asin),
                "verification_status": classification["verification_status"],
                "raw_brand": classification["raw_brand"],
                "brand_source": classification["brand_source"],
                "evidence_source": classification["evidence_source"],
            })
        except Exception:
            products.append(_unknown_result(asin, "VERIFICATION_BLOCKED"))
        finally:
            if page is not None:
                try:
                    page.close()
                except Exception:
                    pass
    return {
        "schema_version": ARTIFACT_SCHEMA,
        "marketplace": MARKETPLACE,
        "generated_at": generated_at or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "products": products,
    }


def _atomic_json_write(path: Path, artifact: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(artifact, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def _read_asins(path: Path) -> list[str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(payload, dict):
        payload = payload.get("asins")
    if not isinstance(payload, list):
        raise ValueError("ASIN input must be a JSON array or an object with an asins array.")
    return [str(value) for value in payload]


def _launch_browser(playwright: Any, headless: bool) -> Any:
    for channel in ("msedge", "chrome"):
        try:
            return playwright.chromium.launch(channel=channel, headless=headless)
        except Exception:
            pass
    return playwright.chromium.launch(headless=headless)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Collect auditable Amazon brand evidence.")
    parser.add_argument("--asins-json", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--marketplace", default=MARKETPLACE, choices=[MARKETPLACE])
    parser.add_argument("--headless", required=True, choices=["true", "false"])
    args = parser.parse_args(argv)

    from playwright.sync_api import sync_playwright

    with sync_playwright() as playwright:
        browser = _launch_browser(playwright, headless=(args.headless == "true"))
        try:
            context = browser.new_context()
            try:
                artifact = collect_brand_enrichment(_read_asins(args.asins_json), context=context)
            finally:
                context.close()
        finally:
            browser.close()
    _atomic_json_write(args.output, artifact)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
