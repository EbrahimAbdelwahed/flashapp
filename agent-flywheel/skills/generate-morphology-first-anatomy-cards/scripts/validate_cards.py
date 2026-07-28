#!/usr/bin/env python3
"""Validate morphology-first anatomy card JSON without third-party packages."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "morphology-first-anatomy-cards@1"
ROLES = {"macro_reconstruction", "atomic_discrimination"}
NOTE_TYPES = {"basic", "cloze"}
GENERATORS = {"codex", "human", "model"}
FAMILIES = {
    "atomic_locator",
    "definition",
    "classification",
    "topology",
    "comparison",
    "process",
    "muscle_profile",
    "contextual_cloze",
}
COGNITIVE_FUNCTIONS = {
    "locate",
    "define",
    "classify",
    "reconstruct",
    "compare",
    "sequence",
    "recall_profile",
    "complete_relation",
}
REQUIRED_CARD_KEYS = {
    "front",
    "back",
    "tags",
    "note_type",
    "role",
    "family",
    "cognitive_function",
    "back_lines",
    "checklist",
    "source_refs",
    "evidence",
    "grounded_claims",
    "rationale",
    "quality",
    "provenance",
}
REQUIRED_SUMMARY_KEYS = {
    "card_count",
    "macro_count",
    "atomic_count",
    "cloze_count",
    "source_count",
    "card_budget",
    "coverage",
    "source_gaps",
    "provenance_note",
}
ALLOWED_TAG = re.compile(r"</?b>|<br\s*/?>", re.IGNORECASE)
ANY_TAG = re.compile(r"<[^>]*>")
MARKDOWN = re.compile(r"(^|\n)\s{0,3}(#{1,6}\s|[-*+]\s|\d+\.\s)|\*\*|__|`", re.MULTILINE)
CLOZE = re.compile(r"\{\{c([1-9]\d*)::(.+?)(?:::[^{}]*)?\}\}", re.DOTALL)
SHA256 = re.compile(r"[0-9a-f]{64}")
CARDINALITY_CUE = re.compile(r"\((\d+)\)\s*\?\s*$")
LEGACY_CARDINALITY_CUE = re.compile(r"\?\s*\((\d+)\)\s*$")


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, location: str, message: str) -> None:
        self.errors.append(f"{location}: {message}")

    def warn(self, location: str, message: str) -> None:
        self.warnings.append(f"{location}: {message}")


def is_nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def visible_text(value: str) -> str:
    return re.sub(r"\s+", " ", ALLOWED_TAG.sub(" ", value)).strip()


def normalized(value: str) -> str:
    return re.sub(r"\W+", " ", visible_text(value).casefold()).strip()


def check_anki_field(value: Any, location: str, report: Report, *, allow_empty: bool) -> str:
    if not isinstance(value, str):
        report.error(location, "must be a string")
        return ""
    if not allow_empty and not value.strip():
        report.error(location, "must not be empty")
    residue = ALLOWED_TAG.sub("", value)
    if ANY_TAG.search(residue):
        report.error(location, "contains HTML other than <b> and <br>")
    if MARKDOWN.search(residue):
        report.error(location, "contains Markdown; use plain text plus <b>/<br>")
    if residue.count("<") or residue.count(">"):
        report.error(location, "contains an unrecognized or malformed angle-bracket construct")
    bold_open = False
    for token in re.findall(r"</?b>", value, re.IGNORECASE):
        if token.casefold() == "<b>":
            if bold_open:
                report.error(location, "has improperly nested <b> tags")
                break
            bold_open = True
        elif not bold_open:
            report.error(location, "has a closing </b> tag without a matching <b>")
            break
        else:
            bold_open = False
    else:
        if bold_open:
            report.error(location, "has an unclosed <b> tag")
    return value


def check_string_list(value: Any, location: str, report: Report, *, nonempty: bool) -> list[str]:
    if not isinstance(value, list):
        report.error(location, "must be an array")
        return []
    if nonempty and not value:
        report.error(location, "must not be empty")
    result: list[str] = []
    for index, item in enumerate(value):
        if not is_nonempty_string(item):
            report.error(f"{location}[{index}]", "must be a non-empty string")
        else:
            result.append(item.strip())
    if len(result) != len(set(result)):
        report.error(location, "contains duplicates")
    return result


def check_provenance(value: Any, location: str, report: Report) -> None:
    required = {"generated_by", "provider", "model", "prompt_version"}
    if not isinstance(value, dict):
        report.error(location, "must be an object")
        return
    missing = required - value.keys()
    if missing:
        report.error(location, f"missing keys: {', '.join(sorted(missing))}")
        return
    generated_by = value.get("generated_by")
    if not isinstance(generated_by, str) or generated_by not in GENERATORS:
        report.error(f"{location}.generated_by", f"must be one of {sorted(GENERATORS)}")
    if not is_nonempty_string(value.get("prompt_version")):
        report.error(f"{location}.prompt_version", "must be a non-empty string")
    provider = value.get("provider")
    model = value.get("model")
    if generated_by == "model":
        if provider != "deepseek":
            report.error(f"{location}.provider", "external model processing must use deepseek")
        if not is_nonempty_string(model):
            report.error(f"{location}.model", "must identify the DeepSeek model")
    elif provider is not None or model is not None:
        report.error(location, "provider and model must be null unless generated_by is model")


def check_evidence(value: Any, refs: set[str], location: str, report: Report) -> set[str]:
    if not isinstance(value, list) or not value:
        report.error(location, "must be a non-empty array")
        return set()
    evidenced: set[str] = set()
    for index, item in enumerate(value):
        item_loc = f"{location}[{index}]"
        if not isinstance(item, dict):
            report.error(item_loc, "must be an object")
            continue
        if set(item) != {"source_ref", "text"}:
            report.error(item_loc, "must contain exactly source_ref and text")
            continue
        source_ref = item.get("source_ref")
        text = item.get("text")
        if not is_nonempty_string(source_ref) or source_ref not in refs:
            report.error(f"{item_loc}.source_ref", "must match a card source_ref")
        else:
            evidenced.add(source_ref)
        if not is_nonempty_string(text):
            report.error(f"{item_loc}.text", "must be a non-empty source excerpt or observation")
    missing = refs - evidenced
    if missing:
        report.error(location, f"missing evidence for source refs: {', '.join(sorted(missing))}")
    return evidenced


def check_images(value: Any, refs: set[str], location: str, report: Report) -> None:
    if value is None:
        return
    if not isinstance(value, list):
        report.error(location, "must be an array")
        return
    if len(value) > 1:
        report.error(location, "must contain at most one verified image")
    required = {"media", "sha256", "verified", "source_ref", "alt"}
    for index, item in enumerate(value):
        item_loc = f"{location}[{index}]"
        if not isinstance(item, dict):
            report.error(item_loc, "must be an object")
            continue
        if set(item) != required:
            report.error(item_loc, f"must contain exactly: {', '.join(sorted(required))}")
            continue
        media = item.get("media")
        if not is_nonempty_string(media) or Path(media).name != media or media in {".", ".."}:
            report.error(f"{item_loc}.media", "must be a basename-only media filename")
        if item.get("verified") is not True:
            report.error(f"{item_loc}.verified", "must be true")
        if not isinstance(item.get("sha256"), str) or not SHA256.fullmatch(item["sha256"]):
            report.error(f"{item_loc}.sha256", "must be a lowercase SHA-256 digest")
        if item.get("source_ref") not in refs:
            report.error(f"{item_loc}.source_ref", "must match a card source_ref")
        if not is_nonempty_string(item.get("alt")):
            report.error(f"{item_loc}.alt", "must be meaningful non-empty text")


def check_grounded_claims(value: Any, refs: set[str], location: str, report: Report) -> None:
    if not isinstance(value, list) or not value:
        report.error(location, "must be a non-empty array")
        return
    for index, item in enumerate(value):
        item_loc = f"{location}[{index}]"
        if not isinstance(item, dict) or set(item) != {"claim", "source_refs"}:
            report.error(item_loc, "must contain exactly claim and source_refs")
            continue
        if not is_nonempty_string(item.get("claim")):
            report.error(f"{item_loc}.claim", "must be a non-empty string")
        claim_refs = set(check_string_list(item.get("source_refs"), f"{item_loc}.source_refs", report, nonempty=True))
        if not claim_refs <= refs:
            report.error(f"{item_loc}.source_refs", "must be a subset of card source_refs")


def check_quality(value: Any, images: Any, location: str, report: Report) -> None:
    required = {"factual_review", "overload", "image_status"}
    if not isinstance(value, dict) or set(value) != required:
        report.error(location, f"must contain exactly: {', '.join(sorted(required))}")
        return
    factual_review = value.get("factual_review")
    if not isinstance(factual_review, str) or factual_review not in {"source_checked", "needs_review"}:
        report.error(f"{location}.factual_review", "must be source_checked or needs_review")
    if value.get("overload") != "pass":
        report.error(f"{location}.overload", "must be pass")
    expected_image_status = "verified" if images else "none"
    if value.get("image_status") != expected_image_status:
        report.error(f"{location}.image_status", f"must be {expected_image_status!r}")


def check_card(card: Any, index: int, report: Report) -> tuple[str, str, str, set[str]]:
    location = f"cards[{index}]"
    if not isinstance(card, dict):
        report.error(location, "must be an object")
        return "", "", "", set()
    missing = REQUIRED_CARD_KEYS - card.keys()
    if missing:
        report.error(location, f"missing keys: {', '.join(sorted(missing))}")

    front = check_anki_field(card.get("front"), f"{location}.front", report, allow_empty=False)
    note_type = card.get("note_type")
    role = card.get("role")
    family = card.get("family")
    cognitive_function = card.get("cognitive_function")
    allow_empty_back = note_type == "cloze"
    back = check_anki_field(card.get("back"), f"{location}.back", report, allow_empty=allow_empty_back)

    if not isinstance(note_type, str) or note_type not in NOTE_TYPES:
        report.error(f"{location}.note_type", f"must be one of {sorted(NOTE_TYPES)}")
    if not isinstance(role, str) or role not in ROLES:
        report.error(f"{location}.role", f"must be one of {sorted(ROLES)}")
    if not isinstance(family, str) or family not in FAMILIES:
        report.error(f"{location}.family", f"must be one of {sorted(FAMILIES)}")
    if not isinstance(cognitive_function, str) or cognitive_function not in COGNITIVE_FUNCTIONS:
        report.error(f"{location}.cognitive_function", f"must be one of {sorted(COGNITIVE_FUNCTIONS)}")
    if note_type == "cloze":
        if role != "atomic_discrimination":
            report.error(location, "Cloze cards must use atomic_discrimination")
        if not CLOZE.search(front):
            report.error(f"{location}.front", "Cloze card has no valid {{c1::...}} deletion")
        if front.count("{{") != front.count("}}"):
            report.error(f"{location}.front", "has unbalanced Cloze delimiters")
        spans = CLOZE.findall(front)
        indices = {index for index, _ in spans}
        if not 2 <= len(spans) <= 4:
            report.error(f"{location}.front", "Cloze cards require 2-4 deletion spans")
        if len(indices) > 2:
            report.error(f"{location}.front", "Cloze cards may use at most two deletion indices")
        if family != "contextual_cloze" or cognitive_function != "complete_relation":
            report.error(location, "Cloze cards require contextual_cloze and complete_relation")
    elif CLOZE.search(front):
        report.error(f"{location}.front", "Basic card must not contain Cloze syntax")

    if note_type == "basic":
        if "?" not in front:
            report.error(f"{location}.front", "Basic card must ask an explicit question")
        elif front.count("?") > 1:
            report.warn(f"{location}.front", "contains multiple questions; prefer one bounded retrieval prompt")
        if re.match(r"\s*descrivi\b", visible_text(front), re.IGNORECASE):
            report.warn(f"{location}.front", "starts with 'Descrivi'; prefer a more precise retrieval-key question")

    front_without_valid_clozes = CLOZE.sub("", front)
    if "{{" in front_without_valid_clozes or "}}" in front_without_valid_clozes:
        report.error(f"{location}.front", "contains residual or malformed Cloze delimiters")
    if "{{" in back or "}}" in back:
        report.error(f"{location}.back", "must not contain Cloze delimiters")

    tags = check_string_list(card.get("tags"), f"{location}.tags", report, nonempty=True)
    for tag in tags:
        if tag != tag.casefold() or re.search(r"\s", tag):
            report.error(f"{location}.tags", f"tag must be lowercase and contain no spaces: {tag!r}")
    refs = set(check_string_list(card.get("source_refs"), f"{location}.source_refs", report, nonempty=True))
    check_evidence(card.get("evidence"), refs, f"{location}.evidence", report)
    images = card.get("image_refs")
    check_images(images, refs, f"{location}.image_refs", report)
    check_grounded_claims(card.get("grounded_claims"), refs, f"{location}.grounded_claims", report)
    if not is_nonempty_string(card.get("rationale")):
        report.error(f"{location}.rationale", "must be a non-empty string")
    check_provenance(card.get("provenance"), f"{location}.provenance", report)
    check_quality(card.get("quality"), images, f"{location}.quality", report)

    back_lines = card.get("back_lines")
    if not isinstance(back_lines, list) or (not back_lines and back):
        report.error(f"{location}.back_lines", "must be a non-empty array when back is non-empty")
        lines: list[str] = []
    else:
        lines = []
        for line_index, line in enumerate(back_lines):
            checked = check_anki_field(line, f"{location}.back_lines[{line_index}]", report, allow_empty=False)
            if "<br" in checked.casefold():
                report.error(f"{location}.back_lines[{line_index}]", "must contain one semantic line without <br>")
            lines.append(checked)
        if "<br>".join(lines) != back:
            report.error(f"{location}.back_lines", "must join with <br> to exactly equal back")

    checklist = check_string_list(card.get("checklist"), f"{location}.checklist", report, nonempty=False)
    if len(checklist) > 5:
        report.error(f"{location}.checklist", "must contain at most five cues")
    bracket = re.search(r"\[([^\]]+)\]", front)
    front_cues = [cue.strip().casefold() for cue in bracket.group(1).split(" - ")] if bracket else []
    if checklist:
        if len(checklist) != len(lines):
            report.error(f"{location}.checklist", "must map one-to-one to back_lines")
        if [cue.casefold() for cue in checklist] != front_cues:
            report.error(f"{location}.checklist", "must match bracketed front cues in order")
    elif bracket:
        report.error(f"{location}.checklist", "must record bracketed front cues")
    if checklist and any("<b>" not in line.casefold() for line in lines):
        report.warn(f"{location}.back_lines", "named checklist dimensions should use stable <b> labels")

    cardinality_match = CARDINALITY_CUE.search(visible_text(front))
    cardinality = int(cardinality_match.group(1)) if cardinality_match else None
    if LEGACY_CARDINALITY_CUE.search(visible_text(front)):
        report.error(f"{location}.front", "place the cardinality cue immediately before the final question mark")
    if cardinality is not None:
        if not 2 <= cardinality <= 7:
            report.error(f"{location}.front", "cardinality cue must be between 2 and 7")
        if checklist:
            report.error(f"{location}.front", "cardinality cue must not duplicate a named checklist")
        if role != "macro_reconstruction" or family not in {"classification", "topology"}:
            report.error(f"{location}.front", "cardinality cue requires a classification/topology macro card")
        if len(lines) != cardinality:
            report.error(
                f"{location}.back_lines",
                f"cardinality cue ({cardinality}) must match the number of answer lines ({len(lines)})",
            )
    line_limit = 7 if cardinality == 7 else 6
    if len(lines) > line_limit:
        report.error(f"{location}.back_lines", f"must contain at most {line_limit} semantic lines")
    if family == "muscle_profile" and len(lines) > 5:
        report.error(f"{location}.back_lines", "muscle_profile allows at most five labeled dimensions")

    front_length = len(visible_text(front))
    back_length = len(visible_text(back))
    front_hard_limit = 180 if family == "muscle_profile" else (220 if note_type == "cloze" else 125)
    if front_length > front_hard_limit:
        report.error(f"{location}.front", f"too long ({front_length} > {front_hard_limit} visible characters)")
    elif note_type == "basic" and not 35 <= front_length <= 105:
        report.warn(f"{location}.front", f"outside Basic target range 35-105 ({front_length})")
    back_hard_limit = 520 if family == "muscle_profile" else 450
    if back_length > back_hard_limit:
        report.error(f"{location}.back", f"too dense ({back_length} > {back_hard_limit} visible characters)")
    elif note_type == "basic" and not 80 <= back_length <= 360:
        report.warn(f"{location}.back", f"outside Basic target range 80-360 ({back_length})")
    if role == "macro_reconstruction" and back.count("<br") < 1 and back_length > 180:
        report.warn(f"{location}.back", "long macro answer is not visually segmented with <br>")

    return normalized(front), normalized(back), str(note_type), refs


def integer(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def check_summary(summary: Any, cards: list[Any], refs: set[str], report: Report) -> None:
    if not isinstance(summary, dict):
        report.error("summary", "must be an object")
        return
    missing = REQUIRED_SUMMARY_KEYS - summary.keys()
    if missing:
        report.error("summary", f"missing keys: {', '.join(sorted(missing))}")
    expected = {
        "card_count": len(cards),
        "macro_count": sum(isinstance(c, dict) and c.get("role") == "macro_reconstruction" for c in cards),
        "atomic_count": sum(isinstance(c, dict) and c.get("role") == "atomic_discrimination" for c in cards),
        "cloze_count": sum(isinstance(c, dict) and c.get("note_type") == "cloze" for c in cards),
        "source_count": len(refs),
    }
    for key, count in expected.items():
        if summary.get(key) != count:
            report.error(f"summary.{key}", f"must equal computed value {count}")
    budget = summary.get("card_budget")
    if not isinstance(budget, dict) or set(budget) != {"min", "max"}:
        report.error("summary.card_budget", "must contain exactly integer min and max")
    elif not integer(budget["min"]) or not integer(budget["max"]) or not (0 <= budget["min"] <= budget["max"]):
        report.error("summary.card_budget", "requires 0 <= integer min <= integer max")
    elif not budget["min"] <= len(cards) <= budget["max"]:
        report.error("summary.card_budget", f"card count {len(cards)} falls outside budget")
    check_string_list(summary.get("coverage"), "summary.coverage", report, nonempty=True)
    check_string_list(summary.get("source_gaps"), "summary.source_gaps", report, nonempty=False)
    if not is_nonempty_string(summary.get("provenance_note")):
        report.error("summary.provenance_note", "must be a non-empty string")


def validate(data: Any) -> Report:
    report = Report()
    if not isinstance(data, dict):
        report.error("root", "must be an object")
        return report
    if data.get("schema_version") != SCHEMA_VERSION:
        report.error("schema_version", f"must be {SCHEMA_VERSION!r}")
    cards = data.get("cards")
    if not isinstance(cards, list) or not cards:
        report.error("cards", "must be a non-empty array")
        return report

    seen_fronts: dict[str, int] = {}
    seen_pairs: dict[tuple[str, str], int] = {}
    all_refs: set[str] = set()
    note_types: Counter[str] = Counter()
    for index, card in enumerate(cards):
        front, back, note_type, refs = check_card(card, index, report)
        all_refs.update(refs)
        note_types[note_type] += 1
        if front:
            if front in seen_fronts:
                report.error(f"cards[{index}].front", f"duplicates normalized front of cards[{seen_fronts[front]}]")
            else:
                seen_fronts[front] = index
        pair = (front, back)
        if front and back and pair in seen_pairs:
            report.error(f"cards[{index}]", f"duplicates normalized front/back of cards[{seen_pairs[pair]}]")
        else:
            seen_pairs[pair] = index

    cloze_limit = max(1, (len(cards) + 19) // 20)
    if note_types["cloze"] > cloze_limit:
        report.error("cards", f"Cloze is not selective ({note_types['cloze']} cards; maximum {cloze_limit})")
    macro_count = sum(
        isinstance(card, dict) and card.get("role") == "macro_reconstruction"
        for card in cards
    )
    atomic_count = sum(
        isinstance(card, dict) and card.get("role") == "atomic_discrimination"
        for card in cards
    )
    if len(cards) >= 2 and macro_count == 0:
        report.error("cards", "sets with at least two cards require a macro_reconstruction card")
    if len(cards) >= 2 and atomic_count > 3 * macro_count:
        report.error(
            "cards",
            f"atomic cards exceed the morphology-first limit ({atomic_count} > 3 * {macro_count} macro cards)",
        )
    check_summary(data.get("summary"), cards, all_refs, report)
    return report


def positive_fixture() -> dict[str, Any]:
    line_one = "<b>Corpo</b>: porzione anteriore portante."
    line_two = "<b>Arco</b>: peduncoli e lamine disposti posteriormente al corpo."
    return {
        "schema_version": SCHEMA_VERSION,
        "cards": [
            {
                "front": "Quali parti delimitano una vertebra tipica? [corpo - arco]",
                "back": f"{line_one}<br>{line_two}",
                "tags": ["anatomia::locomotore::vertebra"],
                "note_type": "basic",
                "role": "macro_reconstruction",
                "family": "topology",
                "cognitive_function": "reconstruct",
                "back_lines": [line_one, line_two],
                "checklist": ["corpo", "arco"],
                "source_refs": ["fixture#p1"],
                "evidence": [{"source_ref": "fixture#p1", "text": "Il corpo è anteriore e l'arco posteriore."}],
                "image_refs": [],
                "grounded_claims": [{"claim": "Corpo e arco delimitano la vertebra.", "source_refs": ["fixture#p1"]}],
                "rationale": "Verifica una ricostruzione morfologica coerente.",
                "quality": {"factual_review": "source_checked", "overload": "pass", "image_status": "none"},
                "provenance": {
                    "generated_by": "codex",
                    "provider": None,
                    "model": None,
                    "prompt_version": SCHEMA_VERSION,
                },
            }
        ],
        "summary": {
            "card_count": 1,
            "macro_count": 1,
            "atomic_count": 0,
            "cloze_count": 0,
            "source_count": 1,
            "card_budget": {"min": 1, "max": 2},
            "coverage": ["vertebra tipica"],
            "source_gaps": [],
            "provenance_note": "Fixture source-grounded senza provider esterno.",
        },
    }


def run_self_test() -> int:
    positive = positive_fixture()
    positive_report = validate(positive)
    if positive_report.errors:
        print("SELF-TEST FAIL: positive fixture was rejected", file=sys.stderr)
        for error in positive_report.errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("SELF-TEST PASS: positive fixture accepted")

    single_atomic = copy.deepcopy(positive)
    single_atomic["cards"][0]["role"] = "atomic_discrimination"
    single_atomic["summary"].update({"macro_count": 0, "atomic_count": 1})
    single_atomic_report = validate(single_atomic)
    if single_atomic_report.errors:
        print(
            f"SELF-TEST FAIL: single atomic fixture was rejected: {single_atomic_report.errors}",
            file=sys.stderr,
        )
        return 1
    print("SELF-TEST PASS: single atomic fixture accepted")

    cardinality = copy.deepcopy(positive)
    cardinality["cards"][0]["front"] = "Quali sono le quattro parti canoniche della struttura (4)?"
    cardinality["cards"][0]["family"] = "classification"
    cardinality["cards"][0]["cognitive_function"] = "classify"
    cardinality["cards"][0]["checklist"] = []
    cardinality_lines = [
        "1) Prima parte documentata.",
        "2) Seconda parte documentata.",
        "3) Terza parte documentata.",
        "4) Quarta parte documentata.",
    ]
    cardinality["cards"][0]["back_lines"] = cardinality_lines
    cardinality["cards"][0]["back"] = "<br>".join(cardinality_lines)
    cardinality_report = validate(cardinality)
    if cardinality_report.errors:
        print(
            f"SELF-TEST FAIL: cardinality fixture was rejected: {cardinality_report.errors}",
            file=sys.stderr,
        )
        return 1
    print("SELF-TEST PASS: closed cardinality fixture accepted")

    def expect_rejected(name: str, fixture: dict[str, Any], expected: str) -> bool:
        try:
            report = validate(fixture)
        except Exception as exc:  # pragma: no cover - the self-test exists to catch this contract break
            print(f"SELF-TEST FAIL: {name} crashed: {exc}", file=sys.stderr)
            return False
        if not any(expected in error for error in report.errors):
            print(
                f"SELF-TEST FAIL: {name} did not report {expected!r}: {report.errors}",
                file=sys.stderr,
            )
            return False
        print(f"SELF-TEST PASS: {name} rejected with {len(report.errors)} error(s)")
        return True

    cases: list[tuple[str, dict[str, Any], str]] = []

    invalid_html = copy.deepcopy(positive)
    invalid_html["cards"][0]["back"] = "<b>Corpo <b>interno</b></b>"
    invalid_html["cards"][0]["back_lines"] = [invalid_html["cards"][0]["back"]]
    invalid_html["cards"][0]["checklist"] = []
    invalid_html["cards"][0]["front"] = "Quali caratteristiche presenta una vertebra tipica?"
    cases.append(("malformed nested bold HTML", invalid_html, "improperly nested <b>"))

    residual_cloze = copy.deepcopy(positive)
    residual_cloze["cards"][0]["front"] += " {{c1::residuo"
    cases.append(("residual Cloze delimiters", residual_cloze, "residual or malformed Cloze"))

    non_scalar_enum = copy.deepcopy(positive)
    non_scalar_enum["cards"][0]["family"] = ["topology"]
    cases.append(("non-scalar enum", non_scalar_enum, ".family: must be one of"))

    non_scalar_provenance = copy.deepcopy(positive)
    non_scalar_provenance["cards"][0]["provenance"]["generated_by"] = {"kind": "codex"}
    cases.append(("non-scalar provenance enum", non_scalar_provenance, ".generated_by: must be one of"))

    non_scalar_quality = copy.deepcopy(positive)
    non_scalar_quality["cards"][0]["quality"]["factual_review"] = ["source_checked"]
    cases.append(("non-scalar quality enum", non_scalar_quality, ".factual_review: must be"))

    all_atomic = copy.deepcopy(positive)
    first = all_atomic["cards"][0]
    first["role"] = "atomic_discrimination"
    second = copy.deepcopy(first)
    second["front"] = "Quale porzione della vertebra è disposta posteriormente? [corpo - arco]"
    all_atomic["cards"].append(second)
    all_atomic["summary"].update({"card_count": 2, "macro_count": 0, "atomic_count": 2})
    cases.append(("all-atomic multi-card set", all_atomic, "require a macro_reconstruction"))

    invalid_image = copy.deepcopy(positive)
    invalid_image["cards"][0]["back"] += '<br><img src="unverified.png">'
    cases.append(("embedded image", invalid_image, "contains HTML other than"))

    missing_question = copy.deepcopy(positive)
    missing_question["cards"][0]["front"] = "Parti che delimitano una vertebra tipica"
    missing_question["cards"][0]["checklist"] = []
    cases.append(("implicit Basic prompt", missing_question, "must ask an explicit question"))

    mismatched_cardinality = copy.deepcopy(cardinality)
    mismatched_cardinality["cards"][0]["front"] = "Quali sono le cinque parti canoniche della struttura (5)?"
    cases.append(("mismatched cardinality", mismatched_cardinality, "must match the number of answer lines"))

    misplaced_cardinality = copy.deepcopy(cardinality)
    misplaced_cardinality["cards"][0]["front"] = "Quali sono le quattro parti canoniche della struttura? (4)"
    cases.append(("misplaced cardinality", misplaced_cardinality, "immediately before the final question mark"))

    if not all(expect_rejected(*case) for case in cases):
        return 1
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path, help="JSON file to validate")
    parser.add_argument("--self-test", action="store_true", help="run inline positive and negative fixtures")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        return run_self_test()
    if args.input is None:
        print("ERROR: input is required unless --self-test is used", file=sys.stderr)
        return 2
    try:
        raw = args.input.read_bytes()
        data = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(f"ERROR: {args.input}: {exc}", file=sys.stderr)
        return 2

    report = validate(data)
    digest = hashlib.sha256(raw).hexdigest()
    for warning in report.warnings:
        print(f"WARNING: {warning}")
    for error in report.errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if report.errors:
        print(
            f"FAIL: {len(report.errors)} error(s), {len(report.warnings)} warning(s); sha256={digest}",
            file=sys.stderr,
        )
        return 1
    print(f"PASS: {len(data['cards'])} card(s), {len(report.warnings)} warning(s); sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
