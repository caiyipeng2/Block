"""Run real Godot checks with bounded time and reliable failure detection."""

import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = Path(
    r"C:\Users\EDY\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
)
SUITES = {
    "rules": ("run_rules_tests.gd", "RULE TESTS PASSED"),
    "ui": ("run_ui_action_tests.gd", "UI ACTION TESTS PASSED"),
    "save": ("run_save_tests.gd", "SAVE TESTS PASSED"),
    "audio": ("run_audio_tests.gd", "AUDIO TESTS PASSED"),
    "exit": ("run_exit_tests.gd", "EXIT TEST PASSED"),
    "terminal": ("run_terminal_flow_tests.gd", "TERMINAL FLOW TESTS PASSED"),
    "leaderboard-client": ("run_leaderboard_client_tests.gd", "LEADERBOARD CLIENT TESTS PASSED"),
    "leaderboard-navigation": ("run_leaderboard_navigation_tests.gd", "LEADERBOARD NAVIGATION TESTS PASSED"),
    "leaderboard-panel": ("run_leaderboard_panel_tests.gd", "Leaderboard panel:"),
    "player-profile": ("run_player_profile_tests.gd", "Player profile:"),
    "leaderboard-localization": ("run_leaderboard_localization_tests.gd", "LEADERBOARD LOCALIZATION TESTS:"),
}


def decode_output(raw: bytes) -> str:
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("gb18030", errors="replace")


def run_suite(godot: Path, name: str) -> bool:
    script, marker = SUITES[name]
    artifacts = ROOT / "work" / "verification"
    artifacts.mkdir(parents=True, exist_ok=True)
    command = [
        str(godot), "--headless", "--path", str(ROOT),
        "--log-file", str(artifacts / f"{name}-godot.log"),
        "--script", f"res://tests/{script}",
    ]
    try:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
    except subprocess.TimeoutExpired as error:
        print(f"FAIL {name}: Godot timed out after 30s", flush=True)
        output = decode_output((error.stdout or b"") + (error.stderr or b""))
        (artifacts / f"{name}-output.txt").write_text(output, encoding="utf-8")
        return False
    stdout = decode_output(result.stdout)
    output = stdout + decode_output(result.stderr)
    (artifacts / f"{name}-output.txt").write_text(output, encoding="utf-8")
    failed = (result.returncode != 0 or marker not in output
              or "ERROR:" in output or "FAIL:" in output
              or "instances were leaked at exit" in output)
    print(f"{'FAIL' if failed else 'PASS'} {name}: exit={result.returncode}", flush=True)
    if failed:
        print(output, flush=True)
    else:
        for line in stdout.splitlines():
            if marker in line:
                print(line, flush=True)
    return not failed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, default=DEFAULT_GODOT)
    parser.add_argument("--suite", choices=[*SUITES, "all"], default="all")
    args = parser.parse_args()
    if not args.godot.is_file():
        parser.error(f"Godot executable missing: {args.godot}")
    names = list(SUITES) if args.suite == "all" else [args.suite]
    passed = [run_suite(args.godot, name) for name in names]
    return 0 if all(passed) else 1


if __name__ == "__main__":
    sys.exit(main())
