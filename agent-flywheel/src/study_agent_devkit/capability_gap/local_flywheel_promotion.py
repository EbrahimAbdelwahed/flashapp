"""Descriptor-relative, no-clobber local Flywheel promotion sink."""

from __future__ import annotations

import ctypes
import errno
import os
import platform
import secrets
import stat
import sys
from collections.abc import Callable
from contextlib import suppress
from hashlib import sha256
from typing import NoReturn, cast

from study_agent_devkit.flywheel.materialization import validate_materialization_plan

from .contracts import (
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    CapabilityGapValidationError,
)
from .resolution_contracts import (
    FlywheelPromotionBundleV1,
    FlywheelPromotionReceiptV1,
)

_SINK_DOMAIN = b"study-agent-devkit-gap06-local-sink-v1\0"
_O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
_O_DIRECTORY = getattr(os, "O_DIRECTORY", 0)
_RENAME_NOREPLACE = 1
_RENAME_EXCL = 0x00000004
_RenameFunction = Callable[[int, bytes, int, bytes, int], int]


def _validation(message: str) -> NoReturn:
    raise CapabilityGapValidationError(message)


def _close(fd: int | None) -> None:
    if fd is not None:
        with suppress(OSError):
            os.close(fd)


def _open_directory(parent_fd: int, name: str) -> int:
    try:
        return os.open(name, os.O_RDONLY | _O_DIRECTORY | _O_NOFOLLOW, dir_fd=parent_fd)
    except OSError as exc:
        if exc.errno in {errno.ELOOP, errno.ENOTDIR}:
            _validation("symlink_or_non_directory")
        raise


def _ensure_directory(parent_fd: int, name: str) -> int:
    try:
        return _open_directory(parent_fd, name)
    except FileNotFoundError:
        with suppress(FileExistsError):
            os.mkdir(name, mode=0o755, dir_fd=parent_fd)
        return _open_directory(parent_fd, name)


def _fsync(fd: int) -> None:
    os.fsync(fd)


def _write_exact(parent_fd: int, name: str, data: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | _O_NOFOLLOW
    fd = os.open(name, flags, 0o644, dir_fd=parent_fd)
    try:
        offset = 0
        while offset < len(data):
            count = os.write(fd, data[offset:])
            if count <= 0:
                raise OSError(errno.EIO, "short file write")
            offset += count
        _fsync(fd)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size != len(data):
            raise OSError(errno.EIO, "staged file verification failed")
    finally:
        _close(fd)


def _immediate(expected: set[str], prefix: str) -> set[str]:
    result: set[str] = set()
    for path in expected:
        if prefix:
            if not path.startswith(prefix + "/"):
                continue
            remainder = path[len(prefix) + 1 :]
        else:
            remainder = path
        result.add(remainder.split("/", 1)[0])
    return result


def _read_file(fd: int, expected: bytes) -> None:
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode):
        raise CapabilityGapCollisionError("materialization_tree_conflict")
    if info.st_size != len(expected):
        raise CapabilityGapCollisionError("materialization_file_conflict")
    chunks: list[bytes] = []
    while True:
        chunk = os.read(fd, 1024 * 1024)
        if not chunk:
            break
        chunks.append(chunk)
    if b"".join(chunks) != expected:
        raise CapabilityGapCollisionError("materialization_file_conflict")


def _verify_tree(root_fd: int, files: dict[str, bytes]) -> None:
    expected_paths = set(files)
    expected_dirs: set[str] = set()
    for path in expected_paths:
        segments = path.split("/")
        expected_dirs.update("/".join(segments[:index]) for index in range(1, len(segments)))

    def visit(fd: int, prefix: str) -> None:
        expected_here = _immediate(expected_paths | expected_dirs, prefix)
        try:
            actual = set(os.listdir(fd))
        except TypeError:
            actual = set(os.listdir(f"/dev/fd/{fd}"))
        if actual != expected_here:
            raise CapabilityGapCollisionError("materialization_tree_conflict")
        for name in sorted(expected_here):
            path = f"{prefix}/{name}" if prefix else name
            if path in files:
                try:
                    child = os.open(
                        name, os.O_RDONLY | os.O_NONBLOCK | _O_NOFOLLOW, dir_fd=fd
                    )
                except OSError as exc:
                    if exc.errno in {errno.ELOOP, errno.ENOTDIR, errno.EISDIR, errno.ENXIO}:
                        raise CapabilityGapCollisionError(
                            "materialization_tree_conflict"
                        ) from exc
                    raise
                try:
                    _read_file(child, files[path])
                except OSError as exc:
                    if exc.errno in {errno.ELOOP, errno.ENOTDIR}:
                        raise CapabilityGapCollisionError("materialization_tree_conflict") from exc
                    raise
                finally:
                    _close(child)
            else:
                try:
                    child = os.open(
                        name, os.O_RDONLY | _O_DIRECTORY | _O_NOFOLLOW, dir_fd=fd
                    )
                except OSError as exc:
                    if exc.errno in {errno.ELOOP, errno.ENOTDIR, errno.EISDIR, errno.ENXIO}:
                        raise CapabilityGapCollisionError(
                            "materialization_tree_conflict"
                        ) from exc
                    raise
                try:
                    visit(child, path)
                except OSError as exc:
                    if exc.errno in {errno.ELOOP, errno.ENOTDIR}:
                        raise CapabilityGapCollisionError("materialization_tree_conflict") from exc
                    raise
                finally:
                    _close(child)

    visit(root_fd, "")


def _rename_adapter() -> tuple[_RenameFunction, int] | None:
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform == "darwin":
        function = getattr(libc, "renameatx_np", None)
        if function is None:
            return None
        function.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        function.restype = ctypes.c_int
        return cast(_RenameFunction, function), _RENAME_EXCL
    function = getattr(libc, "renameat2", None)
    if function is not None:
        function.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        function.restype = ctypes.c_int
        return cast(_RenameFunction, function), _RENAME_NOREPLACE
    syscall_numbers = {
        "x86_64": 316,
        "amd64": 316,
        "aarch64": 276,
        "arm64": 276,
        "armv7l": 382,
        "riscv64": 276,
    }
    number = syscall_numbers.get(platform.machine())
    syscall = getattr(libc, "syscall", None)
    if number is not None and syscall is not None:
        syscall.argtypes = [
            ctypes.c_long,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        syscall.restype = ctypes.c_long

        def renameat2(
            from_fd: int,
            from_name: bytes,
            to_fd: int,
            to_name: bytes,
            flags: int,
        ) -> int:
            return int(syscall(number, from_fd, from_name, to_fd, to_name, flags))

        return renameat2, _RENAME_NOREPLACE
    return None


def _require_rename_adapter() -> tuple[_RenameFunction, int]:
    adapter = _rename_adapter()
    if adapter is None:
        _validation("unsupported_no_clobber_rename")
    return adapter


def _atomic_noclobber_rename(
    source_fd: int, source_name: str, target_fd: int, target_name: str
) -> None:
    function, flags = _require_rename_adapter()
    result = function(
        source_fd,
        os.fsencode(source_name),
        target_fd,
        os.fsencode(target_name),
        flags,
    )
    if result != 0:
        error = ctypes.get_errno()
        if error == errno.EEXIST:
            raise FileExistsError(error, os.strerror(error), target_name)
        raise OSError(error, os.strerror(error), target_name)


def _remove_stage(runs_fd: int, stage_name: str, stage_fd: int) -> None:
    """Remove only the stage opened by this invocation, without following links."""
    try:
        named = os.stat(stage_name, dir_fd=runs_fd, follow_symlinks=False)
        opened = os.fstat(stage_fd)
        if (named.st_dev, named.st_ino) != (opened.st_dev, opened.st_ino):
            return

        def remove_dir(fd: int) -> None:
            for name in os.listdir(fd):
                try:
                    child = os.open(
                        name, os.O_RDONLY | _O_DIRECTORY | _O_NOFOLLOW, dir_fd=fd
                    )
                except OSError as exc:
                    if exc.errno in {errno.ELOOP, errno.ENOTDIR, errno.EISDIR, errno.ENXIO}:
                        os.unlink(name, dir_fd=fd)
                        continue
                    if exc.errno == errno.ENOENT:
                        continue
                    raise
                try:
                    remove_dir(child)
                finally:
                    _close(child)
                with suppress(FileNotFoundError):
                    os.rmdir(name, dir_fd=fd)

        remove_dir(stage_fd)
        named = os.stat(stage_name, dir_fd=runs_fd, follow_symlinks=False)
        opened = os.fstat(stage_fd)
        if (named.st_dev, named.st_ino) == (opened.st_dev, opened.st_ino):
            os.rmdir(stage_name, dir_fd=runs_fd)
            _fsync(runs_fd)
    except FileNotFoundError:
        return


class LocalFlywheelPromotionSink:
    """Materialize a validated plan below one immutable project root."""

    def __init__(self, project_root: str | os.PathLike[str]) -> None:
        raw = os.fspath(project_root)
        if not isinstance(raw, str) or not os.path.isabs(raw):
            _validation("invalid_project_root")
        if os.path.islink(raw) or not os.path.exists(raw) or not os.path.isdir(raw):
            _validation("invalid_project_root")
        absolute = os.path.abspath(raw)
        physical = os.path.realpath(raw)
        if absolute != raw:
            _validation("project_root_alias")
        self._project_root = physical
        root_info = os.stat(raw, follow_symlinks=False)
        if not stat.S_ISDIR(root_info.st_mode):
            _validation("invalid_project_root")
        self._root_identity = (root_info.st_dev, root_info.st_ino)
        self._sink_id = sha256(_SINK_DOMAIN + physical.encode("utf-8")).hexdigest()

    @property
    def sink_id(self) -> str:
        return self._sink_id

    def apply(self, bundle: FlywheelPromotionBundleV1) -> FlywheelPromotionReceiptV1:
        if not isinstance(bundle, FlywheelPromotionBundleV1):
            _validation("invalid_promotion_bundle")
        try:
            exact_bundle = FlywheelPromotionBundleV1.from_bytes(bundle.to_bytes())
        except (TypeError, ValueError, CapabilityGapCorruptionError):
            _validation("invalid_promotion_bundle")
        findings = validate_materialization_plan(exact_bundle.materialization_plan)
        if any(item.severity == "error" for item in findings):
            _validation("invalid_materialization_plan")
        plan = exact_bundle.materialization_plan
        files = {item.relative_path: item.content for item in plan.files}
        final_name = plan.run_id
        if "/" in final_name or "\\" in final_name or final_name in {"", ".", ".."}:
            _validation("invalid_run_id")
        # Resolve the primitive before creating docs/flywheel-runs or a stage.
        _require_rename_adapter()
        root_fd: int | None = None
        docs_fd: int | None = None
        runs_fd: int | None = None
        stage_fd: int | None = None
        stage_name: str | None = None
        try:
            root_fd = os.open(self._project_root, os.O_RDONLY | _O_DIRECTORY | _O_NOFOLLOW)
            root_info = os.fstat(root_fd)
            if (root_info.st_dev, root_info.st_ino) != self._root_identity:
                _validation("project_root_changed")
            docs_fd = _ensure_directory(root_fd, "docs")
            runs_fd = _ensure_directory(docs_fd, "flywheel-runs")
            _fsync(runs_fd)
            _fsync(docs_fd)
            _fsync(root_fd)
            try:
                final_fd = _open_directory(runs_fd, final_name)
            except FileNotFoundError:
                final_fd = None
            except CapabilityGapValidationError as exc:
                raise CapabilityGapCollisionError("materialization_tree_conflict") from exc
            if final_fd is not None:
                try:
                    _verify_tree(final_fd, files)
                    return FlywheelPromotionReceiptV1.for_bundle(exact_bundle, self.sink_id)
                finally:
                    _close(final_fd)
            for _ in range(32):
                candidate = f".{final_name}.stage-{secrets.token_hex(12)}"
                try:
                    os.mkdir(candidate, mode=0o755, dir_fd=runs_fd)
                    stage_name = candidate
                    break
                except FileExistsError:
                    continue
            if stage_name is None:
                raise OSError(errno.EEXIST, "unable to allocate staging directory")
            stage_fd = _open_directory(runs_fd, stage_name)
            directories = sorted(
                {
                    "/".join(item.relative_path.split("/")[:-1])
                    for item in plan.files
                    if "/" in item.relative_path
                },
                key=lambda path: (path.count("/"), path),
            )
            for directory in directories:
                parent = stage_fd
                opened: list[int] = []
                try:
                    for segment in directory.split("/"):
                        parent = _ensure_directory(parent, segment)
                        opened.append(parent)
                    _fsync(parent)
                finally:
                    for fd in reversed(opened):
                        _close(fd)
            for item in plan.files:
                parent = stage_fd
                opened = []
                try:
                    segments = item.relative_path.split("/")
                    for segment in segments[:-1]:
                        parent = _open_directory(parent, segment)
                        opened.append(parent)
                    _write_exact(parent, segments[-1], item.content)
                finally:
                    for fd in reversed(opened):
                        _close(fd)
            _verify_tree(stage_fd, files)
            _fsync(stage_fd)
            for directory in directories:
                fd = stage_fd
                opened = []
                try:
                    for segment in directory.split("/"):
                        fd = _open_directory(fd, segment)
                        opened.append(fd)
                    _fsync(fd)
                finally:
                    for fd in reversed(opened):
                        _close(fd)
            _fsync(runs_fd)
            _fsync(docs_fd)
            _fsync(root_fd)
            try:
                _atomic_noclobber_rename(runs_fd, stage_name, runs_fd, final_name)
            except FileExistsError:
                try:
                    final_fd = _open_directory(runs_fd, final_name)
                except CapabilityGapValidationError as exc:
                    raise CapabilityGapCollisionError("materialization_tree_conflict") from exc
                try:
                    _verify_tree(final_fd, files)
                    return FlywheelPromotionReceiptV1.for_bundle(exact_bundle, self.sink_id)
                finally:
                    _close(final_fd)
            _fsync(runs_fd)
            stage_name = None
            return FlywheelPromotionReceiptV1.for_bundle(exact_bundle, self.sink_id)
        finally:
            if stage_name is not None and runs_fd is not None and stage_fd is not None:
                _remove_stage(runs_fd, stage_name, stage_fd)
            _close(stage_fd)
            _close(runs_fd)
            _close(docs_fd)
            _close(root_fd)


__all__ = ["LocalFlywheelPromotionSink"]
