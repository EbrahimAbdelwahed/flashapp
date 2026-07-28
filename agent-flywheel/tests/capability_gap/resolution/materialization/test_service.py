from __future__ import annotations

import sqlite3
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Barrier
from typing import Any

import pytest

from study_agent_devkit.capability_gap import (
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    CapabilityGapUnavailableError,
    FlywheelPromotionBundleV1,
    FlywheelPromotionReceiptV1,
    LocalFlywheelPromotionSink,
    SQLiteResolutionService,
)

from ..test_service import Clock, Source, package
from ._support import (
    AcceptedAuthority,
    RecordingSink,
    accepted_bundle,
    accepted_database,
    claim_row,
)


def test_claim_is_committed_before_sink_and_sink_failure_leaves_pending_claim(
    tmp_path: Path,
) -> None:
    sink = RecordingSink(callback=lambda _: (_ for _ in ()).throw(RuntimeError("sink down")))
    service, promotion, _ = accepted_bundle(tmp_path, sink=sink)
    with pytest.raises(RuntimeError, match="sink down"):
        service.materialize(promotion.promotion_id)
    assert claim_row(tmp_path / "resolution.sqlite3", promotion.promotion_id) == (
        promotion.promotion_id,
        sink.sink_id,
        None,
    )
    service.close()


def test_completed_retry_returns_persisted_receipt_without_invoking_sink(tmp_path: Path) -> None:
    sink = RecordingSink()
    service, promotion, _ = accepted_bundle(tmp_path, sink=sink)
    first = service.materialize(promotion.promotion_id)
    sink.callback = lambda _: (_ for _ in ()).throw(AssertionError("retry called sink"))
    second = service.materialize(promotion.promotion_id)
    assert second.to_bytes() == first.to_bytes()
    assert sink.calls == 1
    service.close()


def test_process_loss_after_local_final_rename_converges_on_retry(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    sink = LocalFlywheelPromotionSink(tmp_path)
    service, promotion, _ = accepted_bundle(tmp_path, sink=sink)
    original_commit = service._store.commit_materialization_receipt
    calls = 0

    def lose_process(*args: Any, **kwargs: Any) -> FlywheelPromotionReceiptV1:
        nonlocal calls
        calls += 1
        if calls == 1:
            raise RuntimeError("simulated process loss")
        return original_commit(*args, **kwargs)

    monkeypatch.setattr(service._store, "commit_materialization_receipt", lose_process)
    with pytest.raises(RuntimeError, match="simulated process loss"):
        service.materialize(promotion.promotion_id)
    run = tmp_path / "docs" / "flywheel-runs" / promotion.materialization_plan.run_id
    assert run.is_dir()
    receipt = service.materialize(promotion.promotion_id)
    assert receipt.run_id == promotion.materialization_plan.run_id
    row = claim_row(tmp_path / "resolution.sqlite3", promotion.promotion_id)
    assert row is not None and row[2] is not None
    service.close()


def test_same_sink_concurrency_converges_to_one_receipt(tmp_path: Path) -> None:
    sink = RecordingSink()
    database, promotion, _decision_id = accepted_database(tmp_path, sink)
    barrier = Barrier(2)

    class ConcurrentSink(RecordingSink):
        def apply(self, bundle: FlywheelPromotionBundleV1) -> FlywheelPromotionReceiptV1:
            barrier.wait(timeout=10)
            return super().apply(bundle)

    # Each service has the same stable sink identity, while calls can overlap
    # after the short claim transaction has committed.
    shared = ConcurrentSink(sink.sink_id)
    def materialize_in_thread(_: int) -> FlywheelPromotionReceiptV1:
        service = SQLiteResolutionService(
            database, Source(package()), AcceptedAuthority(), Clock(), promotion_sink=shared
        )
        try:
            return service.materialize(promotion.promotion_id)
        finally:
            service.close()

    with ThreadPoolExecutor(max_workers=2) as pool:
        receipts = list(pool.map(materialize_in_thread, (1, 2)))
        assert receipts[0].to_bytes() == receipts[1].to_bytes()
        assert shared.calls == 2


@pytest.mark.parametrize("complete", [False, True])
def test_different_sink_pending_or_completed_claim_collides(
    tmp_path: Path, complete: bool
) -> None:
    first_sink = RecordingSink("a" * 64)
    database, promotion, _ = accepted_database(tmp_path, first_sink)
    first = SQLiteResolutionService(
        database, Source(package()), AcceptedAuthority(), Clock(), promotion_sink=first_sink
    )
    if complete:
        first.materialize(promotion.promotion_id)
    else:
        first_sink.callback = lambda _: (_ for _ in ()).throw(RuntimeError("pending"))
        with pytest.raises(RuntimeError):
            first.materialize(promotion.promotion_id)
    first.close()
    second_sink = RecordingSink("b" * 64)
    second = SQLiteResolutionService(
        database, Source(package()), AcceptedAuthority(), Clock(), promotion_sink=second_sink
    )
    with pytest.raises(CapabilityGapCollisionError, match="sink_collision"):
        second.materialize(promotion.promotion_id)
    assert second_sink.calls == 0
    second.close()


def test_cached_sink_id_orders_callbacks_and_retry_skips_sink_id(tmp_path: Path) -> None:
    class CachedSink(RecordingSink):
        def __init__(self) -> None:
            super().__init__()
            self.fail_property = False

        @property
        def sink_id(self) -> str:
            if self.fail_property:
                raise AssertionError("sink_id must be cached")
            return super().sink_id

    sink = CachedSink()
    service, promotion, _ = accepted_bundle(tmp_path, sink=sink)
    sink.fail_property = True
    first = service.materialize(promotion.promotion_id)
    second = service.materialize(promotion.promotion_id)
    assert second.to_bytes() == first.to_bytes()
    assert sink.calls == 1
    service.close()


@pytest.mark.parametrize("promotion_id", ["f" * 64, "0" * 64])
def test_unknown_or_nonaccepted_promotion_never_reaches_sink(
    tmp_path: Path, promotion_id: str
) -> None:
    sink = RecordingSink()
    service = SQLiteResolutionService(
        tmp_path / "unknown.sqlite3",
        Source(package()),
        AcceptedAuthority(),
        Clock(),
        promotion_sink=sink,
    )
    if promotion_id == "0" * 64:
        # A rejected decision has no promotion row.
        service.close()
        from ._support import RejectedAuthority

        service = SQLiteResolutionService(
            tmp_path / "rejected.sqlite3",
            Source(package()),
            RejectedAuthority(),
            Clock(),
            promotion_sink=sink,
        )
        service.resolve(package().decision.decision_id)
    with pytest.raises(CapabilityGapUnavailableError):
        service.materialize(promotion_id)
    assert sink.calls == 0
    service.close()


def test_wrong_returned_receipt_is_rejected_and_claim_remains_pending(tmp_path: Path) -> None:
    wrong_sink = "b" * 64
    sink = RecordingSink(
        callback=lambda bundle: FlywheelPromotionReceiptV1.for_bundle(bundle, wrong_sink)
    )
    service, promotion, _ = accepted_bundle(tmp_path, sink=sink)
    with pytest.raises(CapabilityGapCollisionError, match="receipt_mismatch"):
        service.materialize(promotion.promotion_id)
    row = claim_row(tmp_path / "resolution.sqlite3", promotion.promotion_id)
    assert row is not None and row[2] is None
    service.close()


def test_corrupt_claim_sink_receipt_missing_promotion_and_schema_fail_closed(
    tmp_path: Path,
) -> None:
    sink = RecordingSink()
    database, promotion, _ = accepted_database(tmp_path, sink)

    pending_sink = RecordingSink(callback=lambda _: (_ for _ in ()).throw(RuntimeError("pending")))
    pending = SQLiteResolutionService(
        database, Source(package()), AcceptedAuthority(), Clock(), promotion_sink=pending_sink
    )
    # The first claim must exist before its bytes can be corrupted.
    with pytest.raises(RuntimeError):
        pending.materialize(promotion.promotion_id)
    pending.close()

    with sqlite3.connect(database) as connection:
        connection.execute(
            "UPDATE materialization_claims SET sink_id=? WHERE promotion_id=?",
            ("not-a-digest", promotion.promotion_id),
        )
    service = SQLiteResolutionService(
        database, Source(package()), AcceptedAuthority(), Clock(), promotion_sink=sink
    )
    with pytest.raises(CapabilityGapCorruptionError):
        service.materialize(promotion.promotion_id)
    service.close()

    # Rebuild a clean database for each independent corruption shape.
    mutations: tuple[tuple[str, Any], ...] = (
        (
            "receipt",
            lambda connection, p: connection.execute(
                "UPDATE materialization_claims SET receipt_bytes=? WHERE promotion_id=?",
                (b"{}", p),
            ),
        ),
        (
            "missing",
            lambda connection, p: connection.execute(
                "INSERT INTO materialization_claims "
                "(promotion_id,sink_id,receipt_bytes) VALUES(?,?,NULL)",
                ("f" * 64, "a" * 64),
            ),
        ),
        (
            "schema",
            lambda connection, p: connection.execute("PRAGMA user_version=99"),
        ),
    )
    for name, mutate in mutations:
        case = tmp_path / f"{name}.sqlite3"
        s, p, _ = accepted_bundle(tmp_path, sink=sink, database_name=f"{name}.sqlite3")
        s.close()
        if name in {"receipt", "schema"}:
            pending_sink = RecordingSink(
                callback=lambda _: (_ for _ in ()).throw(RuntimeError("pending"))
            )
            pending = SQLiteResolutionService(
                case, Source(package()), AcceptedAuthority(), Clock(), promotion_sink=pending_sink
            )
            with pytest.raises(RuntimeError):
                pending.materialize(p.promotion_id)
            pending.close()
        with sqlite3.connect(case) as connection:
            mutate(connection, p.promotion_id)
        if name == "schema":
            with pytest.raises(CapabilityGapCorruptionError):
                SQLiteResolutionService(
                    case, Source(package()), AcceptedAuthority(), Clock(), promotion_sink=sink
                )
        else:
            s = SQLiteResolutionService(
                case, Source(package()), AcceptedAuthority(), Clock(), promotion_sink=sink
            )
            with pytest.raises(CapabilityGapCorruptionError):
                s.materialize(p.promotion_id if name != "missing" else "f" * 64)
            s.close()
