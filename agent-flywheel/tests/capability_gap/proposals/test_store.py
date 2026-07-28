from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from study_agent_devkit.capability_gap import (
    CapabilityGapCorruptionError,
    CapabilityGapValidationError,
)
from study_agent_devkit.capability_gap.proposal_store import _SQLiteProposalStore

from .test_contracts import make_package


def test_store_reopens_and_returns_the_exact_canonical_package(tmp_path: Path) -> None:
    database = tmp_path / "proposals.sqlite3"
    package = make_package()
    with _SQLiteProposalStore(database) as store:
        assert store._create_or_get(package).to_bytes() == package.to_bytes()
        assert store.lookup(package.proposal.evidence.candidate_gap_keys) == package
    with _SQLiteProposalStore(database) as reopened:
        result = reopened.get_by_gap_key("a" * 64)
        assert result is not None
        assert result.to_bytes() == package.to_bytes()


def test__create_or_get_is_idempotent_and_rejects_overlapping_cohorts(tmp_path: Path) -> None:
    database = tmp_path / "proposals.sqlite3"
    first = make_package("a" * 64)
    second = make_package("b" * 64)
    with _SQLiteProposalStore(database) as store:
        assert store._create_or_get(first).to_bytes() == first.to_bytes()
        assert store._create_or_get(first).to_bytes() == first.to_bytes()
        assert store._create_or_get(second).to_bytes() == second.to_bytes()
        # The store's member uniqueness is the final race-safe collision guard.
        overlapping = make_package("a" * 64)
        assert store._create_or_get(overlapping).to_bytes() == first.to_bytes()


def test_schema_version_and_exact_schema_are_fail_closed(tmp_path: Path) -> None:
    database = tmp_path / "proposals.sqlite3"
    with _SQLiteProposalStore(database):
        pass
    connection = sqlite3.connect(database)
    connection.execute("PRAGMA user_version = 99")
    connection.commit()
    connection.close()
    with pytest.raises(CapabilityGapCorruptionError):
        _SQLiteProposalStore(database)


def test_corrupt_package_projection_and_membership_are_rejected(tmp_path: Path) -> None:
    database = tmp_path / "proposals.sqlite3"
    package = make_package()
    with _SQLiteProposalStore(database) as store:
        store._create_or_get(package)
        store.connection.execute(
            "UPDATE proposal_packages SET proposal_id = ?",
            ("f" * 64,),
        )
        with pytest.raises(CapabilityGapCorruptionError):
            store.lookup(("a" * 64,))

    with _SQLiteProposalStore(database) as store:
        store.connection.execute(
            "UPDATE proposal_packages SET proposal_id = ?",
            (package.proposal.proposal_id,),
        )
        store.connection.execute("DELETE FROM proposal_members")
        with pytest.raises(CapabilityGapCorruptionError):
            store.lookup(("a" * 64,))


def test_foreign_key_corruption_is_rejected_before_reads(tmp_path: Path) -> None:
    database = tmp_path / "proposals.sqlite3"
    package = make_package()
    with _SQLiteProposalStore(database) as store:
        store._create_or_get(package)
        store.connection.execute("PRAGMA foreign_keys = OFF")
        store.connection.execute(
            "INSERT INTO proposal_members (proposal_pk, gap_key) VALUES (?, ?)",
            (999, "b" * 64),
        )
        store.connection.execute("PRAGMA foreign_keys = ON")
        with pytest.raises(CapabilityGapCorruptionError):
            store.lookup(("a" * 64,))


def test_invalid_package_does_not_open_a_write_transaction(tmp_path: Path) -> None:
    database = tmp_path / "proposals.sqlite3"
    with _SQLiteProposalStore(database) as store:
        with pytest.raises(CapabilityGapValidationError):
            store._create_or_get(object())  # type: ignore[arg-type]
        assert store.connection.execute("SELECT COUNT(*) FROM proposal_packages").fetchone()[0] == 0
