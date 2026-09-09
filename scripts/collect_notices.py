#!/usr/bin/env python3
"""Preserve license texts for pinned runtime packages in the offline app."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
checkouts = root / ".build/packages/checkouts"
files = sorted(p for p in checkouts.rglob("*") if p.is_file() and p.name in {
    "LICENSE", "LICENSE.txt", "LICENSE.md", "LICENSE.MIT", "NOTICE.txt"
} and ".git" not in p.parts)
if not files:
    raise SystemExit("Resolve the pinned packages first; no local license files found.")
parts = ["Camping Buddy prototype — third-party notices\n\n"
         "Original app source is new. The local tokenizer protocol adapter follows the MLX Swift LM integration example (MIT). "
         "The downloaded model's attribution and pinned source links are available under Manage the model. "
         "Reference metadata is available with each local passage.\n"]
for path in files:
    parts.append("\n" + "=" * 72 + "\n" + str(path.relative_to(checkouts)) + "\n\n" + path.read_text())
destination = root / "Resources/Acknowledgments/ThirdPartyNotices.txt"
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text("\n".join(parts))
print(f"Preserved {len(files)} license/notice files in {destination.relative_to(root)}")
