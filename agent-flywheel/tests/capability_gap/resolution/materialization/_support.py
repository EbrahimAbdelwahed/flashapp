from __future__ import annotations

import sqlite3
from collections.abc import Callable
from pathlib import Path
from threading import Lock
from typing import Any

from study_agent_devkit.capability_gap import (
    DecisionViewV1,
    FlywheelPromotionBundleV1,
    FlywheelPromotionReceiptV1,
    FlywheelPromotionSink,
    GrillReceiptV1,
    GrillSubjectKind,
    ResolutionCommandV1,
    ResolutionOutcome,
    SQLiteResolutionService,
)

from ..test_service import Clock, Source, package


class AcceptedAuthority:
    def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
        return ResolutionCommandV1(
            1,
            view.proposal_id,
            view.decision_id,
            ResolutionOutcome.ACCEPTED,
            "safe",
            None,
            None,
            (
                GrillReceiptV1(GrillSubjectKind.BEAD, "GAP-TEST", "rb", "2" * 64),
                GrillReceiptV1(GrillSubjectKind.PROPOSAL, view.proposal_id, "rp", "1" * 64),
            ),
        )


class RejectedAuthority:
    def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
        return ResolutionCommandV1(
            1,
            view.proposal_id,
            view.decision_id,
            ResolutionOutcome.REJECTED,
            None,
            None,
            None,
            (),
        )


class RecordingSink:
    def __init__(
        self,
        sink_id: str = "a" * 64,
        callback: Callable[[FlywheelPromotionBundleV1], FlywheelPromotionReceiptV1] | None = None,
    ) -> None:
        self._sink_id = sink_id
        self.callback = callback
        self.calls = 0
        self.bundles: list[FlywheelPromotionBundleV1] = []
        self.lock = Lock()

    @property
    def sink_id(self) -> str:
        return self._sink_id

    def apply(self, bundle: FlywheelPromotionBundleV1) -> FlywheelPromotionReceiptV1:
        with self.lock:
            self.calls += 1
            self.bundles.append(bundle)
        if self.callback is not None:
            return self.callback(bundle)
        return FlywheelPromotionReceiptV1.for_bundle(bundle, self._sink_id)


def accepted_bundle(
    tmp_path: Path,
    *,
    sink: FlywheelPromotionSink | None = None,
    database_name: str = "resolution.sqlite3",
) -> tuple[SQLiteResolutionService, FlywheelPromotionBundleV1, str]:
    current = package()
    service = SQLiteResolutionService(
        tmp_path / database_name,
        Source(current),
        AcceptedAuthority(),
        Clock(),
        promotion_sink=sink,
    )
    resolution = service.resolve(current.decision.decision_id)
    promotion = service.get_promotion_by_decision_id(resolution.decision_id)
    assert promotion is not None
    return service, promotion, resolution.decision_id


def accepted_database(
    tmp_path: Path, sink: FlywheelPromotionSink
) -> tuple[Path, FlywheelPromotionBundleV1, str]:
    database = tmp_path / "resolution.sqlite3"
    service, promotion, decision_id = accepted_bundle(tmp_path, sink=sink)
    service.close()
    return database, promotion, decision_id


def claim_row(database: Path, promotion_id: str) -> tuple[Any, ...] | None:
    with sqlite3.connect(database) as connection:
        row = connection.execute(
            "SELECT promotion_id, sink_id, receipt_bytes FROM materialization_claims "
            "WHERE promotion_id=?",
            (promotion_id,),
        ).fetchone()
    return None if row is None else tuple(row)
