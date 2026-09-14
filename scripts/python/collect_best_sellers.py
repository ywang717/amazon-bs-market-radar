"""Collect public Amazon Best Sellers charts without authentication or bypasses.

The parsing and artifact functions are intentionally independent of Playwright.  The
browser dependency is imported only inside the visible-browser boundary.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from uuid import uuid4
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urljoin, urlsplit
from zoneinfo import ZoneInfo


SNAPSHOT_SCHEMA = "amazon-best-sellers-snapshot-v1"
STATUS_SCHEMA = "best-sellers-collection-status-v1"
EXIT_OK = 0
EXIT_RUNTIME_ERROR = 10
EXIT_NO_OBSERVATIONS = 20
EXIT_INCOMPLETE = 21
GLOBAL_RANK_LIMIT = 30
PACIFIC_TZ = ZoneInfo("America/Los_Angeles")

BLOCKED_MARKERS = (
    ("BOT_CHALLENGE", ("robot check", "captcha", "enter the characters you see", "type the characters")),
    ("LOGIN_REQUIRED", ("amazon sign-in", "amazon sign in", "sign in to your account")),
    ("ACCESS_DENIED", ("access denied", "request was blocked", "not authorized to access")),
)

SAFE_FAILURE_REASONS = {
    "ARTIFACT_BUILD_FAILED",
    "ARTIFACT_WRITE_FAILED",
    "ATTEMPT_ERROR",
    "BROWSER_CLEANUP_FAILED",
    "CATEGORY_MISSING",
    "CATEGORY_NOT_COMPLETE",
    "COLLECTOR_RUNTIME_FAILED",
    "COMPLETENESS_NOT_VERIFIED",
    "CONFIG_LOAD_FAILED",
    "CONTEXT_CLEANUP_FAILED",
    "DUPLICATE_ASIN",
    "DUPLICATE_CATEGORY_RESULT",
    "FIXTURE_LOAD_FAILED",
    "INVALID_RANKS",
    "MISSING_ASIN",
    "MISSING_PRICE_EVIDENCE",
    "MISSING_RANK",
    "MISSING_TITLE",
    "PRICE_VERIFICATION_FAILED",
    "SETUP_FAILED",
    "UNEXPECTED_CATEGORY",
    "UNSAFE_DIAGNOSTIC_REDACTED",
}
SAFE_PRICE_REASON_CODES = {
    "DETAIL_PRICE_FOUND",
    "PRICE_MISSING_UNEXPLAINED",
    "PRICE_NOT_PUBLIC",
    "VERIFICATION_BLOCKED",
}
SAFE_DISCOUNT_VERIFICATION_STATUSES = {"VERIFIED", "VERIFICATION_BLOCKED"}
SAFE_BRAND_VERIFICATION_STATUSES = {
    "VERIFIED",
    "MISSING",
    "CONFLICT",
    "IDENTITY_MISMATCH",
    "VERIFICATION_BLOCKED",
}
SAFE_BRAND_SOURCES = {
    "PRODUCT_OVERVIEW_BRAND_FIELD",
    "PRODUCT_DETAILS_BRAND_FIELD",
    "DETAIL_BULLET_BRAND_FIELD",
}
DEFAULT_REGISTRY_PATH = Path(__file__).resolve().parents[2] / "config" / "category-registry.json"
SAFE_AMAZON_ORIGIN = "https://www.amazon.com"


try:
    from brand_evidence import classify_brand_evidence
except ModuleNotFoundError as exc:
    if exc.name != "brand_evidence":
        raise
    _brand_module_path = Path(__file__).with_name("brand_evidence.py")
    _brand_module_spec = importlib.util.spec_from_file_location("brand_evidence", _brand_module_path)
    if _brand_module_spec is None or _brand_module_spec.loader is None:
        raise ImportError(f"Unable to load {_brand_module_path}") from exc
    _brand_module = importlib.util.module_from_spec(_brand_module_spec)
    _brand_module_spec.loader.exec_module(_brand_module)
    classify_brand_evidence = _brand_module.classify_brand_evidence


def _clean_text(value: Any) -> str | None:
    if value is None:
        return None
    cleaned = re.sub(r"\s+", " ", str(value)).strip()
    return cleaned or None


def _parse_rank(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    text = _clean_text(value)
    if not text:
        return None
    match = re.fullmatch(r"#?\s*(\d+)\s*", text)
    return int(match.group(1)) if match else None


def _parse_rating(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    match = re.search(r"\d+(?:\.\d+)?", str(value))
    if not match:
        return None
    try:
        return float(Decimal(match.group(0)).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP))
    except InvalidOperation:
        return None


def _parse_reviews(value: Any) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value if value >= 0 else None
    text = _clean_text(value)
    if not text or re.search(r"(^|\s)-\s*\d", text):
        return None
    match = re.search(r"\d[\d,]*", text)
    return int(match.group(0).replace(",", "")) if match else None


def _category_terms(display_name: str) -> set[str]:
    words = re.findall(r"[a-z0-9]+", display_name.casefold())
    return {word for word in words if word not in {"best", "sellers", "seller"}}


def detect_page_status(page: dict[str, Any], source: dict[str, Any]) -> tuple[str | None, str | None]:
    page_url = (_clean_text(page.get("url")) or "").casefold()
    if any(marker in page_url for marker in ("/ap/signin", "/gp/sign-in", "/signin")):
        return "LOGIN_REQUIRED", "LOGIN_REQUIRED"
    if any(marker in page_url for marker in ("validatecaptcha", "/captcha")):
        return "BOT_CHALLENGE", "BOT_CHALLENGE"

    title_heading = " ".join(
        filter(None, (_clean_text(page.get("title")), _clean_text(page.get("heading"))))
    ).casefold()
    if re.search(r"(^|\s)sign[ -]?in($|\s)", title_heading):
        return "LOGIN_REQUIRED", "LOGIN_REQUIRED"

    visible = " ".join(
        filter(None, (_clean_text(page.get("title")), _clean_text(page.get("heading")), _clean_text(page.get("body_text"))))
    ).casefold()
    for status, markers in BLOCKED_MARKERS:
        if any(marker in visible for marker in markers):
            return status, status

    category_visible = " ".join(
        filter(None, (_clean_text(page.get("title")), _clean_text(page.get("heading"))))
    ).casefold()
    visible_terms = set(re.findall(r"[a-z0-9]+", category_visible))
    expected_terms = _category_terms(str(source.get("display_name", "")))
    if expected_terms and not expected_terms.issubset(visible_terms):
        return "CATEGORY_MISMATCH", "CATEGORY_TITLE_MISMATCH"
    return None, None


def parse_card(card: dict[str, Any], target_count: int) -> tuple[dict[str, Any] | None, str | None]:
    rank = _parse_rank(card.get("rank"))
    if rank is None:
        return None, "MISSING_OR_INVALID_RANK"
    if rank < 1 or rank > GLOBAL_RANK_LIMIT:
        return None, "RANK_OUTSIDE_TARGET"
    asin = _clean_text(card.get("asin"))
    if not asin:
        return None, "MISSING_ASIN"
    raw_url = _clean_text(card.get("url"))
    return {
        "rank": rank,
        "asin": asin.upper(),
        "title": _clean_text(card.get("title")),
        "url": urljoin("https://www.amazon.com", raw_url) if raw_url else None,
        "price": _clean_text(card.get("price")),
        "rating": _parse_rating(card.get("rating")),
        "reviews": _parse_reviews(card.get("reviews")),
        "has_discount": None,
        "discounts": [],
    }, None


def _append_reason(reasons: list[str], reason: str | None) -> None:
    if reason and reason not in reasons:
        reasons.append(reason)


def _parse_cards(cards: list[dict[str, Any]], target_count: int) -> tuple[list[dict[str, Any]], list[str]]:
    observations: list[dict[str, Any]] = []
    reasons: list[str] = []
    ranks: set[int] = set()
    asins: set[str] = set()
    for card in cards:
        item, reason = parse_card(card, target_count)
        if not item:
            _append_reason(reasons, reason)
            continue
        if item["rank"] in ranks:
            _append_reason(reasons, "DUPLICATE_RANK")
            continue
        if item["asin"] in asins:
            _append_reason(reasons, "DUPLICATE_ASIN")
            continue
        ranks.add(item["rank"])
        asins.add(item["asin"])
        observations.append(item)
    return sorted(observations, key=lambda item: item["rank"]), reasons


def collect_chart_from_pages(
    source: dict[str, Any], pages: list[dict[str, Any]], target_count: int = 30
) -> dict[str, Any]:
    target_count = GLOBAL_RANK_LIMIT
    result: dict[str, Any] = {
        "category_key": source.get("category_key"),
        "url": source.get("url"),
        "status": "ZERO_OBSERVATIONS",
        "observation_count": 0,
        "pagination_decision": "NO_LATER_PAGE_AVAILABLE",
        "error_reason": None,
        "rejection_reasons": [],
        "observations": [],
    }
    if not pages:
        result["error_reason"] = "NO_PAGE_OBSERVED"
        return result

    all_observations: list[dict[str, Any]] = []
    all_reasons: list[str] = []
    seen_ranks: set[int] = set()
    seen_asins: set[str] = set()
    pagination_error: str | None = None

    for page_index, page in enumerate(pages):
        blocked_status, blocked_reason = detect_page_status(page, source)
        if blocked_status:
            result["status"] = blocked_status
            result["error_reason"] = blocked_reason
            break

        page_items, page_reasons = _parse_cards(list(page.get("cards") or []), target_count)
        for reason in page_reasons:
            _append_reason(all_reasons, reason)

        if page_index > 0:
            if not page_items:
                result["pagination_decision"] = "EXCLUDED_UNVERIFIED_CONTINUITY"
                pagination_error = "PAGINATION_CONTINUITY_UNVERIFIED"
                break
            minimum_rank = page_items[0]["rank"]
            maximum_seen = max(seen_ranks) if seen_ranks else 0
            if minimum_rank == 1:
                result["pagination_decision"] = "EXCLUDED_RESTART_AT_1"
                pagination_error = "PAGINATION_RESTARTED_AT_1"
                break
            if minimum_rank != maximum_seen + 1:
                result["pagination_decision"] = "EXCLUDED_UNVERIFIED_CONTINUITY"
                pagination_error = "PAGINATION_CONTINUITY_UNVERIFIED"
                break
            page_ranks = [item["rank"] for item in page_items]
            if page_ranks != list(range(maximum_seen + 1, page_ranks[-1] + 1)):
                result["pagination_decision"] = "EXCLUDED_UNVERIFIED_CONTINUITY"
                pagination_error = "PAGINATION_CONTINUITY_UNVERIFIED"
                break
            result["pagination_decision"] = "CONTINUED_VERIFIED_GLOBAL_RANKS"

        for item in page_items:
            if item["rank"] in seen_ranks:
                _append_reason(all_reasons, "DUPLICATE_RANK")
                continue
            if item["asin"] in seen_asins:
                _append_reason(all_reasons, "DUPLICATE_ASIN")
                continue
            seen_ranks.add(item["rank"])
            seen_asins.add(item["asin"])
            all_observations.append(item)
        if len(all_observations) >= target_count:
            if page_index == 0:
                result["pagination_decision"] = "NOT_NEEDED_TARGET_REACHED"
            break

    all_observations = sorted(all_observations, key=lambda item: item["rank"])
    result["observations"] = all_observations
    result["observation_count"] = len(all_observations)
    result["rejection_reasons"] = all_reasons
    if pagination_error:
        result["error_reason"] = pagination_error
    if result["status"] in {"LOGIN_REQUIRED", "BOT_CHALLENGE", "ACCESS_DENIED", "CATEGORY_MISMATCH"}:
        return result
    if not all_observations:
        result["status"] = "ZERO_OBSERVATIONS"
        result["error_reason"] = result["error_reason"] or ";".join(all_reasons) or "NO_VALID_OBSERVATIONS"
        return result

    expected_ranks = set(range(1, target_count + 1))
    missing_ranks = sorted(expected_ranks - seen_ranks)
    quality_reasons = [reason for reason in all_reasons if reason != "RANK_OUTSIDE_TARGET"]
    if not missing_ranks and not quality_reasons and not pagination_error:
        result["status"] = "COMPLETE"
        result["error_reason"] = None
    else:
        result["status"] = "PARTIAL"
        if result["error_reason"] is None:
            details = list(quality_reasons)
            if missing_ranks:
                details.append("MISSING_RANKS:" + ",".join(map(str, missing_ranks)))
            result["error_reason"] = ";".join(details) or None
    return result


def build_artifacts(
    config: dict[str, Any], chart_results: list[dict[str, Any]], market_date: str, observed_at: str
) -> tuple[dict[str, Any], dict[str, Any]]:
    sources = {source["category_key"]: source["url"] for source in config["sources"] if source.get("active")}
    snapshot: dict[str, Any] = {
        "schema_version": SNAPSHOT_SCHEMA,
        "marketplace": config.get("marketplace", "AMAZON_US"),
        "market_date": market_date,
        "observed_at": observed_at,
        "sources": sources,
    }
    charts = []
    total = 0
    by_key = {result["category_key"]: result for result in chart_results}
    for source in config["sources"]:
        if not source.get("active"):
            continue
        result = by_key.get(source["category_key"], {
            "category_key": source["category_key"],
            "url": source["url"],
            "status": "NOT_COLLECTED",
            "observation_count": 0,
            "pagination_decision": "NOT_ATTEMPTED",
            "error_reason": "COLLECTION_INCOMPLETE",
            "observations": [],
        })
        snapshot[source["category_key"]] = result["observations"]
        total += result["observation_count"]
        charts.append(
            {
                "category_key": result["category_key"],
                "url": result["url"],
                "status": result["status"],
                "observation_count": result["observation_count"],
                "pagination_decision": result["pagination_decision"],
                "error_reason": result["error_reason"],
            }
        )
    status = {
        "schema_version": STATUS_SCHEMA,
        "marketplace": config.get("marketplace", "AMAZON_US"),
        "market_date": market_date,
        "observed_at": observed_at,
        "total_observation_count": total,
        "charts": charts,
    }
    return snapshot, status


def _atomic_json_write(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def _canonical_asin(value: Any) -> str | None:
    text = _clean_text(value)
    if not text or re.fullmatch(r"[A-Z0-9]{10}", text) is None:
        return None
    return text


def _canonical_detail_url(asin: str) -> str:
    return f"{SAFE_AMAZON_ORIGIN}/dp/{asin}"


def _safe_reason(value: Any) -> str:
    text = _clean_text(value)
    category = text.split(":", 1)[0] if text else ""
    if category in SAFE_FAILURE_REASONS:
        return category
    return "UNSAFE_DIAGNOSTIC_REDACTED"


def _safe_price_reason(value: Any) -> str:
    text = _clean_text(value)
    return text if text in SAFE_PRICE_REASON_CODES else "UNSAFE_DIAGNOSTIC_REDACTED"


def _safe_discount_verification_status(value: Any) -> str:
    text = _clean_text(value)
    return text if text in SAFE_DISCOUNT_VERIFICATION_STATUSES else "UNSAFE_DIAGNOSTIC_REDACTED"


def _safe_brand_verification_status(value: Any) -> str:
    text = _clean_text(value)
    return text if text in SAFE_BRAND_VERIFICATION_STATUSES else "UNSAFE_DIAGNOSTIC_REDACTED"


def sanitize_recovery_diagnostic(
    diagnostic: dict[str, Any] | None,
    config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Copy only bounded, structured recovery fields safe for persistent artifacts."""
    source = diagnostic if isinstance(diagnostic, dict) else {}
    trusted_sources = _trusted_source_mapping(config)
    raw_attempts = source.get("attempts") if isinstance(source.get("attempts"), list) else []
    attempts = []
    for raw_attempt in raw_attempts:
        if len(attempts) == 3:
            break
        if not isinstance(raw_attempt, dict):
            continue
        observed_identities: set[tuple[str, str]] = set()
        raw_observations = raw_attempt.get("collected_observations")
        if isinstance(raw_observations, list):
            for raw_observation in raw_observations:
                if not isinstance(raw_observation, dict):
                    continue
                category_key = raw_observation.get("category_key")
                asin = _canonical_asin(raw_observation.get("asin"))
                if category_key in trusted_sources and asin is not None:
                    observed_identities.add((category_key, asin))
        evidence = []
        raw_evidence = raw_attempt.get("price_evidence")
        if isinstance(raw_evidence, list):
            for raw_item in raw_evidence:
                if not isinstance(raw_item, dict):
                    continue
                item: dict[str, Any] = {
                    "reason_code": _safe_price_reason(raw_item.get("reason_code")),
                    "supplemented": bool(raw_item.get("supplemented")),
                }
                if raw_item.get("source") == "DETAIL_PAGE":
                    item["source"] = "DETAIL_PAGE"
                category_key = raw_item.get("category_key")
                asin = _canonical_asin(raw_item.get("asin"))
                if asin is not None and (category_key, asin) in observed_identities:
                    item.update({
                        "category_key": category_key,
                        "asin": asin,
                        "chart_url": trusted_sources[category_key],
                        "detail_url": _canonical_detail_url(asin),
                    })
                evidence.append(item)
        discount_evidence = []
        raw_discount_evidence = raw_attempt.get("discount_evidence")
        if isinstance(raw_discount_evidence, list):
            for raw_item in raw_discount_evidence:
                if not isinstance(raw_item, dict):
                    continue
                item: dict[str, Any] = {
                    "verification_status": _safe_discount_verification_status(
                        raw_item.get("verification_status")
                    ),
                }
                if raw_item.get("source") == "DETAIL_PAGE":
                    item["source"] = "DETAIL_PAGE"
                category_key = raw_item.get("category_key")
                asin = _canonical_asin(raw_item.get("asin"))
                if asin is not None and (category_key, asin) in observed_identities:
                    item.update({
                        "category_key": category_key,
                        "asin": asin,
                        "detail_url": _canonical_detail_url(asin),
                    })
                discount_evidence.append(item)
        brand_evidence = []
        raw_brand_evidence = raw_attempt.get("brand_evidence")
        if isinstance(raw_brand_evidence, list):
            for raw_item in raw_brand_evidence:
                if not isinstance(raw_item, dict):
                    continue
                verification_status = _safe_brand_verification_status(
                    raw_item.get("verification_status")
                )
                item: dict[str, Any] = {
                    "verification_status": verification_status,
                }
                if raw_item.get("source") == "DETAIL_PAGE":
                    item["source"] = "DETAIL_PAGE"
                category_key = raw_item.get("category_key")
                asin = _canonical_asin(raw_item.get("asin"))
                if asin is not None and (category_key, asin) in observed_identities:
                    item.update({
                        "category_key": category_key,
                        "asin": asin,
                        "detail_url": _canonical_detail_url(asin),
                    })
                if verification_status == "VERIFIED":
                    raw_brand = _clean_text(raw_item.get("raw_brand"))
                    if raw_brand is not None and raw_item.get("brand_source") == "verified_metadata":
                        item["raw_brand"] = raw_brand
                        item["brand_source"] = "verified_metadata"
                        evidence_source = raw_item.get("evidence_source")
                        if evidence_source in SAFE_BRAND_SOURCES:
                            item["evidence_source"] = evidence_source
                brand_evidence.append(item)
        raw_failures = raw_attempt.get("failures")
        failures = []
        if isinstance(raw_failures, list):
            for failure in raw_failures:
                safe = _safe_reason(failure)
                if safe not in failures:
                    failures.append(safe)
        attempts.append({
            "attempt": len(attempts) + 1,
            "status": "COMPLETE" if raw_attempt.get("status") == "COMPLETE" and not failures else "FAILED",
            "failures": failures,
            "price_evidence": evidence,
            "discount_evidence": discount_evidence,
            "brand_evidence": brand_evidence,
        })
    completeness = "COMPLETE" if source.get("status") == "COMPLETE" and attempts and attempts[-1]["status"] == "COMPLETE" else "FAILED"
    return {"status": completeness, "attempt_count": len(attempts), "attempts": attempts}


def _diagnostic_summary(diagnostic: dict[str, Any]) -> tuple[int, int, int, list[str]]:
    price_verification_count = 0
    discount_verification_count = 0
    brand_verification_count = 0
    failures: list[str] = []
    for attempt in diagnostic["attempts"]:
        price_verification_count += len(attempt["price_evidence"])
        discount_verification_count += len(attempt["discount_evidence"])
        brand_verification_count += len(attempt.get("brand_evidence", []))
        for reason in attempt["failures"]:
            if reason not in failures:
                failures.append(reason)
    return price_verification_count, discount_verification_count, brand_verification_count, failures


def _collected_observation_identities(
    chart_results: list[dict[str, Any]],
) -> list[dict[str, str]]:
    identities: list[dict[str, str]] = []
    for chart in chart_results:
        category_key = chart.get("category_key")
        if not isinstance(category_key, str):
            continue
        for observation in chart.get("observations") or []:
            asin = _canonical_asin(observation.get("asin"))
            if asin is not None:
                identities.append({"category_key": category_key, "asin": asin})
    return identities


def _registry_source_urls(registry_path: Path) -> dict[str, str]:
    """Read trusted identities from the canonical Registry, never caller config.

    Full Registry/schema validation belongs to the shared generation/launch
    boundary; this reader also fails closed on malformed trust-bearing fields.
    """
    registry = json.loads(registry_path.read_text(encoding="utf-8-sig"))
    if (registry.get("schema_version") != "category-registry-v1"
            or registry.get("marketplace", {}).get("storage_code") != "AMAZON_US"
            or not isinstance(registry.get("categories"), list)
            or not registry["categories"]):
        raise ValueError("Invalid Category Registry")
    mapping: dict[str, str] = {}
    keys: set[str] = set()
    nodes: set[str] = set()
    for category in registry["categories"]:
        key = category.get("category_key")
        node = category.get("amazon_node_id")
        source_url = category.get("source_url")
        if (not isinstance(key, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", key)
                or not isinstance(node, str) or not node.isdigit()
                or key in keys or node in nodes
                or not isinstance(category.get("enabled"), bool)
                or not isinstance(source_url, str)):
            raise ValueError("Invalid Category Registry source")
        url = urlsplit(source_url)
        if (url.scheme != "https" or url.netloc != "www.amazon.com"
                or "/zgbs/" not in url.path or url.path.rstrip("/").split("/")[-1] != node
                or url.query or url.fragment):
            raise ValueError("Invalid Category Registry source URL")
        keys.add(key)
        nodes.add(node)
        if category["enabled"]:
            mapping[key] = source_url
    return mapping


def _trusted_source_mapping(
    config: dict[str, Any] | None, registry_path: Path = DEFAULT_REGISTRY_PATH,
) -> dict[str, str]:
    mapping: dict[str, str] = {}
    if not isinstance(config, dict):
        return mapping
    trusted_source_urls = _registry_source_urls(registry_path)
    for source in config.get("sources", []):
        if not isinstance(source, dict) or not source.get("active"):
            continue
        category_key = source.get("category_key")
        source_url = source.get("url")
        approved_url = trusted_source_urls.get(category_key)
        if approved_url is not None and source_url == approved_url:
            mapping[category_key] = approved_url
    return mapping


def _safe_status_for_persistence(
    status: dict[str, Any], config: dict[str, Any] | None = None
) -> dict[str, Any]:
    safe_status = dict(status)
    safe_status["marketplace"] = "AMAZON_US"
    trusted_sources = _trusted_source_mapping(config)
    safe_charts = []
    for chart in status.get("charts", []):
        if not isinstance(chart, dict):
            continue
        category_key = chart.get("category_key")
        chart_url = chart.get("url")
        trusted_url = trusted_sources.get(category_key)
        trusted_identity = trusted_url is not None and chart_url == trusted_url
        safe_charts.append({
            "category_key": category_key if trusted_identity else "REDACTED",
            "url": trusted_url if trusted_identity else None,
            "status": chart.get("status") if chart.get("status") in {
                "ACCESS_DENIED", "BOT_CHALLENGE", "BROWSER_ERROR", "CATEGORY_MISMATCH",
                "COMPLETE", "LOGIN_REQUIRED", "NOT_COLLECTED", "PARTIAL", "ZERO_OBSERVATIONS",
            } else "FAILED",
            "observation_count": int(chart.get("observation_count", 0)),
            "pagination_decision": chart.get("pagination_decision") if chart.get("pagination_decision") in {
                "CONTINUED_VERIFIED_GLOBAL_RANKS", "EXCLUDED_RESTART_AT_1",
                "EXCLUDED_UNVERIFIED_CONTINUITY", "NO_LATER_PAGE_AVAILABLE", "NOT_ATTEMPTED",
                "NOT_NEEDED_TARGET_REACHED",
            } else "NOT_ATTEMPTED",
            "error_reason": _safe_reason(chart.get("error_reason")) if chart.get("error_reason") else None,
        })
    safe_status["charts"] = safe_charts
    return safe_status


def _write_failure_artifacts(
    output_root: str | Path,
    market_date: str,
    observed_at: str,
    reason: str,
) -> dict[str, Any]:
    """Persist a minimal safe failure result without relying on collection data."""
    day_root = Path(output_root) / market_date
    status_path = day_root / "best-sellers-collection-status.json"
    diagnostic_path = day_root / "price-completeness-diagnostic.json"
    safe_reason = _safe_reason(reason)
    diagnostic = {
        "status": "FAILED",
        "attempt_count": 1,
        "attempts": [{
            "attempt": 1,
            "status": "FAILED",
            "failures": [safe_reason],
            "price_evidence": [],
            "discount_evidence": [],
            "brand_evidence": [],
        }],
    }
    status = {
        "schema_version": STATUS_SCHEMA,
        "market_date": market_date,
        "observed_at": observed_at,
        "total_observation_count": 0,
        "charts": [],
        "CompletenessStatus": "FAILED",
        "AttemptCount": 1,
        "PriceVerificationCount": 0,
        "DiscountVerificationCount": 0,
        "BrandVerificationCount": 0,
        "DiagnosticPath": str(diagnostic_path.resolve()),
        "FailureReasons": [safe_reason],
    }
    write_error = None
    try:
        _atomic_json_write(status_path, status)
    except Exception as exc:
        write_error = exc
    try:
        _atomic_json_write(diagnostic_path, diagnostic)
    except Exception as exc:
        if write_error is None:
            write_error = exc
    if write_error is not None:
        raise write_error
    return {
        "Status": "ERROR",
        "ExitCode": EXIT_RUNTIME_ERROR,
        "TotalObservations": 0,
        "SnapshotPath": None,
        "StatusPath": str(status_path.resolve()),
        "CompletenessStatus": "FAILED",
        "AttemptCount": 1,
        "PriceVerificationCount": 0,
        "DiscountVerificationCount": 0,
        "BrandVerificationCount": 0,
        "DiagnosticPath": str(diagnostic_path.resolve()),
        "FailureReasons": [safe_reason],
        "Browser": "UNAVAILABLE",
    }


def write_collection_artifacts(
    output_root: str | Path,
    market_date: str,
    snapshot: dict[str, Any],
    status: dict[str, Any],
    diagnostic: dict[str, Any] | None = None,
    config: dict[str, Any] | None = None,
    preserve_complete_categories: bool = False,
) -> dict[str, Any]:
    day_root = Path(output_root) / market_date
    status_path = day_root / "best-sellers-collection-status.json"
    snapshot_path = day_root / "amazon-bestsellers.json"
    diagnostic_path = day_root / "price-completeness-diagnostic.json"
    if diagnostic is None:
        diagnostic = {
            "status": "FAILED",
            "attempt_count": 1,
            "attempts": [{"attempt": 1, "status": "FAILED", "failures": ["COMPLETENESS_NOT_VERIFIED"], "price_evidence": [], "discount_evidence": [], "brand_evidence": []}],
        }
    safe_diagnostic = sanitize_recovery_diagnostic(diagnostic, config)
    price_verification_count, discount_verification_count, brand_verification_count, failure_reasons = _diagnostic_summary(safe_diagnostic)
    completeness = safe_diagnostic["status"]
    status = _safe_status_for_persistence(status, config)
    status.update({
        "CompletenessStatus": completeness,
        "AttemptCount": safe_diagnostic["attempt_count"],
        "PriceVerificationCount": price_verification_count,
        "DiscountVerificationCount": discount_verification_count,
        "BrandVerificationCount": brand_verification_count,
        "DiagnosticPath": str(diagnostic_path.resolve()),
        "FailureReasons": failure_reasons,
    })
    if completeness != "COMPLETE" and preserve_complete_categories and config:
        complete_keys = []
        evidence = [item for attempt in safe_diagnostic.get("attempts", []) for item in attempt.get("price_evidence", [])]
        for source in config["sources"]:
            key = source["category_key"]
            chart_status = next((chart for chart in status["charts"] if chart["category_key"] == key), None)
            if not source.get("active") or not chart_status:
                continue
            chart = {**chart_status, "observations": snapshot.get(key, [])}
            if not validate_collection_attempt({**config, "sources": [source]}, [chart], [], evidence):
                complete_keys.append(key)
        if complete_keys:
            partial_path = day_root / "partial-captures" / uuid4().hex / "amazon-bestsellers.json"
            partial_snapshot = dict(snapshot)
            for source in config["sources"]:
                if source["category_key"] not in complete_keys:
                    partial_snapshot[source["category_key"]] = []
            _atomic_json_write(partial_path, partial_snapshot)
            status["PartialSnapshotPath"] = str(partial_path.resolve())
            status["CompleteCategories"] = complete_keys
    _atomic_json_write(status_path, status)
    _atomic_json_write(diagnostic_path, safe_diagnostic)
    if completeness != "COMPLETE":
        return {
            "exit_code": EXIT_INCOMPLETE,
            "snapshot_path": None,
            "status_path": str(status_path.resolve()),
            "diagnostic_path": str(diagnostic_path.resolve()),
            "status": status,
        }
    _atomic_json_write(snapshot_path, snapshot)
    return {
        "exit_code": EXIT_OK,
        "snapshot_path": str(snapshot_path.resolve()),
        "status_path": str(status_path.resolve()),
        "diagnostic_path": str(diagnostic_path.resolve()),
        "status": status,
    }


def _extract_page(page: Any) -> dict[str, Any]:
    return page.evaluate(
        r"""
        () => {
          const text = (root, selectors) => {
            for (const selector of selectors) {
              const node = root.querySelector(selector);
              if (node && node.textContent && node.textContent.trim()) return node.textContent.trim();
            }
            return null;
          };
          const attr = (root, selectors, name) => {
            for (const selector of selectors) {
              const node = root.querySelector(selector);
              if (node && node.getAttribute(name)) return node.getAttribute(name);
            }
            return null;
          };
          const roots = Array.from(document.querySelectorAll('#gridItemRoot'));
          const cards = roots.map(root => {
            const link = root.querySelector('a[href*="/dp/"]');
            const href = link ? link.getAttribute('href') : null;
            const asinNode = root.querySelector('[data-asin]');
            const match = href ? href.match(/\/dp\/([A-Z0-9]{10})/i) : null;
            return {
              rank: text(root, ['.zg-bdg-text', '.zg-badge-text']),
              asin: (asinNode && asinNode.getAttribute('data-asin')) || (match && match[1]) || null,
              title: text(root, ['._cDEzb_p13n-sc-css-line-clamp-3_g3dy1', '._cDEzb_p13n-sc-css-line-clamp-4_2q2cc', 'a.a-link-normal span']) || attr(root, ['img[alt]'], 'alt'),
              url: href,
              price: text(root, ['.p13n-sc-price', '[class*="p13n-sc-price_"]', '.a-price .a-offscreen']),
              rating: attr(root, ['[aria-label*="out of 5 stars"]'], 'aria-label') || text(root, ['.a-icon-alt']),
              reviews: text(root, ['a[href*="/product-reviews/"] .a-size-small', 'a[href*="customerReviews"] .a-size-small'])
            };
          });
          return {
            url: window.location.href || null,
            title: document.title || null,
            heading: text(document, ['h1', '#zg_banner_text']),
            body_text: (document.body && document.body.innerText || '').slice(0, 20000),
            cards
          };
        }
        """
    )


def classify_detail_price(page: dict[str, Any]) -> dict[str, Any]:
    """Classify the public price evidence captured from one product detail page."""
    blocked_markers = set(page.get("blocked_markers") or [])
    for status, _ in BLOCKED_MARKERS:
        if status in blocked_markers:
            return {"reason_code": "VERIFICATION_BLOCKED", "price": None, "page_status": status}

    price = _clean_text(page.get("price"))
    if price:
        return {"reason_code": "DETAIL_PRICE_FOUND", "price": price, "page_status": None}

    public_price_unavailable = " ".join(
        filter(None, (_clean_text(page.get("availability")), _clean_text(page.get("buying_options"))))
    ).casefold()
    unavailable_markers = (
        "currently unavailable",
        "out of stock",
        "no featured offers available",
        "see all buying options",
        "sign in to see price",
    )
    if any(marker in public_price_unavailable for marker in unavailable_markers):
        return {"reason_code": "PRICE_NOT_PUBLIC", "price": None, "page_status": None}
    return {"reason_code": "PRICE_MISSING_UNEXPLAINED", "price": None, "page_status": None}


def _discount_amount_from_text(value: Any) -> str | None:
    text = _clean_text(value)
    if not text:
        return None
    percentage = re.search(r"(\d+(?:\.\d+)?)\s*%", text)
    if percentage:
        try:
            amount = Decimal(percentage.group(1)).normalize()
        except InvalidOperation:
            return None
        return f"{amount:f}% off"
    currency = re.search(r"\$\s*(\d+(?:,\d{3})*(?:\.\d{1,2})?)", text)
    if currency:
        amount = _usd_amount(currency.group(0))
        return _format_usd_discount(amount) if amount is not None else None
    return None


def _has_explicit_discount_language(value: Any) -> bool:
    text = _clean_text(value)
    if not text:
        return False
    return re.search(r"\b(?:save|savings?|off|discount(?:ed)?)\b", text, re.IGNORECASE) is not None


def _is_prime_exclusive_offer(value: Any) -> bool:
    """Recognize a Prime-only price, while excluding delivery-only Prime messaging."""
    text = _clean_text(value)
    if not text or re.search(r"\bprime\b", text, re.IGNORECASE) is None:
        return False
    if _has_explicit_discount_language(text):
        return True
    if re.search(r"\bprime\s+(?:exclusive|price)\b", text, re.IGNORECASE):
        return True
    return _usd_amount(text) is not None and re.search(
        r"\b(?:with\s+prime|prime\s+members?)\b", text, re.IGNORECASE
    ) is not None


def _usd_amount(value: Any) -> Decimal | None:
    text = _clean_text(value)
    if not text:
        return None
    match = re.search(r"\$\s*(\d+(?:,\d{3})*(?:\.\d{1,2})?)", text)
    if not match:
        return None
    try:
        return Decimal(match.group(1).replace(",", ""))
    except InvalidOperation:
        return None


def _format_usd_discount(value: Decimal) -> str:
    return f"${value.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP):.2f} off"


def _is_verified_detail_identity(page: dict[str, Any], asin: str) -> bool:
    """Require a public, extracted product identity that matches the requested ASIN."""
    return _canonical_asin(page.get("detail_asin")) == asin


def classify_detail_discounts(page: dict[str, Any]) -> dict[str, Any]:
    """Classify only publicly visible, verifiable product-detail discounts."""
    blocked_markers = set(page.get("blocked_markers") or [])
    if any(status in blocked_markers for status, _ in BLOCKED_MARKERS):
        return {"has_discount": None, "discounts": []}
    if not _clean_text(page.get("title")) and not _clean_text(page.get("heading")):
        return {"has_discount": None, "discounts": []}

    discounts: list[dict[str, str]] = []
    coupon_amount = _discount_amount_from_text(page.get("coupon"))
    if coupon_amount:
        discounts.append({"kind": "COUPON", "amount": coupon_amount})

    prime_text = _clean_text(page.get("prime_discount"))
    verified_prime_signal = _is_prime_exclusive_offer(prime_text)
    if verified_prime_signal:
        prime_amount = _discount_amount_from_text(prime_text) if _has_explicit_discount_language(prime_text) else None
        if prime_amount is None:
            prime_price = _usd_amount(prime_text)
            prime_amount = f"Prime price ${prime_price:.2f}" if prime_price is not None else "Prime exclusive"
        discounts.append({
            "kind": "PRIME_EXCLUSIVE",
            "amount": prime_amount,
        })

    list_price = _usd_amount(page.get("list_price"))
    current_price = _usd_amount(page.get("current_price"))
    if list_price is not None and current_price is not None and list_price > current_price:
        kind = "PRIME_EXCLUSIVE" if verified_prime_signal else "PRICE_DROP"
        discount = {"kind": kind, "amount": _format_usd_discount(list_price - current_price)}
        if discount not in discounts:
            discounts.append(discount)

    return {"has_discount": bool(discounts), "discounts": discounts}


def _extract_detail_page(page: Any) -> dict[str, Any]:
    """Extract price signals and explicit, structured brand candidates from a product page."""
    blocked_marker_map = {status: markers for status, markers in BLOCKED_MARKERS}
    extracted = page.evaluate(
        r"""
        () => {
          const text = (selectors) => {
            for (const selector of selectors) {
              const node = document.querySelector(selector);
              if (node && node.textContent && node.textContent.trim()) return node.textContent.trim();
            }
            return null;
          };
          const attr = (selectors, name) => {
            for (const selector of selectors) {
              const node = document.querySelector(selector);
              if (node && node.getAttribute(name)) return node.getAttribute(name);
            }
            return null;
          };
          const primaryOffer = document.querySelector('#corePrice_feature_div')
            || document.querySelector('#apex_desktop')
            || document.querySelector('#buybox_feature_div');
          const listPriceOffer = document.querySelector('#corePriceDisplay_desktop_feature_div')
            || document.querySelector('#apex_desktop')
            || primaryOffer;
          const offerText = (offer, selectors) => {
            if (!offer) return null;
            for (const selector of selectors) {
              const node = offer.querySelector(selector);
              if (node && node.textContent && node.textContent.trim()) return node.textContent.trim();
            }
            return null;
          };
          const exactBrandTableValue = (selectors) => {
            for (const selector of selectors) {
              for (const row of document.querySelectorAll(selector + ' tr')) {
                const cells = row.querySelectorAll(':scope > th, :scope > td');
                const label = cells[0];
                const value = cells[1];
                if (!label || !value) continue;
                if (label.textContent.trim().replace(/:\s*$/, '') !== 'Brand') continue;
                if (value.textContent && value.textContent.trim()) return value.textContent.trim();
              }
            }
            return null;
          };
          const explicitDetailBulletBrand = () => {
            for (const bullet of document.querySelectorAll('#detailBullets_feature_div li, #detailBulletsWrapper_feature_div li')) {
              const match = /^\s*Brand\s*:\s*(.+?)\s*$/.exec(bullet.textContent || '');
              if (match && match[1].trim()) return match[1].trim();
            }
            return null;
          };
          const visible = [document.title, document.body && document.body.innerText || ''].join(' ').toLowerCase();
          const blocked = [];
          const markers = """
        + json.dumps(blocked_marker_map)
        + r""";
          for (const [status, values] of Object.entries(markers)) {
            if (values.some(value => visible.includes(value))) blocked.push(status);
          }
          return {
            url: window.location.href || null,
            title: document.title || null,
            heading: text(['h1', '#productTitle']),
            detail_asin: attr(['#ASIN', 'input[name="ASIN"]'], 'value') || attr(['[data-asin]'], 'data-asin'),
            price: text(['#corePrice_feature_div .a-price .a-offscreen', '#corePrice_feature_div .a-offscreen', '.a-price .a-offscreen', '#priceblock_ourprice']),
            primary_offer_current_price: offerText(primaryOffer, ['.priceToPay .a-offscreen', '.apexPriceToPay .a-offscreen', '.a-price:not(.a-text-price) .a-offscreen', '#priceblock_ourprice']),
            primary_offer_list_price: offerText(listPriceOffer, ['.basisPrice .a-offscreen', '.a-text-price .a-offscreen', '#priceblock_listprice']),
            coupon: text(['#couponText', '#couponFeature .a-color-success', '#couponFeature .a-text-bold']),
            prime_discount: text(['#primeExclusivePricing', '#primedp', '#prime-exclusive-price', '[data-feature-name="primeExclusivePricing"]']),
            availability: text(['#availability span', '#availability']),
            buying_options: text(['#buybox_feature_div', '#buybox', '#outOfStock', '#olp_feature_div']),
            brand_candidates: [
              ['PRODUCT_OVERVIEW_BRAND_FIELD', exactBrandTableValue(['#productOverview_feature_div'])],
              ['PRODUCT_DETAILS_BRAND_FIELD', exactBrandTableValue(['#productDetails_detailBullets_sections1', '#productDetails_techSpec_section_1'])],
              ['DETAIL_BULLET_BRAND_FIELD', explicitDetailBulletBrand()]
            ].filter(([, value]) => value).map(([evidence_source, value]) => ({evidence_source, value})),
            blocked_markers: blocked
          };
        }
        """
    )
    allowed_statuses = {status for status, _ in BLOCKED_MARKERS}
    result = {
        "url": _clean_text(extracted.get("url")),
        "title": _clean_text(extracted.get("title")),
        "heading": _clean_text(extracted.get("heading")),
        "detail_asin": _canonical_asin(extracted.get("detail_asin")),
        "price": _clean_text(extracted.get("price")),
        "current_price": _clean_text(extracted.get("primary_offer_current_price")),
        "list_price": _clean_text(extracted.get("primary_offer_list_price")),
        "coupon": _clean_text(extracted.get("coupon")),
        "prime_discount": _clean_text(extracted.get("prime_discount")),
        "availability": _clean_text(extracted.get("availability")),
        "buying_options": _clean_text(extracted.get("buying_options")),
        "brand_candidates": [],
        "blocked_markers": list(dict.fromkeys(
            marker for marker in (extracted.get("blocked_markers") or []) if marker in allowed_statuses
        )),
    }
    if "brand_candidates" in extracted:
        trusted_sources = {
            "PRODUCT_OVERVIEW_BRAND_FIELD",
            "PRODUCT_DETAILS_BRAND_FIELD",
            "DETAIL_BULLET_BRAND_FIELD",
        }
        brand_candidates = []
        for candidate in extracted.get("brand_candidates") or []:
            if not isinstance(candidate, dict):
                continue
            evidence_source = candidate.get("evidence_source")
            value = _clean_text(candidate.get("value"))
            if evidence_source in trusted_sources and value is not None:
                brand_candidates.append({"evidence_source": evidence_source, "value": value})
        result["brand_candidates"] = brand_candidates
    return result


def verify_chart_prices(
    context: Any, chart_results: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str]]:
    """Supplement missing chart prices with classified public detail-page evidence."""
    evidence: list[dict[str, Any]] = []
    failures: list[str] = []
    for chart in chart_results:
        for observation in chart.get("observations") or []:
            if observation.get("price") is not None:
                continue
            asin = _canonical_asin(observation.get("asin"))
            evidence_asin = asin or "UNKNOWN_ASIN"
            detail_url = _canonical_detail_url(asin) if asin is not None else None
            classification: dict[str, Any]
            tab = None
            try:
                if asin is None:
                    classification = {
                        "reason_code": "VERIFICATION_BLOCKED",
                        "price": None,
                        "page_status": "INVALID_ASIN",
                    }
                else:
                    tab = context.new_page()
                    tab.goto(detail_url, wait_until="domcontentloaded", timeout=60000)
                    classification = classify_detail_price(_extract_detail_page(tab))
            except Exception as exc:
                classification = {
                    "reason_code": "VERIFICATION_BLOCKED",
                    "price": None,
                    "page_status": type(exc).__name__,
                }
            finally:
                if tab is not None:
                    try:
                        tab.close()
                    except Exception:
                        pass

            reason_code = classification["reason_code"]
            supplemented = reason_code == "DETAIL_PRICE_FOUND"
            if supplemented:
                observation["price"] = classification["price"]
            evidence.append({
                "category_key": chart.get("category_key"),
                "asin": evidence_asin,
                "chart_url": chart.get("url"),
                "detail_url": detail_url,
                "reason_code": reason_code,
                "supplemented": supplemented,
                "source": "DETAIL_PAGE",
            })
            if reason_code == "VERIFICATION_BLOCKED":
                failures.append(
                    f"PRICE_VERIFICATION_FAILED:{evidence_asin}:{reason_code}:{classification['page_status']}"
                )
            elif reason_code not in {"DETAIL_PRICE_FOUND", "PRICE_NOT_PUBLIC"}:
                failures.append(f"PRICE_VERIFICATION_FAILED:{evidence_asin}:{reason_code}")
    return chart_results, evidence, failures


def verify_chart_discounts(
    context: Any, chart_results: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    """Verify discounts and classify brands from one detail-page navigation per observation."""
    discount_evidence: list[dict[str, Any]] = []
    brand_evidence: list[dict[str, Any]] = []
    for chart in chart_results:
        for observation in chart.get("observations") or []:
            asin = _canonical_asin(observation.get("asin"))
            evidence_asin = asin or "UNKNOWN_ASIN"
            detail_url = _canonical_detail_url(asin) if asin is not None else None
            classification = {"has_discount": None, "discounts": []}
            brand_classification = {
                "verification_status": "IDENTITY_MISMATCH",
                "raw_brand": None,
                "brand_source": "unknown",
                "evidence_source": None,
            }
            tab = None
            try:
                if asin is None:
                    pass
                else:
                    tab = context.new_page()
                    tab.goto(detail_url, wait_until="domcontentloaded", timeout=60000)
                    detail_page = _extract_detail_page(tab)
                    classification = (
                        classify_detail_discounts(detail_page)
                        if _is_verified_detail_identity(detail_page, asin)
                        else {"has_discount": None, "discounts": []}
                    )
                    try:
                        brand_classification = classify_brand_evidence(detail_page, asin)
                    except Exception:
                        brand_classification = {
                            "verification_status": "VERIFICATION_BLOCKED",
                            "raw_brand": None,
                            "brand_source": "unknown",
                            "evidence_source": None,
                        }
            except Exception:
                classification = {"has_discount": None, "discounts": []}
                brand_classification = {
                    "verification_status": "VERIFICATION_BLOCKED",
                    "raw_brand": None,
                    "brand_source": "unknown",
                    "evidence_source": None,
                }
            finally:
                if tab is not None:
                    try:
                        tab.close()
                    except Exception:
                        pass

            observation["has_discount"] = classification["has_discount"]
            observation["discounts"] = classification["discounts"]
            observation.pop("raw_brand", None)
            observation.pop("brand_source", None)
            discount_evidence.append({
                "category_key": chart.get("category_key"),
                "asin": evidence_asin,
                "detail_url": detail_url,
                "verification_status": "VERIFIED" if classification["has_discount"] is not None else "VERIFICATION_BLOCKED",
                "source": "DETAIL_PAGE",
            })
            brand_item = {
                "category_key": chart.get("category_key"),
                "asin": evidence_asin,
                "detail_url": detail_url,
                "verification_status": brand_classification.get(
                    "verification_status", "VERIFICATION_BLOCKED"
                ),
                "source": "DETAIL_PAGE",
            }
            if brand_item["verification_status"] == "VERIFIED":
                brand_item["raw_brand"] = brand_classification.get("raw_brand")
                brand_item["brand_source"] = brand_classification.get("brand_source")
                brand_item["evidence_source"] = brand_classification.get("evidence_source")
                observation["raw_brand"] = brand_classification["raw_brand"]
                observation["brand_source"] = brand_classification["brand_source"]
            brand_evidence.append(brand_item)
    return chart_results, discount_evidence, brand_evidence


def _launch_visible_browser(playwright: Any, headless: bool) -> tuple[Any, str]:
    errors = []
    for channel, label in (("msedge", "MICROSOFT_EDGE"), ("chrome", "GOOGLE_CHROME")):
        try:
            return playwright.chromium.launch(channel=channel, headless=headless), label
        except Exception as exc:  # Playwright supplies environment-specific exception types.
            errors.append(f"{label}:{type(exc).__name__}")
    try:
        return playwright.chromium.launch(headless=headless), "PLAYWRIGHT_CHROMIUM"
    except Exception as exc:
        errors.append(f"PLAYWRIGHT_CHROMIUM:{type(exc).__name__}")
        raise RuntimeError("No supported browser could be launched (" + ",".join(errors) + ")") from exc


def validate_collection_attempt(
    config: dict[str, Any],
    chart_results: list[dict[str, Any]],
    price_failures: list[str],
    price_evidence: list[dict[str, Any]] | None = None,
) -> list[str]:
    """Return deterministic reasons that make one complete attempt unpublishable."""
    failures = list(dict.fromkeys(price_failures))
    active_sources = [source for source in config["sources"] if source.get("active")]
    charts_by_key = {chart.get("category_key"): chart for chart in chart_results}
    active_keys = {source["category_key"] for source in active_sources}
    accepted_null_prices = {
        (_clean_text(item.get("category_key")), _clean_text(item.get("asin")))
        for item in (price_evidence or [])
        if item.get("reason_code") == "PRICE_NOT_PUBLIC"
    }
    failed_price_asins = {
        failure.split(":", 2)[1]
        for failure in price_failures
        if failure.startswith("PRICE_VERIFICATION_FAILED:") and failure.count(":") >= 2
    }
    category_counts: dict[Any, int] = {}
    for chart in chart_results:
        category_key = chart.get("category_key")
        category_counts[category_key] = category_counts.get(category_key, 0) + 1
    for category_key, count in category_counts.items():
        if count > 1:
            _append_reason(failures, f"DUPLICATE_CATEGORY_RESULT:{category_key}")

    for source in active_sources:
        category_key = source["category_key"]
        chart = charts_by_key.get(category_key)
        if chart is None:
            _append_reason(failures, f"CATEGORY_MISSING:{category_key}")
            continue
        if chart.get("status") != "COMPLETE":
            _append_reason(
                failures,
                f"CATEGORY_NOT_COMPLETE:{category_key}:{chart.get('status') or 'UNKNOWN'}",
            )

        observations = list(chart.get("observations") or [])
        ranks = [observation.get("rank") for observation in observations]
        if ranks != list(range(1, GLOBAL_RANK_LIMIT + 1)):
            _append_reason(failures, f"INVALID_RANKS:{category_key}")

        seen_asins: set[str] = set()
        for observation in observations:
            rank = observation.get("rank")
            asin = _clean_text(observation.get("asin"))
            title = _clean_text(observation.get("title"))
            if rank is None:
                _append_reason(failures, f"MISSING_RANK:{category_key}")
            if not asin:
                _append_reason(failures, f"MISSING_ASIN:{category_key}:{rank}")
            elif asin in seen_asins:
                _append_reason(failures, f"DUPLICATE_ASIN:{category_key}:{asin}")
            else:
                seen_asins.add(asin)
            if not title:
                _append_reason(failures, f"MISSING_TITLE:{category_key}:{rank}")
            if (
                observation.get("price") is None
                and (category_key, asin) not in accepted_null_prices
                and asin not in failed_price_asins
            ):
                _append_reason(
                    failures,
                    f"MISSING_PRICE_EVIDENCE:{category_key}:{asin or 'UNKNOWN_ASIN'}",
                )

    for chart in chart_results:
        category_key = chart.get("category_key")
        if category_key not in active_keys:
            _append_reason(failures, f"UNEXPECTED_CATEGORY:{category_key}")
    return failures


class _CleanupFailure(RuntimeError):
    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


def _collect_attempt(
    browser: Any, config: dict[str, Any]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str], list[dict[str, Any]], list[dict[str, Any]]]:
    """Collect, price-verify, and strictly validate one ephemeral context."""
    results: list[dict[str, Any]] = []
    context = browser.new_context(user_agent=(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"
    ))
    try:
        for source in config["sources"]:
            if not source.get("active"):
                continue
            pages = []
            tab = None
            chart_result = None
            try:
                tab = context.new_page()
                tab.goto(source["url"], wait_until="domcontentloaded", timeout=60000)
                pages.append(_extract_page(tab))
                preliminary = collect_chart_from_pages(source, pages, GLOBAL_RANK_LIMIT)
                while preliminary["observation_count"] < GLOBAL_RANK_LIMIT:
                    if preliminary["status"] in {"LOGIN_REQUIRED", "BOT_CHALLENGE", "ACCESS_DENIED", "CATEGORY_MISMATCH"}:
                        break
                    next_link = tab.locator('a[aria-label="Next page"]:not(.a-disabled), .a-pagination .a-last a').first
                    if next_link.count() == 0:
                        break
                    next_link.click()
                    tab.wait_for_load_state("domcontentloaded")
                    pages.append(_extract_page(tab))
                    preliminary = collect_chart_from_pages(source, pages, GLOBAL_RANK_LIMIT)
                    if preliminary["pagination_decision"].startswith("EXCLUDED_"):
                        break
                chart_result = preliminary
            except Exception as exc:
                chart_result = {
                    "category_key": source["category_key"], "url": source["url"], "status": "BROWSER_ERROR",
                    "observation_count": 0, "pagination_decision": "NOT_ATTEMPTED",
                    "error_reason": f"BROWSER_ERROR:{type(exc).__name__}", "rejection_reasons": [], "observations": [],
                }
            finally:
                if tab is not None:
                    try:
                        tab.close()
                    except Exception:
                        pass
            results.append(chart_result)

        verified, evidence, price_failures = verify_chart_prices(context, results)
        failures = validate_collection_attempt(config, verified, price_failures, evidence)
        if failures:
            return verified, evidence, failures, [], []
        discount_verified, discount_evidence, brand_evidence = verify_chart_discounts(context, verified)
        return discount_verified, evidence, failures, discount_evidence, brand_evidence
    finally:
        try:
            context.close()
        except Exception as exc:
            raise _CleanupFailure(f"CONTEXT_CLEANUP_FAILED:{type(exc).__name__}") from None


def collect_with_recovery(
    config: dict[str, Any],
    headless: bool = False,
    playwright_factory: Any | None = None,
    max_attempts: int = 3,
    preserve_complete_categories: bool = False,
) -> tuple[list[dict[str, Any]], str, dict[str, Any]]:
    """Retry failed complete collections in new ephemeral browser sessions."""
    if playwright_factory is None:
        from playwright.sync_api import sync_playwright

        playwright_factory = sync_playwright

    attempt_limit = min(max(int(max_attempts), 1), 3)
    diagnostic: dict[str, Any] = {"status": "FAILED", "attempt_count": 0, "attempts": []}
    browser_name = "UNAVAILABLE"
    complete_charts: dict[str, dict[str, Any]] = {}
    with playwright_factory() as playwright:
        for attempt_number in range(1, attempt_limit + 1):
            browser = None
            failures: list[str]
            evidence: list[dict[str, Any]] = []
            discount_evidence: list[dict[str, Any]] = []
            brand_evidence: list[dict[str, Any]] = []
            charts: list[dict[str, Any]] = []
            cleanup_failed = False
            try:
                browser, browser_name = _launch_visible_browser(playwright, headless)
                charts, evidence, failures, discount_evidence, brand_evidence = _collect_attempt(browser, config)
            except _CleanupFailure as exc:
                failures = [exc.reason]
                cleanup_failed = True
            except Exception as exc:
                failures = [f"ATTEMPT_ERROR:{type(exc).__name__}"]
            finally:
                if browser is not None:
                    try:
                        browser.close()
                    except Exception as exc:
                        _append_reason(failures, f"BROWSER_CLEANUP_FAILED:{type(exc).__name__}")
                        cleanup_failed = True

            attempt_status = "COMPLETE" if not failures else "FAILED"
            diagnostic["attempts"].append({
                "attempt": attempt_number,
                "status": attempt_status,
                "failures": failures,
                "price_evidence": evidence,
                "discount_evidence": discount_evidence,
                "brand_evidence": brand_evidence,
                "collected_observations": _collected_observation_identities(charts),
            })
            diagnostic["attempt_count"] = attempt_number
            if not failures:
                diagnostic["status"] = "COMPLETE"
                return charts, browser_name, diagnostic
            if cleanup_failed:
                break
            if preserve_complete_categories:
                for source in config["sources"]:
                    key = source["category_key"]
                    chart = next((item for item in charts if item["category_key"] == key), None)
                    if source.get("active") and chart and not validate_collection_attempt({**config, "sources": [source]}, [chart], [], evidence):
                        complete_charts[key] = chart
    return list(complete_charts.values()), browser_name, diagnostic


def collect_with_browser(
    config: dict[str, Any], headless: bool = False, playwright_factory: Any | None = None
) -> tuple[list[dict[str, Any]], str]:
    """Compatibility wrapper for callers that request a single browser attempt."""
    if playwright_factory is None:
        from playwright.sync_api import sync_playwright

        playwright_factory = sync_playwright

    with playwright_factory() as playwright:
        browser, browser_name = _launch_visible_browser(playwright, headless)
        try:
            results, _, _, _, _ = _collect_attempt(browser, config)
        finally:
            browser.close()
    return results, browser_name


def _load_fixture_attempt(
    config: dict[str, Any], fixture_path: Path
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    charts = fixture.get("charts", {})
    results = [
        collect_chart_from_pages(source, list(charts.get(source["category_key"], [])), GLOBAL_RANK_LIMIT)
        for source in config["sources"] if source.get("active")
    ]
    raw_evidence = fixture.get("price_evidence")
    evidence = raw_evidence if isinstance(raw_evidence, list) else []
    failures = validate_collection_attempt(config, results, [], evidence)
    attempt_status = "COMPLETE" if not failures else "FAILED"
    diagnostic = {
        "status": attempt_status,
        "attempt_count": 1,
        "attempts": [{
            "attempt": 1,
            "status": attempt_status,
            "failures": failures,
            "price_evidence": evidence,
            "discount_evidence": [],
            "brand_evidence": [],
            "collected_observations": _collected_observation_identities(results),
        }],
    }
    return results, diagnostic


def _load_fixture_results(config: dict[str, Any], fixture_path: Path) -> list[dict[str, Any]]:
    """Compatibility wrapper for fixture callers that only need parsed charts."""
    return _load_fixture_attempt(config, fixture_path)[0]


def main(argv: list[str] | None = None) -> int:
    script_path = Path(__file__).resolve()
    default_root = script_path.parents[2]
    parser = argparse.ArgumentParser(description="Collect public Amazon Best Sellers Top 30 charts.")
    parser.add_argument("--project-root", type=Path, default=default_root)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--output-root", type=Path)
    parser.add_argument("--market-date", default=datetime.now(PACIFIC_TZ).date().isoformat())
    parser.add_argument("--headless", action="store_true", help="Test-only/headless browser mode.")
    parser.add_argument("--fixture-input", type=Path, help="Offline extracted-page fixture; does not launch a browser.")
    args = parser.parse_args(argv)

    output_root = args.output_root or args.project_root / "var" / "amazon-bestsellers"
    observed_at = ""
    failure_reason = "SETUP_FAILED"
    try:
        project_root = args.project_root.resolve()
        config_path = (args.config or project_root / "config" / "best-sellers-sources.json").resolve()
        output_root = output_root.resolve()
        observed_at = datetime.now(PACIFIC_TZ).isoformat(timespec="milliseconds")
        failure_reason = "CONFIG_LOAD_FAILED"
        config = json.loads(config_path.read_text(encoding="utf-8-sig"))
        if args.fixture_input:
            failure_reason = "FIXTURE_LOAD_FAILED"
            chart_results, diagnostic = _load_fixture_attempt(config, args.fixture_input.resolve())
            browser_name = "FIXTURE_NO_BROWSER"
        else:
            try:
                chart_results, browser_name, diagnostic = collect_with_recovery(config, args.headless, preserve_complete_categories=True)
            except Exception as exc:
                chart_results = []
                browser_name = "UNAVAILABLE"
                diagnostic = {
                    "status": "FAILED",
                    "attempt_count": 1,
                    "attempts": [{
                        "attempt": 1,
                        "status": "FAILED",
                        "failures": [f"ATTEMPT_ERROR:{type(exc).__name__}"],
                        "price_evidence": [],
                        "discount_evidence": [],
                        "brand_evidence": [],
                    }],
                }
        failure_reason = "ARTIFACT_BUILD_FAILED"
        snapshot, status = build_artifacts(config, chart_results, args.market_date, observed_at)
        failure_reason = "ARTIFACT_WRITE_FAILED"
        written = write_collection_artifacts(output_root, args.market_date, snapshot, status, diagnostic, config, preserve_complete_categories=True)
        extended_status = written["status"]
        total = status["total_observation_count"]
        run_status = "COMPLETE" if extended_status["CompletenessStatus"] == "COMPLETE" else "INCOMPLETE"
        output = {
            "Status": run_status,
            "ExitCode": written["exit_code"],
            "TotalObservations": total,
            "SnapshotPath": written["snapshot_path"],
            "PartialSnapshotPath": extended_status.get("PartialSnapshotPath"),
            "CompleteCategories": extended_status.get("CompleteCategories", []),
            "StatusPath": written["status_path"],
            "CompletenessStatus": extended_status["CompletenessStatus"],
            "AttemptCount": extended_status["AttemptCount"],
            "PriceVerificationCount": extended_status["PriceVerificationCount"],
            "DiscountVerificationCount": extended_status["DiscountVerificationCount"],
            "BrandVerificationCount": extended_status["BrandVerificationCount"],
            "DiagnosticPath": written["diagnostic_path"],
            "FailureReasons": extended_status["FailureReasons"],
            "Browser": browser_name,
        }
        # The PowerShell launcher captures this one-line control message through
        # a native-process pipe.  Escaping non-ASCII paths keeps the JSON
        # boundary lossless on Windows PowerShell systems using legacy code pages.
        print(json.dumps(output, ensure_ascii=True, separators=(",", ":")))
        return int(written["exit_code"])
    except Exception:
        if not observed_at:
            observed_at = datetime.now(PACIFIC_TZ).isoformat(timespec="milliseconds")
        try:
            output = _write_failure_artifacts(output_root, args.market_date, observed_at, failure_reason)
        except Exception:
            output = {
                "Status": "ERROR",
                "ExitCode": EXIT_RUNTIME_ERROR,
                "TotalObservations": 0,
                "SnapshotPath": None,
                "CompletenessStatus": "FAILED",
                "AttemptCount": 1,
                "PriceVerificationCount": 0,
                "DiscountVerificationCount": 0,
                "BrandVerificationCount": 0,
                "FailureReasons": ["ARTIFACT_WRITE_FAILED"],
                "Browser": "UNAVAILABLE",
            }
        print(json.dumps(output, ensure_ascii=True, separators=(",", ":")))
        return EXIT_RUNTIME_ERROR


if __name__ == "__main__":
    sys.exit(main())
