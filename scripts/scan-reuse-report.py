#!/usr/bin/env python3
"""Summarize a non-overlapping window of scanner App Platform logs from stdin."""

import re
import sys
from collections import Counter, defaultdict
from collections.abc import Iterable

ANSI = re.compile(r"\x1b\[[0-9;]*m")
FIELD = re.compile(r'(\w+)=(?:"([^"\n]*)"|([^\s}]+))')
COUNTERS = (
    "lookups",
    "candidate_files",
    "reused_files",
    "reused_bytes",
    "engine_files",
    "engine_bytes",
    "engine_us",
    "overhead_us",
    "inserted_files",
    "evicted_files",
    "cache_errors",
    "validated_files",
    "mismatched_files",
)


def summarize(lines: Iterable[str]) -> dict[tuple[str, str, str], Counter[str]]:
    """Reject malformed metric records instead of understating errors or work."""
    totals: dict[tuple[str, str, str], Counter[str]] = defaultdict(Counter)
    for line in lines:
        fields = {
            key: quoted or plain
            for key, quoted, plain in FIELD.findall(ANSI.sub("", line))
        }
        if fields.get("event") != "scan_reuse":
            continue
        group = (
            fields["scanner"],
            fields["mode"],
            fields.get("rules_commit", "unknown"),
        )
        values = {key: int(fields[key]) for key in COUNTERS}
        if any(value < 0 for value in values.values()):
            raise ValueError("negative scan reuse counter")
        totals[group].update(values)
        totals[group]["jobs"] += 1
    return totals


def main() -> None:
    totals = summarize(sys.stdin)
    if not totals:
        raise SystemExit("No scan_reuse records in this log window.")
    for (scanner, mode, commit), values in sorted(totals.items()):
        denominator = values["engine_files"] + values["reused_files"]
        fraction = 100 * values["reused_files"] / denominator if denominator else 0
        print(f"{scanner} / {mode} / rules {commit}: {values['jobs']} jobs")
        print(
            f"  Candidate hits: {values['candidate_files']:,} / {values['lookups']:,} lookups"
        )
        print(
            f"  Avoided engine inputs: {values['reused_files']:,} files ({fraction:.1f}%), "
            f"{values['reused_bytes'] / 1024**2:.2f} MiB"
        )
        print(
            f"  Engine wall time: {values['engine_us'] / 1_000_000:.3f}s; "
            f"cache overhead: {values['overhead_us'] / 1_000_000:.3f}s"
        )
        print(
            f"  Validated: {values['validated_files']:,}; mismatched: {values['mismatched_files']:,}; "
            f"cache errors: {values['cache_errors']:,}; evicted: {values['evicted_files']:,}"
        )


if __name__ == "__main__":
    main()
