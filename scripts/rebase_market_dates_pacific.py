"""Create a non-destructive Pacific-market-date view of historical snapshots."""
import hashlib, json, shutil
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "var" / "amazon-bestsellers"
DST = ROOT / "var" / "amazon-bestsellers-pacific-v2"
TZ = ZoneInfo("America/Los_Angeles")

def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

for source_dir in sorted(p for p in SRC.iterdir() if p.is_dir()):
    snapshot_path = source_dir / "amazon-bestsellers.json"
    receipt_path = source_dir / "best-sellers-capture-receipt.json"
    if not snapshot_path.exists() or not receipt_path.exists():
        continue
    snapshot = read(snapshot_path)
    observed = datetime.fromisoformat(snapshot["observed_at"].replace("Z", "+00:00")).astimezone(TZ)
    # Preserve the user's explicit historical 08-25/08-26 split; all later
    # dates are derived strictly from the Pacific capture date.
    target_date = source_dir.name if source_dir.name in {"2026-08-25", "2026-08-26"} else observed.date().isoformat()
    target_dir = DST / target_date
    if target_dir.exists() and source_dir.name not in {"2026-08-25", "2026-08-26"}:
        target_dir = DST / f"{target_date}--source-{source_dir.name}"
    transformed = dict(snapshot)
    transformed["market_date"] = target_date
    transformed["observed_at"] = observed.isoformat(timespec="milliseconds")
    raw = json.dumps(transformed, ensure_ascii=False, indent=2) + "\n"
    target_dir.mkdir(parents=True, exist_ok=True)
    (target_dir / "amazon-bestsellers.json").write_text(raw, encoding="utf-8")
    sha = hashlib.sha256(raw.encode()).hexdigest()
    receipt = read(receipt_path)
    receipt.update({"market_date": target_date, "observed_at": transformed["observed_at"], "snapshot_sha256": sha,
                    "snapshot_byte_count": len(raw.encode()), "snapshot_path": str(target_dir / "amazon-bestsellers.json")})
    dump(target_dir / "best-sellers-capture-receipt.json", receipt)
    bundle_path = source_dir / "dashboard-sync-bundle.json"
    if bundle_path.exists():
        bundle = read(bundle_path)
        bundle["marketDate"] = target_date
        bundle["observedAt"] = transformed["observed_at"]
        bundle["receiptSha256"] = sha
        dump(target_dir / "dashboard-sync-bundle.json", bundle)
    print(f"{source_dir.name} -> {target_dir.relative_to(DST)}")
