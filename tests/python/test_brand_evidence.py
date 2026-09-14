import importlib.util
import sys
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = PROJECT_ROOT / "scripts" / "python" / "brand_evidence.py"


def load_brand_evidence():
    spec = importlib.util.spec_from_file_location("brand_evidence", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class BrandEvidenceClassificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.brand_evidence = load_brand_evidence()

    def test_matching_asin_with_one_trusted_brand_is_verified(self):
        result = self.brand_evidence.classify_brand_evidence(
            {
                "detail_asin": "b000000001",
                "brand_candidates": [
                    {"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "  Acme Tools  "}
                ],
            },
            "B000000001",
        )

        self.assertEqual(
            {
                "raw_brand": "Acme Tools",
                "brand_source": "verified_metadata",
                "verification_status": "VERIFIED",
                "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD",
            },
            result,
        )

    def test_matching_trusted_sources_with_case_insensitive_same_value_are_verified(self):
        result = self.brand_evidence.classify_brand_evidence(
            {
                "detail_asin": "B000000001",
                "brand_candidates": [
                    {"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "Acme Tools"},
                    {"evidence_source": "PRODUCT_DETAILS_BRAND_FIELD", "value": " acme   tools "},
                ],
            },
            "B000000001",
        )

        self.assertEqual("VERIFIED", result["verification_status"])
        self.assertEqual("Acme Tools", result["raw_brand"])
        self.assertEqual("PRODUCT_OVERVIEW_BRAND_FIELD", result["evidence_source"])

    def test_equivalent_trusted_candidates_use_fixed_source_priority_not_input_order(self):
        result = self.brand_evidence.classify_brand_evidence(
            {
                "detail_asin": "B000000001",
                "brand_candidates": [
                    {"evidence_source": "DETAIL_BULLET_BRAND_FIELD", "value": "ACME TOOLS"},
                    {"evidence_source": "PRODUCT_DETAILS_BRAND_FIELD", "value": " acme   tools "},
                    {"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "Acme Tools"},
                ],
            },
            "B000000001",
        )

        self.assertEqual(
            {
                "raw_brand": "Acme Tools",
                "brand_source": "verified_metadata",
                "verification_status": "VERIFIED",
                "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD",
            },
            result,
        )

    def test_conflicting_trusted_brand_values_are_not_writable(self):
        result = self.brand_evidence.classify_brand_evidence(
            {
                "detail_asin": "B000000001",
                "brand_candidates": [
                    {"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "Acme Tools"},
                    {"evidence_source": "PRODUCT_DETAILS_BRAND_FIELD", "value": "Other Brand"},
                ],
            },
            "B000000001",
        )

        self.assertEqual("CONFLICT", result["verification_status"])
        self.assertIsNone(result["raw_brand"])
        self.assertEqual("unknown", result["brand_source"])
        self.assertIsNone(result["evidence_source"])

    def test_mismatched_detail_asin_is_identity_mismatch(self):
        result = self.brand_evidence.classify_brand_evidence(
            {
                "detail_asin": "B000000002",
                "brand_candidates": [
                    {"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "Acme Tools"}
                ],
            },
            "B000000001",
        )

        self.assertEqual("IDENTITY_MISMATCH", result["verification_status"])
        self.assertIsNone(result["raw_brand"])

    def test_invalid_requested_and_detail_asins_are_not_a_verified_identity(self):
        result = self.brand_evidence.classify_brand_evidence(
            {
                "detail_asin": "not-an-asin",
                "brand_candidates": [
                    {"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "Acme Tools"}
                ],
            },
            "not-an-asin",
        )

        self.assertEqual("IDENTITY_MISMATCH", result["verification_status"])
        self.assertIsNone(result["raw_brand"])

    def test_blocked_page_is_verification_blocked(self):
        result = self.brand_evidence.classify_brand_evidence(
            {"detail_asin": "B000000001", "blocked_markers": ["BOT_CHALLENGE"]},
            "B000000001",
        )

        self.assertEqual("VERIFICATION_BLOCKED", result["verification_status"])
        self.assertIsNone(result["raw_brand"])

    def test_missing_or_blank_trusted_brand_values_are_missing(self):
        for candidates in ([], [{"evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD", "value": "  "}]):
            with self.subTest(candidates=candidates):
                result = self.brand_evidence.classify_brand_evidence(
                    {"detail_asin": "B000000001", "brand_candidates": candidates},
                    "B000000001",
                )

                self.assertEqual("MISSING", result["verification_status"])
                self.assertIsNone(result["raw_brand"])
                self.assertEqual("unknown", result["brand_source"])

    def test_non_string_trusted_candidate_values_are_missing(self):
        for malformed_value in (123, ["Acme Tools"], {"brand": "Acme Tools"}, True):
            with self.subTest(malformed_value=malformed_value):
                result = self.brand_evidence.classify_brand_evidence(
                    {
                        "detail_asin": "B000000001",
                        "brand_candidates": [{
                            "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD",
                            "value": malformed_value,
                        }],
                    },
                    "B000000001",
                )

                self.assertEqual("MISSING", result["verification_status"])
                self.assertIsNone(result["raw_brand"])
                self.assertEqual("unknown", result["brand_source"])
                self.assertIsNone(result["evidence_source"])


if __name__ == "__main__":
    unittest.main()
