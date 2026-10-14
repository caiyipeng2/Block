"""Export the Windows build and package all dependencies without running the game."""

from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PRESET = "Windows Desktop"
OPTIONAL_DLLS = {
    "D3D12Core.x86_64.dll": "x86_64/D3D12Core.dll",
    "d3d12SDKLayers.x86_64.dll": "x86_64/d3d12SDKLayers.dll",
    "WinPixEventRuntime.x86_64.dll": "WinPixEventRuntime.dll",
}
ERROR_MARKERS = ("SCRIPT ERROR:", "ERROR:", "Parse Error:", "Compile Error:")


def command(args: list[str], timeout: int = 30) -> str:
    result = subprocess.run(
        args, cwd=PROJECT_ROOT, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        encoding="utf-8", errors="replace", timeout=timeout,
        env={**os.environ, "GIT_OPTIONAL_LOCKS": "0"},
    )
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}):\n{result.stdout}")
    return result.stdout.strip()


def read_config(path: Path) -> configparser.ConfigParser:
    config = configparser.ConfigParser(interpolation=None, strict=True)
    # Godot stores config_version before its first INI section.
    config.read_string("[metadata]\n" + path.read_text(encoding="utf-8-sig"))
    return config


def unquote(value: str) -> str:
    return json.loads(value)


def preflight(args: argparse.Namespace) -> tuple[Path, str, str, Path]:
    executable = args.godot or os.environ.get("GODOT_BIN")
    executable = executable or shutil.which("godot") or shutil.which("godot4")
    if not executable:
        raise ValueError("Godot editor not found. Supply --godot <path-to-editor.exe>.")
    engine = Path(executable).expanduser().resolve()
    if not engine.is_file():
        raise ValueError(f"Godot editor does not exist: {engine}")
    engine_version = command([str(engine), "--version"])
    match = re.match(r"^(\d+\.\d+(?:\.\d+)?)\.([^.]+)\.", engine_version)
    if not match or match.group(1).split(".")[:2] != ["4", "7"]:
        raise ValueError(f"This project needs a Godot 4.7 editor; found {engine_version}")
    template_version = f"{match.group(1)}.{match.group(2)}"

    project = read_config(PROJECT_ROOT / "project.godot")
    version = unquote(project["application"]["config/version"])
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("config/version must be a three-component version, e.g. 0.1.0.")
    preset = read_config(PROJECT_ROOT / "export_presets.cfg")
    if unquote(preset["preset.0"]["name"]) != PRESET:
        raise ValueError(f"Expected export preset: {PRESET}")
    options = preset["preset.0.options"]
    if unquote(options["binary_format/architecture"]) != "x86_64":
        raise ValueError("Windows preset architecture must be x86_64.")
    if options["binary_format/embed_pck"] != "false":
        raise ValueError("Packaging expects an external Block.pck (embed_pck=false).")
    if options["application/export_d3d12"] != "1" or options["application/d3d12_agility_sdk_multiarch"] != "true":
        raise ValueError("Windows preset must export the D3D12 dependencies in multiarch mode.")

    if args.templates_dir:
        templates = args.templates_dir.expanduser().resolve()
    else:
        appdata = os.environ.get("APPDATA")
        if not appdata:
            raise ValueError("APPDATA is unavailable; supply --templates-dir <version-directory>.")
        templates = Path(appdata) / "Godot" / "export_templates" / template_version
    template_exe = f"windows_{args.configuration}_x86_64.exe"
    required = ["version.txt", template_exe]
    missing = [name for name in required if not (templates / name).is_file()]
    if missing:
        raise ValueError(
            f"Missing {template_version} Windows export files in {templates}:\n"
            + "\n".join(f"  {name}" for name in missing)
            + "\nInstall the matching official export templates, or use --templates-dir."
        )
    found_version = (templates / "version.txt").read_text(encoding="utf-8-sig").strip()
    if found_version != template_version:
        raise ValueError(f"Template version mismatch: {found_version}; editor needs {template_version}.")
    for name in [template_exe, *[name for name in OPTIONAL_DLLS if (templates / name).is_file()]]:
        require_pe_x64(templates / name)
    runtime = "bundled Agility SDK" if (templates / "D3D12Core.x86_64.dll").is_file() else "Windows system D3D12"
    print(f"Project: Block {version}\nEditor: {engine_version}\nTemplates: {templates}\nD3D12 runtime: {runtime}", flush=True)
    return engine, engine_version, version, templates


def require_pe_x64(path: Path) -> None:
    with path.open("rb") as handle:
        if handle.read(2) != b"MZ":
            raise ValueError(f"Invalid Windows executable/library: {path}")
        handle.seek(0x3C)
        offset = struct.unpack("<I", handle.read(4))[0]
        handle.seek(offset)
        if handle.read(4) != b"PE\0\0" or struct.unpack("<H", handle.read(2))[0] != 0x8664:
            raise ValueError(f"Expected an x86_64 PE binary: {path}")


def sha256(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest() if sys.version_info >= (3, 11) else hash_stream(handle)


def hash_stream(handle) -> str:
    digest = hashlib.sha256()
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


def write_manifest(payload: Path, version: str, configuration: str, engine_version: str) -> None:
    try:
        revision = command(["git", "--no-optional-locks", "rev-parse", "HEAD"])
        dirty = bool(command(["git", "--no-optional-locks", "status", "--porcelain"]))
    except (OSError, RuntimeError):
        revision, dirty = "unknown", None
    files = [
        {"path": file.relative_to(payload).as_posix(), "bytes": file.stat().st_size, "sha256": sha256(file)}
        for file in sorted(payload.rglob("*")) if file.is_file()
    ]
    info = {
        "project": "Block", "version": version, "configuration": configuration,
        "architecture": "x86_64", "renderer": "Forward Plus / D3D12",
        "godot": engine_version, "source_commit": revision, "source_dirty": dirty,
        "runtime_acceptance": "pending_user", "files": files,
    }
    (payload / "build-info.json").write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build(args: argparse.Namespace, engine: Path, engine_version: str, version: str, templates: Path) -> None:
    build_parent = PROJECT_ROOT / "build" / "windows" / version
    output = build_parent / args.configuration
    distribution = PROJECT_ROOT / "dist"
    archive = distribution / f"Block-{version}-windows-x86_64-{args.configuration}.zip"
    checksum = archive.with_suffix(archive.suffix + ".sha256")
    if output.exists() or archive.exists() or checksum.exists():
        raise ValueError("Build output already exists. Move the previous build aside or increment config/version.")
    build_parent.mkdir(parents=True, exist_ok=True)
    distribution.mkdir(parents=True, exist_ok=True)
    work = PROJECT_ROOT / "work" / "windows-export"
    work.mkdir(parents=True, exist_ok=True)
    log = work / f"{version}-{args.configuration}.log"

    # The private copy holds machine-specific template paths and imported caches.
    # It never changes the user's project, installed templates, or saved game.
    with tempfile.TemporaryDirectory(prefix="project-", dir=work) as source_temp, tempfile.TemporaryDirectory(prefix="payload-", dir=build_parent) as binary_temp:
        source = Path(source_temp) / "project"
        payload = Path(binary_temp) / "Block"
        payload.mkdir()
        ignored = shutil.ignore_patterns(
            ".git", ".godot", ".codegraph", ".agents", ".codex", "work", "build", "dist",
            "__pycache__", "tests", "tools", "docs", ".env*", "*.log", "*.tmp", "export_credentials.cfg",
        )
        shutil.copytree(PROJECT_ROOT, source, ignore=ignored)
        preset_path = source / "export_presets.cfg"
        preset_text = preset_path.read_text(encoding="utf-8-sig")
        template_path = (templates / f"windows_{args.configuration}_x86_64.exe").as_posix()
        key = f"custom_template/{args.configuration}"
        preset_text, count = re.subn(rf"(?m)^{re.escape(key)}=.*$", lambda _: f"{key}={json.dumps(template_path)}", preset_text)
        if count != 1:
            raise ValueError(f"Expected exactly one {key} in the preset.")
        preset_path.write_text(preset_text, encoding="utf-8")
        print(f"Exporting {args.configuration}; log: {log}", flush=True)
        try:
            export_log = command([
                str(engine), "--headless", "--path", str(source), "--log-file", str(log),
                f"--export-{args.configuration}", PRESET, str(payload / "Block.exe"),
            ], timeout=300)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"Export timed out after 300 seconds; see {log}") from error
        if any(marker in export_log for marker in ERROR_MARKERS):
            raise RuntimeError(f"Godot reported export errors:\n{export_log}")
        require_pe_x64(payload / "Block.exe")
        pack = payload / "Block.pck"
        with pack.open("rb") as handle:
            if handle.read(4) != b"GDPC":
                raise ValueError("Export did not produce a valid Block.pck.")
        # Godot 4.7's official templates use system D3D12 when optional Agility
        # SDK libraries are absent. If supplied, every copied library is checked.
        for source_name, target_name in OPTIONAL_DLLS.items():
            if (templates / source_name).is_file():
                require_pe_x64(payload / target_name)
        (payload / "START-HERE.txt").write_text(
            f"Block {version} ({args.configuration})\n\n"
            "完整解压 ZIP 后运行 Block.exe；请保留 Block.pck、DLL 和 x86_64 子目录。\n"
            "鼠标拖放；Esc 暂停/继续；R 重新开始。\n"
            "最高分和设置保存在 Windows 用户目录，移动或替换游戏文件不会清空存档。\n"
            "Windows x86_64；Forward Plus / D3D12。本构建未签名，运行验收待用户完成。\n",
            encoding="utf-8-sig",
        )
        notices = PROJECT_ROOT / "packaging" / "notices"
        shutil.copytree(notices, payload / "licenses")
        write_manifest(payload, version, args.configuration, engine_version)
        temporary_zip = Path(binary_temp) / archive.name
        with zipfile.ZipFile(temporary_zip, "w", compression=zipfile.ZIP_DEFLATED) as package:
            for file in sorted(payload.rglob("*")):
                if file.is_file():
                    package.write(file, file.relative_to(payload))
        # All published paths are fresh; no old payload can leak into a new ZIP.
        payload.rename(output)
        temporary_zip.replace(archive)
        checksum.write_text(f"{sha256(archive)}  {archive.name}\n", encoding="ascii")
    print(f"Export complete (not runtime acceptance):\n  {output}\n  {archive}\n  {checksum}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Godot 4.7 editor executable; falls back to GODOT_BIN or PATH")
    parser.add_argument("--configuration", choices=("debug", "release"), default="release")
    parser.add_argument("--templates-dir", type=Path, help="Matching version directory containing Windows EXE templates and DLLs")
    parser.add_argument("--check", action="store_true", help="Check configuration and dependencies; do not export or run the game")
    args = parser.parse_args()
    try:
        engine, engine_version, version, templates = preflight(args)
        if args.check:
            print("Preflight passed; no game or export was run.")
        else:
            build(args, engine, engine_version, version, templates)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired, configparser.Error) as error:
        print(f"Export preparation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
