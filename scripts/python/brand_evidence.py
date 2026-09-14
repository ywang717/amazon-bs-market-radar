"""Classify structured Amazon product-detail brand evidence conservatively."""

from __future__ import annotations

import re
from typing import Any


TRUSTED_BRAND_SOURCES = (
    "PRODUCT_OVERVIEW_BRAND_FIELD",
    "PRODUCT_DETAILS_BRAND_FIELD",
    "DETAIL_BULLET_BRAND_FIELD",
)


def _clean_text(value: Any) -> str | None:
    if value is None:
        return None
    cleaned = re.sub(r"\s+", " ", str(value)).strip()
    return cleaned or None


def _canonical_asin(value: Any) -> str | None:
    text = _clean_text(value)
    if not text or re.fullmatch(r"[A-Z0-9]{10}", text.upper()) is None:
        return None
    return text.upper()


def _result(
    verification_status: str,
    raw_brand: str | None = None,
    evidence_source: str | None = None,
) -> dict[str, str | None]:
    return {
        "raw_brand": raw_brand,
        "brand_source": "verified_metadata" if raw_brand is not None else "unknown",
        "verification_status": verification_status,
        "evidence_source": evidence_source,
    }


def classify_brand_evidence(detail_page: dict, requested_asin: str) -> dict:
    """Return a writable raw brand only for matching, consistent trusted evidence."""
    if detail_page.get("blocked_markers"):
        return _result("VERIFICATION_BLOCKED")

    detail_asin = _canonical_asin(detail_page.get("detail_asin"))
    requested_identity = _canonical_asin(requested_asin)
    if detail_asin is None or requested_identity is None or detail_asin != requested_identity:
        return _result("IDENTITY_MISMATCH")

    candidates = detail_page.get("brand_candidates")
    if not isinstance(candidates, list):
        candidates = []

    trusted_values: list[tuple[str, str]] = []
    for candidate in candidates:
        if not isinstance(candidate, dict):
            continue
        source = candidate.get("evidence_source")
        candidate_value = candidate.get("value")
        if not isinstance(candidate_value, str):
            continue
        value = _clean_text(candidate_value)
        if source in TRUSTED_BRAND_SOURCES and value is not None:
            trusted_values.append((source, value))

    if not trusted_values:
        return _result("MISSING")

    normalized_values = {value.casefold() for _, value in trusted_values}
    if len(normalized_values) != 1:
        return _result("CONFLICT")

    source, raw_brand = min(
        trusted_values,
        key=lambda item: TRUSTED_BRAND_SOURCES.index(item[0]),
    )
    return _result("VERIFIED", raw_brand, source)
