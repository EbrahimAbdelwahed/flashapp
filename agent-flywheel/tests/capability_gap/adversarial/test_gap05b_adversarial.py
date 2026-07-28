from __future__ import annotations

import json
import multiprocessing
import threading
from dataclasses import asdict, fields
from pathlib import Path

import pytest
from study_agent.feedback.outbox import GapOutboxRecord

from study_agent_devkit.capability_gap import (
    ActiveWorkKind,
    ActiveWorkSnapshot,
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    DeliveryImportContext,
    InMemoryActiveWorkIndex,
    ReproductionRegistry,
    ReproductionResult,
    ReproductionStatus,
    SQLiteCapabilityGapStore,
)

from ._support import (
    blocking_import_worker,
    bundle,
    canonical_json,
    context,
    dimensions,
    healthy_registry,
    record,
)


def test_process_kill_before_commit_reopens_empty_and_retry_commits_once(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("1" * 64))
    database = tmp_path / "crash.sqlite3"
    process_context = multiprocessing.get_context("spawn")
    entered = process_context.Event()
    release = process_context.Event()
    worker = process_context.Process(
        target=blocking_import_worker,
        args=(payload, str(database), "a" * 64, fingerprint, entered, release),
    )
    worker.start()
    try:
        assert entered.wait(timeout=10), "child did not enter transaction callback"
        worker.terminate()
        worker.join(timeout=10)
        assert not worker.is_alive()
    finally:
        if worker.is_alive():
            worker.kill()
            worker.join(timeout=10)

    with SQLiteCapabilityGapStore(database) as store:
        assert store.list_candidates() == ()
        first = store.import_bundle(payload, context(fingerprint), reproduction=healthy_registry())
        second = store.import_bundle(payload, context(fingerprint), reproduction=healthy_registry())
        assert first.to_bytes() == second.to_bytes()
        candidate = store.get_candidate("1" * 64)
        assert len(candidate.contributions) == 1
        assert candidate.contributions[0].reproduction.fixture_id == "fixture@healthy"


def test_concurrent_same_delivery_is_one_contribution_and_callbacks_once(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("2" * 64))
    database = tmp_path / "concurrent.sqlite3"
    # Create the schema before racing the two independent connections; the
    # concurrency assertion is about import claims, not first-open migration.
    with SQLiteCapabilityGapStore(database):
        pass
    barrier = threading.Barrier(2)
    callback_lock = threading.Lock()
    callback_count = 0
    receipts: list[bytes] = []
    errors: list[BaseException] = []

    def callback(_record: GapOutboxRecord) -> ReproductionResult:
        nonlocal callback_count
        with callback_lock:
            callback_count += 1
        return ReproductionResult(ReproductionStatus.REPRODUCED, "f" * 64)

    registry = ReproductionRegistry()
    registry.register("fixture@concurrent", dimensions(), callback)

    def run(seed: str) -> None:
        try:
            with SQLiteCapabilityGapStore(database) as store:
                barrier.wait(timeout=10)
                receipt = store.import_bundle(
                    payload,
                    context(fingerprint, seed),
                    reproduction=registry,
                )
                receipts.append(receipt.to_bytes())
        except BaseException as error:  # surfaced after bounded joins
            errors.append(error)

    threads = [threading.Thread(target=run, args=(seed,)) for seed in ("a", "a")]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=15)
    assert all(not thread.is_alive() for thread in threads)
    assert errors == []
    assert len(receipts) == 2
    assert receipts[0] == receipts[1]
    assert callback_count == 1
    with SQLiteCapabilityGapStore(database) as store:
        assert len(store.get_candidate("2" * 64).contributions) == 1


def test_late_fixture_failure_rolls_back_all_records_and_retry_is_complete(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("3" * 64), record("4" * 64))
    failing = ReproductionRegistry()

    def fail_late(value: GapOutboxRecord) -> ReproductionResult:
        if value.gap_key.value == "4" * 64:
            raise RuntimeError("late fixture failure")
        return ReproductionResult(ReproductionStatus.REPRODUCED, "f" * 64)

    failing.register("fixture@failing", dimensions(), fail_late)
    database = tmp_path / "rollback.sqlite3"
    with SQLiteCapabilityGapStore(database) as store:
        with pytest.raises(RuntimeError, match="late fixture failure"):
            store.import_bundle(payload, context(fingerprint), reproduction=failing)
        assert store.list_candidates() == ()
    with SQLiteCapabilityGapStore(database) as reopened:
        receipt = reopened.import_bundle(
            payload, context(fingerprint), reproduction=healthy_registry()
        )
        assert receipt.candidate_gap_keys == ("3" * 64, "4" * 64)
        assert all(
            len(reopened.get_candidate(key).contributions) == 1 for key in ("3" * 64, "4" * 64)
        )


@pytest.mark.parametrize("variant", ("noncanonical", "unknown_schema", "tampered_key_binding"))
def test_hostile_bundle_variants_fail_before_callbacks_or_mutation(
    tmp_path: Path, variant: str
) -> None:
    payload, fingerprint = bundle(record("5" * 64))
    decoded = json.loads(payload)
    if variant == "noncanonical":
        hostile = json.dumps(decoded, ensure_ascii=False).encode("utf-8")
    elif variant == "unknown_schema":
        decoded["schema_version"] = 999
        hostile = canonical_json(decoded)
    else:
        decoded["records"][0]["key_binding"] = "0" * 64
        hostile = canonical_json(decoded)
    callbacks = 0
    registry = ReproductionRegistry()

    def callback(_record: GapOutboxRecord) -> ReproductionResult:
        nonlocal callbacks
        callbacks += 1
        return ReproductionResult(ReproductionStatus.REPRODUCED, "f" * 64)

    registry.register("fixture@hostile", dimensions(), callback)
    with SQLiteCapabilityGapStore(tmp_path / f"{variant}.sqlite3") as store:
        with pytest.raises((CapabilityGapCorruptionError, CapabilityGapCollisionError)):
            store.import_bundle(hostile, context(fingerprint), reproduction=registry)
        assert callbacks == 0
        assert store.list_candidates() == ()


def test_delivery_fingerprint_mismatch_fails_before_callbacks_or_mutation(tmp_path: Path) -> None:
    payload, _fingerprint = bundle(record("6" * 64))
    callbacks = 0
    registry = ReproductionRegistry()

    def callback(_record: GapOutboxRecord) -> ReproductionResult:
        nonlocal callbacks
        callbacks += 1
        return ReproductionResult(ReproductionStatus.REPRODUCED, "f" * 64)

    registry.register("fixture@mismatch", dimensions(), callback)
    with SQLiteCapabilityGapStore(tmp_path / "mismatch.sqlite3") as store:
        with pytest.raises(CapabilityGapCollisionError, match="bundle_fingerprint_mismatch"):
            store.import_bundle(
                payload,
                DeliveryImportContext("b" * 64, "c" * 64),
                reproduction=registry,
            )
        assert callbacks == 0
        assert store.list_candidates() == ()


def test_arbitrary_size_counts_aggregate_across_distinct_deliveries(tmp_path: Path) -> None:
    huge = 2**63 + 9
    payload, fingerprint = bundle(record("7" * 64, count=huge))
    with SQLiteCapabilityGapStore(tmp_path / "huge.sqlite3") as store:
        store.import_bundle(payload, context(fingerprint, "a"))
        store.import_bundle(payload, context(fingerprint, "b"))
        assert store.get_candidate("7" * 64).occurrence_count == huge * 2


def test_active_work_link_is_informational_and_snapshots_omit_delivery_identity(
    tmp_path: Path,
) -> None:
    payload, fingerprint = bundle(record("8" * 64))
    work = InMemoryActiveWorkIndex((ActiveWorkSnapshot("8" * 64, ActiveWorkKind.BEAD, "GAP-05B"),))
    with SQLiteCapabilityGapStore(tmp_path / "evidence.sqlite3") as store:
        store.import_bundle(payload, context(fingerprint, "c"), active_work=work)
        store.import_bundle(payload, context(fingerprint, "d"), active_work=work)
        snapshot = store.get_candidate("8" * 64)
        assert len(snapshot.contributions) == 2
        assert snapshot.active_work == work.matches("8" * 64, dimensions())
        serialized = repr(snapshot) + repr(asdict(snapshot))
        assert "delivery_import_id" not in serialized
        assert "sender_scope" not in serialized
        assert "c" * 64 not in serialized
        assert "d" * 64 not in serialized
        assert all(field.name != "delivery_import_id" for field in fields(snapshot))
