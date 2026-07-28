"""Compare-and-set maintainer resolution and accepted-only promotion outbox."""

from __future__ import annotations

import re
import sqlite3
from collections.abc import Callable
from contextlib import suppress
from datetime import UTC, datetime
from typing import Any, cast

from study_agent.state import canonical_json_bytes

from study_agent_devkit.flywheel.materialization import (
    PromotedRunInputV1,
    RunArtifactV1,
    plan_run,
    validate_materialization_plan,
)

from .contracts import (
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    CapabilityGapUnavailableError,
    CapabilityGapValidationError,
)
from .proposal_contracts import (
    DraftArtifactKind,
    ProposalDecisionPackageV1,
    RequestedAuthority,
)
from .resolution_contracts import (
    ApprovedArtifactV1,
    DecisionViewV1,
    FlywheelPromotionBundleV1,
    FlywheelPromotionReceiptV1,
    FlywheelPromotionSink,
    GapResolutionV1,
    GrillSubjectKind,
    ImplementationGoalV1,
    MaintainerResolutionAuthority,
    ProposalPackageSource,
    ResolutionClock,
    ResolutionCommandV1,
    ResolutionOutcome,
    _render_promotion_context,
    decision_view_for_package,
)
from .resolution_store import _SQLiteResolutionStore

_DIGEST = re.compile(r"^[0-9a-f]{64}$")
_OPAQUE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@-]{0,127}$")


class _CallableClock:
    def __init__(self, callback: Callable[[], datetime]) -> None:
        self._callback = callback

    def now(self) -> datetime:
        return self._callback()


class SQLiteResolutionService:
    """Resolve a decision once; the private store is never caller-visible."""

    def __init__(
        self,
        database: object,
        proposal_source: ProposalPackageSource,
        authority: MaintainerResolutionAuthority,
        clock: ResolutionClock | Callable[[], datetime],
        *,
        promotion_sink: FlywheelPromotionSink | None = None,
    ) -> None:
        if isinstance(database, _SQLiteResolutionStore):
            raise CapabilityGapValidationError("invalid_resolution_database")
        if not hasattr(proposal_source, "get_by_decision_id") or not hasattr(
            proposal_source, "get_by_proposal_id"
        ):
            raise CapabilityGapValidationError("invalid_proposal_source")
        if not hasattr(authority, "resolve"):
            raise CapabilityGapValidationError("invalid_resolution_authority")
        if callable(clock):
            self._clock: ResolutionClock = _CallableClock(clock)
        elif hasattr(clock, "now"):
            self._clock = clock
        else:
            raise CapabilityGapValidationError("invalid_resolution_clock")
        self._store = _SQLiteResolutionStore(database)
        self._proposal_source = proposal_source
        self._authority = authority
        self._promotion_sink = promotion_sink
        self._promotion_sink_id: str | None = None
        if promotion_sink is not None:
            try:
                sink_id = promotion_sink.sink_id
                apply = promotion_sink.apply
            except Exception:
                raise CapabilityGapValidationError("invalid_promotion_sink") from None
            if not callable(apply):
                raise CapabilityGapValidationError("invalid_promotion_sink")
            self._promotion_sink_id = _validate_digest(sink_id, "sink_id")

    def close(self) -> None:
        self._store.close()

    def __enter__(self) -> SQLiteResolutionService:
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()

    def get_promotion_by_decision_id(self, decision_id: str) -> FlywheelPromotionBundleV1 | None:
        _validate_digest(decision_id, "decision_id")
        row = self._store.get_by_decision_id(decision_id)
        return None if row is None else row[1]

    def get_by_promotion_id(self, promotion_id: str) -> FlywheelPromotionBundleV1 | None:
        _validate_digest(promotion_id, "promotion_id")
        row = self._store.get_by_promotion_id(promotion_id)
        return None if row is None else row[1]

    def materialize(self, promotion_id: str) -> FlywheelPromotionReceiptV1:
        """Materialize an accepted promotion through the injected idempotent sink."""
        _validate_digest(promotion_id, "promotion_id")
        if self._promotion_sink is None:
            existing = self._store.get_materialization_receipt(promotion_id)
            if existing is not None:
                return existing
            raise CapabilityGapUnavailableError("promotion_sink_unavailable")
        sink_id = self._promotion_sink_id
        if sink_id is None:
            raise CapabilityGapValidationError("invalid_promotion_sink")
        promotion, persisted = self._store.claim_materialization(promotion_id, sink_id)
        if persisted is not None:
            return persisted
        # The external sink is intentionally called with no SQLite transaction
        # held. Its exception is part of the adapter contract and propagates
        # unchanged, leaving the durable claim pending for retry.
        returned = self._promotion_sink.apply(promotion)
        if not isinstance(returned, FlywheelPromotionReceiptV1):
            raise CapabilityGapValidationError("invalid_promotion_receipt")
        try:
            returned_bytes = returned.to_bytes()
            canonical_returned = FlywheelPromotionReceiptV1.from_bytes(returned_bytes)
        except Exception:
            raise CapabilityGapValidationError("invalid_promotion_receipt") from None
        expected = FlywheelPromotionReceiptV1.for_bundle(promotion, sink_id)
        if canonical_returned.to_bytes() != expected.to_bytes():
            raise CapabilityGapCollisionError("promotion_receipt_mismatch")
        return self._store.commit_materialization_receipt(
            promotion_id, sink_id, canonical_returned
        )

    def resolve(self, decision_id: str) -> GapResolutionV1:
        _validate_digest(decision_id, "decision_id")
        # CAS lookup is deliberately before source, authority, and clock.
        persisted = self._store.get_by_decision_id(decision_id)
        if persisted is not None:
            return persisted[0]
        package = self._proposal_source.get_by_decision_id(decision_id)
        if package is None or not isinstance(package, ProposalDecisionPackageV1):
            raise CapabilityGapValidationError("unknown_decision")
        package = ProposalDecisionPackageV1.from_bytes(package.to_bytes())
        if (
            package.decision.decision_id != decision_id
            or package.decision.proposal_id != package.proposal.proposal_id
        ):
            raise CapabilityGapCorruptionError("source_decision_mismatch")
        view = decision_view_for_package(package)
        command = self._authority.resolve(view)
        if command is None:
            raise CapabilityGapCollisionError("resolution_authority_rejected")
        if not isinstance(command, ResolutionCommandV1):
            raise CapabilityGapValidationError("invalid_resolution_command")
        if (
            command.proposal_id != package.proposal.proposal_id
            or command.decision_id != package.decision.decision_id
        ):
            raise CapabilityGapCollisionError("resolution_authority_mismatch")
        self._validate_command(package, command, view)
        if command.outcome is ResolutionOutcome.DUPLICATE:
            target = self._proposal_source.get_by_proposal_id(
                command.duplicate_of_proposal_id or ""
            )
            if target is None or target.proposal.proposal_id == package.proposal.proposal_id:
                raise CapabilityGapValidationError("invalid_duplicate_target")
            target = ProposalDecisionPackageV1.from_bytes(target.to_bytes())
            if target.proposal.proposal_id != command.duplicate_of_proposal_id:
                raise CapabilityGapCorruptionError("duplicate_target_mismatch")
        now = self._clock.now()
        if not isinstance(now, datetime) or now.tzinfo is None or now.utcoffset() is None:
            raise CapabilityGapValidationError("invalid_resolution_clock")
        now = now.astimezone(UTC)
        authority_fp = command.authority_receipt_fingerprint
        resolution_id = GapResolutionV1.derive_id(
            package.proposal.proposal_id,
            decision_id,
            command,
            authority_fp,
            package.decision.requested_authority,
            now,
        )
        resolution = GapResolutionV1(
            1,
            resolution_id,
            package.proposal.proposal_id,
            decision_id,
            command.outcome,
            command.selected_option_id,
            command.defer_reference,
            command.duplicate_of_proposal_id,
            command.grill_receipts,
            authority_fp,
            package.decision.requested_authority,
            now,
        )
        promotion = None
        if command.outcome is ResolutionOutcome.ACCEPTED:
            promotion = self._build_promotion(package, resolution)
        connection = self._store.connection
        try:
            connection.execute("BEGIN IMMEDIATE")
            self._store._validate_schema()
            self._store._integrity(connection)
            self._store._validate_all(connection)
            existing = connection.execute(
                "SELECT * FROM resolution_packages WHERE decision_id=?", (decision_id,)
            ).fetchone()
            if existing is not None:
                winner, _ = self._store._decode_row(existing)
                connection.execute("COMMIT")
                return winner
            if command.outcome is ResolutionOutcome.DUPLICATE and self._store.has_inbound_duplicate(
                package.proposal.proposal_id, connection
            ):
                raise CapabilityGapCollisionError("duplicate_inbound_link")
            if command.outcome is ResolutionOutcome.DUPLICATE:
                target_row = connection.execute(
                    "SELECT * FROM resolution_packages WHERE proposal_id=?",
                    (command.duplicate_of_proposal_id,),
                ).fetchone()
                if target_row is not None:
                    target_resolution, _ = self._store._decode_row(target_row)
                    if target_resolution.outcome is ResolutionOutcome.DUPLICATE:
                        raise CapabilityGapCollisionError("duplicate_target_is_duplicate")
            self._store.insert(connection, resolution, promotion)
            self._store._validate_all(connection)
            connection.execute("COMMIT")
            return resolution
        except sqlite3.IntegrityError:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            persisted_winner = self._store.get_by_decision_id(decision_id)
            if persisted_winner is not None:
                return persisted_winner[0]
            raise CapabilityGapCollisionError("resolution_cas_conflict") from None
        except BaseException:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            raise

    @staticmethod
    def _validate_command(
        package: ProposalDecisionPackageV1, command: ResolutionCommandV1, view: DecisionViewV1
    ) -> None:
        if command.outcome is ResolutionOutcome.ACCEPTED:
            if command.selected_option_id not in view.option_ids:
                raise CapabilityGapValidationError("invalid_selected_option")
            expected = {
                (GrillSubjectKind.PROPOSAL.value, package.proposal.proposal_id),
                *((GrillSubjectKind.BEAD.value, item) for item in view.bead_ids),
            }
            actual = {(item.subject_kind.value, item.subject_id) for item in command.grill_receipts}
            if actual != expected or len(command.grill_receipts) != len(expected):
                raise CapabilityGapValidationError("invalid_grill_receipts")

    @staticmethod
    def _build_promotion(
        package: ProposalDecisionPackageV1, resolution: GapResolutionV1
    ) -> FlywheelPromotionBundleV1:
        draft = package.proposal.draft
        approved = tuple(
            ApprovedArtifactV1(item.kind, item.artifact_id, "approved", item.body, item.depends_on)
            for item in sorted(
                draft.artifacts,
                key=lambda item: (
                    {
                        DraftArtifactKind.ADR: 0,
                        DraftArtifactKind.SPEC: 1,
                        DraftArtifactKind.BEAD: 2,
                    }[item.kind],
                    item.artifact_id,
                ),
            )
        )
        spec = next(item for item in approved if item.kind is DraftArtifactKind.SPEC)
        adrs = tuple(
            RunArtifactV1("adr", item.artifact_id, item.body, item.depends_on)
            for item in approved
            if item.kind is DraftArtifactKind.ADR
        )
        tasks = tuple(
            RunArtifactV1("task", item.artifact_id, item.body, item.depends_on)
            for item in approved
            if item.kind is DraftArtifactKind.BEAD
        )
        context_body = _render_promotion_context(
            package.proposal.proposal_id,
            package.decision.decision_id,
            package.proposal.evidence_fingerprint,
            resolution.selected_option_id or "",
            package.proposal.evidence.candidate_gap_keys,
            package.proposal.evidence.candidates,
        )
        run_id = f"gap06-{resolution.resolution_id[:24]}"
        goal = None
        goal_json = None
        if (
            package.decision.requested_authority
            is RequestedAuthority.PLANNING_AND_IMPLEMENTATION_GOAL
        ):
            bead_ids = tuple(
                sorted(item.artifact_id for item in approved if item.kind is DraftArtifactKind.BEAD)
            )
            goal_id = ImplementationGoalV1.derive_id(
                package.proposal.proposal_id, spec.artifact_id, bead_ids, "authorized_not_started"
            )
            goal = ImplementationGoalV1(
                1,
                goal_id,
                package.proposal.proposal_id,
                spec.artifact_id,
                bead_ids,
                "authorized_not_started",
            )
            goal_json = canonical_json_bytes(cast(Any, goal.to_json()))
        run_input = PromotedRunInputV1(
            1,
            run_id,
            f"Capability gap {package.proposal.proposal_id}",
            "docs/specs/capability-gap-resolution-promotion.md",
            context_body,
            RunArtifactV1("spec", spec.artifact_id, spec.body, ()),
            adrs,
            tasks,
            goal_json,
        )
        plan = plan_run(run_input)
        if any(item.severity == "error" for item in validate_materialization_plan(plan)):
            raise CapabilityGapValidationError("invalid_materialization_plan")
        return FlywheelPromotionBundleV1.create(
            1,
            resolution.resolution_id,
            resolution.proposal_id,
            resolution.decision_id,
            package.proposal.evidence.candidate_gap_keys,
            resolution.selected_option_id or "",
            package.decision.requested_authority,
            approved,
            resolution.grill_receipts,
            plan,
            draft.verification,
            draft.non_goals,
            implementation_goal=goal,
        )


def _validate_digest(value: object, field: str) -> str:
    if type(value) is not str or _DIGEST.fullmatch(value) is None:
        raise CapabilityGapValidationError(f"invalid_{field}")
    return value


def _promotion_from_bytes(data: bytes) -> FlywheelPromotionBundleV1:
    return FlywheelPromotionBundleV1.from_bytes(data)


__all__ = ["SQLiteResolutionService"]
