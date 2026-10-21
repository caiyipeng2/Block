"""Export signed Android APK/AAB from a private copy; never start the game.

The credentials JSON contains {"alias": "upload", "password": "..."} and must
remain outside source control. Keystore and key passwords must be identical.
"""

from __future__ import annotations

import argparse
import configparser
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.funblockstudio.block"
PRESETS = {"apk": "Android APK", "aab": "Android AAB"}
ERROR_MARKERS = ("SCRIPT ERROR:", "ERROR:", "Parse Error:", "Compile Error:")
SOURCE_ROOTS = ("assets", "config", "scenes", "scripts", "addons")
SOURCE_FILES = ("project.godot", "export_presets.cfg", "icon.svg", "icon.svg.import")
RUNTIME_DATA = ("config/adventure_levels.csv", "assets/localization/messages.json")
EXCLUDED_NAMES = {
    ".git", ".godot", ".codegraph", ".agents", ".codex", "work", "build",
    "dist", "docs", "tools", "tests", "packaging", "__pycache__",
    "godot_ai", "godot-ai", "godotai", "export_credentials.cfg", "godot-ai-license.txt",
}
EXCLUDED_PATTERNS = (
    ".env*", "*.log", "*.tmp", "*.bak", "*.keystore", "*.jks", "*.p12",
    "*.pfx", "*.pem", "*credentials*", "*credential*", "*secret*", "*private_key*",
)


def digest(path: Path, algorithm: str = "sha256") -> str:
    # MD5 is used only for Godot's custom-template identifier, not verification.
    result = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def command(arguments: list[str], *, env: dict[str, str] | None = None,
            timeout: int = 30, log: Path | None = None,
            secrets: tuple[str, ...] = ()) -> str:
    process = subprocess.Popen(
        arguments, cwd=PROJECT_ROOT, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        encoding="utf-8", errors="replace",
        env=env or {**os.environ, "GIT_OPTIONAL_LOCKS": "0"},
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    timed_out = False
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           check=False, creationflags=subprocess.CREATE_NO_WINDOW)
        process.kill()
        output, _ = process.communicate()
    for secret in sorted((value for value in secrets if value), key=len, reverse=True):
        output = output.replace(secret, "[REDACTED]")
        output = output.replace(json.dumps(secret)[1:-1], "[REDACTED]")
    if log:
        log.write_text(output, encoding="utf-8")
    if timed_out:
        raise RuntimeError(f"Command timed out after {timeout} seconds; see {log}.")
    if process.returncode:
        # Never echo untrusted subprocess output: it may contain signing data.
        raise RuntimeError(f"Command exited with {process.returncode}; see {log or 'local tool diagnostics'}.")
    return output.strip()


def read_config(path: Path) -> configparser.ConfigParser:
    config = configparser.ConfigParser(interpolation=None, strict=True)
    config.read_string("[metadata]\n" + path.read_text(encoding="utf-8-sig"))
    return config


def set_section_values(text: str, section: str, values: dict[str, str]) -> str:
    pattern = re.compile(r"(?ms)^\[" + re.escape(section) + r"\]\s*\n(.*?)(?=^\[|\Z)")
    match = pattern.search(text)
    if not match:
        raise ValueError(f"Missing configuration section: {section}")
    body = match.group(1)
    for key, value in values.items():
        key_pattern = re.compile(r"(?m)^" + re.escape(key) + r"=.*$")
        if key_pattern.search(body):
            body = key_pattern.sub(lambda _: key + "=" + value, body)
        else:
            body = body.rstrip() + "\n" + key + "=" + value + "\n\n"
    return text[:match.start(1)] + body + text[match.end(1):]


def preflight(args: argparse.Namespace) -> tuple[Path, str, str, Path, str, str, str]:
    engine = args.godot.expanduser().resolve(strict=True)
    args.sdk = args.sdk.expanduser().resolve(strict=True)
    args.java = args.java.expanduser().resolve(strict=True)
    args.keystore = args.keystore.expanduser().resolve(strict=True)
    if not engine.is_file() or not args.keystore.is_file():
        raise ValueError("Godot and keystore paths must be files.")
    engine_version = command([str(engine), "--version"])
    match = re.match(r"^(4\.7(?:\.\d+)?)\.([^.]+)\.", engine_version)
    if not match:
        raise ValueError("This project requires a Godot 4.7 editor and matching templates.")
    template_version = f"{match.group(1)}.{match.group(2)}"
    default_templates = Path(os.environ.get("APPDATA", "")) / "Godot/export_templates" / template_version
    templates = (args.templates_dir or default_templates).expanduser().resolve(strict=True)
    needed = ("android_debug.apk", "android_release.apk", "android_source.zip")
    if any(not (templates / name).is_file() for name in needed):
        raise ValueError("Install the complete matching Android export templates.")
    version_file = templates / "version.txt"
    # Godot's installed-template manager may omit the archive's version.txt;
    # in that case the canonical version directory is the version evidence.
    found_version = (version_file.read_text(encoding="utf-8-sig").strip()
                     if version_file.is_file() else templates.name)
    if found_version != template_version:
        raise ValueError("Android export-template version does not match the editor; "
                         "use a matching version directory or version.txt.")
    executable_suffix = ".exe" if os.name == "nt" else ""
    for required in (args.sdk / "platform-tools" / f"adb{executable_suffix}",
                     args.java / "bin" / f"java{executable_suffix}",
                     args.java / "bin" / f"keytool{executable_suffix}"):
        if not required.is_file():
            raise ValueError(f"Required Android dependency is missing: {required}")
    java_version = command([str(args.java / "bin" / f"java{executable_suffix}"), "-version"])
    java_match = re.search(r'version "(\d+)', java_version)
    if not java_match or int(java_match.group(1)) < 17:
        raise ValueError("Godot Android export needs JDK 17 or newer.")
    credentials = json.loads(args.credentials_file.read_text(encoding="utf-8-sig"))
    if not isinstance(credentials, dict) or set(credentials) != {"alias", "password"}:
        raise ValueError("Credentials JSON must contain exactly alias and password.")
    if any(not isinstance(credentials[key], str) or not credentials[key] for key in credentials):
        raise ValueError("Credentials alias and password must be nonempty strings.")
    project = read_config(PROJECT_ROOT / "project.godot")
    version = json.loads(project["application"]["config/version"])
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Project config/version must use three numeric components.")
    config = read_config(PROJECT_ROOT / "export_presets.cfg")
    candidates = [section for section in config.sections()
                  if re.fullmatch(r"preset\.\d+", section)
                  and json.loads(config[section].get("name", '""')) == PRESETS[args.format]]
    if len(candidates) != 1:
        raise ValueError(f"Expected exactly one export preset named {PRESETS[args.format]}.")
    section = candidates[0]
    options = config[section + ".options"]
    if json.loads(options["package/unique_name"]) != PACKAGE:
        raise ValueError(f"Android package must be {PACKAGE}.")
    included = {item.strip() for item in json.loads(config[section]["include_filter"]).split(",")}
    if not set(RUNTIME_DATA).issubset(included):
        raise ValueError("Export include_filter must preserve the level CSV and localization catalog.")
    use_gradle = options.get("gradle_build/use_gradle_build") == "true"
    if use_gradle != (args.format == "aab") or options.get("gradle_build/export_format") != str(int(args.format == "aab")):
        raise ValueError("APK must use native APK export; AAB must use Gradle AAB export.")
    if options.get("package/signed") != "true":
        raise ValueError("The Android release preset must enable signing.")
    return engine, engine_version, version, templates, section, credentials["alias"], credentials["password"]


def copy_project(destination: Path, private_files: set[Path]) -> None:
    destination.mkdir(parents=True)
    files: list[Path] = []
    for name in SOURCE_FILES:
        source = PROJECT_ROOT / name
        if source.is_file():
            files.append(source)
    for name in SOURCE_ROOTS:
        source = PROJECT_ROOT / name
        if source.is_dir():
            for directory, subdirs, filenames in os.walk(source, followlinks=False):
                current = Path(directory)
                subdirs[:] = sorted(value for value in subdirs
                                    if value.lower() not in EXCLUDED_NAMES
                                    and not (current / value).is_symlink())
                files.extend(current / value for value in sorted(filenames))
    for source in sorted(files):
        if source.is_symlink() or source.resolve() in private_files:
            continue
        if any(part.lower() in EXCLUDED_NAMES for part in source.relative_to(PROJECT_ROOT).parts):
            continue
        if any(fnmatch.fnmatch(source.name.lower(), pattern) for pattern in EXCLUDED_PATTERNS):
            continue
        target = destination / source.relative_to(PROJECT_ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    project_path = destination / "project.godot"
    text = project_path.read_text(encoding="utf-8-sig")
    text = re.sub(r'(?m)^_mcp_game_helper=.*\n?', "", text)
    text = set_section_values(text, "editor_plugins", {"enabled": "PackedStringArray()"})
    project_path.write_text(text, encoding="utf-8")
    for resource in RUNTIME_DATA:
        if digest(PROJECT_ROOT / resource) != digest(destination / resource):
            raise ValueError(f"Staged runtime data differs from the original: {resource}")


def isolated_engine(engine: Path, work: Path, sdk: Path, java: Path) -> Path:
    # A dedicated self-contained copy keeps SDK/JDK configuration and editor
    # caches away from the user's running editor. No signing data is written here.
    runtime = work / "runtime"
    runtime.mkdir(parents=True, exist_ok=True)
    private_engine = runtime / engine.name
    if not private_engine.is_file() or digest(private_engine) != digest(engine):
        shutil.copy2(engine, private_engine)
    (runtime / "_sc_").write_text("", encoding="utf-8")
    settings_dir = runtime / "editor_data"
    settings_dir.mkdir(exist_ok=True)
    (settings_dir / "editor_settings-4.7.tres").write_text(
        '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
        f'export/android/android_sdk_path = {json.dumps(sdk.as_posix())}\n'
        f'export/android/java_sdk_path = {json.dumps(java.as_posix())}\n'
        'export/android/shutdown_adb_on_exit = false\n', encoding="utf-8")
    return private_engine


def install_gradle_template(source_zip: Path, destination: Path) -> str:
    build_dir = destination / "android/build"
    build_dir.mkdir(parents=True)
    with zipfile.ZipFile(source_zip) as archive:
        for member in archive.infolist():
            path = PurePosixPath(member.filename)
            if path.is_absolute() or ".." in path.parts or "\\" in member.filename:
                raise ValueError("Unsafe path inside Android source template.")
            archive.extract(member, build_dir)
        if archive.testzip() is not None:
            raise ValueError("Android source template has a CRC failure.")
    (build_dir / ".gdignore").write_text("\n", encoding="utf-8")
    # Match ExportTemplateManager::get_android_template_identifier in Godot 4.7:
    # a custom source template uses '<absolute path> [<MD5>]'.
    identifier = f"{source_zip.as_posix()} [{digest(source_zip, 'md5')}]"
    (destination / "android/.build_version").write_text(identifier + "\n", encoding="utf-8")
    return source_zip.as_posix()


def build(args: argparse.Namespace, engine: Path, engine_version: str, version: str,
          templates: Path, section: str, alias: str, password: str) -> None:
    work = PROJECT_ROOT / "work/android-export"
    staging = work / "staging"
    staging.mkdir(parents=True, exist_ok=True)
    distribution = PROJECT_ROOT / "dist"
    distribution.mkdir(exist_ok=True)
    output = distribution / f"Block-{version}-android-release.{args.format}"
    if output.exists():
        raise ValueError(f"Output already exists; preserve/move the old build before rebuilding: {output}")
    stage = Path(tempfile.mkdtemp(prefix=f"{version}-{args.format}-", dir=staging)) / "project"
    private_output = stage.parent / output.name
    copy_project(stage, {args.keystore, args.credentials_file.expanduser().resolve()})
    preset_path = stage / "export_presets.cfg"
    text = preset_path.read_text(encoding="utf-8-sig")
    # Clear every copied signing field, even if another local preset contains one.
    text = re.sub(r'(?m)^keystore/(?:debug|release)(?:_user|_password)?=.*$',
                  lambda match: match.group().split("=", 1)[0] + '=""', text)
    overrides = {"custom_template/debug": json.dumps((templates / "android_debug.apk").as_posix()),
                 "custom_template/release": json.dumps((templates / "android_release.apk").as_posix())}
    if args.format == "aab":
        overrides["gradle_build/android_source_template"] = json.dumps(
            install_gradle_template(templates / "android_source.zip", stage))
        overrides["gradle_build/gradle_build_directory"] = '"res://android"'
    text = set_section_values(text, section + ".options", overrides)
    preset_path.write_text(text, encoding="utf-8")
    export_engine = isolated_engine(engine, work, args.sdk, args.java)
    environment = {**os.environ, "GIT_OPTIONAL_LOCKS": "0",
                   "JAVA_HOME": str(args.java), "ANDROID_HOME": str(args.sdk),
                   "PATH": str(args.java / "bin") + os.pathsep + os.environ.get("PATH", ""),
                   "ANDROID_SDK_ROOT": str(args.sdk),
                   "GRADLE_USER_HOME": str(work / "gradle-home"),
                   "GODOT_ANDROID_KEYSTORE_RELEASE_PATH": args.keystore.as_posix(),
                   "GODOT_ANDROID_KEYSTORE_RELEASE_USER": alias,
                   "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": password}
    log = work / f"{version}-{args.format}-release.log"
    print(f"Exporting {PRESETS[args.format]} from {stage}; log: {log}", flush=True)
    export_log = command([str(export_engine), "--headless", "--path", str(stage),
                          "--export-release", PRESETS[args.format], str(private_output)],
                         env=environment, timeout=1800, log=log, secrets=(password,))
    if any(marker in export_log for marker in ERROR_MARKERS):
        raise RuntimeError(f"Godot reported export errors; see {log}.")
    if not private_output.is_file() or private_output.stat().st_size == 0:
        raise ValueError("Godot did not produce an Android output file.")
    with zipfile.ZipFile(private_output) as archive:
        if archive.testzip() is not None:
            raise ValueError("Android output failed ZIP CRC verification.")
        for resource in RUNTIME_DATA:
            entries = [name for name in archive.namelist() if name.endswith("/" + resource)]
            if len(entries) != 1 or archive.read(entries[0]) != (PROJECT_ROOT / resource).read_bytes():
                raise ValueError(f"Exported runtime data is missing or differs: {resource}")
    # A failed export stays private, so dist never advertises a partial package.
    # Both paths are on the same project volume; publish by atomic rename only
    # after CRC validation, and recheck for a concurrently created destination.
    if output.exists():
        raise ValueError(f"Output appeared during export; keep the checked package at {private_output}.")
    private_output.replace(output)
    if os.name == "nt":
        # A same-volume rename preserves the private staging file's ACL. Reset
        # this published artifact only, so it inherits dist's normal read access.
        # Signing files and their containing directories are never touched.
        command(["icacls", str(output), "/reset"])
    try:
        revision = command(["git", "--no-optional-locks", "rev-parse", "HEAD"])
        dirty = bool(command(["git", "--no-optional-locks", "status", "--porcelain"]))
    except (OSError, RuntimeError):
        revision, dirty = "unknown", None
    info = {"project": "Block", "version": version, "package": PACKAGE,
            "format": args.format, "configuration": "release", "godot": engine_version,
            "source_commit": revision, "source_dirty": dirty,
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "file": output.name, "bytes": output.stat().st_size, "sha256": digest(output),
            "level_config_sha256": digest(stage / "config/adventure_levels.csv"),
            "localization_sha256": digest(stage / "assets/localization/messages.json"),
            "zip_crc": "passed", "signature_verification": "pending_separate_check",
            "runtime_acceptance": "pending_user", "google_play_acceptance": "not_performed"}
    info_path = work / args.format / "build-info.json"
    info_path.parent.mkdir(exist_ok=True)
    info_path.write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    output.with_suffix(output.suffix + ".sha256").write_text(f"{info['sha256']}  {output.name}\n", encoding="ascii")
    print(f"Exported and ZIP-checked (not runtime/Play acceptance):\n{output}\n{info_path}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True, help="Godot 4.7 editor executable")
    parser.add_argument("--sdk", type=Path, required=True, help="Android SDK root")
    parser.add_argument("--java", type=Path, required=True, help="JDK root (not java.exe)")
    parser.add_argument("--keystore", type=Path, required=True, help="Local release upload keystore")
    parser.add_argument("--credentials-file", type=Path, required=True, help="Private JSON with alias and password")
    parser.add_argument("--format", choices=tuple(PRESETS), required=True)
    parser.add_argument("--templates-dir", type=Path, help="Matching export-template version directory")
    parser.add_argument("--check", action="store_true", help="Check dependencies/preset without exporting")
    args = parser.parse_args()
    try:
        details = preflight(args)
        if args.check:
            print("Android export preflight passed; no export or game was run.")
        else:
            build(args, *details)
    except (OSError, ValueError, KeyError, RuntimeError, configparser.Error, zipfile.BadZipFile) as error:
        print(f"Android export failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
