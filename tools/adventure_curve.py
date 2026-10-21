#!/usr/bin/env python3
"""Generate the 96-level adventure curve from the approved JSON template.

The template only describes target pass-rate bands and coarse lever scales.
This tool turns it into the runtime CSV without inventing per-level magic
numbers, so the same rule template can be reviewed, regenerated and committed
alongside its simulation snapshot.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASE = ROOT / "config" / "adventure_levels.csv"
DEFAULT_SPEC = ROOT / "docs" / "difficulty" / "adventure_curve_spec.json"
DEFAULT_OUT = ROOT / "tools" / "candidates" / "adventure_levels_candidate.csv"
DEFAULT_PLAN = ROOT / "tools" / "candidates" / "adventure_curve_plan.json"

TARGET_COLUMNS = ["blue_diamond", "gold_gem", "yellow_star", "red_star"]
COLUMNS = [
    "level_id", "objective_type", "target_score", "blue_diamond", "gold_gem",
    "yellow_star", "red_star", "difficulty", "template_id", "mirror",
    "initial_fill", "initial_markers", "seed", "difficulty_label", "note",
    "retry_assist_step", "retry_assist_max",
    "shape_profile", "extra_blocks", "near_win_lines", "randomness",
]
PHASE_NAMES = {
    "build": "建立期",
    "peak": "阻塞峰值",
    "secondary_peak": "次级峰值",
    "relax": "放松期",
    "final_peak": "终局峰值",
    "finale_relax": "终局放松",
    "tutorial": "教学",
}


def lerp(start: float, end: float, t: float) -> float:
    return start + (end - start) * t


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def load_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 96:
        raise SystemExit(f"{path}: expected 96 rows, found {len(rows)}")
    return rows


def slot_definition(spec: dict, level_id: int) -> dict:
    cycle = spec["cycle"]
    if level_id >= cycle["finale_start"]:
        offset = level_id - cycle["finale_start"]
        finale = spec["finale_targets"][offset]
        return {
            "slot": 0,
            "cycle_index": cycle["count"],
            "phase": finale["phase"],
            "target": float(finale["target"]),
            "band_low": float(finale["band_low"]),
            "band_high": float(finale["band_high"]),
            "quota_scale": float(finale["quota_scale"]),
            "profile": finale["profile"],
            "randomness": float(finale["randomness"]),
            "extras": int(finale.get("extras", 0)),
            "near_win": int(finale.get("near_win", 0)),
            "cycle_t": 1.0,
        }
    index = level_id - 1
    slot = index % cycle["length"] + 1
    cycle_index = index // cycle["length"]
    cycle_t = cycle_index / max(1, cycle["count"] - 1)
    definition = next(item for item in spec["slot_targets"] if int(item["slot"]) == slot)
    target = lerp(float(definition["start"]), float(definition["end"]), cycle_t)
    extras = 0
    if "extras_start" in definition:
        extras = round(lerp(float(definition["extras_start"]), float(definition["extras_end"]), cycle_t))
    return {
        "slot": slot,
        "cycle_index": cycle_index,
        "phase": definition["phase"],
        "target": target,
        "band_low": float(definition["band_low"]),
        "band_high": float(definition["band_high"]),
        "quota_scale": float(definition["quota_scale"]),
        "profile": definition["profile"],
        "randomness": float(definition["randomness"]),
        "extras": extras,
        "near_win": int(definition.get("near_win", 0)),
        "cycle_t": cycle_t,
    }


def curve_pass_rate(spec: dict, level_id: int, definition: dict) -> float:
    if definition["phase"] == "tutorial":
        return 92.0
    target = definition["target"]
    cycle = spec["cycle"]
    if level_id < cycle["finale_start"]:
        amplitude = lerp(
            float(spec["sine"]["amplitude_start"]),
            float(spec["sine"]["amplitude_end"]),
            (level_id - 1) / 95.0,
        )
        target += amplitude * math.sin(2.0 * math.pi * (level_id - 1) / float(spec["sine"]["period"]))
    return clamp(target, definition["band_low"], definition["band_high"])


def distribute_quota(quota: int, kinds: list[str]) -> dict[str, int]:
    result = {kind: 0 for kind in TARGET_COLUMNS}
    if not kinds:
        kinds = TARGET_COLUMNS
    base, remainder = divmod(quota, len(kinds))
    for index, kind in enumerate(kinds):
        result[kind] = base + (1 if index < remainder else 0)
    return result


def apply_level_override(spec: dict, level_id: int, definition: dict) -> dict:
    override = spec.get("level_overrides", {}).get(str(level_id), {})
    applied: dict = {}
    for key in ("quota", "quota_scale", "difficulty", "profile", "randomness", "extras", "near_win"):
        if key in override:
            definition[key] = override[key]
            applied[key] = override[key]
    return applied


def build_rows(spec: dict, base_rows: list[dict[str, str]]) -> tuple[list[dict], list[dict]]:
    quota_spec = spec["quota"]
    difficulty_spec = spec["difficulty"]
    rows: list[dict] = []
    plan: list[dict] = []
    for level_id in range(1, 97):
        source = next(row for row in base_rows if int(row["level_id"]) == level_id)
        objective = source["objective_type"]
        definition = slot_definition(spec, level_id)
        override = apply_level_override(spec, level_id, definition)
        if objective == "score":
            definition["phase"] = "tutorial"
            definition["extras"] = 0
            definition["near_win"] = 0
            override = {}
        pass_rate = curve_pass_rate(spec, level_id, definition)
        difficulty = clamp(
            (100.0 - pass_rate) * float(difficulty_spec["pass_to_difficulty_factor"]),
            float(difficulty_spec["minimum"]),
            float(difficulty_spec["maximum"]),
        )
        if "difficulty" in override:
            difficulty = clamp(float(override["difficulty"]), 0.0, 100.0)
        row = {column: source.get(column, "") for column in COLUMNS}
        row["level_id"] = str(level_id)
        row["objective_type"] = objective
        row["difficulty"] = f"{difficulty:.2f}"
        row["shape_profile"] = definition["profile"] if objective == "collect" else "mixed"
        row["extra_blocks"] = str(definition["extras"]) if objective == "collect" else "0"
        row["near_win_lines"] = str(definition["near_win"]) if objective == "collect" else "0"
        row["randomness"] = f"{definition['randomness']:.0f}" if objective == "collect" else "50"
        if objective == "collect":
            t = (level_id - 3) / 93.0
            base_quota = lerp(float(quota_spec["base_start"]), float(quota_spec["base_end"]), t)
            quota = round(base_quota * definition["quota_scale"])
            quota = int(clamp(quota, float(quota_spec["minimum"]), float(quota_spec["maximum"])))
            if "quota" in override:
                quota = int(override["quota"])
            kinds = [kind for kind in TARGET_COLUMNS if int(source[kind]) > 0]
            counts = distribute_quota(quota, kinds)
            for kind in TARGET_COLUMNS:
                row[kind] = str(counts[kind])
            row["target_score"] = "0"
            row["initial_fill"] = "0"
            row["note"] = (
                f"曲线{PHASE_NAMES.get(definition['phase'], definition['phase'])}；"
                f"参考通过率目标 {pass_rate:.0f}%；配额 {quota}"
            )
        else:
            row["note"] = source["note"]
        rows.append(row)
        plan.append({
            "level_id": level_id,
            "objective_type": objective,
            "phase": definition["phase"],
            "slot": definition["slot"],
            "cycle_index": definition["cycle_index"],
            "pass_rate_target": round(pass_rate, 2),
            "band_low": definition["band_low"],
            "band_high": definition["band_high"],
            "difficulty": round(difficulty, 2),
            "quota_total": sum(int(row[kind]) for kind in TARGET_COLUMNS),
            "quota_scale": definition["quota_scale"],
            "shape_profile": row["shape_profile"],
            "extra_blocks": int(row["extra_blocks"]),
            "near_win_lines": int(row["near_win_lines"]),
            "randomness": float(row["randomness"]),
            "overrides": override,
        })
    return rows, plan


def validate(rows: list[dict], plan: list[dict], spec: dict) -> list[str]:
    errors: list[str] = []
    if len(rows) != 96:
        errors.append(f"expected 96 rows, found {len(rows)}")
    allowed_overrides = {"quota", "quota_scale", "difficulty", "profile", "randomness", "extras", "near_win"}
    for raw_level, override in spec.get("level_overrides", {}).items():
        if not isinstance(override, dict):
            errors.append(f"level override {raw_level}: expected an object")
            continue
        try:
            level_id = int(raw_level)
        except ValueError:
            errors.append(f"level override {raw_level}: level id must be an integer")
            continue
        if not 3 <= level_id <= 96:
            errors.append(f"level override {raw_level}: only collection levels 3-96 may use overrides")
        unknown = sorted(set(override) - allowed_overrides)
        if unknown:
            errors.append(f"level override {raw_level}: unknown keys {', '.join(unknown)}")
        if "quota_scale" in override and not 0.5 <= float(override["quota_scale"]) <= 2.5:
            errors.append(f"level override {raw_level}: quota_scale must be within 0.5-2.5")
        if "quota" in override and not 24 <= int(override["quota"]) <= 104:
            errors.append(f"level override {raw_level}: quota must be within 24-104")
        if "quota" in override and "quota_scale" in override:
            errors.append(f"level override {raw_level}: use either quota or quota_scale, not both")
        if "difficulty" in override and not 0 <= float(override["difficulty"]) <= 100:
            errors.append(f"level override {raw_level}: difficulty must be within 0-100")
        if "profile" in override and override["profile"] not in {"friendly", "mixed", "pressure"}:
            errors.append(f"level override {raw_level}: invalid profile")
        if "randomness" in override and not 0 <= float(override["randomness"]) <= 100:
            errors.append(f"level override {raw_level}: randomness must be within 0-100")
        if "extras" in override and not 0 <= int(override["extras"]) <= 12:
            errors.append(f"level override {raw_level}: extras must be within 0-12")
        if "near_win" in override and not 0 <= int(override["near_win"]) <= 3:
            errors.append(f"level override {raw_level}: near_win must be within 0-3")
    for row in rows:
        level_id = int(row["level_id"])
        if row["objective_type"] == "score":
            if int(row["extra_blocks"]) != 0 or int(row["near_win_lines"]) != 0:
                errors.append(f"level {level_id}: tutorial level has non-default pressure levers")
            continue
        extras = int(row["extra_blocks"])
        near = int(row["near_win_lines"])
        if not 0 <= extras <= 12:
            errors.append(f"level {level_id}: extra_blocks out of range")
        if not 0 <= near <= 3 or near > extras:
            errors.append(f"level {level_id}: near_win_lines out of range or above extra_blocks")
        if row["shape_profile"] not in {"friendly", "mixed", "pressure"}:
            errors.append(f"level {level_id}: invalid shape_profile")
        randomness = float(row["randomness"])
        if not 0 <= randomness <= 100:
            errors.append(f"level {level_id}: randomness out of range")
        if sum(int(row[kind]) for kind in TARGET_COLUMNS) <= 0:
            errors.append(f"level {level_id}: empty collection quota")
    peaks = [item["level_id"] for item in plan if item["phase"] in {"peak", "final_peak", "secondary_peak"}]
    for peak in peaks:
        if peak + 1 in peaks:
            errors.append(f"level {peak}: peak is immediately followed by another peak")
        next_item = next((item for item in plan if item["level_id"] == peak + 1), None)
        if next_item and "relax" not in next_item["phase"]:
            errors.append(f"level {peak}: peak is not followed by a relax phase")
    for item in plan:
        target = item["pass_rate_target"]
        if not item["band_low"] <= target <= item["band_high"]:
            errors.append(f"level {item['level_id']}: target outside its band")
    return errors


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_plan(path: Path, spec: dict, base_path: Path, rows_path: Path, plan: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "spec": spec,
        "source": str(base_path.relative_to(ROOT)).replace("\\", "/"),
        "source_md5": hashlib.md5(base_path.read_bytes()).hexdigest(),
        "candidate_csv": str(rows_path.relative_to(ROOT)).replace("\\", "/"),
        "levels": plan,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, default=DEFAULT_BASE)
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--plan", type=Path, default=DEFAULT_PLAN)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()

    spec = json.loads(args.spec.read_text(encoding="utf-8"))
    base_rows = load_csv(args.base)
    rows, plan = build_rows(spec, base_rows)
    errors = validate(rows, plan, spec)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        raise SystemExit(1)
    if not args.check_only:
        write_csv(args.out, rows)
        write_plan(args.plan, spec, args.base, args.out, plan)
    print(f"curve ok: {len(rows)} rows, peaks={sum(1 for item in plan if 'peak' in item['phase'])}")
    print("id phase       target band     diff quota profile  extras near rand")
    for item in plan:
        print(
            f"{item['level_id']:3d} {item['phase']:12s} {item['pass_rate_target']:6.1f} "
            f"{item['band_low']:2.0f}-{item['band_high']:2.0f} {item['difficulty']:5.1f} "
            f"{item['quota_total']:5d} {item['shape_profile']:8s} {item['extra_blocks']:6d} "
            f"{item['near_win_lines']:4d} {item['randomness']:4.0f}"
        )


if __name__ == "__main__":
    main()
