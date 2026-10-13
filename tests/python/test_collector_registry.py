import copy
import json
import tempfile
import unittest
from pathlib import Path

from test_best_sellers_collector import PROJECT_ROOT, load_collector


class CollectorRegistryTests(unittest.TestCase):
    def test_garden_registry_covers_verified_root_and_all_immediate_children(self):
        registry = json.loads((PROJECT_ROOT / "config/category-registry.json").read_text())
        garden = [row for row in registry["categories"] if row.get("group_key") == "patio_lawn_garden"]
        self.assertEqual(14, len(garden))
        self.assertTrue(all(row["enabled"] and row["target_count"] == 30 for row in garden))
        self.assertEqual({"553632", "4619352011", "3610851", "552808", "553760", "551242", "553788", "13638732011", "13400641", "553824", "553844", "1272941011", "3043471"},
                         {row["amazon_node_id"] for row in garden if row.get("parent_category_key") == "patio_lawn_garden"})
        self.assertEqual(17, len(registry["categories"]))

    def test_trust_follows_injected_registry_and_rejects_disabled_unknown_or_stale_urls(self):
        collector = load_collector()
        registry_path = PROJECT_ROOT / "config" / "category-registry.json"
        original = registry_path.read_bytes()
        registry = json.loads(original)
        category = copy.deepcopy(registry["categories"][1])
        category.update(category_key="test_category", amazon_node_id="999999999",
                        source_url="https://www.amazon.com/zgbs/hi/999999999")
        registry["categories"].append(category)
        config = {"sources": [{"category_key": "test_category", "active": True,
                               "url": category["source_url"]}]}
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "registry.json"
            fixture.write_text(json.dumps(registry), encoding="utf-8")
            self.assertEqual({"test_category": "https://www.amazon.com/zgbs/hi/999999999"},
                             collector._trusted_source_mapping(config, fixture))
            self.assertEqual({}, collector._trusted_source_mapping(config))
            config["sources"][0]["url"] += "/untrusted"
            self.assertEqual({}, collector._trusted_source_mapping(config, fixture))
            config["sources"][0]["url"] = category["source_url"]
            category["enabled"] = False
            fixture.write_text(json.dumps(registry), encoding="utf-8")
            self.assertEqual({}, collector._trusted_source_mapping(config, fixture))
            config["sources"][0]["category_key"] = "unknown_category"
            self.assertEqual({}, collector._trusted_source_mapping(config, fixture))
        self.assertEqual(original, registry_path.read_bytes())

    def test_invalid_registry_cannot_supply_trusted_source_identity(self):
        collector = load_collector()
        config = {"sources": [{"category_key": "test_category", "active": True,
                               "url": "https://www.amazon.com/zgbs/hi/999999999"}]}
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "registry.json"
            fixture.write_text('{"categories": []}', encoding="utf-8")
            with self.assertRaises(ValueError):
                collector._trusted_source_mapping(config, fixture)


if __name__ == "__main__":
    unittest.main()
