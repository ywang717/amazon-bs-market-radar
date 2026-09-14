import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = PROJECT_ROOT / "scripts" / "python" / "collect_best_sellers.py"


def load_collector():
    spec = importlib.util.spec_from_file_location("collect_best_sellers", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class DetailBrandExtractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    def extract_from_html(self, detail_html):
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            self.skipTest("Playwright is not installed")

        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="msedge", headless=True)
            try:
                page = browser.new_page()
                page.set_content(detail_html)
                return self.collector._extract_detail_page(page)
            finally:
                browser.close()

    def test_extracts_each_explicit_brand_field_from_real_detail_dom(self):
        extracted = self.extract_from_html(
            """
            <html><head><title>Example product</title></head><body>
              <input id="ASIN" value="B000000001" />
              <div id="productOverview_feature_div"><table>
                <tr><td>Brand</td><td>Overview Brand</td></tr>
              </table></div>
              <table id="productDetails_detailBullets_sections1">
                <tr><th>Brand</th><td>Details Brand</td></tr>
              </table>
              <div id="detailBullets_feature_div"><ul><li>Brand: Bullet Brand</li></ul></div>
            </body></html>
            """
        )

        self.assertEqual(
            [
                {"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "Overview Brand"},
                {"evidence_source": "PRODUCT_DETAILS_BRAND_FIELD", "value": "Details Brand"},
                {"evidence_source": "DETAIL_BULLET_BRAND_FIELD", "value": "Bullet Brand"},
            ],
            extracted["brand_candidates"],
        )

    def test_ignores_byline_titles_recommendations_and_inexact_brand_labels(self):
        extracted = self.extract_from_html(
            """
            <html><head><title>Title Brand Pressure Washer</title></head><body>
              <input id="ASIN" value="B000000001" />
              <div id="bylineInfo">Visit the Byline Brand Store</div>
              <div class="recommendation">Recommended Brand</div>
              <div id="productOverview_feature_div"><table>
                <tr><td>Brand Name</td><td>Untrusted Brand</td></tr>
              </table></div>
              <table id="productDetails_detailBullets_sections1">
                <tr><th>Branding</th><td>Untrusted Brand</td></tr>
              </table>
              <div id="detailBullets_feature_div"><ul><li>Brand Name: Untrusted Brand</li></ul></div>
            </body></html>
            """
        )

        self.assertEqual([], extracted["brand_candidates"])

    def test_preserves_detail_asin_blocked_markers_and_cleaned_candidates(self):
        extracted = self.extract_from_html(
            """
            <html><head><title>Robot Check</title></head><body>
              <input id="ASIN" value=" B000000001 " />
              <div id="productOverview_feature_div"><table>
                <tr><td>Brand</td><td>  Acme   Tools  </td></tr>
              </table></div>
              Robot Check
            </body></html>
            """
        )

        self.assertEqual("B000000001", extracted["detail_asin"])
        self.assertEqual(["BOT_CHALLENGE"], extracted["blocked_markers"])
        self.assertEqual(
            [{"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "Acme Tools"}],
            extracted["brand_candidates"],
        )

    def test_missing_browser_brand_candidates_defaults_to_empty_list(self):
        page = BrandEvidenceReuseTests.DetailPage({
            "url": "https://www.amazon.com/dp/B000000001",
            "title": "Example product",
            "detail_asin": "B000000001",
            "coupon": "Save 10% with coupon",
        })

        extracted = self.collector._extract_detail_page(page)

        self.assertEqual([], extracted["brand_candidates"])


class BrandEvidenceReuseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    class DetailPage:
        def __init__(self, extracted):
            self.extracted = extracted
            self.goto_calls = 0
            self.closed = False

        def goto(self, url, **kwargs):
            self.goto_calls += 1

        def evaluate(self, script):
            return self.extracted

        def close(self):
            self.closed = True

    class DetailContext:
        def __init__(self, pages):
            self.pages = list(pages)
            self.new_page_calls = 0

        def new_page(self):
            self.new_page_calls += 1
            return self.pages.pop(0)

    def test_reuses_one_detail_navigation_for_discount_and_verified_brand_evidence(self):
        page = self.DetailPage({
            "url": "https://www.amazon.com/dp/B000000001",
            "title": "Example product",
            "detail_asin": "B000000001",
            "coupon": "Save 10% with coupon",
            "brand_candidates": [
                {"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "Acme Tools"},
                {"evidence_source": "PRODUCT_DETAILS_BRAND_FIELD", "value": "acme tools"},
                {"evidence_source": "DETAIL_BULLET_BRAND_FIELD", "value": "ACME TOOLS"},
            ],
        })
        charts = [{
            "category_key": "pressure_washers",
            "observations": [{"asin": "B000000001", "price": "$9.99"}],
        }]

        verified, discount_evidence, brand_evidence = self.collector.verify_chart_discounts(
            self.DetailContext([page]), charts
        )

        self.assertEqual(1, page.goto_calls)
        self.assertEqual(True, verified[0]["observations"][0]["has_discount"])
        self.assertEqual("Acme Tools", verified[0]["observations"][0]["raw_brand"])
        self.assertEqual("verified_metadata", verified[0]["observations"][0]["brand_source"])
        self.assertEqual("VERIFIED", discount_evidence[0]["verification_status"])
        self.assertEqual("VERIFIED", brand_evidence[0]["verification_status"])

    def test_brand_parser_error_keeps_discount_and_observation_successful(self):
        page = self.DetailPage({
            "url": "https://www.amazon.com/dp/B000000001",
            "title": "Example product",
            "detail_asin": "B000000001",
            "coupon": "Save 10% with coupon",
            "brand_candidates": [],
        })
        charts = [{
            "category_key": "pressure_washers",
            "observations": [{"asin": "B000000001", "price": "$9.99"}],
        }]

        with patch.object(self.collector, "classify_brand_evidence", side_effect=RuntimeError("parser failed")):
            verified, discount_evidence, brand_evidence = self.collector.verify_chart_discounts(
                self.DetailContext([page]), charts
            )

        observation = verified[0]["observations"][0]
        self.assertEqual(True, observation["has_discount"])
        self.assertNotIn("raw_brand", observation)
        self.assertEqual("VERIFIED", discount_evidence[0]["verification_status"])
        self.assertEqual("VERIFICATION_BLOCKED", brand_evidence[0]["verification_status"])


if __name__ == "__main__":
    unittest.main()
