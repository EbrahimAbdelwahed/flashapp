from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from pathlib import Path

import pytest
from study_agent.state import canonical_json_bytes

from study_agent_devkit.capability_gap import (
    CandidateSnapshot,
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    ProposalService,
)
from study_agent_devkit.capability_gap.proposal_contracts import (
    CohortMergeReceiptV1,
    ProposalDraftV1,
    ProposalEvidenceV1,
)
from study_agent_devkit.capability_gap.proposal_store import _SQLiteProposalStore

from ..test_contracts import make_candidate, make_draft, make_package


class _CountingBuilder:
    def __init__(self, result: ProposalDraftV1 | None = None) -> None:
        self.calls = 0
        self._result = result or make_draft()

    def build(self, _evidence: ProposalEvidenceV1) -> ProposalDraftV1:
        self.calls += 1
        return self._result


class _CountingAuthority:
    def __init__(self, result: CohortMergeReceiptV1 | None) -> None:
        self.calls = 0
        self._result = result

    def authorize(self, _keys: tuple[str, ...]) -> CohortMergeReceiptV1 | None:
        self.calls += 1
        return self._result


class _CountingClock:
    def __init__(self, value: datetime | None = None) -> None:
        self.calls = 0
        self._value = value or datetime(2026, 1, 5, tzinfo=UTC)

    def now(self) -> datetime:
        self.calls += 1
        return self._value


def _multi_candidates() -> tuple[CandidateSnapshot, CandidateSnapshot]:
    return make_candidate("a" * 64), make_candidate("b" * 64, seed="b")


def _multi_receipt() -> CohortMergeReceiptV1:
    return CohortMergeReceiptV1(("a" * 64, "b" * 64), "review@adversarial")


def test_exact_multi_retry_skips_changed_authority_builder_and_clock(tmp_path: Path) -> None:
    database = tmp_path / "retry.sqlite3"
    candidates = _multi_candidates()
    accepting = _CountingAuthority(_multi_receipt())
    first_builder = _CountingBuilder()
    first_clock = _CountingClock()
    with ProposalService(database, authority=accepting, clock=first_clock) as service:
        first = service.create(candidates, first_builder)
        rejecting = _CountingAuthority(None)
        second_builder = _CountingBuilder()
        second_clock = _CountingClock()
        changed = (make_candidate("a" * 64, count=99), candidates[1])
        with ProposalService(database, authority=rejecting, clock=second_clock) as retry:
            second = retry.create(changed, second_builder)
    assert second.to_bytes() == first.to_bytes()
    assert accepting.calls == 1
    assert first_builder.calls == 1
    assert first_clock.calls == 1
    assert rejecting.calls == 0
    assert second_builder.calls == 0
    assert second_clock.calls == 0


def test_identical_concurrent_creation_returns_one_package_after_barrier(tmp_path: Path) -> None:
    database = tmp_path / "concurrent.sqlite3"
    with ProposalService(database):
        pass
    barrier = threading.Barrier(2)

    class BarrierBuilder(_CountingBuilder):
        def build(self, evidence: ProposalEvidenceV1) -> ProposalDraftV1:
            result = super().build(evidence)
            barrier.wait(timeout=10)
            return result

    candidates = (make_candidate(),)

    def create_one(_: int) -> bytes:
        with ProposalService(database, clock=lambda: datetime(2026, 1, 6, tzinfo=UTC)) as service:
            return service.create(candidates, BarrierBuilder()).to_bytes()

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = tuple(pool.map(create_one, (1, 2)))
    assert results[0] == results[1]
    with _SQLiteProposalStore(database) as store:
        assert store.connection.execute("SELECT COUNT(*) FROM proposal_packages").fetchone()[0] == 1
        assert store.connection.execute("SELECT COUNT(*) FROM proposal_members").fetchone()[0] == 1
        assert store.lookup(("a" * 64,)) is not None


def test_process_loss_after_package_insert_leaves_no_visible_rows(tmp_path: Path) -> None:
    database = tmp_path / "process-loss.sqlite3"
    with _SQLiteProposalStore(database):
        pass
    root = Path(__file__).resolve().parents[4]
    script = """
import os
import sqlite3
import sys
from study_agent_devkit.capability_gap.proposal_store import _SQLiteProposalStore
from tests.capability_gap.proposals.test_contracts import make_package

store = _SQLiteProposalStore(sys.argv[1])
def authorize(action, arg1, _arg2, _db, _source):
    if action == sqlite3.SQLITE_INSERT and arg1 == "proposal_packages":
        os._exit(0)
    return sqlite3.SQLITE_OK

store.connection.set_authorizer(authorize)
store._create_or_get(make_package())
raise SystemExit("authorizer callback did not fire")
"""
    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join(
        (str(root / "src"), str(root), env.get("PYTHONPATH", ""))
    )
    result = subprocess.run(
        [sys.executable, "-c", script, str(database)],
        cwd=root,
        env=env,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0
    with _SQLiteProposalStore(database) as store:
        assert store.lookup(("a" * 64,)) is None
        assert store.connection.execute("SELECT COUNT(*) FROM proposal_packages").fetchone()[0] == 0
        assert store.connection.execute("SELECT COUNT(*) FROM proposal_members").fetchone()[0] == 0


@pytest.mark.parametrize(
    ("column", "value"),
    (("proposal_id", "f" * 64), ("decision_id", "f" * 64), ("cohort_fingerprint", "f" * 64)),
)
def test_projection_tampering_fails_closed(tmp_path: Path, column: str, value: str) -> None:
    database = tmp_path / f"projection-{column}.sqlite3"
    with _SQLiteProposalStore(database) as store:
        store._create_or_get(make_package())
        store.connection.execute(f"UPDATE proposal_packages SET {column} = ?", (value,))
        with pytest.raises(CapabilityGapCorruptionError):
            store.lookup(("a" * 64,))


def test_package_bytes_tampering_fails_closed(tmp_path: Path) -> None:
    database = tmp_path / "bytes.sqlite3"
    with _SQLiteProposalStore(database) as store:
        store._create_or_get(make_package())
        store.connection.execute("UPDATE proposal_packages SET package_bytes = ?", (b"{}",))
        with pytest.raises(CapabilityGapCorruptionError):
            store.lookup(("a" * 64,))


@pytest.mark.parametrize("mutation", ("delete", "change", "add"))
def test_membership_tampering_fails_closed(tmp_path: Path, mutation: str) -> None:
    database = tmp_path / f"membership-{mutation}.sqlite3"
    with _SQLiteProposalStore(database) as store:
        store._create_or_get(make_package())
        if mutation == "delete":
            store.connection.execute("DELETE FROM proposal_members")
        elif mutation == "change":
            store.connection.execute("UPDATE proposal_members SET gap_key = ?", ("b" * 64,))
        else:
            store.connection.execute(
                "INSERT INTO proposal_members (proposal_pk, gap_key) VALUES (1, ?)",
                ("b" * 64,),
            )
        with pytest.raises(CapabilityGapCorruptionError):
            store.lookup(("a" * 64,))


@pytest.mark.parametrize("schema_change", ("extra-index", "partial-index", "extra-table"))
def test_schema_drift_is_rejected_on_reopen(tmp_path: Path, schema_change: str) -> None:
    database = tmp_path / f"schema-{schema_change}.sqlite3"
    with _SQLiteProposalStore(database):
        pass
    connection = sqlite3.connect(database)
    if schema_change == "extra-index":
        connection.execute("CREATE INDEX drift_index ON proposal_members(gap_key)")
    elif schema_change == "partial-index":
        connection.execute(
            "CREATE INDEX drift_partial ON proposal_members(gap_key) WHERE gap_key LIKE 'a%'"
        )
    else:
        connection.execute("CREATE TABLE drift_table (value TEXT NOT NULL)")
    connection.commit()
    connection.close()
    with pytest.raises(CapabilityGapCorruptionError):
        _SQLiteProposalStore(database)


def test_foreign_key_swap_is_rejected_before_reads(tmp_path: Path) -> None:
    database = tmp_path / "foreign-key-swap.sqlite3"
    with _SQLiteProposalStore(database) as store:
        store._create_or_get(make_package())
        store.connection.execute("PRAGMA foreign_keys = OFF")
        store.connection.execute("UPDATE proposal_members SET proposal_pk = 999")
        store.connection.execute("PRAGMA foreign_keys = ON")
        with pytest.raises(CapabilityGapCorruptionError):
            store.lookup(("a" * 64,))


def test_unknown_fields_noncanonical_base64_and_wrong_hash_domain_fail_closed() -> None:
    package = make_package()
    raw = json.loads(package.to_bytes())
    raw["proposal"]["evidence"]["unknown"] = True
    with pytest.raises(CapabilityGapCorruptionError):
        type(package).from_bytes(canonical_json_bytes(raw))

    raw = json.loads(package.to_bytes())
    contribution = raw["proposal"]["evidence"]["candidates"][0]["contributions"][0]
    encoded = contribution["record_b64"]
    contribution["record_b64"] = encoded[:-1] if encoded.endswith("=") else encoded + "="
    with pytest.raises(CapabilityGapCorruptionError):
        type(package).from_bytes(canonical_json_bytes(raw))

    raw = json.loads(package.to_bytes())
    raw["proposal"]["evidence_fingerprint"] = "0" * 64
    with pytest.raises(CapabilityGapCorruptionError):
        type(package).from_bytes(canonical_json_bytes(raw))


def test_oversized_text_and_invalid_control_are_rejected() -> None:
    from study_agent_devkit.capability_gap.proposal_contracts import ProposalOptionV1

    with pytest.raises(ValueError):
        ProposalOptionV1("safe", "x" * (16 * 1024 + 1), ("tradeoff",))
    with pytest.raises(ValueError):
        ProposalOptionV1("safe", "contains\x7fcontrol", ("tradeoff",))


def test_corrupt_retry_does_not_invoke_any_callback(tmp_path: Path) -> None:
    database = tmp_path / "corrupt-retry.sqlite3"
    candidates = _multi_candidates()
    with ProposalService(
        database, authority=_CountingAuthority(_multi_receipt()), clock=_CountingClock()
    ) as service:
        first = service.create(candidates, _CountingBuilder())
    with _SQLiteProposalStore(database) as store:
        store.connection.execute(
            "UPDATE proposal_packages SET package_bytes = ? WHERE proposal_id = ?",
            (b"not-json", first.proposal.proposal_id),
        )
        authority = _CountingAuthority(None)
        builder = _CountingBuilder()
        clock = _CountingClock()
        with pytest.raises(CapabilityGapCorruptionError), ProposalService(
            database, authority=authority, clock=clock
        ) as service:
            service.create(candidates, builder)
        assert authority.calls == 0
        assert builder.calls == 0
        assert clock.calls == 0


def test_forged_merge_receipt_must_match_exact_sorted_key_tuple(tmp_path: Path) -> None:
    candidates = _multi_candidates()
    wrong_keys = CohortMergeReceiptV1(("a" * 64, "c" * 64), "review@adversarial")
    with ProposalService(
        tmp_path / "forged-receipt.sqlite3",
        authority=_CountingAuthority(wrong_keys),
        clock=_CountingClock(),
    ) as service, pytest.raises(CapabilityGapCollisionError, match="mismatch"):
        service.create(candidates, _CountingBuilder())
