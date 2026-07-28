from __future__ import annotations

import base64
import json
import sqlite3
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path
from threading import Barrier

import pytest
from study_agent.state import canonical_json_bytes

from study_agent_devkit.capability_gap import (
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    CapabilityGapValidationError,
    DecisionViewV1,
    DraftArtifactKind,
    DraftArtifactState,
    FlywheelPromotionBundleV1,
    GapResolutionV1,
    GrillReceiptV1,
    GrillSubjectKind,
    MaintainerResolutionAuthority,
    ResolutionCommandV1,
    ResolutionOutcome,
    SQLiteResolutionService,
)
from study_agent_devkit.capability_gap import resolution_service as resolution_service_module
from study_agent_devkit.capability_gap.proposal_contracts import (
    DraftArtifactV1,
    ImprovementProposalV1,
    ProposalDecisionPackageV1,
    RequestedAuthority,
)
from study_agent_devkit.flywheel.materialization import validate_materialization_plan

from ..test_service import TASK_BODY, Clock, Source, package


class AcceptedAuthority:
    def __init__(self, *, wait: Barrier | None = None) -> None:
        self.wait = wait
        self.calls = 0

    def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
        self.calls += 1
        if self.wait is not None:
            self.wait.wait()
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


def _accepted_service(
    database: Path,
    source: Source,
    *,
    authority: MaintainerResolutionAuthority | None = None,
) -> SQLiteResolutionService:
    return SQLiteResolutionService(database, source, authority or AcceptedAuthority(), Clock())


def test_exact_retry_reads_db_before_source_authority_and_clock_even_when_callbacks_fail(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    current = package()
    database = tmp_path / "retry.sqlite3"
    with _accepted_service(database, Source(current)) as service:
        first = service.resolve(current.decision.decision_id)

    def exploding_planner(_: object) -> object:
        raise AssertionError("planner must not run on exact retry")

    monkeypatch.setattr(resolution_service_module, "plan_run", exploding_planner)

    class ExplodingSource(Source):
        def get_by_decision_id(self, decision_id: str) -> ProposalDecisionPackageV1 | None:
            raise AssertionError("source callback must not run on exact retry")

        def get_by_proposal_id(self, proposal_id: str) -> ProposalDecisionPackageV1 | None:
            raise AssertionError("target callback must not run on exact retry")

    class ExplodingAuthority:
        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1 | None:
            raise AssertionError("authority callback must not run on exact retry")

    class ExplodingClock:
        def now(self) -> datetime:
            raise AssertionError("clock callback must not run on exact retry")

    with SQLiteResolutionService(
        database, ExplodingSource(current), ExplodingAuthority(), ExplodingClock()
    ) as service:
        assert service.resolve(current.decision.decision_id).to_bytes() == first.to_bytes()


def test_malformed_decision_id_fails_before_any_callback(tmp_path: Path) -> None:
    class ExplodingSource:
        def get_by_decision_id(
            self, decision_id: str
        ) -> ProposalDecisionPackageV1 | None:
            raise AssertionError

        def get_by_proposal_id(
            self, proposal_id: str
        ) -> ProposalDecisionPackageV1 | None:
            raise AssertionError

    class ExplodingAuthority:
        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1 | None:
            raise AssertionError

    class ExplodingClock:
        def now(self) -> datetime:
            raise AssertionError

    with (
        SQLiteResolutionService(
            tmp_path / "malformed.sqlite3",
            ExplodingSource(),
            ExplodingAuthority(),
            ExplodingClock(),
        ) as service,
        pytest.raises(CapabilityGapValidationError),
    ):
        service.resolve("not-a-digest")


def test_source_package_substitution_and_stale_crosslinks_fail_closed(tmp_path: Path) -> None:
    current, other = package("a" * 64), package("b" * 64)

    class SubstitutingSource(Source):
        def get_by_decision_id(self, decision_id: str) -> ProposalDecisionPackageV1 | None:
            return other

    with (
        SQLiteResolutionService(
            tmp_path / "substitution.sqlite3",
            SubstitutingSource(current, other),
            AcceptedAuthority(),
            Clock(),
        ) as service,
        pytest.raises(CapabilityGapCorruptionError),
    ):
        service.resolve(current.decision.decision_id)


@pytest.mark.parametrize("mode", ("missing_bead", "extra_subject", "invalid_option"))
def test_accepted_command_requires_exact_grills_and_option_binding(
    tmp_path: Path, mode: str
) -> None:
    current = package()

    class InvalidAcceptedAuthority:
        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            receipts = (
                (GrillReceiptV1(GrillSubjectKind.PROPOSAL, view.proposal_id, "rp", "1" * 64),)
                if mode == "missing_bead"
                    else (
                        GrillReceiptV1(GrillSubjectKind.BEAD, "GAP-TEST", "rb", "2" * 64),
                        GrillReceiptV1(GrillSubjectKind.BEAD, "extra", "rx", "3" * 64),
                        GrillReceiptV1(GrillSubjectKind.PROPOSAL, view.proposal_id, "rp", "1" * 64),
                    )
                if mode == "extra_subject"
                else (
                    GrillReceiptV1(GrillSubjectKind.BEAD, "GAP-TEST", "rb", "2" * 64),
                    GrillReceiptV1(GrillSubjectKind.PROPOSAL, view.proposal_id, "rp", "1" * 64),
                )
            )
            return ResolutionCommandV1(
                1,
                view.proposal_id,
                view.decision_id,
                ResolutionOutcome.ACCEPTED,
                "missing" if mode == "invalid_option" else "safe",
                None,
                None,
                receipts,
            )

    database = tmp_path / f"invalid-{mode}.sqlite3"
    with SQLiteResolutionService(
        database, Source(current), InvalidAcceptedAuthority(), Clock()
    ) as service:
        with pytest.raises(CapabilityGapValidationError):
            service.resolve(current.decision.decision_id)
        with sqlite3.connect(database) as connection:
            assert connection.execute("SELECT COUNT(*) FROM resolution_packages").fetchone()[0] == 0

    class StaleAuthority:
        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            return ResolutionCommandV1(
                1, "c" * 64, view.decision_id, ResolutionOutcome.REJECTED, None, None, None, ()
            )

    with (
        SQLiteResolutionService(
            tmp_path / "stale.sqlite3", Source(current), StaleAuthority(), Clock()
        ) as service,
        pytest.raises(CapabilityGapCollisionError),
    ):
        service.resolve(current.decision.decision_id)


def test_clock_or_planner_failure_leaves_no_resolution_row(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    current = package()

    class RaisingClock:
        def now(self) -> datetime:
            raise RuntimeError("clock failed")

    database = tmp_path / "clock.sqlite3"
    with SQLiteResolutionService(
        database, Source(current), AcceptedAuthority(), RaisingClock()
    ) as service:
        with pytest.raises(RuntimeError):
            service.resolve(current.decision.decision_id)
        assert service.get_promotion_by_decision_id("0" * 64) is None
        with sqlite3.connect(database) as connection:
            assert (
                connection.execute(
                    "SELECT COUNT(*) FROM resolution_packages WHERE decision_id=?",
                    (current.decision.decision_id,),
                ).fetchone()[0]
                == 0
            )

    database = tmp_path / "planner.sqlite3"

    def fail_plan(_: object) -> object:
        raise RuntimeError("planner failed")

    monkeypatch.setattr(resolution_service_module, "plan_run", fail_plan)
    with SQLiteResolutionService(
        database, Source(current), AcceptedAuthority(), Clock()
    ) as service:
        with pytest.raises(RuntimeError):
            service.resolve(current.decision.decision_id)
        with sqlite3.connect(database) as connection:
            assert (
                connection.execute(
                    "SELECT COUNT(*) FROM resolution_packages WHERE decision_id=?",
                    (current.decision.decision_id,),
                ).fetchone()[0]
                == 0
            )


def test_concurrent_different_commands_return_one_persisted_winner(tmp_path: Path) -> None:
    current = package()
    database = tmp_path / "different-winners.sqlite3"
    barrier = Barrier(2)

    class VaryingAuthority:
        def __init__(self) -> None:
            self.calls = 0

        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            barrier.wait(timeout=10)
            self.calls += 1
            outcome = ResolutionOutcome.REJECTED if self.calls == 1 else ResolutionOutcome.DEFERRED
            return ResolutionCommandV1(
                1,
                view.proposal_id,
                view.decision_id,
                outcome,
                None,
                None if outcome is ResolutionOutcome.REJECTED else "later",
                None,
                (),
            )

    authority = VaryingAuthority()
    # Initialize the exact schema before coordinating authority callbacks. This
    # keeps the test focused on resolution CAS rather than concurrent DDL.
    with SQLiteResolutionService(
        database, Source(current), authority, Clock()
    ):
        pass

    def run(_: int) -> bytes:
        with SQLiteResolutionService(database, Source(current), authority, Clock()) as service:
            return service.resolve(current.decision.decision_id).to_bytes()

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = tuple(pool.map(run, (1, 2)))
    assert results[0] == results[1]


def test_accepted_promotion_has_exact_artifacts_plan_gates_and_goal_contract(
    tmp_path: Path,
) -> None:
    current = package()
    with _accepted_service(tmp_path / "promotion.sqlite3", Source(current)) as service:
        resolution = service.resolve(current.decision.decision_id)
        promotion = service.get_promotion_by_decision_id(current.decision.decision_id)
        assert promotion is not None
        assert resolution.outcome is ResolutionOutcome.ACCEPTED
        assert (
            tuple(item.artifact_state for item in promotion.approved_artifacts) == ("approved",) * 3
        )
        order = {"adr": 0, "spec": 1, "bead": 2}
        assert tuple(item.body for item in promotion.approved_artifacts) == tuple(
            item.body
            for item in sorted(
                current.proposal.draft.artifacts,
                key=lambda item: (order[item.kind.value], item.artifact_id),
            )
        )
        assert promotion.materialization_plan.run_id == f"gap06-{resolution.resolution_id[:24]}"
        assert not validate_materialization_plan(promotion.materialization_plan)
        assert promotion.required_gates == (
            "worker_briefs",
            "tests",
            "semantic_review",
            "publication_authority",
        )
        assert promotion.exclusions == ("github_issue", "repository_merge", "release", "deployment")
        assert promotion.implementation_goal is None
        promotion_raw = json.loads(promotion.to_bytes())
        promotion_raw["promotion_id"] = "0" * 64
        with pytest.raises(CapabilityGapCorruptionError):
            type(promotion).from_bytes(canonical_json_bytes(promotion_raw))
        with pytest.raises(CapabilityGapCorruptionError):
            replace(promotion, promotion_id="0" * 64)

        promotion_raw = json.loads(promotion.to_bytes())
        promotion_raw["materialization_plan"]["files"] = [
            item
            for item in promotion_raw["materialization_plan"]["files"]
            if item["relative_path"] != "manifest.json"
        ]
        promotion_raw["promotion_id"] = FlywheelPromotionBundleV1.derive_id(
            {key: value for key, value in promotion_raw.items() if key != "promotion_id"}
        )
        with pytest.raises(CapabilityGapCorruptionError):
            FlywheelPromotionBundleV1.from_bytes(canonical_json_bytes(promotion_raw))

        promotion_raw = json.loads(promotion.to_bytes())
        for item in promotion_raw["materialization_plan"]["files"]:
            if item["relative_path"] == "manifest.json":
                manifest = json.loads(base64.b64decode(item["content_b64"]))
                manifest["feature"]["title"] = "forged"
                item["content_b64"] = base64.b64encode(
                    canonical_json_bytes(manifest)
                ).decode("ascii")
                break
        promotion_raw["promotion_id"] = FlywheelPromotionBundleV1.derive_id(
            {key: value for key, value in promotion_raw.items() if key != "promotion_id"}
        )
        with pytest.raises(CapabilityGapCorruptionError):
            FlywheelPromotionBundleV1.from_bytes(canonical_json_bytes(promotion_raw))

        promotion_raw = json.loads(promotion.to_bytes())
        for item in promotion_raw["materialization_plan"]["files"]:
            if item["relative_path"] == "context/context.md":
                context = base64.b64decode(item["content_b64"]).decode("utf-8")
                context = context.replace(
                    f"selected_option_id: {promotion.selected_option_id}",
                    "selected_option_id: forged",
                )
                item["content_b64"] = base64.b64encode(context.encode("utf-8")).decode(
                    "ascii"
                )
                break
        promotion_raw["promotion_id"] = FlywheelPromotionBundleV1.derive_id(
            {key: value for key, value in promotion_raw.items() if key != "promotion_id"}
        )
        with pytest.raises(CapabilityGapCorruptionError):
            FlywheelPromotionBundleV1.from_bytes(canonical_json_bytes(promotion_raw))

        promotion_raw = json.loads(promotion.to_bytes())
        promotion_raw["approved_artifacts"] = [
            item for item in promotion_raw["approved_artifacts"] if item["kind"] != "adr"
        ]
        promotion_raw["promotion_id"] = FlywheelPromotionBundleV1.derive_id(
            {key: value for key, value in promotion_raw.items() if key != "promotion_id"}
        )
        with pytest.raises(CapabilityGapCorruptionError):
            FlywheelPromotionBundleV1.from_bytes(canonical_json_bytes(promotion_raw))


def test_accepted_promotion_preserves_unsorted_dependencies(tmp_path: Path) -> None:
    current = package()
    draft = current.proposal.draft

    def bead(artifact_id: str, depends_on: tuple[str, ...]) -> DraftArtifactV1:
        body = TASK_BODY.replace("GAP-TEST Test task", f"{artifact_id} {artifact_id} task")
        body = body.replace("create `lesson-worker`", "none needed")
        body = body.replace("Depends On: none", "Depends On: " + (", ".join(depends_on) or "none"))
        return DraftArtifactV1(
            DraftArtifactKind.BEAD,
            artifact_id,
            DraftArtifactState.DRAFT,
            body,
            depends_on,
        )

    beads = (bead("GAP-A", ()), bead("GAP-B", ()), bead("GAP-C", ("GAP-B", "GAP-A")))
    proposal = ImprovementProposalV1.create(
        current.proposal.evidence,
        replace(draft, artifacts=(draft.artifacts[0], draft.artifacts[1], *beads)),
        current.proposal.created_at,
    )
    source = Source(ProposalDecisionPackageV1.create(proposal))

    class Authority:
        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            receipts = tuple(
                sorted(
                    [GrillReceiptV1(GrillSubjectKind.PROPOSAL, view.proposal_id, "rp", "1" * 64)]
                    + [
                        GrillReceiptV1(GrillSubjectKind.BEAD, item, f"r-{item}", "2" * 64)
                        for item in view.bead_ids
                    ],
                    key=lambda item: (item.subject_kind.value, item.subject_id),
                )
            )
            return ResolutionCommandV1(
                1, view.proposal_id, view.decision_id, ResolutionOutcome.ACCEPTED,
                "safe", None, None, receipts,
            )

    decision_id = next(iter(source.packages))
    with SQLiteResolutionService(
        tmp_path / "unsorted.sqlite3", source, Authority(), Clock()
    ) as service:
        service.resolve(decision_id)
        promotion = service.get_promotion_by_decision_id(decision_id)
        assert promotion is not None
        bead_artifact = next(
            item for item in promotion.approved_artifacts if item.artifact_id == "GAP-C"
        )
        assert bead_artifact.depends_on == ("GAP-B", "GAP-A")


def test_promotion_rejects_plan_artifact_divergence_and_store_binding_drift(
    tmp_path: Path,
) -> None:
    current = package()
    database = tmp_path / "promotion-binding.sqlite3"
    with _accepted_service(database, Source(current)) as service:
        service.resolve(current.decision.decision_id)
        promotion = service.get_promotion_by_decision_id(current.decision.decision_id)
        assert promotion is not None
        raw = json.loads(promotion.to_bytes())
        spec = next(item for item in raw["approved_artifacts"] if item["kind"] == "spec")
        spec["body"] = spec["body"] + "\nchanged"
        raw["promotion_id"] = FlywheelPromotionBundleV1.derive_id(
            {key: value for key, value in raw.items() if key != "promotion_id"}
        )
        with pytest.raises(CapabilityGapCorruptionError):
            FlywheelPromotionBundleV1.from_bytes(canonical_json_bytes(raw))

        raw = json.loads(promotion.to_bytes())
        raw["selected_option_id"] = "small"
        raw["promotion_id"] = FlywheelPromotionBundleV1.derive_id(
            {key: value for key, value in raw.items() if key != "promotion_id"}
        )
        connection = sqlite3.connect(database)
        connection.execute(
            "UPDATE resolution_packages SET promotion_id=?, promotion_bytes=? WHERE decision_id=?",
            (raw["promotion_id"], canonical_json_bytes(raw), current.decision.decision_id),
        )
        connection.commit()
        connection.close()
        with pytest.raises(CapabilityGapCorruptionError):
            service.get_promotion_by_decision_id(current.decision.decision_id)

    goal_draft = replace(
        current.proposal.draft,
        requested_authority=RequestedAuthority.PLANNING_AND_IMPLEMENTATION_GOAL,
    )
    goal_proposal = ImprovementProposalV1.create(
        current.proposal.evidence, goal_draft, current.proposal.created_at
    )
    goal_package = ProposalDecisionPackageV1.create(goal_proposal)
    with _accepted_service(tmp_path / "promotion-goal.sqlite3", Source(goal_package)) as service:
        service.resolve(goal_package.decision.decision_id)
        goal_promotion = service.get_promotion_by_decision_id(goal_package.decision.decision_id)
        assert goal_promotion is not None
        assert goal_promotion.implementation_goal is not None
        assert goal_promotion.implementation_goal.proposal_id == goal_package.proposal.proposal_id
        assert goal_promotion.implementation_goal.status == "authorized_not_started"
        goal_raw = json.loads(goal_promotion.to_bytes())
        goal_raw["implementation_goal"]["proposal_id"] = "f" * 64
        goal_raw["implementation_goal"]["goal_id"] = "0" * 64
        with pytest.raises(CapabilityGapCorruptionError):
            FlywheelPromotionBundleV1.from_bytes(canonical_json_bytes(goal_raw))


def test_corrupted_schema_index_projection_and_bytes_fail_closed(tmp_path: Path) -> None:
    current = package()
    database = tmp_path / "corruption.sqlite3"
    with _accepted_service(database, Source(current)) as service:
        service.resolve(current.decision.decision_id)
    connection = sqlite3.connect(database)
    connection.execute("UPDATE resolution_packages SET resolution_bytes=?", (b"{}",))
    connection.commit()
    connection.close()
    with (
        SQLiteResolutionService(database, Source(current), AcceptedAuthority(), Clock()) as service,
        pytest.raises(CapabilityGapCorruptionError),
    ):
        service.get_promotion_by_decision_id(current.decision.decision_id)

    index_db = tmp_path / "index.sqlite3"
    with _accepted_service(index_db, Source(current)) as service:
        service.resolve(current.decision.decision_id)
    connection = sqlite3.connect(index_db)
    connection.execute("CREATE INDEX adversarial_extra_index ON resolution_packages(outcome)")
    connection.commit()
    connection.close()
    with pytest.raises(CapabilityGapCorruptionError):
        SQLiteResolutionService(index_db, Source(current), AcceptedAuthority(), Clock())

    ddl_db = tmp_path / "ddl.sqlite3"
    connection = sqlite3.connect(ddl_db)
    connection.execute("CREATE TABLE resolution_packages (resolution_pk INTEGER PRIMARY KEY)")
    connection.execute("CREATE TABLE materialization_claims (claim_pk INTEGER PRIMARY KEY)")
    connection.execute("PRAGMA user_version=1")
    connection.commit()
    connection.close()
    with pytest.raises(CapabilityGapCorruptionError):
        SQLiteResolutionService(ddl_db, Source(current), AcceptedAuthority(), Clock())

    partial_v0_db = tmp_path / "partial-v0.sqlite3"
    connection = sqlite3.connect(partial_v0_db)
    connection.execute("CREATE TABLE resolution_packages (resolution_pk INTEGER PRIMARY KEY)")
    connection.commit()
    connection.close()
    with pytest.raises(CapabilityGapCorruptionError):
        SQLiteResolutionService(partial_v0_db, Source(current), AcceptedAuthority(), Clock())

    drift_db = tmp_path / "post-init-drift.sqlite3"
    with _accepted_service(drift_db, Source(current)) as service:
        service.resolve(current.decision.decision_id)
        connection = sqlite3.connect(drift_db)
        connection.execute("CREATE TABLE drift (value TEXT)")
        connection.commit()
        connection.close()
        with pytest.raises(CapabilityGapCorruptionError):
            service.get_promotion_by_decision_id(current.decision.decision_id)

    claim_db = tmp_path / "non-null-claim.sqlite3"
    with _accepted_service(claim_db, Source(current)) as service:
        service.resolve(current.decision.decision_id)
        promotion = service.get_promotion_by_decision_id(current.decision.decision_id)
        assert promotion is not None
        connection = sqlite3.connect(claim_db)
        connection.execute(
            "INSERT INTO materialization_claims "
            "(promotion_id, sink_id, receipt_bytes) VALUES (?, ?, ?)",
            (promotion.promotion_id, "1" * 64, b"{}"),
        )
        connection.commit()
        connection.close()
        with pytest.raises(CapabilityGapCorruptionError):
            service.get_promotion_by_decision_id(current.decision.decision_id)


def test_duplicate_graph_cycle_is_rejected_on_read(tmp_path: Path) -> None:
    first, second = package("a" * 64), package("b" * 64)
    database = tmp_path / "cycle.sqlite3"

    class DuplicateAuthority:
        def __init__(self, target: str) -> None:
            self.target = target

        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            return ResolutionCommandV1(
                1,
                view.proposal_id,
                view.decision_id,
                ResolutionOutcome.DUPLICATE,
                None,
                None,
                self.target,
                (),
            )

    with SQLiteResolutionService(
        database, Source(first, second), DuplicateAuthority(second.proposal.proposal_id), Clock()
    ) as service:
        service.resolve(first.decision.decision_id)

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

    with SQLiteResolutionService(
        database, Source(first, second), RejectedAuthority(), Clock()
    ) as service:
        service.resolve(second.decision.decision_id)

    # Replace the second row with a valid resolution whose edge points back to A;
    # the store must reject the resulting cycle before exposing any row.
    with SQLiteResolutionService(
        database, Source(first, second), DuplicateAuthority(first.proposal.proposal_id), Clock()
    ) as service:
        command = ResolutionCommandV1(
            1,
            second.proposal.proposal_id,
            second.decision.decision_id,
            ResolutionOutcome.DUPLICATE,
            None,
            None,
            first.proposal.proposal_id,
            (),
        )
        now = datetime(2026, 1, 3, tzinfo=UTC)
        fingerprint = command.authority_receipt_fingerprint
        replacement = GapResolutionV1(
            1,
            GapResolutionV1.derive_id(
                second.proposal.proposal_id,
                second.decision.decision_id,
                command,
                fingerprint,
                second.decision.requested_authority,
                now,
            ),
            second.proposal.proposal_id,
            second.decision.decision_id,
            ResolutionOutcome.DUPLICATE,
            None,
            None,
            first.proposal.proposal_id,
            (),
            fingerprint,
            second.decision.requested_authority,
            now,
        )
        connection = sqlite3.connect(database)
        connection.execute(
            "UPDATE resolution_packages SET resolution_id=?, outcome=?, "
            "resolution_bytes=? WHERE proposal_id=?",
            (
                replacement.resolution_id,
                "duplicate",
                replacement.to_bytes(),
                second.proposal.proposal_id,
            ),
        )
        connection.commit()
        connection.close()
        with pytest.raises(CapabilityGapCorruptionError):
            service.get_promotion_by_decision_id(first.decision.decision_id)


def test_ordered_duplicate_a_to_b_then_b_to_c_rolls_back_second_insert(
    tmp_path: Path,
) -> None:
    first, second, third = package("a" * 64), package("b" * 64), package("c" * 64)
    database = tmp_path / "ordered-duplicate.sqlite3"

    class DuplicateAuthority:
        def __init__(self, target: str) -> None:
            self.target = target

        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            return ResolutionCommandV1(
                1,
                view.proposal_id,
                view.decision_id,
                ResolutionOutcome.DUPLICATE,
                None,
                None,
                self.target,
                (),
            )

    with SQLiteResolutionService(
        database,
        Source(first, second, third),
        DuplicateAuthority(second.proposal.proposal_id),
        Clock(),
    ) as service:
        service.resolve(first.decision.decision_id)

    with SQLiteResolutionService(
        database,
        Source(first, second, third),
        DuplicateAuthority(third.proposal.proposal_id),
        Clock(),
    ) as service:
        with pytest.raises(CapabilityGapCollisionError):
            service.resolve(second.decision.decision_id)
        assert service.get_by_promotion_id("0" * 64) is None
        with sqlite3.connect(database) as connection:
            assert connection.execute(
                "SELECT COUNT(*) FROM resolution_packages WHERE decision_id=?",
                (second.decision.decision_id,),
            ).fetchone()[0] == 0
