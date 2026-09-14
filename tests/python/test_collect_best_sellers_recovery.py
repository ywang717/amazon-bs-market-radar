import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = PROJECT_ROOT / "scripts" / "python" / "collect_best_sellers.py"


def load_collector():
    spec = importlib.util.spec_from_file_location("collect_best_sellers_recovery", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class BrandEvidenceRecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()
        cls.source_urls = {source["category_key"]: source["url"] for source in json.loads(
            (PROJECT_ROOT / "config" / "best-sellers-sources.json").read_text(encoding="utf-8-sig")
        )["sources"]}

    def test_brand_evidence_survives_diagnostic_sanitization(self):
        category_key = "pressure_washers"
        config = {
            "sources": [{
                "active": True,
                "category_key": category_key,
                "url": self.source_urls[category_key],
            }],
        }
        diagnostic = {
            "status": "COMPLETE",
            "attempts": [{
                "attempt": 1,
                "status": "COMPLETE",
                "failures": [],
                "collected_observations": [{"category_key": category_key, "asin": "B000000001"}],
                "price_evidence": [],
                "discount_evidence": [],
                "brand_evidence": [{
                    "category_key": category_key,
                    "asin": "B000000001",
                    "detail_url": "https://attacker.example/secret",
                    "verification_status": "VERIFIED",
                    "raw_brand": "Acme Tools",
                    "brand_source": "verified_metadata",
                    "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD",
                    "source": "DETAIL_PAGE",
                }],
            }],
        }

        sanitized = self.collector.sanitize_recovery_diagnostic(diagnostic, config)

        self.assertEqual({
            "category_key": category_key,
            "asin": "B000000001",
            "detail_url": "https://www.amazon.com/dp/B000000001",
            "verification_status": "VERIFIED",
            "raw_brand": "Acme Tools",
            "brand_source": "verified_metadata",
            "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD",
            "source": "DETAIL_PAGE",
        }, sanitized["attempts"][0]["brand_evidence"][0])

    def test_brand_evidence_is_counted_without_affecting_completeness(self):
        category_key = "pressure_washers"
        config = {
            "sources": [{
                "active": True,
                "category_key": category_key,
                "url": self.source_urls[category_key],
            }],
        }
        snapshot = {"schema_version": self.collector.SNAPSHOT_SCHEMA}
        status = {"schema_version": self.collector.STATUS_SCHEMA, "charts": []}
        diagnostic = {
            "status": "COMPLETE",
            "attempts": [{
                "attempt": 1,
                "status": "COMPLETE",
                "failures": [],
                "collected_observations": [],
                "price_evidence": [],
                "discount_evidence": [],
                "brand_evidence": [{"verification_status": "MISSING"}],
            }],
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            result = self.collector.write_collection_artifacts(
                temp_dir, "2026-08-29", snapshot, status, diagnostic, config
            )
            persisted_status = json.loads(
                (Path(temp_dir) / "2026-08-29" / "best-sellers-collection-status.json").read_text()
            )

        self.assertEqual(self.collector.EXIT_OK, result["exit_code"])
        self.assertEqual("COMPLETE", persisted_status["CompletenessStatus"])
        self.assertEqual(1, persisted_status["BrandVerificationCount"])


if __name__ == "__main__":
    unittest.main()
