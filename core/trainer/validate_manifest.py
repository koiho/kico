from __future__ import annotations

import argparse
from collections import Counter

try:
    from .data import load_manifest_entries
except ImportError:  # pragma: no cover
    from data import load_manifest_entries


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    entries = load_manifest_entries(args.manifest)
    counts = Counter(entry.source_type for entry in entries)
    print(
        "manifest ok | "
        f"samples={len(entries)} synthetic={counts.get('synthetic', 0)} "
        f"fitted_real_ref={counts.get('fitted_real_ref', 0)}"
    )


if __name__ == "__main__":
    main()
