from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Any

import pytest

import study_agent_devkit.capability_gap.local_flywheel_promotion as sink_module
from study_agent_devkit.capability_gap import (
    CapabilityGapCollisionError,
    CapabilityGapUnavailableError,
    CapabilityGapValidationError,
    FlywheelPromotionBundleV1,
    LocalFlywheelPromotionSink,
)
from study_agent_devkit.flywheel.materialization import (
    ValidationFindingV1,
    validate_materialization_plan,
)

from ._support import accepted_bundle


def _files(bundle: FlywheelPromotionBundleV1) -> dict[str, bytes]:
    return {item.relative_path: item.content for item in bundle.materialization_plan.files}


def test_local_sink_writes_exact_validated_tree_without_dispatch_side_effects(
    tmp_path: Path,
) -> None:
    sink = LocalFlywheelPromotionSink(tmp_path)
    service, bundle, _ = accepted_bundle(tmp_path, sink=sink)
    receipt = sink.apply(bundle)
    plan = bundle.materialization_plan
    assert validate_materialization_plan(plan) == ()
    run = tmp_path / "docs" / "flywheel-runs" / plan.run_id
    actual = {
        path.relative_to(run).as_posix(): path.read_bytes()
        for path in run.rglob("*")
        if path.is_file()
    }
    assert actual == _files(bundle)
    assert receipt.run_id == plan.run_id
    assert not list(tmp_path.glob("**/*dispatch*"))
    assert not list(tmp_path.glob("**/br"))
    assert not list(tmp_path.glob("**/implementation-goal.sqlite*"))
    expected: set[str] = set()
    for path in _files(bundle):
        parts = path.split("/")
        expected.update(
            f"{'/'.join(parts[:index])}"
            for index in range(1, len(parts))
        )
        expected.add(path)
    assert sorted(
        path.relative_to(run).as_posix() for path in run.rglob("*")
    ) == sorted(expected)
    assert sink.apply(bundle).to_bytes() == receipt.to_bytes()
    service.close()


def test_local_sink_allows_warning_only_plan_findings(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    sink = LocalFlywheelPromotionSink(tmp_path)
    service, bundle, _ = accepted_bundle(tmp_path, sink=sink)
    monkeypatch.setattr(
        sink_module,
        "validate_materialization_plan",
        lambda _: (
            ValidationFindingV1(1, "warning", "open-questions", "spec/feature-spec.md", "review"),
        ),
    )
    assert sink.apply(bundle).run_id == bundle.materialization_plan.run_id
    service.close()


@pytest.mark.parametrize("conflict", ["changed", "missing", "extra", "file_dir"])
def test_existing_tree_conflicts_fail_closed(tmp_path: Path, conflict: str) -> None:
    sink = LocalFlywheelPromotionSink(tmp_path)
    service, bundle, _ = accepted_bundle(tmp_path, sink=sink)
    sink.apply(bundle)
    run = tmp_path / "docs" / "flywheel-runs" / bundle.materialization_plan.run_id
    files = _files(bundle)
    if conflict == "changed":
        target = run / next(iter(files))
        target.write_bytes(target.read_bytes() + b"changed")
    elif conflict == "missing":
        (run / next(iter(files))).unlink()
    elif conflict == "extra":
        (run / "extra.txt").write_bytes(b"extra")
    else:
        relative = next(path for path in files if "/" in path)
        directory = run / relative.split("/", 1)[0]
        shutil.rmtree(directory)
        directory.write_bytes(b"not a directory")
    with pytest.raises(
        CapabilityGapCollisionError, match=r"materialization_(tree|file)_conflict"
    ):
        sink.apply(bundle)
    service.close()


def test_existing_fifo_leaf_is_rejected_without_blocking(tmp_path: Path) -> None:
    sink = LocalFlywheelPromotionSink(tmp_path)
    service, bundle, _ = accepted_bundle(tmp_path, sink=sink)
    sink.apply(bundle)
    run = tmp_path / "docs" / "flywheel-runs" / bundle.materialization_plan.run_id
    target = run / next(path for path in _files(bundle) if "/" not in path)
    target.unlink()
    os.mkfifo(target)
    with pytest.raises(CapabilityGapCollisionError, match="materialization_tree_conflict"):
        sink.apply(bundle)
    service.close()


@pytest.mark.parametrize("kind", ["root", "docs", "runs", "final", "intermediate", "file"])
def test_symlink_root_and_every_materialization_boundary_is_rejected(
    tmp_path: Path, kind: str
) -> None:
    outside = tmp_path / "outside"
    outside.mkdir()
    if kind == "root":
        root = tmp_path / "root-link"
        root.symlink_to(outside, target_is_directory=True)
        with pytest.raises(CapabilityGapValidationError):
            LocalFlywheelPromotionSink(root)
        return

    root = tmp_path / "project"
    root.mkdir()
    sink = LocalFlywheelPromotionSink(root)
    service, bundle, _ = accepted_bundle(tmp_path, sink=LocalFlywheelPromotionSink(root))
    plan = bundle.materialization_plan
    if kind == "docs":
        (root / "docs").symlink_to(outside, target_is_directory=True)
    elif kind == "runs":
        (root / "docs").mkdir()
        (root / "docs" / "flywheel-runs").symlink_to(outside, target_is_directory=True)
    else:
        # Build the canonical parent, then place the symlink at the selected
        # final, nested-directory, or file boundary before applying.
        (root / "docs" / "flywheel-runs").mkdir(parents=True)
        final = root / "docs" / "flywheel-runs" / plan.run_id
        final.mkdir()
        files = _files(bundle)
        if kind == "final":
            shutil.rmtree(final)
            final.symlink_to(outside, target_is_directory=True)
        elif kind == "intermediate":
            directory = next(path.split("/", 1)[0] for path in files if "/" in path)
            (final / directory).symlink_to(outside, target_is_directory=True)
        else:
            file_path = final / next(path for path in files if "/" not in path)
            file_path.symlink_to(outside / "file")
    with pytest.raises((CapabilityGapValidationError, CapabilityGapCollisionError)):
        sink.apply(bundle)
    service.close()


def test_stage_failure_leaves_no_final_run_or_stage_directory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    sink = LocalFlywheelPromotionSink(tmp_path)
    service, bundle, _ = accepted_bundle(tmp_path, sink=sink)
    original_write = sink_module._write_exact
    calls = 0

    def fail_after_one(*args: Any, **kwargs: Any) -> None:
        nonlocal calls
        calls += 1
        if calls == 2:
            raise OSError("stage write failed")
        original_write(*args, **kwargs)

    monkeypatch.setattr(sink_module, "_write_exact", fail_after_one)
    with pytest.raises(OSError, match="stage write failed"):
        sink.apply(bundle)
    runs = tmp_path / "docs" / "flywheel-runs"
    assert not (runs / bundle.materialization_plan.run_id).exists()
    assert not list(runs.glob(f".{bundle.materialization_plan.run_id}.stage-*"))
    service.close()


def test_orphan_stage_is_ignored_and_never_promoted(tmp_path: Path) -> None:
    sink = LocalFlywheelPromotionSink(tmp_path)
    service, bundle, _ = accepted_bundle(tmp_path, sink=sink)
    runs = tmp_path / "docs" / "flywheel-runs"
    runs.mkdir(parents=True)
    orphan = runs / f".{bundle.materialization_plan.run_id}.stage-orphan"
    orphan.mkdir()
    (orphan / "junk").write_bytes(b"junk")
    sink.apply(bundle)
    assert orphan.is_dir()
    assert (runs / bundle.materialization_plan.run_id).is_dir()
    service.close()


def test_no_clobber_rename_race_never_overwrites_conflicting_run(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    sink = LocalFlywheelPromotionSink(tmp_path)
    service, bundle, _ = accepted_bundle(tmp_path, sink=sink)
    runs = tmp_path / "docs" / "flywheel-runs"
    original = runs / bundle.materialization_plan.run_id

    def race(*args: object, **kwargs: object) -> None:
        original.mkdir()
        (original / "race").write_bytes(b"preserve")
        raise FileExistsError

    monkeypatch.setattr(sink_module, "_atomic_noclobber_rename", race)
    with pytest.raises(CapabilityGapCollisionError):
        sink.apply(bundle)
    assert (original / "race").read_bytes() == b"preserve"
    service.close()


def test_rejected_resolution_produces_no_tree(tmp_path: Path) -> None:
    from study_agent_devkit.capability_gap import SQLiteResolutionService

    from ..test_service import Clock, Source, package
    from ._support import RejectedAuthority

    current = package()
    sink = LocalFlywheelPromotionSink(tmp_path)
    service = SQLiteResolutionService(
        tmp_path / "rejected.sqlite3",
        Source(current),
        RejectedAuthority(),
        Clock(),
        promotion_sink=sink,
    )
    resolution = service.resolve(current.decision.decision_id)
    with pytest.raises(CapabilityGapUnavailableError):
        service.materialize(resolution.resolution_id)
    assert not (tmp_path / "docs").exists()
    service.close()
