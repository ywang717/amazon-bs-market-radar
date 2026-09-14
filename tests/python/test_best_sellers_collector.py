import copy
import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = PROJECT_ROOT / "scripts" / "python" / "collect_best_sellers.py"
FIXTURES = Path(__file__).parent / "fixtures"
CANONICAL_PRESSURE_WASHER_URL = "https://www.amazon.com/Best-Sellers-Patio-Lawn-Garden-Pressure-Washers/zgbs/lawn-garden/552856"


def load_collector():
    spec = importlib.util.spec_from_file_location("collect_best_sellers", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_fixture(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


SOURCE = {
    "category_key": "pressure_washers",
    "display_name": "Pressure Washers Best Sellers",
    "url": "https://www.amazon.com/Best-Sellers-Pressure-Washers/zgbs/552856",
}


class CollectorParsingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    def test_complete_global_ranks_one_through_thirty_are_sorted(self):
        result = self.collector.collect_chart_from_pages(SOURCE, [load_fixture("complete-page.json")], 30)
        self.assertEqual("COMPLETE", result["status"])
        self.assertEqual(list(range(1, 31)), [item["rank"] for item in result["observations"]])
        self.assertEqual("NOT_NEEDED_TARGET_REACHED", result["pagination_decision"])

    def test_unseen_optional_fields_remain_json_null(self):
        page = load_fixture("complete-page.json")
        page["cards"] = [{"rank": "#1", "asin": "B0NULL0001"}]
        result = self.collector.collect_chart_from_pages(SOURCE, [page], 30)
        item = result["observations"][0]
        self.assertEqual(
            {
                "rank": 1,
                "asin": "B0NULL0001",
                "title": None,
                "url": None,
                "price": None,
                "rating": None,
                "reviews": None,
                "has_discount": None,
                "discounts": [],
            },
            item,
        )

    def test_rating_is_rounded_to_one_decimal_without_using_the_review_count(self):
        item, reason = self.collector.parse_card(
            {
                "rank": "#1",
                "asin": "B0RATING001",
                "rating": "4.65 out of 5 stars, 13,471 ratings",
                "reviews": "13,471",
            },
            30,
        )

        self.assertIsNone(reason)
        self.assertEqual(4.7, item["rating"])
        self.assertEqual(13471, item["reviews"])

    def test_negative_integer_review_count_is_unknown(self):
        item, reason = self.collector.parse_card(
            {"rank": "#1", "asin": "B0RATING001", "reviews": -1}, 30
        )

        self.assertIsNone(reason)
        self.assertIsNone(item["reviews"])

    def test_duplicate_rank_and_asin_are_excluded(self):
        page = load_fixture("complete-page.json")
        page["cards"] = [
            {"rank": "#1", "asin": "B0UNIQUE01"},
            {"rank": "#1", "asin": "B0UNIQUE02"},
            {"rank": "#2", "asin": "B0UNIQUE01"},
        ]
        result = self.collector.collect_chart_from_pages(SOURCE, [page], 30)
        self.assertEqual(["DUPLICATE_RANK", "DUPLICATE_ASIN"], result["rejection_reasons"])
        self.assertEqual([1], [item["rank"] for item in result["observations"]])

    def test_item_without_integer_rank_is_excluded(self):
        page = load_fixture("complete-page.json")
        page["cards"] = [{"rank": None, "asin": "B0NORANK01"}, {"rank": "#2", "asin": "B0RANK0002"}]
        result = self.collector.collect_chart_from_pages(SOURCE, [page], 30)
        self.assertEqual([2], [item["rank"] for item in result["observations"]])
        self.assertIn("MISSING_OR_INVALID_RANK", result["rejection_reasons"])

    def test_later_page_continuing_at_next_global_rank_is_included(self):
        page_one = load_fixture("complete-page.json")
        page_two = copy.deepcopy(page_one)
        page_one["cards"] = page_one["cards"][:15]
        page_two["cards"] = page_two["cards"][15:]
        result = self.collector.collect_chart_from_pages(SOURCE, [page_one, page_two], 30)
        self.assertEqual(list(range(1, 31)), [item["rank"] for item in result["observations"]])
        self.assertEqual("CONTINUED_VERIFIED_GLOBAL_RANKS", result["pagination_decision"])

    def test_later_page_restarting_at_one_is_excluded(self):
        page_one = load_fixture("complete-page.json")
        page_two = copy.deepcopy(page_one)
        page_one["cards"] = page_one["cards"][:15]
        page_two["cards"] = page_two["cards"][:15]
        result = self.collector.collect_chart_from_pages(SOURCE, [page_one, page_two], 30)
        self.assertEqual(list(range(1, 16)), [item["rank"] for item in result["observations"]])
        self.assertEqual("EXCLUDED_RESTART_AT_1", result["pagination_decision"])
        self.assertEqual("PAGINATION_RESTARTED_AT_1", result["error_reason"])

    def test_later_page_with_unverifiable_gap_is_excluded(self):
        page_one = load_fixture("complete-page.json")
        page_two = copy.deepcopy(page_one)
        page_one["cards"] = page_one["cards"][:10]
        page_two["cards"] = page_two["cards"][11:]
        result = self.collector.collect_chart_from_pages(SOURCE, [page_one, page_two], 30)
        self.assertEqual(list(range(1, 11)), [item["rank"] for item in result["observations"]])
        self.assertEqual("EXCLUDED_UNVERIFIED_CONTINUITY", result["pagination_decision"])

    def test_later_page_with_internal_rank_gap_is_excluded(self):
        page_one = load_fixture("complete-page.json")
        page_two = copy.deepcopy(page_one)
        page_one["cards"] = page_one["cards"][:10]
        page_two["cards"] = [page_two["cards"][10], *page_two["cards"][12:]]
        result = self.collector.collect_chart_from_pages(SOURCE, [page_one, page_two], 30)
        self.assertEqual(list(range(1, 11)), [item["rank"] for item in result["observations"]])
        self.assertEqual("EXCLUDED_UNVERIFIED_CONTINUITY", result["pagination_decision"])
        self.assertEqual("PAGINATION_CONTINUITY_UNVERIFIED", result["error_reason"])

    def test_category_title_mismatch_stops_only_that_chart(self):
        page = load_fixture("complete-page.json")
        page["title"] = "Amazon Best Sellers: Best Coffee Makers"
        page["heading"] = "Best Sellers in Coffee Makers"
        result = self.collector.collect_chart_from_pages(SOURCE, [page], 30)
        self.assertEqual("CATEGORY_MISMATCH", result["status"])
        self.assertEqual([], result["observations"])

    def test_login_page_is_not_parsed_or_authenticated(self):
        page = {"title": "Amazon Sign-In", "heading": "Sign in", "body_text": "Password", "cards": []}
        result = self.collector.collect_chart_from_pages(SOURCE, [page], 30)
        self.assertEqual("LOGIN_REQUIRED", result["status"])
        self.assertEqual("LOGIN_REQUIRED", result["error_reason"])

    def test_robot_check_and_captcha_are_detected(self):
        for marker in ("Robot Check", "Enter the characters you see below", "CAPTCHA"):
            with self.subTest(marker=marker):
                page = {"title": marker, "heading": marker, "body_text": marker, "cards": []}
                result = self.collector.collect_chart_from_pages(SOURCE, [page], 30)
                self.assertEqual("BOT_CHALLENGE", result["status"])

    def test_redirect_url_and_common_page_signals_are_checked_before_category_mismatch(self):
        cases = (
            (
                {"url": "https://www.amazon.com/ap/signin", "title": "Sign in", "heading": "Sign in", "body_text": "", "cards": []},
                "LOGIN_REQUIRED",
            ),
            (
                {"url": "https://www.amazon.com/errors/validateCaptcha", "title": "Amazon", "heading": "Type the characters", "body_text": "", "cards": []},
                "BOT_CHALLENGE",
            ),
            (
                {"url": "https://www.amazon.com/errors/validateCaptcha", "title": "Amazon", "heading": "Amazon", "body_text": "", "cards": []},
                "BOT_CHALLENGE",
            ),
        )
        for page, expected in cases:
            with self.subTest(page=page):
                result = self.collector.collect_chart_from_pages(SOURCE, [page], 30)
                self.assertEqual(expected, result["status"])

    def test_mutable_config_target_cannot_admit_rank_above_thirty(self):
        page = load_fixture("complete-page.json")
        page["cards"].append({"rank": "#31", "asin": "B000000031"})
        result = self.collector.collect_chart_from_pages(SOURCE, [page], 99)
        self.assertEqual(list(range(1, 31)), [item["rank"] for item in result["observations"]])
        self.assertIn("RANK_OUTSIDE_TARGET", result["rejection_reasons"])
        self.assertEqual("COMPLETE", result["status"])

    def test_access_denied_is_detected(self):
        page = {"title": "Access Denied", "heading": "Access Denied", "body_text": "Sorry", "cards": []}
        result = self.collector.collect_chart_from_pages(SOURCE, [page], 30)
        self.assertEqual("ACCESS_DENIED", result["status"])


class ArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    def test_zero_observations_writes_status_and_protects_existing_snapshot(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            output_root = Path(temp_dir)
            day = output_root / "2026-08-11"
            day.mkdir()
            snapshot_path = day / "amazon-bestsellers.json"
            original = '{"schema_version":"amazon-best-sellers-snapshot-v1","keep":true}'
            snapshot_path.write_text(original, encoding="utf-8")
            status = {
                "schema_version": "best-sellers-collection-status-v1",
                "market_date": "2026-08-11",
                "total_observation_count": 0,
                "charts": [],
            }
            snapshot = {"schema_version": "amazon-best-sellers-snapshot-v1"}

            result = self.collector.write_collection_artifacts(output_root, "2026-08-11", snapshot, status)

            self.assertEqual(self.collector.EXIT_INCOMPLETE, result["exit_code"])
            self.assertEqual(original, snapshot_path.read_text(encoding="utf-8"))
            written_status = json.loads((day / "best-sellers-collection-status.json").read_text(encoding="utf-8"))
            self.assertEqual(0, written_status["total_observation_count"])

    def test_browser_launch_failure_writes_sanitized_zero_observation_status(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            config_path = root / "sources.json"
            output_root = root / "snapshots"
            config_path.write_text(
                json.dumps(
                    {
                        "marketplace": "AMAZON_US",
                        "target_count": 30,
                        "sources": [dict(SOURCE, active=True)],
                    }
                ),
                encoding="utf-8",
            )
            stdout = io.StringIO()
            with patch.object(
                self.collector,
                "collect_with_recovery",
                side_effect=RuntimeError("cookie=secret profile=C:/private/profile"),
            ), contextlib.redirect_stdout(stdout):
                exit_code = self.collector.main(
                    [
                        "--project-root", str(root),
                        "--config", str(config_path),
                        "--output-root", str(output_root),
                        "--market-date", "2026-08-11",
                    ]
                )

            self.assertEqual(self.collector.EXIT_INCOMPLETE, exit_code)
            output = json.loads(stdout.getvalue())
            self.assertEqual("INCOMPLETE", output["Status"])
            self.assertIsNone(output["SnapshotPath"])
            status_text = (output_root / "2026-08-11" / "best-sellers-collection-status.json").read_text(encoding="utf-8")
            self.assertNotIn("cookie", status_text.casefold())
            self.assertNotIn("profile", status_text.casefold())
            self.assertEqual("ATTEMPT_ERROR", json.loads(status_text)["FailureReasons"][0])
            diagnostic_text = (output_root / "2026-08-11" / "price-completeness-diagnostic.json").read_text(encoding="utf-8")
            self.assertNotIn("cookie", diagnostic_text.casefold())
            self.assertNotIn("profile", diagnostic_text.casefold())


class _FakeLocator:
    @property
    def first(self):
        return self

    def count(self):
        return 0


class _FakePage:
    def __init__(self, extracted, close_error=False):
        self.extracted = extracted
        self.close_error = close_error

    def goto(self, *args, **kwargs):
        return None

    def evaluate(self, script):
        return copy.deepcopy(self.extracted)

    def locator(self, selector):
        return _FakeLocator()

    def close(self):
        if self.close_error:
            raise RuntimeError("page close failed")


class _FakeContext:
    def __init__(self, page_results):
        self.page_results = list(page_results)

    def new_page(self):
        result = self.page_results.pop(0)
        if isinstance(result, Exception):
            raise result
        return result

    def close(self):
        return None


class _FakeBrowser:
    def __init__(self, context):
        self.context = context
        self.context_kwargs = None

    def new_context(self, **kwargs):
        self.context_kwargs = kwargs
        return self.context

    def close(self):
        return None


class _FakeChromium:
    def __init__(self, browser):
        self.browser = browser
        self.launch_calls = []

    def launch(self, **kwargs):
        self.launch_calls.append(kwargs)
        return self.browser


class _FakePlaywrightManager:
    def __init__(self, context):
        self.playwright = type("Playwright", (), {"chromium": _FakeChromium(_FakeBrowser(context))})()

    def __enter__(self):
        return self.playwright

    def __exit__(self, exc_type, exc, traceback):
        return False


class BrowserIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    @staticmethod
    def source(key, name):
        return {"category_key": key, "display_name": name, "url": f"https://www.amazon.com/{key}", "active": True}

    @staticmethod
    def page(name, asin):
        return {
            "url": "https://www.amazon.com/chart",
            "title": f"Amazon Best Sellers: Best {name}",
            "heading": f"Best Sellers in {name}",
            "body_text": "Public chart",
            "cards": [{"rank": "#1", "asin": asin}],
        }

    def test_new_page_failure_isolated_between_prior_and_remaining_charts(self):
        sources = [self.source("one", "Pressure Washers"), self.source("two", "Sump Pumps"), self.source("three", "Pressure Washer Accessories")]
        context = _FakeContext([
            _FakePage(self.page("Pressure Washers", "B0FIRST001")),
            RuntimeError("new page failed"),
            _FakePage(self.page("Pressure Washer Accessories", "B0THIRD001")),
        ])
        results, browser_name = self.collector.collect_with_browser(
            {"target_count": 30, "sources": sources},
            playwright_factory=lambda: _FakePlaywrightManager(context),
        )
        self.assertEqual("MICROSOFT_EDGE", browser_name)
        self.assertEqual(["one", "two", "three"], [item["category_key"] for item in results])
        self.assertEqual([1, 0, 1], [item["observation_count"] for item in results])
        self.assertEqual("BROWSER_ERROR", results[1]["status"])

    def test_tab_close_failure_does_not_discard_result_or_stop_remaining_chart(self):
        sources = [self.source("one", "Pressure Washers"), self.source("two", "Sump Pumps")]
        context = _FakeContext([
            _FakePage(self.page("Pressure Washers", "B0FIRST001"), close_error=True),
            _FakePage(self.page("Sump Pumps", "B0SECOND01")),
        ])
        results, _ = self.collector.collect_with_browser(
            {"target_count": 30, "sources": sources},
            playwright_factory=lambda: _FakePlaywrightManager(context),
        )
        self.assertEqual(["one", "two"], [item["category_key"] for item in results])
        self.assertEqual([1, 1], [item["observation_count"] for item in results])

    def test_browser_uses_ephemeral_context_without_profile_or_cache_arguments(self):
        context = _FakeContext([_FakePage(self.page("Pressure Washers", "B0FIRST001"))])
        manager = _FakePlaywrightManager(context)

        self.collector.collect_with_browser(
            {"target_count": 30, "sources": [self.source("one", "Pressure Washers")]},
            playwright_factory=lambda: manager,
        )

        chromium = manager.playwright.chromium
        self.assertEqual({"channel": "msedge", "headless": False}, chromium.launch_calls[0])
        self.assertEqual({}, chromium.browser.context_kwargs)


class BrowserExtractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    def test_extracts_price_from_current_best_sellers_card_markup(self):
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            self.skipTest("Playwright is not installed")

        card_html = """
        <html><head><title>Amazon Best Sellers: Best Pressure Washers</title></head><body>
          <h1>Best Sellers in Pressure Washers</h1>
          <div id="gridItemRoot">
            <span class="zg-bdg-text">#1</span>
            <div data-asin="B0BVGSX46M"></div>
            <a href="/Example/dp/B0BVGSX46M"><span><div class="_cDEzb_p13n-sc-css-line-clamp-3_g3dy1">Example washer</div></span></a>
            <div class="_cDEzb_p13n-sc-price-animation-wrapper_3PzN2">
              <span class="a-size-base a-color-price"><span class="_cDEzb_p13n-sc-price_3mJ9Z">$169.00</span></span>
            </div>
          </div>
        </body></html>
        """
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="msedge", headless=True)
            try:
                page = browser.new_page()
                page.set_content(card_html)
                extracted = self.collector._extract_page(page)
            finally:
                browser.close()

        self.assertEqual("$169.00", extracted["cards"][0]["price"])

    def test_extracts_review_count_from_the_star_adjacent_card_text(self):
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            self.skipTest("Playwright is not installed")

        card_html = """
        <html><head><title>Amazon Best Sellers: Best Pressure Washers</title></head><body>
          <h1>Best Sellers in Pressure Washers</h1>
          <div id="gridItemRoot">
            <span class="zg-bdg-text">#1</span>
            <div data-asin="B0BVGSX46M"></div>
            <a href="/Example/dp/B0BVGSX46M"><span><div class="_cDEzb_p13n-sc-css-line-clamp-3_g3dy1">Example washer</div></span></a>
            <div class="a-icon-row">
              <a aria-label="4.6 out of 5 stars, 13,471 ratings" href="/product-reviews/B0BVGSX46M">
                <i><span class="a-icon-alt">4.6 out of 5 stars</span></i>
                <span aria-hidden="true" class="a-size-small">13,471</span>
              </a>
            </div>
          </div>
        </body></html>
        """
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="msedge", headless=True)
            try:
                page = browser.new_page()
                page.set_content(card_html)
                extracted = self.collector._extract_page(page)
            finally:
                browser.close()

        self.assertEqual("13,471", extracted["cards"][0]["reviews"])

    def test_extracts_public_detail_asin_with_real_detail_page_script(self):
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            self.skipTest("Playwright is not installed")

        detail_html = """
        <html><head><title>Example product</title></head><body>
          <h1 id="productTitle">Example product</h1>
          <input id="ASIN" value="B000000001" />
        </body></html>
        """
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="msedge", headless=True)
            try:
                page = browser.new_page()
                page.set_content(detail_html)
                extracted = self.collector._extract_detail_page(page)
            finally:
                browser.close()

        self.assertEqual("B000000001", extracted["detail_asin"])

    def test_extracts_price_drop_from_new_offer_when_apex_contains_an_empty_placeholder(self):
        class Page:
            def evaluate(self, script):
                core_price_index = script.index("document.querySelector('#corePrice_feature_div')")
                apex_index = script.index("document.querySelector('#apex_desktop')")
                current_price = "$169.00" if core_price_index < apex_index else None
                return {
                    "url": "https://www.amazon.com/dp/B0BVGSX46M",
                    "title": "Example product",
                    "detail_asin": "B0BVGSX46M",
                    "primary_offer_current_price": current_price,
                    "primary_offer_list_price": "$199.00",
                }

        extracted = self.collector._extract_detail_page(Page())

        self.assertEqual("$169.00", extracted["current_price"])
        self.assertEqual("$199.00", extracted["list_price"])
        self.assertEqual(
            {"has_discount": True, "discounts": [{"kind": "PRICE_DROP", "amount": "$30.00 off"}]},
            self.collector.classify_detail_discounts(extracted),
        )

    def test_recommendation_prices_are_not_detail_discount_price_evidence(self):
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            self.skipTest("Playwright is not installed")

        detail_html = """
        <html><head><title>Example product</title></head><body>
          <h1 id="productTitle">Example product</h1>
          <input id="ASIN" value="B000000001" />
          <div id="centerCol">
            <div class="recommendation">
              <span class="a-price a-text-price"><span class="a-offscreen">$99.99</span></span>
              <span class="a-price"><span class="a-offscreen">$89.99</span></span>
            </div>
          </div>
        </body></html>
        """
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="msedge", headless=True)
            try:
                page = browser.new_page()
                page.set_content(detail_html)
                extracted = self.collector._extract_detail_page(page)
            finally:
                browser.close()

        self.assertIsNone(extracted["current_price"])
        self.assertIsNone(extracted["list_price"])
        self.assertEqual(
            {"has_discount": False, "discounts": []},
            self.collector.classify_detail_discounts(extracted),
        )


class DetailPriceClassificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    def test_classifies_detail_price_evidence_with_literal_reason_codes(self):
        cases = (
            ({"price": "  $19.99  "}, "DETAIL_PRICE_FOUND", "$19.99", None),
            ({"availability": "Currently unavailable."}, "PRICE_NOT_PUBLIC", None, None),
            ({"availability": "Out of Stock"}, "PRICE_NOT_PUBLIC", None, None),
            ({"buying_options": "No featured offers available"}, "PRICE_NOT_PUBLIC", None, None),
            ({"buying_options": "See All Buying Options"}, "PRICE_NOT_PUBLIC", None, None),
            ({"buying_options": "Sign in to see price"}, "PRICE_NOT_PUBLIC", None, None),
            ({"blocked_markers": ["BOT_CHALLENGE"]}, "VERIFICATION_BLOCKED", None, "BOT_CHALLENGE"),
            ({"blocked_markers": ["LOGIN_REQUIRED"]}, "VERIFICATION_BLOCKED", None, "LOGIN_REQUIRED"),
            ({"blocked_markers": ["ACCESS_DENIED"]}, "VERIFICATION_BLOCKED", None, "ACCESS_DENIED"),
            ({"title": "Example product", "heading": "Example product"}, "PRICE_MISSING_UNEXPLAINED", None, None),
        )
        for page, reason_code, price, page_status in cases:
            with self.subTest(page=page):
                self.assertEqual(
                    {"reason_code": reason_code, "price": price, "page_status": page_status},
                    self.collector.classify_detail_price(page),
                )

    def test_missing_price_selector_is_not_evidence_that_price_is_not_public(self):
        result = self.collector.classify_detail_price(
            {"url": "https://www.amazon.com/dp/B000000000", "title": "Example", "heading": "Example"}
        )

        self.assertEqual("PRICE_MISSING_UNEXPLAINED", result["reason_code"])

    def test_classifies_explicit_coupon_and_verified_price_drop_separately(self):
        result = self.collector.classify_detail_discounts(
            {
                "title": "Example product",
                "coupon": "Save 10% with coupon",
                "current_price": "$89.99",
                "list_price": "$99.99",
            }
        )

        self.assertEqual(
            {
                "has_discount": True,
                "discounts": [
                    {"kind": "COUPON", "amount": "10% off"},
                    {"kind": "PRICE_DROP", "amount": "$10.00 off"},
                ],
            },
            result,
        )

    def test_classifies_prime_exclusive_and_treats_unreadable_detail_as_unknown(self):
        self.assertEqual(
            {
                "has_discount": True,
                "discounts": [{"kind": "PRIME_EXCLUSIVE", "amount": "Prime exclusive"}],
            },
            self.collector.classify_detail_discounts(
                {"title": "Example product", "prime_discount": "Prime Exclusive Discount"}
            ),
        )
        self.assertEqual(
            {"has_discount": None, "discounts": []},
            self.collector.classify_detail_discounts({"url": "https://www.amazon.com/dp/B000000001"}),
        )

    def test_prime_member_price_is_treated_as_prime_exclusive_discount(self):
        self.assertEqual(
            {
                "has_discount": True,
                "discounts": [{"kind": "PRIME_EXCLUSIVE", "amount": "Prime price $89.99"}],
            },
            self.collector.classify_detail_discounts(
                {"title": "Example product", "prime_discount": "$89.99 with Prime"}
            ),
        )

    def test_explicit_prime_savings_remains_a_supported_discount(self):
        self.assertEqual(
            {
                "has_discount": True,
                "discounts": [{"kind": "PRIME_EXCLUSIVE", "amount": "$10.00 off"}],
            },
            self.collector.classify_detail_discounts(
                {"title": "Example product", "prime_discount": "Prime members save $10.00"}
            ),
        )

    def test_extract_detail_page_returns_only_sanitized_supported_signals(self):
        class Page:
            def evaluate(self, script):
                return {
                    "url": " https://www.amazon.com/dp/B000000000 ",
                    "title": " Example product ",
                    "heading": " Product details ",
                    "price": " $19.99 ",
                    "availability": " Currently unavailable. ",
                    "buying_options": " See All Buying Options ",
                    "blocked_markers": ["BOT_CHALLENGE", "unknown", "BOT_CHALLENGE"],
                    "body_text": "sensitive unstructured page text",
                }

        self.assertEqual(
            {
                "url": "https://www.amazon.com/dp/B000000000",
                "title": "Example product",
                "heading": "Product details",
                "detail_asin": None,
                "price": "$19.99",
                "availability": "Currently unavailable.",
                "buying_options": "See All Buying Options",
                "coupon": None,
                "prime_discount": None,
                "current_price": None,
                "list_price": None,
                "brand_candidates": [],
                "blocked_markers": ["BOT_CHALLENGE"],
            },
            self.collector._extract_detail_page(Page()),
        )

    def test_extract_detail_page_keeps_only_public_discount_signals(self):
        class Page:
            def evaluate(self, script):
                return {
                    "url": "https://www.amazon.com/dp/B000000000",
                    "title": "Example product",
                    "coupon": "Save 10% with coupon",
                    "prime_discount": "Prime Exclusive Deal",
                    "primary_offer_current_price": "$89.99",
                    "primary_offer_list_price": "$99.99",
                    "body_text": "sensitive unstructured page text",
                }

        result = self.collector._extract_detail_page(Page())

        self.assertEqual("Save 10% with coupon", result["coupon"])
        self.assertEqual("Prime Exclusive Deal", result["prime_discount"])
        self.assertEqual("$89.99", result["current_price"])
        self.assertEqual("$99.99", result["list_price"])
        self.assertNotIn("body_text", result)

    def test_recommendation_prices_cannot_create_a_price_drop(self):
        evaluated_scripts = []

        class Page:
            def evaluate(self, script):
                evaluated_scripts.append(script)
                return {
                    "url": "https://www.amazon.com/dp/B000000000",
                    "title": "Example product",
                    "current_price": "$89.99",
                    "list_price": "$99.99",
                }

        extracted = self.collector._extract_detail_page(Page())

        self.assertNotIn("#centerCol", evaluated_scripts[0])
        self.assertIn("#corePrice_feature_div", evaluated_scripts[0])
        self.assertIsNone(extracted["current_price"])
        self.assertIsNone(extracted["list_price"])
        self.assertEqual(
            {"has_discount": False, "discounts": []},
            self.collector.classify_detail_discounts(extracted),
        )


class PriceVerificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    @staticmethod
    def chart(observations):
        return [{
            "category_key": "pressure_washers",
            "url": "https://www.amazon.com/Best-Sellers-Pressure-Washers/zgbs/552856",
            "observations": observations,
        }]

    class DetailPage:
        def __init__(self, extracted, goto_error=None, evaluate_error=None):
            self.extracted = extracted
            self.goto_error = goto_error
            self.evaluate_error = evaluate_error
            self.goto_urls = []
            self.closed = False

        def goto(self, url, **kwargs):
            self.goto_urls.append(url)
            if self.goto_error:
                raise self.goto_error

        def evaluate(self, script):
            if self.evaluate_error:
                raise self.evaluate_error
            return copy.deepcopy(self.extracted)

        def close(self):
            self.closed = True

    class DetailContext:
        def __init__(self, pages):
            self.pages = list(pages)
            self.new_page_calls = 0

        def new_page(self):
            self.new_page_calls += 1
            page = self.pages.pop(0)
            if isinstance(page, Exception):
                raise page
            return page

    def test_already_priced_observations_do_not_open_detail_tabs(self):
        context = self.DetailContext([])
        charts = self.chart([{"asin": "B000000001", "url": "https://www.amazon.com/dp/B000000001", "price": "$9.99"}])

        verified, evidence, failures = self.collector.verify_chart_prices(context, charts)

        self.assertEqual(0, context.new_page_calls)
        self.assertEqual(charts, verified)
        self.assertEqual([], evidence)
        self.assertEqual([], failures)

    def test_detail_verification_sets_discount_states_for_every_observation(self):
        coupon_page = self.DetailPage({
            "url": "https://www.amazon.com/dp/B000000001",
            "title": "Coupon product",
            "detail_asin": "B000000001",
            "coupon": "Save 10% with coupon",
        })
        no_discount_page = self.DetailPage({
            "url": "https://www.amazon.com/dp/B000000002",
            "title": "Regular product",
            "detail_asin": "B000000002",
        })
        blocked_page = self.DetailPage({
            "url": "https://www.amazon.com/dp/B000000003",
            "blocked_markers": ["BOT_CHALLENGE"],
        })
        context = self.DetailContext([coupon_page, no_discount_page, blocked_page])
        charts = self.chart([
            {"asin": "B000000001", "price": "$9.99"},
            {"asin": "B000000002", "price": "$9.99"},
            {"asin": "B000000003", "price": "$9.99"},
        ])

        verified, evidence, _ = self.collector.verify_chart_discounts(context, charts)

        observations = verified[0]["observations"]
        self.assertEqual(3, context.new_page_calls)
        self.assertEqual(True, observations[0]["has_discount"])
        self.assertEqual([{"kind": "COUPON", "amount": "10% off"}], observations[0]["discounts"])
        self.assertEqual(False, observations[1]["has_discount"])
        self.assertEqual([], observations[1]["discounts"])
        self.assertIsNone(observations[2]["has_discount"])
        self.assertEqual([], observations[2]["discounts"])
        self.assertTrue(all(page.closed for page in (coupon_page, no_discount_page, blocked_page)))
        self.assertEqual(
            ["VERIFIED", "VERIFIED", "VERIFICATION_BLOCKED"],
            [item["verification_status"] for item in evidence],
        )

    def test_discount_navigation_error_is_unknown_and_closes_open_tab(self):
        page = self.DetailPage({}, goto_error=RuntimeError("navigation failed"))
        verified, evidence, _ = self.collector.verify_chart_discounts(
            self.DetailContext([page]), self.chart([{"asin": "B000000001", "price": "$9.99"}])
        )

        self.assertTrue(page.closed)
        self.assertIsNone(verified[0]["observations"][0]["has_discount"])
        self.assertEqual([], verified[0]["observations"][0]["discounts"])
        self.assertEqual("VERIFICATION_BLOCKED", evidence[0]["verification_status"])

    def test_discount_redirect_to_non_product_page_is_unknown(self):
        page = self.DetailPage({
            "url": "https://www.amazon.com/s?k=B000000001",
            "title": "Amazon.com: B000000001",
        })
        verified, evidence, _ = self.collector.verify_chart_discounts(
            self.DetailContext([page]), self.chart([{"asin": "B000000001", "price": "$9.99"}])
        )

        self.assertTrue(page.closed)
        self.assertIsNone(verified[0]["observations"][0]["has_discount"])
        self.assertEqual([], verified[0]["observations"][0]["discounts"])
        self.assertEqual("VERIFICATION_BLOCKED", evidence[0]["verification_status"])

    def test_discount_canonical_url_error_page_without_product_identity_is_unknown(self):
        page = self.DetailPage({
            "url": "https://www.amazon.com/dp/B000000001",
            "title": "Sorry, we couldn't find that page",
        })
        verified, evidence, _ = self.collector.verify_chart_discounts(
            self.DetailContext([page]), self.chart([{"asin": "B000000001", "price": "$9.99"}])
        )

        self.assertTrue(page.closed)
        self.assertIsNone(verified[0]["observations"][0]["has_discount"])
        self.assertEqual([], verified[0]["observations"][0]["discounts"])
        self.assertEqual("VERIFICATION_BLOCKED", evidence[0]["verification_status"])

    def test_detail_price_supplements_only_missing_price_and_records_sanitized_evidence(self):
        detail_page = self.DetailPage({"url": "https://www.amazon.com/dp/B000000001", "price": " $19.99 "})
        context = self.DetailContext([detail_page])
        charts = self.chart([
            {"asin": "B000000001", "url": "https://www.amazon.com/dp/B000000001", "price": None, "title": "Missing"},
            {"asin": "B000000002", "url": "https://www.amazon.com/dp/B000000002", "price": "$8.00", "title": "Already priced"},
        ])

        verified, evidence, failures = self.collector.verify_chart_prices(context, charts)

        self.assertEqual("$19.99", verified[0]["observations"][0]["price"])
        self.assertEqual("$8.00", verified[0]["observations"][1]["price"])
        self.assertTrue(detail_page.closed)
        self.assertEqual(["https://www.amazon.com/dp/B000000001"], detail_page.goto_urls)
        self.assertEqual([], failures)
        self.assertEqual({
            "category_key": "pressure_washers",
            "asin": "B000000001",
            "chart_url": "https://www.amazon.com/Best-Sellers-Pressure-Washers/zgbs/552856",
            "detail_url": "https://www.amazon.com/dp/B000000001",
            "reason_code": "DETAIL_PRICE_FOUND",
            "supplemented": True,
            "source": "DETAIL_PAGE",
        }, evidence[0])
        self.assertNotIn("body_text", evidence[0])

    def test_price_not_public_keeps_null_price_without_failure(self):
        detail_page = self.DetailPage({"url": "https://www.amazon.com/dp/B000000001", "availability": "Currently unavailable."})
        verified, evidence, failures = self.collector.verify_chart_prices(
            self.DetailContext([detail_page]),
            self.chart([{"asin": "B000000001", "url": "https://www.amazon.com/dp/B000000001", "price": None}]),
        )

        self.assertIsNone(verified[0]["observations"][0]["price"])
        self.assertEqual([], failures)
        self.assertEqual("PRICE_NOT_PUBLIC", evidence[0]["reason_code"])
        self.assertFalse(evidence[0]["supplemented"])

    def test_off_origin_observation_href_is_never_used_for_detail_navigation(self):
        detail_page = self.DetailPage({"availability": "Currently unavailable."})
        context = self.DetailContext([detail_page])

        _, evidence, failures = self.collector.verify_chart_prices(
            context,
            self.chart([{
                "asin": "B000000001",
                "url": "https://attacker.example/collect?session_token=secret",
                "price": None,
            }]),
        )

        self.assertEqual(["https://www.amazon.com/dp/B000000001"], detail_page.goto_urls)
        self.assertEqual("https://www.amazon.com/dp/B000000001", evidence[0]["detail_url"])
        self.assertEqual([], failures)

    def test_mismatched_amazon_href_is_never_used_for_detail_navigation(self):
        detail_page = self.DetailPage({"availability": "Currently unavailable."})

        _, evidence, failures = self.collector.verify_chart_prices(
            self.DetailContext([detail_page]),
            self.chart([{
                "asin": "B000000001",
                "url": "https://www.amazon.com/dp/B000000002?authorization=secret",
                "price": None,
            }]),
        )

        self.assertEqual(["https://www.amazon.com/dp/B000000001"], detail_page.goto_urls)
        self.assertEqual("https://www.amazon.com/dp/B000000001", evidence[0]["detail_url"])
        self.assertEqual([], failures)

    def test_invalid_asin_blocks_verification_without_opening_or_navigating(self):
        for invalid_asin in ("B00000001/", "b000000001"):
            with self.subTest(invalid_asin=invalid_asin):
                context = self.DetailContext([])

                _, evidence, failures = self.collector.verify_chart_prices(
                    context,
                    self.chart([{
                        "asin": invalid_asin,
                        "url": "https://attacker.example/collect",
                        "price": None,
                    }]),
                )

                self.assertEqual(0, context.new_page_calls)
                self.assertEqual("VERIFICATION_BLOCKED", evidence[0]["reason_code"])
                self.assertIsNone(evidence[0]["detail_url"])
                self.assertEqual(
                    ["PRICE_VERIFICATION_FAILED:UNKNOWN_ASIN:VERIFICATION_BLOCKED:INVALID_ASIN"],
                    failures,
                )

    def test_blocked_and_unexplained_detail_results_return_deterministic_failure_reasons(self):
        context = self.DetailContext([
            self.DetailPage({"url": "https://www.amazon.com/dp/B000000001", "blocked_markers": ["BOT_CHALLENGE"]}),
            self.DetailPage({"url": "https://www.amazon.com/dp/B000000002", "title": "Readable product"}),
        ])

        _, evidence, failures = self.collector.verify_chart_prices(context, self.chart([
            {"asin": "B000000001", "url": "https://www.amazon.com/dp/B000000001", "price": None},
            {"asin": "B000000002", "url": "https://www.amazon.com/dp/B000000002", "price": None},
        ]))

        self.assertEqual([
            "PRICE_VERIFICATION_FAILED:B000000001:VERIFICATION_BLOCKED:BOT_CHALLENGE",
            "PRICE_VERIFICATION_FAILED:B000000002:PRICE_MISSING_UNEXPLAINED",
        ], failures)
        self.assertEqual(["VERIFICATION_BLOCKED", "PRICE_MISSING_UNEXPLAINED"], [item["reason_code"] for item in evidence])

    def test_detail_context_and_navigation_errors_are_blocked_and_close_open_tabs(self):
        navigation_page = self.DetailPage({}, goto_error=RuntimeError("navigation failed"))
        context = self.DetailContext([RuntimeError("context page failed"), navigation_page])

        _, evidence, failures = self.collector.verify_chart_prices(context, self.chart([
            {"asin": "B000000001", "url": "https://www.amazon.com/dp/B000000001", "price": None},
            {"asin": "B000000002", "url": "https://www.amazon.com/dp/B000000002", "price": None},
        ]))

        self.assertTrue(navigation_page.closed)
        self.assertEqual(["VERIFICATION_BLOCKED", "VERIFICATION_BLOCKED"], [item["reason_code"] for item in evidence])
        self.assertEqual([
            "PRICE_VERIFICATION_FAILED:B000000001:VERIFICATION_BLOCKED:RuntimeError",
            "PRICE_VERIFICATION_FAILED:B000000002:VERIFICATION_BLOCKED:RuntimeError",
        ], failures)

    def test_detail_extraction_exception_closes_open_tab(self):
        detail_page = self.DetailPage({}, evaluate_error=RuntimeError("evaluate failed"))

        _, evidence, failures = self.collector.verify_chart_prices(
            self.DetailContext([detail_page]),
            self.chart([{
                "asin": "B000000001",
                "url": "https://www.amazon.com/dp/B000000001",
                "price": None,
            }]),
        )

        self.assertTrue(detail_page.closed)
        self.assertEqual("VERIFICATION_BLOCKED", evidence[0]["reason_code"])
        self.assertEqual(
            ["PRICE_VERIFICATION_FAILED:B000000001:VERIFICATION_BLOCKED:RuntimeError"],
            failures,
        )


class CollectionRecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    @staticmethod
    def config(count=1):
        names = ("Pressure Washers", "Sump Pumps", "Pressure Washer Accessories")
        return {
            "target_count": 30,
            "sources": [
                {
                    "category_key": f"category_{index}",
                    "display_name": f"{name} Best Sellers",
                    "url": f"https://www.amazon.com/category-{index}",
                    "active": True,
                }
                for index, name in enumerate(names[:count], start=1)
            ],
        }

    @staticmethod
    def complete_chart(category_key="category_1", asin_prefix="A"):
        observations = [
            {
                "rank": rank,
                "asin": f"{asin_prefix}{rank:09d}",
                "title": f"Product {rank}",
                "url": f"https://www.amazon.com/dp/{asin_prefix}{rank:09d}",
                "price": "$9.99",
                "rating": None,
                "reviews": None,
            }
            for rank in range(1, 31)
        ]
        return {
            "category_key": category_key,
            "url": f"https://www.amazon.com/{category_key}",
            "status": "COMPLETE",
            "observation_count": 30,
            "pagination_decision": "NOT_NEEDED_TARGET_REACHED",
            "error_reason": None,
            "rejection_reasons": [],
            "observations": observations,
        }

    def test_strict_validation_rejects_missing_title(self):
        chart = self.complete_chart()
        chart["observations"][4]["title"] = None

        failures = self.collector.validate_collection_attempt(self.config(), [chart], [])

        self.assertEqual(["MISSING_TITLE:category_1:5"], failures)

    def test_strict_validation_rejects_non_contiguous_ranks(self):
        chart = self.complete_chart()
        chart["observations"][9]["rank"] = 31

        failures = self.collector.validate_collection_attempt(self.config(), [chart], [])

        self.assertEqual(["INVALID_RANKS:category_1"], failures)

    def test_strict_validation_rejects_duplicate_asin(self):
        chart = self.complete_chart()
        chart["observations"][1]["asin"] = chart["observations"][0]["asin"]

        failures = self.collector.validate_collection_attempt(self.config(), [chart], [])

        self.assertEqual(["DUPLICATE_ASIN:category_1:A000000001"], failures)

    def test_strict_validation_rejects_non_complete_category(self):
        chart = self.complete_chart()
        chart["status"] = "PARTIAL"

        failures = self.collector.validate_collection_attempt(self.config(), [chart], [])

        self.assertEqual(["CATEGORY_NOT_COMPLETE:category_1:PARTIAL"], failures)

    def test_strict_validation_rejects_unexplained_null_price(self):
        chart = self.complete_chart()
        chart["observations"][0]["price"] = None

        failures = self.collector.validate_collection_attempt(
            self.config(),
            [chart],
            ["PRICE_VERIFICATION_FAILED:A000000001:PRICE_MISSING_UNEXPLAINED"],
        )

        self.assertEqual(
            ["PRICE_VERIFICATION_FAILED:A000000001:PRICE_MISSING_UNEXPLAINED"],
            failures,
        )

    def test_strict_validation_rejects_null_without_price_not_public_evidence(self):
        chart = self.complete_chart()
        chart["observations"][0]["price"] = None

        failures = self.collector.validate_collection_attempt(self.config(), [chart], [])

        self.assertEqual(["MISSING_PRICE_EVIDENCE:category_1:A000000001"], failures)

    def test_strict_validation_rejects_null_with_mismatched_price_not_public_evidence(self):
        chart = self.complete_chart()
        chart["observations"][0]["price"] = None
        evidence = [{
            "category_key": "category_1",
            "asin": "A000000002",
            "reason_code": "PRICE_NOT_PUBLIC",
        }]

        failures = self.collector.validate_collection_attempt(self.config(), [chart], [], evidence)

        self.assertEqual(["MISSING_PRICE_EVIDENCE:category_1:A000000001"], failures)

    def test_strict_validation_rejects_duplicate_category_results(self):
        chart = self.complete_chart()

        failures = self.collector.validate_collection_attempt(self.config(), [chart, copy.deepcopy(chart)], [])

        self.assertEqual(["DUPLICATE_CATEGORY_RESULT:category_1"], failures)

    def test_strict_validation_accepts_null_after_price_not_public_evidence(self):
        chart = self.complete_chart()
        chart["observations"][0]["price"] = None
        context = PriceVerificationTests.DetailContext([
            PriceVerificationTests.DetailPage({
                "url": chart["observations"][0]["url"],
                "availability": "Currently unavailable.",
            })
        ])

        verified, evidence, price_failures = self.collector.verify_chart_prices(context, [chart])
        failures = self.collector.validate_collection_attempt(
            self.config(), verified, price_failures, evidence
        )

        self.assertEqual("PRICE_NOT_PUBLIC", evidence[0]["reason_code"])
        self.assertEqual([], failures)

    class Page:
        def __init__(self, extracted):
            self.extracted = extracted
            self.closed = False

        def goto(self, *args, **kwargs):
            return None

        def evaluate(self, script):
            return copy.deepcopy(self.extracted)

        def locator(self, selector):
            return _FakeLocator()

        def close(self):
            self.closed = True

    class Context:
        def __init__(self, pages, close_error=False):
            self.pages = list(pages)
            self.new_page_calls = 0
            self.closed = False
            self.close_error = close_error

        def new_page(self):
            self.new_page_calls += 1
            return self.pages.pop(0)

        def close(self):
            if self.close_error:
                raise RuntimeError("context close failed")
            self.closed = True

    class Browser:
        def __init__(self, context, close_error=False):
            self.context = context
            self.closed = False
            self.context_kwargs = None
            self.close_error = close_error

        def new_context(self, **kwargs):
            self.context_kwargs = kwargs
            return self.context

        def close(self):
            if self.close_error:
                raise RuntimeError("browser close failed")
            self.closed = True

    class Chromium:
        def __init__(self, browsers):
            self.browsers = list(browsers)
            self.launch_calls = []
            self.previous_browser = None

        def launch(self, **kwargs):
            if self.previous_browser is not None and (
                not self.previous_browser.closed or not self.previous_browser.context.closed
            ):
                raise AssertionError("previous attempt was not closed before retry")
            self.launch_calls.append(kwargs)
            self.previous_browser = self.browsers.pop(0)
            return self.previous_browser

    class Manager:
        def __init__(self, browsers):
            self.playwright = type("Playwright", (), {"chromium": CollectionRecoveryTests.Chromium(browsers)})()

        def __enter__(self):
            return self.playwright

        def __exit__(self, exc_type, exc, traceback):
            return False

    @classmethod
    def attempt_browser(cls, config, asin_prefix, incomplete=False):
        pages = []
        detail_pages = []
        for source_index, source in enumerate(config["sources"], start=1):
            cards = [
                {
                    "rank": f"#{rank}",
                    "asin": f"{asin_prefix}{source_index}{rank:08d}",
                    "title": f"Attempt {asin_prefix} product {rank}",
                    "url": f"/dp/{asin_prefix}{source_index}{rank:08d}",
                    "price": "$9.99",
                }
                for rank in range(1, 31)
            ]
            if incomplete and source_index == 1:
                cards.pop()
            pages.append(cls.Page({
                "url": source["url"],
                "title": f"Amazon Best Sellers: Best {source['display_name']}",
                "heading": source["display_name"],
                "body_text": "Public chart",
                "cards": cards,
            }))
            detail_pages.extend(
                cls.Page({
                    "url": f"https://www.amazon.com/dp/{asin_prefix}{source_index}{rank:08d}",
                    "title": f"Attempt {asin_prefix} product {rank}",
                    "detail_asin": f"{asin_prefix}{source_index}{rank:08d}",
                })
                for rank in range(1, 31)
            )
        context = cls.Context([*pages, *detail_pages])
        return cls.Browser(context)

    def test_complete_attempt_verifies_discounts_for_all_observations(self):
        config = self.config(1)
        browser = self.attempt_browser(config, "S")

        charts, _, diagnostic = self.collector.collect_with_recovery(
            config, playwright_factory=lambda: self.Manager([browser])
        )

        observations = charts[0]["observations"]
        self.assertEqual("COMPLETE", diagnostic["status"])
        self.assertEqual(31, browser.context.new_page_calls)
        self.assertTrue(all(item["has_discount"] is False for item in observations))
        self.assertTrue(all(item["discounts"] == [] for item in observations))
        self.assertEqual(30, len(diagnostic["attempts"][0]["discount_evidence"]))

    def test_three_complete_categories_verify_ninety_discount_observations(self):
        config = self.config(3)
        browser = self.attempt_browser(config, "S")

        charts, _, diagnostic = self.collector.collect_with_recovery(
            config, playwright_factory=lambda: self.Manager([browser])
        )

        self.assertEqual("COMPLETE", diagnostic["status"])
        self.assertEqual(90, sum(len(chart["observations"]) for chart in charts))
        self.assertEqual(90, len(diagnostic["attempts"][0]["discount_evidence"]))
        self.assertEqual(93, browser.context.new_page_calls)

    def test_failed_attempt_then_success_uses_only_second_attempt(self):
        config = self.config(3)
        browsers = [
            self.attempt_browser(config, "F", incomplete=True),
            self.attempt_browser(config, "S"),
        ]
        manager = self.Manager(browsers)

        charts, browser_name, diagnostic = self.collector.collect_with_recovery(
            config, playwright_factory=lambda: manager
        )

        self.assertEqual("MICROSOFT_EDGE", browser_name)
        self.assertEqual("COMPLETE", diagnostic["status"])
        self.assertEqual(2, diagnostic["attempt_count"])
        self.assertEqual(["FAILED", "COMPLETE"], [attempt["status"] for attempt in diagnostic["attempts"]])
        self.assertTrue(all(item["asin"].startswith("S") for chart in charts for item in chart["observations"]))
        self.assertTrue(all(browser.closed and browser.context.closed for browser in browsers))
        self.assertEqual([3, 93], [browser.context.new_page_calls for browser in browsers])
        self.assertTrue(all(browser.context_kwargs == {} for browser in browsers))

    def test_category_recovery_retains_complete_markets_without_replacing_canonical_snapshot(self):
        config = self.config(3)
        source_urls = {source["category_key"]: source["url"] for source in json.loads(
            (PROJECT_ROOT / "config" / "best-sellers-sources.json").read_text(encoding="utf-8-sig")
        )["sources"]}
        for source, key in zip(config["sources"], ("pressure_washers", "sump_pumps", "pressure_washer_accessories")):
            source["category_key"] = key
            source["url"] = source_urls[key]
        browsers = [self.attempt_browser(config, prefix, incomplete=True) for prefix in ("A", "B", "C")]
        charts, _, diagnostic = self.collector.collect_with_recovery(
            config, playwright_factory=lambda: self.Manager(browsers), preserve_complete_categories=True
        )
        self.assertEqual("FAILED", diagnostic["status"])
        self.assertEqual(60, sum(len(chart["observations"]) for chart in charts))
        snapshot, status = self.collector.build_artifacts(config, charts, "2026-09-09", "2026-09-10T01:00:00Z")
        with tempfile.TemporaryDirectory() as root:
            canonical = Path(root) / "2026-09-09" / "amazon-bestsellers.json"
            canonical.parent.mkdir()
            canonical.write_text("existing verified snapshot", encoding="utf-8")
            result = self.collector.write_collection_artifacts(root, "2026-09-09", snapshot, status, diagnostic, config, preserve_complete_categories=True)
            self.assertIsNone(result["snapshot_path"])
            self.assertEqual("existing verified snapshot", canonical.read_text(encoding="utf-8"))
            self.assertEqual(2, len(result["status"]["CompleteCategories"]))
            self.assertTrue(Path(result["status"]["PartialSnapshotPath"]).is_file())
            config_path = Path(root) / "sources.json"
            config_path.write_text(json.dumps(config), encoding="utf-8")
            stdout = io.StringIO()
            with patch.object(self.collector, "collect_with_recovery", return_value=(charts, "MICROSOFT_EDGE", diagnostic)), contextlib.redirect_stdout(stdout):
                exit_code = self.collector.main(["--config", str(config_path), "--output-root", root, "--market-date", "2026-09-09"])
            control = json.loads(stdout.getvalue())
            self.assertNotEqual(0, exit_code)
            self.assertEqual(result["status"]["CompleteCategories"], control.get("CompleteCategories"))
            self.assertTrue(Path(control["PartialSnapshotPath"]).is_file())
            self.assertEqual("existing verified snapshot", canonical.read_text(encoding="utf-8"))

    def test_three_failed_attempts_return_no_publishable_charts(self):
        config = self.config(3)
        browsers = [self.attempt_browser(config, prefix, incomplete=True) for prefix in ("A", "B", "C")]
        manager = self.Manager(browsers)

        charts, _, diagnostic = self.collector.collect_with_recovery(
            config, playwright_factory=lambda: manager
        )

        self.assertEqual([], charts)
        self.assertEqual("FAILED", diagnostic["status"])
        self.assertEqual(3, diagnostic["attempt_count"])
        self.assertEqual(["FAILED", "FAILED", "FAILED"], [attempt["status"] for attempt in diagnostic["attempts"]])
        self.assertTrue(all(browser.closed and browser.context.closed for browser in browsers))
        self.assertTrue(all(browser.context.new_page_calls == 3 for browser in browsers))
        self.assertNotIn("cards", json.dumps(diagnostic))

    def test_context_close_failure_stops_without_retrying_in_uncertain_session_state(self):
        config = self.config(1)
        first = self.attempt_browser(config, "A", incomplete=True)
        first.context.close_error = True
        second = self.attempt_browser(config, "B")
        manager = self.Manager([first, second])

        charts, _, diagnostic = self.collector.collect_with_recovery(
            config, playwright_factory=lambda: manager
        )

        self.assertEqual([], charts)
        self.assertEqual(1, diagnostic["attempt_count"])
        self.assertEqual(
            ["CONTEXT_CLEANUP_FAILED:RuntimeError"],
            diagnostic["attempts"][0]["failures"],
        )
        self.assertEqual(1, len(manager.playwright.chromium.launch_calls))
        self.assertTrue(first.closed)

    def test_browser_close_failure_stops_without_retrying_in_uncertain_session_state(self):
        config = self.config(1)
        first = self.attempt_browser(config, "A", incomplete=True)
        first.close_error = True
        second = self.attempt_browser(config, "B")
        manager = self.Manager([first, second])

        charts, _, diagnostic = self.collector.collect_with_recovery(
            config, playwright_factory=lambda: manager
        )

        self.assertEqual([], charts)
        self.assertEqual(1, diagnostic["attempt_count"])
        self.assertIn("BROWSER_CLEANUP_FAILED:RuntimeError", diagnostic["attempts"][0]["failures"])
        self.assertEqual(1, len(manager.playwright.chromium.launch_calls))
        self.assertTrue(first.context.closed)


class CompletenessArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    @staticmethod
    def config():
        return {
            "marketplace": "AMAZON_US",
            "target_count": 30,
            "sources": [dict(SOURCE, active=True)],
        }

    @staticmethod
    def complete_chart(price="$9.99"):
        observations = [
            {
                "rank": rank,
                "asin": f"A{rank:09d}",
                "title": f"Product {rank}",
                "url": f"https://www.amazon.com/dp/A{rank:09d}",
                "price": price if rank == 1 else "$9.99",
                "rating": None,
                "reviews": None,
            }
            for rank in range(1, 31)
        ]
        return {
            "category_key": SOURCE["category_key"],
            "url": SOURCE["url"],
            "status": "COMPLETE",
            "observation_count": 30,
            "pagination_decision": "NOT_NEEDED_TARGET_REACHED",
            "error_reason": None,
            "rejection_reasons": [],
            "observations": observations,
        }

    def run_main(self, root, recovery_result=None, fixture=None):
        config_path = root / "sources.json"
        output_root = root / "snapshots"
        config_path.write_text(json.dumps(self.config()), encoding="utf-8")
        arguments = [
            "--project-root", str(root),
            "--config", str(config_path),
            "--output-root", str(output_root),
            "--market-date", "2026-08-13",
        ]
        if fixture is not None:
            fixture_path = root / "fixture.json"
            fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
            arguments += ["--fixture-input", str(fixture_path)]
        stdout = io.StringIO()
        patcher = (
            patch.object(self.collector, "collect_with_recovery", return_value=recovery_result)
            if recovery_result is not None
            else patch.object(self.collector, "collect_with_recovery", side_effect=AssertionError("fixture used network recovery"))
        )
        with patcher, contextlib.redirect_stdout(stdout):
            exit_code = self.collector.main(arguments)
        return exit_code, json.loads(stdout.getvalue()), output_root / "2026-08-13"

    def test_complete_run_writes_atomic_diagnostic_and_extends_status_and_control(self):
        diagnostic = {"status": "COMPLETE", "attempt_count": 1, "attempts": [
            {"attempt": 1, "status": "COMPLETE", "failures": [], "price_evidence": []}
        ]}
        with tempfile.TemporaryDirectory() as temp_dir:
            exit_code, control, day = self.run_main(
                Path(temp_dir), ([self.complete_chart()], "MICROSOFT_EDGE", diagnostic)
            )

            status = json.loads((day / "best-sellers-collection-status.json").read_text(encoding="utf-8"))
            written_diagnostic = json.loads((day / "price-completeness-diagnostic.json").read_text(encoding="utf-8"))
            snapshot = json.loads((day / "amazon-bestsellers.json").read_text(encoding="utf-8"))
            self.assertEqual(self.collector.EXIT_OK, exit_code)
            self.assertEqual("amazon-best-sellers-snapshot-v1", snapshot["schema_version"])
            self.assertNotIn("CompletenessStatus", snapshot)
            for artifact in (status, control):
                self.assertEqual("COMPLETE", artifact["CompletenessStatus"])
                self.assertEqual(1, artifact["AttemptCount"])
                self.assertEqual(0, artifact["PriceVerificationCount"])
                self.assertEqual([], artifact["FailureReasons"])
            self.assertEqual(control["DiagnosticPath"], status["DiagnosticPath"])
            self.assertEqual("COMPLETE", written_diagnostic["status"])

    def test_supplemented_price_is_published_and_counted(self):
        chart = self.complete_chart(price="$19.99")
        evidence = [{
            "category_key": SOURCE["category_key"], "asin": "A000000001",
            "chart_url": SOURCE["url"], "detail_url": "https://www.amazon.com/dp/A000000001",
            "reason_code": "DETAIL_PRICE_FOUND", "supplemented": True, "source": "DETAIL_PAGE",
        }]
        diagnostic = {"status": "COMPLETE", "attempt_count": 1, "attempts": [
            {"attempt": 1, "status": "COMPLETE", "failures": [], "price_evidence": evidence}
        ]}
        with tempfile.TemporaryDirectory() as temp_dir:
            exit_code, control, day = self.run_main(Path(temp_dir), ([chart], "MICROSOFT_EDGE", diagnostic))

            snapshot = json.loads((day / "amazon-bestsellers.json").read_text(encoding="utf-8"))
            self.assertEqual(self.collector.EXIT_OK, exit_code)
            self.assertEqual("$19.99", snapshot[SOURCE["category_key"]][0]["price"])
            self.assertEqual(1, control["PriceVerificationCount"])

    def test_discount_evidence_is_sanitized_and_counted_separately(self):
        config = self.config()
        config["sources"][0]["url"] = CANONICAL_PRESSURE_WASHER_URL
        chart = self.complete_chart()
        snapshot, status = self.collector.build_artifacts(
            config, [chart], "2026-08-13", "2026-08-13T00:00:00Z"
        )
        diagnostic = {"status": "COMPLETE", "attempt_count": 1, "attempts": [{
            "attempt": 1,
            "status": "COMPLETE",
            "failures": [],
            "collected_observations": [{"category_key": SOURCE["category_key"], "asin": "A000000001"}],
            "price_evidence": [],
            "discount_evidence": [{
                "category_key": SOURCE["category_key"],
                "asin": "A000000001",
                "detail_url": "https://attacker.example/dp/A000000001?token=secret",
                "verification_status": "VERIFIED",
                "source": "DETAIL_PAGE",
                "exception": "credential=secret",
            }],
        }]}
        with tempfile.TemporaryDirectory() as temp_dir:
            self.collector.write_collection_artifacts(
                temp_dir, "2026-08-13", snapshot, status, diagnostic, config
            )
            persisted = json.loads(
                (Path(temp_dir) / "2026-08-13" / "price-completeness-diagnostic.json").read_text(encoding="utf-8")
            )

        self.assertEqual(1, persisted["attempts"][0]["discount_evidence"].__len__())
        self.assertEqual(
            {
                "category_key": SOURCE["category_key"],
                "asin": "A000000001",
                "detail_url": "https://www.amazon.com/dp/A000000001",
                "verification_status": "VERIFIED",
                "source": "DETAIL_PAGE",
            },
            persisted["attempts"][0]["discount_evidence"][0],
        )
        self.assertNotIn("secret", json.dumps(persisted).casefold())

    def test_persisted_evidence_keeps_only_attempt_observation_associations(self):
        category_key = "pressure_washers"
        canonical_chart_url = CANONICAL_PRESSURE_WASHER_URL
        config = self.config()
        config["sources"][0]["url"] = canonical_chart_url
        chart = self.complete_chart()
        snapshot, status = self.collector.build_artifacts(
            config, [chart], "2026-08-13", "2026-08-13T00:00:00Z"
        )
        diagnostic = {
            "status": "COMPLETE",
            "attempts": [{
                "attempt": 1,
                "status": "COMPLETE",
                "failures": [],
                "collected_observations": [{"category_key": category_key, "asin": "A000000001"}],
                "price_evidence": [
                    {
                        "category_key": category_key,
                        "asin": "A000000001",
                        "chart_url": "https://attacker.example/chart?token=secret",
                        "detail_url": "https://attacker.example/item?token=secret",
                        "reason_code": "DETAIL_PRICE_FOUND",
                        "supplemented": True,
                        "source": "DETAIL_PAGE",
                    },
                    {
                        "category_key": "sump_pumps",
                        "asin": "A000000001",
                        "chart_url": "https://www.amazon.com/secret-category",
                        "detail_url": "https://www.amazon.com/dp/A000000001?token=secret",
                        "reason_code": "VERIFICATION_BLOCKED",
                        "supplemented": False,
                        "source": "DETAIL_PAGE",
                    },
                    {
                        "category_key": category_key,
                        "asin": "A000000099",
                        "chart_url": canonical_chart_url,
                        "detail_url": "https://www.amazon.com/dp/A000000099?token=secret",
                        "reason_code": "VERIFICATION_BLOCKED",
                        "supplemented": False,
                        "source": "DETAIL_PAGE",
                    },
                ],
            }],
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            self.collector.write_collection_artifacts(
                temp_dir, "2026-08-13", snapshot, status, diagnostic, config
            )
            persisted = json.loads(
                (Path(temp_dir) / "2026-08-13" / "price-completeness-diagnostic.json")
                .read_text(encoding="utf-8")
            )["attempts"][0]["price_evidence"]

        self.assertEqual({
            "category_key": category_key,
            "asin": "A000000001",
            "chart_url": canonical_chart_url,
            "detail_url": "https://www.amazon.com/dp/A000000001",
            "reason_code": "DETAIL_PRICE_FOUND",
            "supplemented": True,
            "source": "DETAIL_PAGE",
        }, persisted[0])
        for unassociated in persisted[1:]:
            self.assertNotIn("category_key", unassociated)
            self.assertNotIn("asin", unassociated)
            self.assertNotIn("chart_url", unassociated)
            self.assertNotIn("detail_url", unassociated)
        self.assertNotIn("token", json.dumps(persisted).casefold())

    def test_fixture_attempt_records_associations_needed_for_auditable_evidence(self):
        category_key = "pressure_washers"
        canonical_chart_url = CANONICAL_PRESSURE_WASHER_URL
        config = self.config()
        config["sources"][0]["url"] = canonical_chart_url
        page = load_fixture("complete-page.json")
        page["cards"][0]["price"] = None
        asin = page["cards"][0]["asin"]
        fixture = {
            "charts": {category_key: [page]},
            "price_evidence": [{
                "category_key": category_key,
                "asin": asin,
                "chart_url": "https://attacker.example/chart",
                "detail_url": "https://attacker.example/detail",
                "reason_code": "PRICE_NOT_PUBLIC",
                "supplemented": False,
                "source": "DETAIL_PAGE",
            }],
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fixture_path = root / "fixture.json"
            fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
            charts, diagnostic = self.collector._load_fixture_attempt(config, fixture_path)
            snapshot, status = self.collector.build_artifacts(
                config, charts, "2026-08-13", "2026-08-13T00:00:00Z"
            )
            self.collector.write_collection_artifacts(
                root, "2026-08-13", snapshot, status, diagnostic, config
            )
            evidence = json.loads(
                (root / "2026-08-13" / "price-completeness-diagnostic.json")
                .read_text(encoding="utf-8")
            )["attempts"][0]["price_evidence"][0]

        self.assertEqual(category_key, evidence["category_key"])
        self.assertEqual(asin, evidence["asin"])
        self.assertEqual(canonical_chart_url, evidence["chart_url"])
        self.assertEqual(f"https://www.amazon.com/dp/{asin}", evidence["detail_url"])

    def test_price_not_public_null_is_accepted_by_fixture_validation_gate_without_network(self):
        page = load_fixture("complete-page.json")
        page["cards"][0]["price"] = None
        fixture = {
            "charts": {SOURCE["category_key"]: [page]},
            "price_evidence": [{
                "category_key": SOURCE["category_key"],
                "asin": page["cards"][0]["asin"],
                "reason_code": "PRICE_NOT_PUBLIC",
                "supplemented": False,
                "source": "DETAIL_PAGE",
            }],
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            exit_code, control, day = self.run_main(Path(temp_dir), fixture=fixture)

            snapshot = json.loads((day / "amazon-bestsellers.json").read_text(encoding="utf-8"))
            self.assertEqual(self.collector.EXIT_OK, exit_code)
            self.assertEqual("COMPLETE", control["CompletenessStatus"])
            self.assertEqual(1, control["AttemptCount"])
            self.assertEqual(1, control["PriceVerificationCount"])
            self.assertIsNone(snapshot[SOURCE["category_key"]][0]["price"])

    def test_three_failed_attempts_write_sanitized_diagnostics_and_preserve_snapshot_bytes(self):
        diagnostic = {
            "status": "FAILED",
            "attempt_count": 3,
            "cookies": [{"password": "top-secret"}],
            "browser_settings": {"profile": "C:/private"},
            "attempts": [
                {
                    "attempt": attempt,
                    "status": "FAILED",
                    "failures": [
                        "INVALID_RANKS:pressure_washers",
                        "TOKEN:secret",
                        "AUTHORIZATION:Bearer",
                        "session_token",
                    ],
                    "price_evidence": [{
                        "category_key": "cookie=secret",
                        "asin": "credential=secret",
                        "reason_code": "VERIFICATION_BLOCKED",
                        "supplemented": False,
                        "source": "profile=C:/private",
                        "chart_url": "https://www.amazon.com/zgbs/123?cookie=top-secret#credential",
                        "detail_url": "https://www.amazon.com/dp/B000000001?session_token=hidden",
                    }],
                    "body_text": "credential=secret cookie=session",
                }
                for attempt in range(1, 4)
            ],
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            day = root / "snapshots" / "2026-08-13"
            day.mkdir(parents=True)
            snapshot_path = day / "amazon-bestsellers.json"
            original = b'{"schema_version":"amazon-best-sellers-snapshot-v1","keep":true}\r\n'
            snapshot_path.write_bytes(original)

            exit_code, control, day = self.run_main(root, ([], "MICROSOFT_EDGE", diagnostic))

            status = json.loads((day / "best-sellers-collection-status.json").read_text(encoding="utf-8"))
            diagnostic_text = (day / "price-completeness-diagnostic.json").read_text(encoding="utf-8")
            self.assertNotEqual(0, exit_code)
            self.assertEqual(original, snapshot_path.read_bytes())
            self.assertIsNone(control["SnapshotPath"])
            self.assertEqual("FAILED", control["CompletenessStatus"])
            self.assertEqual(3, control["AttemptCount"])
            self.assertEqual(
                ["INVALID_RANKS", "UNSAFE_DIAGNOSTIC_REDACTED"],
                control["FailureReasons"],
            )
            self.assertEqual("FAILED", status["CompletenessStatus"])
            for forbidden in (
                "body_text", "cookie", "credential", "password", "profile", "browser_settings",
                "top-secret", "token", "authorization", "bearer", "hidden",
            ):
                self.assertNotIn(forbidden, diagnostic_text.casefold())
            persisted = json.loads(diagnostic_text)
            evidence = persisted["attempts"][0]["price_evidence"][0]
            self.assertNotIn("category_key", evidence)
            self.assertNotIn("asin", evidence)
            self.assertNotIn("source", evidence)
            self.assertNotIn("chart_url", evidence)
            self.assertNotIn("detail_url", evidence)

    def test_malformed_attempt_entries_are_skipped_and_renumbered_sequentially(self):
        diagnostic = {
            "status": "FAILED",
            "attempts": [None, {"attempt": 99, "status": "FAILED", "failures": ["INVALID_RANKS:anything"]}],
        }

        sanitized = self.collector.sanitize_recovery_diagnostic(diagnostic)

        self.assertEqual(1, sanitized["attempt_count"])
        self.assertEqual([1], [attempt["attempt"] for attempt in sanitized["attempts"]])

    def assert_safe_outer_failure(self, exit_code, control, day, expected_reason, forbidden):
        self.assertEqual(self.collector.EXIT_RUNTIME_ERROR, exit_code)
        self.assertEqual("ERROR", control["Status"])
        self.assertEqual("FAILED", control["CompletenessStatus"])
        self.assertEqual([expected_reason], control["FailureReasons"])
        self.assertIsNone(control["SnapshotPath"])
        status_text = (day / "best-sellers-collection-status.json").read_text(encoding="utf-8")
        diagnostic_text = (day / "price-completeness-diagnostic.json").read_text(encoding="utf-8")
        for secret in forbidden:
            self.assertNotIn(secret.casefold(), json.dumps(control).casefold())
            self.assertNotIn(secret.casefold(), status_text.casefold())
            self.assertNotIn(secret.casefold(), diagnostic_text.casefold())
        self.assertEqual([expected_reason], json.loads(status_text)["FailureReasons"])
        self.assertEqual([expected_reason], json.loads(diagnostic_text)["attempts"][0]["failures"])

    def test_malformed_config_writes_safe_failure_artifacts(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output_root = root / "snapshots"
            config_path = root / "sources.json"
            config_path.write_text('{"TOKEN":"top-secret"', encoding="utf-8")
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = self.collector.main([
                    "--project-root", str(root), "--config", str(config_path),
                    "--output-root", str(output_root), "--market-date", "2026-08-13",
                ])

            self.assert_safe_outer_failure(
                exit_code, json.loads(stdout.getvalue()), output_root / "2026-08-13",
                "CONFIG_LOAD_FAILED", ("TOKEN", "top-secret"),
            )

    def test_malformed_fixture_writes_safe_failure_artifacts(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            config_path = root / "sources.json"
            config_path.write_text(json.dumps(self.config()), encoding="utf-8")
            fixture_path = root / "fixture.json"
            fixture_path.write_text('{"AUTHORIZATION":"Bearer secret"', encoding="utf-8")
            output_root = root / "snapshots"
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = self.collector.main([
                    "--project-root", str(root), "--config", str(config_path),
                    "--fixture-input", str(fixture_path), "--output-root", str(output_root),
                    "--market-date", "2026-08-13",
                ])

            self.assert_safe_outer_failure(
                exit_code, json.loads(stdout.getvalue()), output_root / "2026-08-13",
                "FIXTURE_LOAD_FAILED", ("AUTHORIZATION", "Bearer secret"),
            )

    def test_build_and_artifact_exceptions_write_safe_failure_artifacts(self):
        cases = (
            ("build_artifacts", "ARTIFACT_BUILD_FAILED"),
            ("write_collection_artifacts", "ARTIFACT_WRITE_FAILED"),
        )
        diagnostic = {"status": "COMPLETE", "attempt_count": 1, "attempts": [
            {"attempt": 1, "status": "COMPLETE", "failures": [], "price_evidence": []}
        ]}
        for patched_name, expected_reason in cases:
            with self.subTest(patched_name=patched_name), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                config_path = root / "sources.json"
                config_path.write_text(json.dumps(self.config()), encoding="utf-8")
                output_root = root / "snapshots"
                stdout = io.StringIO()
                with (
                    patch.object(self.collector, "collect_with_recovery", return_value=([self.complete_chart()], "EDGE", diagnostic)),
                    patch.object(self.collector, patched_name, side_effect=RuntimeError("session_token=very-secret")),
                    contextlib.redirect_stdout(stdout),
                ):
                    exit_code = self.collector.main([
                        "--project-root", str(root), "--config", str(config_path),
                        "--output-root", str(output_root), "--market-date", "2026-08-13",
                    ])

                self.assert_safe_outer_failure(
                    exit_code, json.loads(stdout.getvalue()), output_root / "2026-08-13",
                    expected_reason, ("session_token", "very-secret"),
                )

    def test_untrusted_config_identifiers_and_urls_do_not_persist_in_failed_status(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output_root = root / "snapshots"
            config_path = root / "sources.json"
            config_path.write_text(json.dumps({
                "marketplace": "TOKEN=top-secret",
                "target_count": 30,
                "sources": [{
                    "category_key": "TOKEN=top-secret",
                    "display_name": "AUTHORIZATION=Bearer-hidden",
                    "url": "https://www.amazon.com/zgbs/123?session_token=hidden#credential",
                    "active": True,
                }],
            }), encoding="utf-8")
            fixture_path = root / "fixture.json"
            fixture_path.write_text(json.dumps({"charts": {}}), encoding="utf-8")
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = self.collector.main([
                    "--project-root", str(root), "--config", str(config_path),
                    "--fixture-input", str(fixture_path), "--output-root", str(output_root),
                    "--market-date", "2026-08-13",
                ])

            self.assertEqual(self.collector.EXIT_INCOMPLETE, exit_code)
            status_text = (output_root / "2026-08-13" / "best-sellers-collection-status.json").read_text(encoding="utf-8")
            control_text = stdout.getvalue()
            for secret in ("TOKEN", "top-secret", "AUTHORIZATION", "Bearer-hidden", "session_token", "hidden", "credential"):
                self.assertNotIn(secret.casefold(), status_text.casefold())
                self.assertNotIn(secret.casefold(), control_text.casefold())

    def test_secret_bearing_amazon_subdomain_is_normalized_to_fixed_origin(self):
        diagnostic = {"status": "FAILED", "attempts": [{
            "attempt": 1,
            "status": "FAILED",
            "failures": ["INVALID_RANKS:anything"],
            "price_evidence": [{
                "reason_code": "VERIFICATION_BLOCKED",
                "chart_url": "https://session-token.amazon.com/private?AUTHORIZATION=Bearer",
            }],
        }]}

        sanitized = self.collector.sanitize_recovery_diagnostic(diagnostic)

        text = json.dumps(sanitized)
        self.assertNotIn("session-token", text)
        self.assertNotIn("AUTHORIZATION", text)
        self.assertNotIn("chart_url", sanitized["attempts"][0]["price_evidence"][0])

    def test_complete_three_category_status_preserves_exact_trusted_source_identity(self):
        sources = [
            {
                "category_key": "pressure_washers",
                "display_name": "Pressure Washers Best Sellers",
                "url": "https://www.amazon.com/Best-Sellers-Patio-Lawn-Garden-Pressure-Washers/zgbs/lawn-garden/552856",
                "active": True,
            },
            {
                "category_key": "sump_pumps",
                "display_name": "Sump Pumps Best Sellers",
                "url": "https://www.amazon.com/Best-Sellers-Tools-Home-Improvement-Sump-Pumps/zgbs/hi/680335011",
                "active": True,
            },
            {
                "category_key": "pressure_washer_accessories",
                "display_name": "Accessories Best Sellers",
                "url": "https://www.amazon.com/Best-Sellers-Patio-Lawn-Garden-Pressure-Washer-Parts-Accessories/zgbs/lawn-garden/3023451",
                "active": True,
            },
        ]
        config = {"marketplace": "AMAZON_US", "target_count": 30, "sources": sources}
        charts = [
            self.complete_chart() | {"category_key": source["category_key"], "url": source["url"]}
            for source in sources
        ]
        snapshot, status = self.collector.build_artifacts(config, charts, "2026-08-13", "2026-08-13T00:00:00Z")
        diagnostic = {"status": "COMPLETE", "attempts": [
            {"attempt": 1, "status": "COMPLETE", "failures": [], "price_evidence": []}
        ]}
        with tempfile.TemporaryDirectory() as temp_dir:
            day = Path(temp_dir) / "2026-08-13"
            self.collector.write_collection_artifacts(
                temp_dir, "2026-08-13", snapshot, status, diagnostic, config
            )

            persisted = json.loads((day / "best-sellers-collection-status.json").read_text(encoding="utf-8"))
            self.assertEqual(
                [(source["category_key"], source["url"]) for source in sources],
                [(chart["category_key"], chart["url"]) for chart in persisted["charts"]],
            )

    def test_allowlisted_key_with_noncanonical_secret_path_is_redacted(self):
        malicious_url = "https://www.amazon.com:8443/TOKEN=top-secret/zgbs/552856"
        config = {
            "marketplace": "AMAZON_US",
            "sources": [{
                "category_key": "pressure_washers",
                "display_name": "Pressure Washers",
                "url": malicious_url,
                "active": True,
            }],
        }
        status = {
            "schema_version": "best-sellers-collection-status-v1",
            "market_date": "2026-08-13",
            "observed_at": "2026-08-13T00:00:00Z",
            "total_observation_count": 0,
            "charts": [{
                "category_key": "pressure_washers", "url": malicious_url,
                "status": "ZERO_OBSERVATIONS", "observation_count": 0,
                "pagination_decision": "NO_LATER_PAGE_AVAILABLE", "error_reason": "NO_PAGE_OBSERVED",
            }],
        }

        persisted = self.collector._safe_status_for_persistence(status, config)

        text = json.dumps(persisted)
        self.assertNotIn("TOKEN", text)
        self.assertNotIn("top-secret", text)
        self.assertEqual("REDACTED", persisted["charts"][0]["category_key"])
        self.assertIsNone(persisted["charts"][0]["url"])

    def test_failure_writer_attempts_diagnostic_when_status_write_fails(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            calls = []

            def selective_write(path, value):
                calls.append(path.name)
                if path.name == "best-sellers-collection-status.json":
                    raise OSError("TOKEN=secret")

            with patch.object(self.collector, "_atomic_json_write", side_effect=selective_write):
                with self.assertRaises(OSError):
                    self.collector._write_failure_artifacts(root, "2026-08-13", "2026-08-13T00:00:00Z", "CONFIG_LOAD_FAILED")

            self.assertEqual(
                ["best-sellers-collection-status.json", "price-completeness-diagnostic.json"],
                calls,
            )

    def test_post_parse_path_setup_failure_writes_safe_failure_artifacts(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            output_root = root / "snapshots"
            config_path = root / "sources.json"
            config_path.write_text(json.dumps(self.config()), encoding="utf-8")
            real_resolve = Path.resolve

            def resolve_with_output_failure(path, *args, **kwargs):
                if path == output_root:
                    raise OSError("AUTHORIZATION=Bearer-secret")
                return real_resolve(path, *args, **kwargs)

            stdout = io.StringIO()
            with patch.object(Path, "resolve", resolve_with_output_failure), contextlib.redirect_stdout(stdout):
                exit_code = self.collector.main([
                    "--project-root", str(root), "--config", str(config_path),
                    "--output-root", str(output_root), "--market-date", "2026-08-13",
                ])

            self.assert_safe_outer_failure(
                exit_code, json.loads(stdout.getvalue()), output_root / "2026-08-13",
                "SETUP_FAILED", ("AUTHORIZATION", "Bearer-secret"),
            )


if __name__ == "__main__":
    unittest.main()
