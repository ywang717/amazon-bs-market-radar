"""Contract tests for the standalone historical brand collector."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = ROOT / "scripts" / "python" / "collect_brand_enrichment.py"


def load_subject():
    spec = importlib.util.spec_from_file_location("collect_brand_enrichment", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakePage:
    def __init__(self, detail, failure=None):
        self.detail = detail
        self.failure = failure
        self.visited = []
        self.closed = False

    def goto(self, url, **_kwargs):
        self.visited.append(url)
        if self.failure:
            raise self.failure

    def evaluate(self, _script):
        return self.detail

    def close(self):
        self.closed = True


class FakeContext:
    def __init__(self, pages):
        self.pages = list(pages)

    def new_page(self):
        return self.pages.pop(0)


class FakeChromium:
    def __init__(self, outcomes):
        self.outcomes = outcomes
        self.calls = []

    def launch(self, **kwargs):
        self.calls.append(kwargs)
        outcome = self.outcomes.get(kwargs.get("channel"))
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


class FakePlaywright:
    def __init__(self, outcomes):
        self.chromium = FakeChromium(outcomes)


class CollectBrandEnrichmentTests(unittest.TestCase):
    def test_browser_launch_prefers_edge_without_attempting_bundled_chromium(self):
        subject = load_subject()
        playwright = FakePlaywright({"msedge": "edge-browser"})

        browser = subject._launch_browser(playwright, headless=True)

        self.assertEqual("edge-browser", browser)
        self.assertEqual([{"channel": "msedge", "headless": True}], playwright.chromium.calls)

    def test_browser_launch_falls_back_to_bundled_chromium_after_edge_and_chrome_fail(self):
        subject = load_subject()
        playwright = FakePlaywright({"msedge": RuntimeError("edge missing"), "chrome": RuntimeError("chrome missing"), None: "bundled-browser"})

        browser = subject._launch_browser(playwright, headless=False)

        self.assertEqual("bundled-browser", browser)
        self.assertEqual([
            {"channel": "msedge", "headless": False},
            {"channel": "chrome", "headless": False},
            {"headless": False},
        ], playwright.chromium.calls)

    def test_edge_failure_uses_and_closes_chrome_without_trying_bundled_chromium(self):
        subject = load_subject()

        class BrowserContext:
            def __init__(self):
                self.closed = False

            def new_page(self):
                raise AssertionError("An empty ASIN cohort must not create a page")

            def close(self):
                self.closed = True

        class Browser:
            def __init__(self):
                self.context = BrowserContext()
                self.new_context_calls = 0
                self.closed = False

            def new_context(self):
                self.new_context_calls += 1
                return self.context

            def close(self):
                self.closed = True

        chrome_browser = Browser()
        playwright = FakePlaywright({
            "msedge": RuntimeError("edge failed"),
            "chrome": chrome_browser,
        })

        class PlaywrightManager:
            def __enter__(self):
                return playwright

            def __exit__(self, _exc_type, _exc, _traceback):
                return False

        sync_api = types.ModuleType("playwright.sync_api")
        sync_api.sync_playwright = PlaywrightManager
        playwright_package = types.ModuleType("playwright")
        playwright_package.sync_api = sync_api

        with tempfile.TemporaryDirectory() as temp_dir:
            asins_path = Path(temp_dir) / "asins.json"
            output_path = Path(temp_dir) / "artifact.json"
            asins_path.write_text("[]", encoding="utf-8")

            with patch.dict(
                sys.modules,
                {"playwright": playwright_package, "playwright.sync_api": sync_api},
            ):
                exit_code = subject.main([
                    "--asins-json", str(asins_path),
                    "--output", str(output_path),
                    "--marketplace", "AMAZON_US",
                    "--headless", "true",
                ])

            artifact = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertEqual(0, exit_code)
        self.assertEqual([], artifact["products"])
        self.assertEqual([
            {"channel": "msedge", "headless": True},
            {"channel": "chrome", "headless": True},
        ], playwright.chromium.calls)
        self.assertEqual(1, chrome_browser.new_context_calls)
        self.assertTrue(chrome_browser.context.closed)
        self.assertTrue(chrome_browser.closed)

    def test_edge_failure_uses_chrome_to_collect_one_trusted_product_and_closes_resources(self):
        subject = load_subject()
        detail_page = FakePage({
            "url": "https://www.amazon.com/dp/B000000001",
            "title": "Example product",
            "detail_asin": "B000000001",
            "blocked_markers": [],
            "brand_candidates": [{
                "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD",
                "value": "Northstar",
            }],
        })

        class BrowserContext:
            def __init__(self):
                self.new_page_calls = 0
                self.closed = False

            def new_page(self):
                self.new_page_calls += 1
                return detail_page

            def close(self):
                self.closed = True

        class Browser:
            def __init__(self):
                self.context = BrowserContext()
                self.closed = False

            def new_context(self):
                return self.context

            def close(self):
                self.closed = True

        chrome_browser = Browser()
        playwright = FakePlaywright({
            "msedge": RuntimeError("edge failed"),
            "chrome": chrome_browser,
        })

        class PlaywrightManager:
            def __enter__(self):
                return playwright

            def __exit__(self, _exc_type, _exc, _traceback):
                return False

        sync_api = types.ModuleType("playwright.sync_api")
        sync_api.sync_playwright = PlaywrightManager
        playwright_package = types.ModuleType("playwright")
        playwright_package.sync_api = sync_api

        with tempfile.TemporaryDirectory() as temp_dir:
            asins_path = Path(temp_dir) / "asins.json"
            output_path = Path(temp_dir) / "artifact.json"
            asins_path.write_text('["B000000001"]', encoding="utf-8")

            with patch.dict(
                sys.modules,
                {"playwright": playwright_package, "playwright.sync_api": sync_api},
            ):
                exit_code = subject.main([
                    "--asins-json", str(asins_path),
                    "--output", str(output_path),
                    "--marketplace", "AMAZON_US",
                    "--headless", "true",
                ])

            artifact = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertEqual(0, exit_code)
        self.assertEqual([{
            "asin": "B000000001",
            "detail_url": "https://www.amazon.com/dp/B000000001",
            "verification_status": "VERIFIED",
            "raw_brand": "Northstar",
            "brand_source": "verified_metadata",
            "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD",
        }], artifact["products"])
        self.assertEqual([
            {"channel": "msedge", "headless": True},
            {"channel": "chrome", "headless": True},
        ], playwright.chromium.calls)
        self.assertEqual(1, chrome_browser.context.new_page_calls)
        self.assertEqual(["https://www.amazon.com/dp/B000000001"], detail_page.visited)
        self.assertTrue(detail_page.closed)
        self.assertTrue(chrome_browser.context.closed)
        self.assertTrue(chrome_browser.closed)

    def test_collects_each_unique_asin_once_and_emits_sorted_explicit_evidence(self):
        subject = load_subject()
        first = FakePage({
            "detail_asin": "B000000001",
            "blocked_markers": [],
            "brand_candidates": [{"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "Northstar"}],
        })
        second = FakePage({
            "detail_asin": "B000000002",
            "blocked_markers": [],
            "brand_candidates": [{"evidence_source": "PRODUCT_DETAILS_BRAND_FIELD", "value": "Acme"}],
        })

        artifact = subject.collect_brand_enrichment(
            ["B000000002", "B000000001", "B000000002"],
            context=FakeContext([first, second]),
            generated_at="2026-08-28T00:00:00Z",
        )

        self.assertEqual("amazon-brand-enrichment-v1", artifact["schema_version"])
        self.assertEqual("AMAZON_US", artifact["marketplace"])
        self.assertEqual(["B000000001", "B000000002"], [item["asin"] for item in artifact["products"]])
        self.assertEqual("Northstar", artifact["products"][0]["raw_brand"])
        self.assertEqual("verified_metadata", artifact["products"][0]["brand_source"])
        self.assertEqual("PRODUCT_DETAILS_BRAND_FIELD", artifact["products"][1]["evidence_source"])
        self.assertEqual(["https://www.amazon.com/dp/B000000001"], first.visited)
        self.assertEqual(["https://www.amazon.com/dp/B000000002"], second.visited)

    def test_records_one_blocked_result_when_a_single_detail_visit_fails(self):
        subject = load_subject()
        failing = FakePage({}, failure=TimeoutError("not persisted"))
        verified = FakePage({
            "detail_asin": "B000000002",
            "blocked_markers": [],
            "brand_candidates": [{"evidence_source": "DETAIL_BULLET_BRAND_FIELD", "value": "Acme"}],
        })

        artifact = subject.collect_brand_enrichment(
            ["B000000001", "B000000002"],
            context=FakeContext([failing, verified]),
            generated_at="2026-08-28T00:00:00Z",
        )

        self.assertEqual("VERIFICATION_BLOCKED", artifact["products"][0]["verification_status"])
        self.assertIsNone(artifact["products"][0]["raw_brand"])
        self.assertEqual("VERIFIED", artifact["products"][1]["verification_status"])
        self.assertEqual("Acme", artifact["products"][1]["raw_brand"])


if __name__ == "__main__":
    unittest.main()
