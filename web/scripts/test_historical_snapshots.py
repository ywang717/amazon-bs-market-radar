"""Read-only reconciliation must compare the published capture, not a folder label."""
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from historical_snapshots import load_captures, select_captures


class HistoricalCapturesTest(unittest.TestCase):
    def capture(self, root, folder, asin, *, receipt_sha=None, market_date='2026-09-12'):
        directory = root / folder
        directory.mkdir(parents=True)
        snapshot = json.dumps({'market_date': market_date, 'pressure_washers': [
            {'rank': rank, 'asin': f'{asin}{rank:09}'} for rank in range(1, 31)
        ]}).encode()
        sha = hashlib.sha256(snapshot).hexdigest()
        (directory / 'amazon-bestsellers.json').write_bytes(snapshot)
        (directory / 'best-sellers-capture-receipt.json').write_text(json.dumps({
            'market_date': market_date, 'status': 'COMPLETE_VALIDATED',
            'snapshot_sha256': receipt_sha or sha,
        }))
        return sha

    def test_snapshot_time_is_authoritative_even_when_receipt_time_was_localized(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            self.capture(root, 'amazon-bestsellers/2026-09-12', 'A')
            directory = root / 'amazon-bestsellers/2026-09-12'
            snapshot = json.loads((directory / 'amazon-bestsellers.json').read_text())
            snapshot['observed_at'] = '2026-09-12T18:03:30.131Z'
            raw = json.dumps(snapshot).encode()
            (directory / 'amazon-bestsellers.json').write_bytes(raw)
            receipt_path = directory / 'best-sellers-capture-receipt.json'
            receipt = json.loads(receipt_path.read_text())
            receipt.update(snapshot_sha256=hashlib.sha256(raw).hexdigest(), observed_at='09/12/2026 18:03:30')
            receipt_path.write_text(json.dumps(receipt))
            captures, _ = load_captures(root)
            self.assertEqual(captures[0]['observed_at'], snapshot['observed_at'])

    def test_published_hash_selects_pacific_capture_instead_of_canonical_folder(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            self.capture(root, 'amazon-bestsellers/2026-09-12', 'A')
            published = self.capture(root, 'amazon-bestsellers-pacific/2026-09-12--source-2026-09-13', 'B')
            captures, rejected = load_captures(root)
            selected = select_captures(captures, {'2026-09-12': published})
            self.assertEqual(len(selected), 1)
            self.assertEqual(selected[0]['sha'], published)
            self.assertTrue(selected[0]['rows']['pressure_washers'][0][1].startswith('B'))
            self.assertEqual(rejected, [])

    def test_rejects_hash_tampering_and_never_falls_back_for_unknown_published_hash(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            self.capture(root, 'amazon-bestsellers/2026-09-12', 'A', receipt_sha='f' * 64)
            self.capture(root, 'amazon-bestsellers-pacific/2026-09-12', 'B')
            captures, rejected = load_captures(root)
            self.assertEqual(len(rejected), 1)
            self.assertEqual(select_captures(captures, {'2026-09-12': 'c' * 64}), [])

    def test_uses_receipt_date_and_deduplicates_identical_migration_copies(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            sha = self.capture(root, 'amazon-bestsellers-pacific/2026-09-13', 'A')
            self.capture(root, 'history-upload-20260917/snapshots/2026-09-12', 'A')
            captures, _ = load_captures(root)
            self.assertEqual(len(captures), 1)
            self.assertEqual(captures[0]['date'], '2026-09-12')
            self.assertEqual(captures[0]['sha'], sha)
            self.assertEqual(len(captures[0]['receipts']), 2)

    def test_ambiguous_date_requires_published_hash_and_unknown_date_fails(self):
        captures = [{'date': '2026-09-12', 'sha': 'a'}, {'date': '2026-09-12', 'sha': 'b'}]
        with self.assertRaisesRegex(ValueError, 'published'):
            select_captures(captures)
        with self.assertRaisesRegex(ValueError, 'date'):
            select_captures(captures, {'2026-09-12': 'a'}, market_date='2026-09-11')


if __name__ == '__main__':
    unittest.main()
