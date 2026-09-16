"""Check that reporting does not confuse candidates with avoided work."""

import importlib.util
from pathlib import Path

import pytest

SPEC = importlib.util.spec_from_file_location(
    "scan_reuse_report", Path(__file__).parents[1] / "scripts" / "scan-reuse-report.py"
)
assert SPEC is not None and SPEC.loader is not None
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


def record(mode: str, **counts: int) -> str:
    fields = {key: 0 for key in REPORT.COUNTERS} | counts
    return (
        f'event="scan_reuse" scanner="yara" mode={mode} rules_commit=abc '
        + " ".join(f"{key}={value}" for key, value in fields.items())
    )


def test_observation_candidates_are_not_savings() -> None:
    result = REPORT.summarize(
        [
            "unrelated log message",
            record("Observe", lookups=10, candidate_files=8, engine_files=10),
            record(
                "Reuse", lookups=10, candidate_files=8, reused_files=7, engine_files=3
            ),
        ]
    )
    assert result[("yara", "Observe", "abc")]["reused_files"] == 0
    assert result[("yara", "Reuse", "abc")]["reused_files"] == 7
    assert result[("yara", "Reuse", "abc")]["jobs"] == 1


def test_missing_counters_are_not_silently_reported_as_zero() -> None:
    with pytest.raises(KeyError):
        REPORT.summarize(['event="scan_reuse" scanner=yara mode=Reuse'])
