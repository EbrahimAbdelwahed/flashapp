from __future__ import annotations

import ast
import re
import sqlite3
from pathlib import Path

import pytest
from study_agent.feedback.contracts import RequestedOperationKind

from study_agent_devkit.capability_gap import (
    CapabilityGapCorruptionError,
    CapabilityGapUnavailableError,
    DecisionViewV1,
    DeliveryImportContext,
    FlywheelPromotionBundleV1,
    FlywheelPromotionReceiptV1,
    GapResolutionV1,
    LocalFlywheelPromotionSink,
    ProposalDecisionPackageV1,
    ProposalService,
    ReproductionRegistry,
    ReproductionResult,
    ReproductionStatus,
    RequestedAuthority,
    ResolutionCommandV1,
    ResolutionOutcome,
    SQLiteCapabilityGapStore,
    SQLiteResolutionService,
)
from study_agent_devkit.flywheel.materialization import validate_materialization_plan

from ._support import (
    Authority,
    Clock,
    import_to_proposal,
    public_export,
)


class CountingSink:
    def __init__(self, root: Path) -> None:
        self._delegate = LocalFlywheelPromotionSink(root)
        self.calls = 0

    @property
    def sink_id(self) -> str:
        return self._delegate.sink_id

    def apply(self, bundle: FlywheelPromotionBundleV1) -> FlywheelPromotionReceiptV1:
        self.calls += 1
        return self._delegate.apply(bundle)


class FailingSink:
    def __init__(self, sink_id: str) -> None:
        self._sink_id = sink_id
        self.calls = 0

    @property
    def sink_id(self) -> str:
        return self._sink_id

    def apply(self, _bundle: FlywheelPromotionBundleV1) -> FlywheelPromotionReceiptV1:
        self.calls += 1
        raise RuntimeError("pending sink")


def _files(root: Path) -> dict[str, bytes]:
    return {
        path.relative_to(root).as_posix(): path.read_bytes()
        for path in root.rglob("*")
        if path.is_file()
    }


def _run_files(root: Path, run_id: str) -> dict[str, bytes]:
    return _files(root / "docs" / "flywheel-runs" / run_id)


def _forbidden_state_paths(root: Path) -> set[str]:
    forbidden_names = {
        ".beads",
        ".br",
        "br.db",
        "dispatch",
        ".dispatch",
        "dispatch.json",
        "dispatch.packet",
        "dispatch.db",
        "dispatches",
        "goal-state.db",
        "goal-state.sqlite3",
        "implementation-goal.sqlite3",
        "implementation_goal.sqlite3",
        "task.db",
        "tasks.db",
        "task-state.db",
        "task-state.sqlite",
        "task-state.sqlite3",
        "task-state.json",
        "task_state.db",
        "task_state.sqlite",
        "task_state.sqlite3",
        "task_state.json",
        "tasks.sqlite3",
        "worker-state.sqlite3",
    }
    return {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.name in forbidden_names
    }


def _chain(
    tmp_path: Path,
    *,
    requested: RequestedAuthority = RequestedAuthority.PLANNING_ONLY,
    outcome: ResolutionOutcome = ResolutionOutcome.ACCEPTED,
) -> tuple[
    SQLiteResolutionService,
    ProposalService,
    ProposalDecisionPackageV1,
    Authority,
    CountingSink,
    GapResolutionV1,
    Clock,
]:
    payload, fingerprint, record = public_export(tmp_path)
    imported, package = import_to_proposal(tmp_path, payload, fingerprint, record, requested)
    imported.close()
    # The source passed to resolution is the reopened, persisted proposal
    # service, rather than an in-memory package fixture.
    proposal_source = ProposalService(tmp_path / "proposal.sqlite3", clock=Clock())
    sink = CountingSink(tmp_path)
    authority = Authority(outcome)
    clock = Clock()
    service = SQLiteResolutionService(
        tmp_path / "resolution.sqlite3",
        proposal_source,
        authority,
        clock,
        promotion_sink=sink,
    )
    resolution = service.resolve(package.decision.decision_id)
    return service, proposal_source, package, authority, sink, resolution, clock


def _close(service: SQLiteResolutionService, source: ProposalService) -> None:
    service.close()
    source.close()


def test_public_export_to_private_import_to_accepted_planning_only_run_is_closed(
    tmp_path: Path,
) -> None:
    service, source, package, authority, sink, resolution, _clock = _chain(tmp_path)
    try:
        promotion = service.get_promotion_by_decision_id(package.decision.decision_id)
        assert promotion is not None
        assert resolution.outcome is ResolutionOutcome.ACCEPTED
        assert promotion.implementation_goal is None
        assert promotion.required_gates == (
            "worker_briefs",
            "tests",
            "semantic_review",
            "publication_authority",
        )
        assert promotion.exclusions == ("github_issue", "repository_merge", "release", "deployment")
        assert validate_materialization_plan(promotion.materialization_plan) == ()

        first = service.materialize(promotion.promotion_id)
        second = service.materialize(promotion.promotion_id)
        assert second.to_bytes() == first.to_bytes()
        assert sink.calls == 1
        assert _run_files(tmp_path, promotion.materialization_plan.run_id) == {
            item.relative_path: item.content for item in promotion.materialization_plan.files
        }
        assert _forbidden_state_paths(tmp_path) == set()
        assert authority.calls == 1
    finally:
        _close(service, source)


def test_accepted_goal_contains_only_exact_authorized_not_started_artifact(tmp_path: Path) -> None:
    service, source, package, authority, sink, resolution, _clock = _chain(
        tmp_path, requested=RequestedAuthority.PLANNING_AND_IMPLEMENTATION_GOAL
    )
    try:
        promotion = service.get_promotion_by_decision_id(package.decision.decision_id)
        assert promotion is not None and promotion.implementation_goal is not None
        assert promotion.implementation_goal.status == "authorized_not_started"
        receipt = service.materialize(promotion.promotion_id)
        expected = {
            item.relative_path: item.content for item in promotion.materialization_plan.files
        }
        assert _run_files(tmp_path, receipt.run_id) == expected
        goal_path = (
            tmp_path
            / "docs"
            / "flywheel-runs"
            / receipt.run_id
            / "implementation-goal.json"
        )
        assert goal_path.read_bytes() == promotion.implementation_goal.to_bytes()
        assert _forbidden_state_paths(tmp_path) == set()
        assert resolution.outcome is ResolutionOutcome.ACCEPTED
        assert authority.calls == 1
        assert sink.calls == 1
    finally:
        _close(service, source)


@pytest.mark.parametrize("outcome", [ResolutionOutcome.REJECTED, ResolutionOutcome.DEFERRED])
def test_nonaccepted_resolution_creates_no_promotion_claim_receipt_or_run(
    tmp_path: Path, outcome: ResolutionOutcome
) -> None:
    service, source, package, _authority, sink, resolution, _clock = _chain(
        tmp_path, outcome=outcome
    )
    try:
        assert service.get_promotion_by_decision_id(package.decision.decision_id) is None
        with pytest.raises(CapabilityGapUnavailableError):
            service.materialize(resolution.resolution_id)
        with sqlite3.connect(tmp_path / "resolution.sqlite3") as connection:
            assert (
                connection.execute("SELECT COUNT(*) FROM materialization_claims").fetchone()[0]
                == 0
            )
        assert sink.calls == 0
        assert not (tmp_path / "docs").exists()
    finally:
        _close(service, source)


def test_duplicate_resolution_uses_one_reopened_persisted_proposal_source(
    tmp_path: Path,
) -> None:
    first_payload, first_fp, first_record = public_export(tmp_path)
    first_store, target = import_to_proposal(tmp_path, first_payload, first_fp, first_record)
    first_store.close()
    second_payload, second_fp, second_record = public_export(
        tmp_path,
        operation=RequestedOperationKind.EXTRACT_TEXT,
        database_name="public-second.sqlite3",
    )
    second_store, current = import_to_proposal(
        tmp_path,
        second_payload,
        second_fp,
        second_record,
        database_name="private-second.sqlite3",
    )
    second_store.close()

    class DuplicateAuthority:
        def __init__(self) -> None:
            self.calls = 0

        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            self.calls += 1
            return ResolutionCommandV1(
                1,
                view.proposal_id,
                view.decision_id,
                ResolutionOutcome.DUPLICATE,
                None,
                None,
                target.proposal.proposal_id,
                (),
            )

    source = ProposalService(tmp_path / "proposal.sqlite3", clock=Clock())
    authority = DuplicateAuthority()
    sink = CountingSink(tmp_path)
    service = SQLiteResolutionService(
        tmp_path / "duplicate.sqlite3", source, authority, Clock(), promotion_sink=sink
    )
    try:
        resolution = service.resolve(current.decision.decision_id)
        assert resolution.outcome is ResolutionOutcome.DUPLICATE
        assert service.get_promotion_by_decision_id(current.decision.decision_id) is None
        with pytest.raises(CapabilityGapUnavailableError):
            service.materialize(resolution.resolution_id)
        with sqlite3.connect(tmp_path / "duplicate.sqlite3") as connection:
            assert (
                connection.execute("SELECT COUNT(*) FROM materialization_claims").fetchone()[0]
                == 0
            )
        assert sink.calls == 0
        assert authority.calls == 1
    finally:
        _close(service, source)


def test_exact_resolution_retry_returns_winner_before_source_authority_or_clock(
    tmp_path: Path,
) -> None:
    service, source, package, authority, _sink, first, clock = _chain(tmp_path)
    source_calls: list[str] = []
    original = source.get_by_decision_id

    def counted(decision_id: str) -> ProposalDecisionPackageV1 | None:
        source_calls.append(decision_id)
        return original(decision_id)

    source.get_by_decision_id = counted  # type: ignore[method-assign]
    source_calls.clear()
    try:
        again = service.resolve(package.decision.decision_id)
        assert again.to_bytes() == first.to_bytes()
        assert source_calls == []
        assert authority.calls == 1
        assert clock.calls == 1
    finally:
        _close(service, source)


def test_materialization_loss_after_atomic_rename_converges_to_exact_tree_and_receipt(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service, source, package, _authority, sink, _resolution, _clock = _chain(tmp_path)
    promotion = service.get_promotion_by_decision_id(package.decision.decision_id)
    assert promotion is not None
    original = service._store.commit_materialization_receipt
    attempts = 0

    def lose_receipt(
        promotion_id: str,
        sink_id: str,
        expected_receipt: FlywheelPromotionReceiptV1,
    ) -> FlywheelPromotionReceiptV1:
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise RuntimeError("receipt persistence lost")
        return original(promotion_id, sink_id, expected_receipt)

    monkeypatch.setattr(service._store, "commit_materialization_receipt", lose_receipt)
    try:
        with pytest.raises(RuntimeError, match="receipt persistence lost"):
            service.materialize(promotion.promotion_id)
        expected = {
            item.relative_path: item.content for item in promotion.materialization_plan.files
        }
        assert _run_files(tmp_path, promotion.materialization_plan.run_id) == expected
    finally:
        _close(service, source)

    reopened_source = ProposalService(tmp_path / "proposal.sqlite3", clock=Clock())
    reopened = SQLiteResolutionService(
        tmp_path / "resolution.sqlite3",
        reopened_source,
        Authority(ResolutionOutcome.ACCEPTED),
        Clock(),
        promotion_sink=sink,
    )
    try:
        persisted = reopened.materialize(promotion.promotion_id)
        assert persisted.to_bytes() == FlywheelPromotionReceiptV1.for_bundle(
            promotion, sink.sink_id
        ).to_bytes()
        assert _run_files(tmp_path, promotion.materialization_plan.run_id) == expected
        assert sink.calls == 2
        assert reopened.materialize(promotion.promotion_id).to_bytes() == persisted.to_bytes()
        assert sink.calls == 2
    finally:
        _close(reopened, reopened_source)


@pytest.mark.parametrize(
    ("table", "column", "value"),
    [
        ("deliveries", "receipt_bytes", b"{}"),
        ("candidates", "dimensions_bytes", b"{}"),
        ("contributions", "record_bytes", b"{}"),
        ("reproductions", "evidence_digest", "not-a-digest"),
    ],
)
def test_persisted_import_boundaries_fail_closed_before_reproduction_or_filesystem(
    tmp_path: Path, table: str, column: str, value: bytes | str
) -> None:
    payload, fingerprint, record = public_export(tmp_path)
    imported, _package = import_to_proposal(tmp_path, payload, fingerprint, record)
    imported.close()
    with sqlite3.connect(tmp_path / "private.sqlite3") as connection:
        connection.execute(f"UPDATE {table} SET {column}=?", (value,))

    calls = 0
    registry = ReproductionRegistry()

    def reproduce(_record: object) -> ReproductionResult:
        nonlocal calls
        calls += 1
        return ReproductionResult(ReproductionStatus.REPRODUCED, "f" * 64)

    registry.register("fixture@e2e", record.dimensions, reproduce)
    retry = SQLiteCapabilityGapStore(tmp_path / "private.sqlite3")
    try:
        with pytest.raises(CapabilityGapCorruptionError):
            retry.import_bundle(
                payload,
                DeliveryImportContext.for_local_bundle(fingerprint),
                reproduction=registry,
            )
        assert calls == 0
        assert _forbidden_state_paths(tmp_path) == set()
        assert not (tmp_path / "docs").exists()
    finally:
        retry.close()


def test_corrupt_persisted_proposal_fails_before_builder_and_later_callbacks(
    tmp_path: Path,
) -> None:
    payload, fingerprint, record = public_export(tmp_path)
    imported, package = import_to_proposal(tmp_path, payload, fingerprint, record)
    candidate = imported.get_candidate(record.gap_key.value)
    imported.close()
    with sqlite3.connect(tmp_path / "proposal.sqlite3") as connection:
        connection.execute("UPDATE proposal_packages SET package_bytes=?", (b"{}",))
    builder_calls = 0

    def builder(_evidence: object) -> object:
        nonlocal builder_calls
        builder_calls += 1
        return object()

    retry = ProposalService(tmp_path / "proposal.sqlite3", clock=Clock())
    try:
        with pytest.raises(CapabilityGapCorruptionError):
            retry.create((candidate,), builder)  # type: ignore[arg-type]
        assert builder_calls == 0
        assert package.proposal.proposal_id
        assert _forbidden_state_paths(tmp_path) == set()
    finally:
        retry.close()


@pytest.mark.parametrize("column", ["resolution_bytes", "promotion_bytes"])
def test_corrupt_resolution_or_promotion_fails_before_authority_sink_or_filesystem(
    tmp_path: Path, column: str
) -> None:
    service, source, package, _authority, _sink, _resolution, _clock = _chain(tmp_path)
    _close(service, source)
    with sqlite3.connect(tmp_path / "resolution.sqlite3") as connection:
        connection.execute(f"UPDATE resolution_packages SET {column}=?", (b"{}",))
    retry_source = ProposalService(tmp_path / "proposal.sqlite3", clock=Clock())
    authority = Authority(ResolutionOutcome.ACCEPTED)
    sink = CountingSink(tmp_path)
    retry = SQLiteResolutionService(
        tmp_path / "resolution.sqlite3", retry_source, authority, Clock(), promotion_sink=sink
    )
    try:
        with pytest.raises(CapabilityGapCorruptionError):
            retry.resolve(package.decision.decision_id)
        assert authority.calls == 0
        assert sink.calls == 0
        assert not (tmp_path / "docs").exists()
    finally:
        _close(retry, retry_source)


@pytest.mark.parametrize("corruption", ["claim", "receipt"])
def test_corrupt_materialization_claim_or_receipt_fails_before_sink_and_preserves_tree(
    tmp_path: Path, corruption: str
) -> None:
    service, source, package, _authority, sink, _resolution, _clock = _chain(tmp_path)
    promotion = service.get_promotion_by_decision_id(package.decision.decision_id)
    assert promotion is not None
    expected = {item.relative_path: item.content for item in promotion.materialization_plan.files}
    if corruption == "claim":
        failing = FailingSink(sink.sink_id)
        service._promotion_sink = failing
        with pytest.raises(RuntimeError, match="pending sink"):
            service.materialize(promotion.promotion_id)
        expected = {}
    else:
        service.materialize(promotion.promotion_id)
    _close(service, source)
    with sqlite3.connect(tmp_path / "resolution.sqlite3") as connection:
        if corruption == "claim":
            connection.execute(
                "UPDATE materialization_claims SET sink_id=? WHERE promotion_id=?",
                ("not-a-digest", promotion.promotion_id),
            )
        else:
            connection.execute(
                "UPDATE materialization_claims SET receipt_bytes=? WHERE promotion_id=?",
                (b"{}", promotion.promotion_id),
            )
    retry_source = ProposalService(tmp_path / "proposal.sqlite3", clock=Clock())
    retry_sink = CountingSink(tmp_path)
    retry = SQLiteResolutionService(
        tmp_path / "resolution.sqlite3",
        retry_source,
        Authority(ResolutionOutcome.ACCEPTED),
        Clock(),
        promotion_sink=retry_sink,
    )
    try:
        with pytest.raises(CapabilityGapCorruptionError):
            retry.materialize(promotion.promotion_id)
        assert retry_sink.calls == 0
        assert _run_files(tmp_path, promotion.materialization_plan.run_id) == expected
    finally:
        _close(retry, retry_source)


def test_capability_gap_modules_have_ast_import_and_call_firewall() -> None:
    root = Path(__file__).parents[3] / "src" / "study_agent_devkit" / "capability_gap"
    paths = (
        root / "store.py",
        root / "proposal_contracts.py",
        root / "proposal_service.py",
        root / "proposal_store.py",
        root / "resolution_contracts.py",
        root / "resolution_service.py",
        root / "resolution_store.py",
        root / "local_flywheel_promotion.py",
    )
    forbidden = {
        "anthropic",
        "br",
        "codex",
        "deployment",
        "git",
        "github",
        "httpx",
        "openai",
        "publication",
        "publish",
        "provider",
        "model",
        "network",
        "http",
        "requests",
        "release",
        "socket",
        "spawn",
        "subprocess",
        "urllib",
        "worker",
        "product",
        "tutor",
        "learner",
        "dispatch",
    }
    forbidden_goal_calls = ("create_goal", "goal_api", "resume_goal", "start_goal", "update_goal")
    forbidden_effect_methods = (".deploy", ".merge", ".publish", ".release", ".spawn")

    def has_forbidden_segment(value: str) -> bool:
        segments = [segment for segment in re.split(r"[._]+", value.lower()) if segment]
        return any(segment in forbidden or segment.startswith("http") for segment in segments)

    for path in paths:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported = [alias.name.lower() for alias in node.names]
                assert not any(has_forbidden_segment(name) for name in imported), path
            elif isinstance(node, ast.ImportFrom):
                module = (node.module or "").lower()
                assert not has_forbidden_segment(module), path
            elif isinstance(node, ast.Call):
                function = ast.unparse(node.func).lower()
                assert not has_forbidden_segment(function), path
                assert not any(name in function for name in forbidden_goal_calls), path
                assert not function.endswith(forbidden_effect_methods), path
