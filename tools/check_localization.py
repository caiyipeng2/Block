"""Statically check player-facing localization without starting Godot.

Run from any directory: python tools/check_localization.py
Chinese source literals, explicit L10n.t literals, English presentation text
and CSV difficulty labels require English and French catalog entries. Comments,
paths, identifiers and English diagnostic machine codes are not UI sources.
"""

from __future__ import annotations

import argparse
import ast
import csv
import json
from pathlib import Path
import re
import sys
import unicodedata


REQUIRED_LANGUAGES = ("en", "fr")
ALLOWED_LANGUAGES = {"zh_CN", *REQUIRED_LANGUAGES}
CJK = re.compile(r"[\u3400-\u9fff]")
PRINTF = re.compile(r"%%|%[-+ #0]*\d*(?:\.\d+)?[sdifvxoXcuhHeEgG]")
# Match comments before string tokens so commented examples are never sources.
GD_TOKENS = re.compile(
    r"\#[^\n]*|(?:\br)?\"\"\"[\s\S]*?\"\"\"|(?:\br)?'''[\s\S]*?'''"
    r"|(?:\br)?\"(?:\\[\s\S]|[^\"\\])*\"|(?:\br)?'(?:\\[\s\S]|[^'\\])*'"
)
TRANSLATION_CALL = re.compile(r"\bL10n\.t\(\s*$")
# These English phrases are presentation sources, rather than internal codes.
ENGLISH_UI_SOURCES = {
    "Nice!", "Combo", "Perfect!", "Excellent!", "Unbelievable!", "Well Done!",
    "Final Block!", "COMBO", "%d Line", "%d Lines", "%d%% Done", "SCORE %06d",
    "COMBO x%d", "COMBO --", "English", "Français",
}
NON_UI_SCRIPT_NAMES = {"leaderboard_bots.gd"}


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def source_keys(project_root: Path) -> tuple[set[str], int]:
    required = set(ENGLISH_UI_SOURCES)
    script_count = 0
    for path in sorted((project_root / "scripts").rglob("*.gd")):
        if path.name in NON_UI_SCRIPT_NAMES:
            continue
        script_count += 1
        text = path.read_text(encoding="utf-8-sig")
        for match in GD_TOKENS.finditer(text):
            token = match.group()
            if token.startswith("#"):
                continue
            try:
                value = ast.literal_eval(token)
            except (SyntaxError, ValueError) as error:
                line = text.count("\n", 0, match.start()) + 1
                raise ValueError(f"{path}:{line}: cannot decode source string") from error
            if not isinstance(value, str) or not value:
                continue
            if CJK.search(value) or TRANSLATION_CALL.search(text[:match.start()]):
                required.add(value)
    with (project_root / "config/adventure_levels.csv").open(
        encoding="utf-8-sig", newline=""
    ) as stream:
        for row in csv.DictReader(stream):
            if row["difficulty_label"]:
                required.add(row["difficulty_label"])
    return required, script_count


def check_catalog(project_root: Path) -> tuple[list[str], dict[str, int]]:
    catalog_path = project_root / "assets/localization/messages.json"
    catalog = json.loads(
        catalog_path.read_text(encoding="utf-8"), object_pairs_hook=unique_object
    )
    if not isinstance(catalog, dict):
        raise ValueError("catalog root must be a JSON object")
    required, script_count = source_keys(project_root)
    errors = [f"missing source key: {key!r}" for key in sorted(required - catalog.keys())]
    translated_count = 0
    checked_tokens = 0
    for source, values in catalog.items():
        if not source or "\ufffd" in source:
            errors.append(f"invalid source key: {source!r}")
        if not isinstance(values, dict):
            errors.append(f"{source!r}: translations must be an object")
            continue
        missing = set(REQUIRED_LANGUAGES) - values.keys()
        unknown = values.keys() - ALLOWED_LANGUAGES
        if missing or unknown:
            errors.append(f"{source!r}: missing languages {sorted(missing)}, unknown languages {sorted(unknown)}")
        expected = PRINTF.findall(source)
        for language, translated in values.items():
            translated_count += 1
            if not isinstance(translated, str) or not translated:
                errors.append(f"{source!r} [{language}]: translation must be a nonempty string")
                continue
            if "\ufffd" in translated or unicodedata.normalize("NFC", translated) != translated:
                errors.append(f"{source!r} [{language}]: replacement character or non-NFC text")
            actual = PRINTF.findall(translated)
            checked_tokens += len(actual)
            if actual != expected:
                errors.append(f"{source!r} [{language}]: printf tokens {actual!r}, expected {expected!r}")
            if re.findall(r"\n+", translated) != re.findall(r"\n+", source):
                errors.append(f"{source!r} [{language}]: newline groups differ")
            if translated.startswith("\n") != source.startswith("\n") or translated.endswith("\n") != source.endswith("\n"):
                errors.append(f"{source!r} [{language}]: boundary newlines differ")
            if translated.count("%") != source.count("%"):
                errors.append(f"{source!r} [{language}]: percent sign count differs")
    return errors, {
        "catalog_keys": len(catalog),
        "translations": translated_count,
        "required_sources": len(required),
        "scripts_scanned": script_count,
        "printf_tokens_checked": checked_tokens,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    try:
        errors, counts = check_catalog(args.project_root.resolve())
    except (OSError, ValueError, KeyError) as error:
        print(f"Localization check failed: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        print(f"Localization check failed: {len(errors)} issue(s)", file=sys.stderr)
        return 1
    print("Localization check passed: " + json.dumps(counts, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
