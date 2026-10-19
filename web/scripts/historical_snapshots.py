"""Load immutable, receipt-verified captures from the known migration roots."""
import hashlib
import json
from pathlib import Path


def load_captures(var_root):
    var_root = Path(var_root)
    patterns = (
        'amazon-bestsellers/2026-*/best-sellers-capture-receipt.json',
        'amazon-bestsellers-pacific*/2026-*/best-sellers-capture-receipt.json',
        'history-upload-*/snapshots/2026-*/best-sellers-capture-receipt.json',
    )
    captures, rejected = {}, []
    paths = {path for pattern in patterns for path in var_root.glob(pattern)}
    for receipt in sorted(paths):
        relative = str(receipt.relative_to(var_root))
        try:
            data = json.loads(receipt.read_text(encoding='utf-8-sig'))
            if data.get('status') != 'COMPLETE_VALIDATED':
                continue
            snapshot_path = receipt.parent / 'amazon-bestsellers.json'
            raw = snapshot_path.read_bytes()
            sha = hashlib.sha256(raw).hexdigest()
            snapshot = json.loads(raw.decode('utf-8-sig'))
            date = data['market_date']
            if sha != data.get('snapshot_sha256'):
                raise ValueError('receipt hash mismatch')
            if snapshot.get('market_date') != date:
                raise ValueError('receipt and snapshot dates differ')
            rows = {}
            for key, values in snapshot.items():
                if not isinstance(values, list) or len(values) != 30:
                    continue
                ranked = sorted((int(v['rank']), v['asin']) for v in values)
                if [v[0] for v in ranked] != list(range(1, 31)) or len({v[1] for v in ranked}) != 30:
                    raise ValueError('invalid complete ranking')
                rows[key] = ranked
            if not rows:
                raise ValueError('no complete rankings')
            key = (date, sha)
            if key in captures:
                captures[key]['receipts'].append(relative)
            else:
                captures[key] = {'date': date, 'sha': sha, 'rows': rows,
                                 'observed_at': snapshot.get('observed_at'), 'receipts': [relative]}
        except (OSError, ValueError, KeyError, TypeError) as error:
            rejected.append({'receipt': relative, 'reason': str(error)})
    return list(captures.values()), rejected


def select_captures(captures, published_hashes=None, market_date=None):
    """An explicit published hash never silently falls back to another capture."""
    if market_date:
        if published_hashes is not None and market_date not in published_hashes:
            raise ValueError('Requested date is absent from published provenance')
        captures = [capture for capture in captures if capture['date'] == market_date]
        if not captures:
            raise ValueError('Requested date has no validated source capture')
    if published_hashes is None:
        dates = [capture['date'] for capture in captures]
        if len(dates) != len(set(dates)):
            raise ValueError('Multiple captures for one date; provide published provenance hashes')
        return list(captures)
    return [capture for capture in captures
            if published_hashes.get(capture['date']) == capture['sha']]
