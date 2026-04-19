#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build-testcases.sh [--output-dir DIR] [--release-tag TAG] [--min-app-version VERSION]

Builds a compressed testcase bundle and manifest from dsa-catalog.

Options:
  --output-dir DIR         Output directory for manifest.json and testcases.tar.gz
                           Default: dist/testcases-release
  --release-tag TAG        Bundle version / release tag recorded in the manifest
                           Default: dev
  --min-app-version VER    Minimum compatible grindx app version recorded in the manifest
                           Required
  -h, --help               Show this help text
EOF
}

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

output_dir="dist/testcases-release"
release_tag="dev"
min_app_version=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    --release-tag)
      release_tag="$2"
      shift 2
      ;;
    --min-app-version)
      min_app_version="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$min_app_version" ]]; then
  echo "error: --min-app-version is required" >&2
  usage >&2
  exit 1
fi

archive_path="$output_dir/testcases.tar.gz"
manifest_path="$output_dir/manifest.json"

mkdir -p "$output_dir"

export GRINDX_REPO_ROOT="$repo_root"
export GRINDX_TESTCASE_ARCHIVE="$archive_path"
export GRINDX_TESTCASE_MANIFEST="$manifest_path"
export GRINDX_TESTCASE_RELEASE_TAG="$release_tag"
export GRINDX_TESTCASE_MIN_APP_VERSION="$min_app_version"

python3 - <<'PY'
from __future__ import annotations

import gzip
import hashlib
import json
import os
import pathlib
import subprocess
import tarfile
from datetime import datetime, timezone

repo_root = pathlib.Path(os.environ["GRINDX_REPO_ROOT"])
archive_path = pathlib.Path(os.environ["GRINDX_TESTCASE_ARCHIVE"])
manifest_path = pathlib.Path(os.environ["GRINDX_TESTCASE_MANIFEST"])
release_tag = os.environ["GRINDX_TESTCASE_RELEASE_TAG"]
min_app_version = os.environ["GRINDX_TESTCASE_MIN_APP_VERSION"]

catalog_root = repo_root / "grindx" / "catalog"
topics_path = catalog_root / "topics.json"
problems_root = catalog_root / "problems"


def git_output(args: list[str], default: str) -> str:
    try:
        return subprocess.check_output(
            ["git", *args],
            cwd=repo_root,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (FileNotFoundError, subprocess.CalledProcessError):
        return default

topics = json.loads(topics_path.read_text())
problem_ids: list[str] = []
seen: set[str] = set()
for topic in topics:
    for problem_id in topic.get("problem_ids", []):
        if problem_id in seen:
            continue
        seen.add(problem_id)
        problem_ids.append(problem_id)

missing_problem_json: list[str] = []
missing_testcases: list[str] = []
for problem_id in problem_ids:
    problem_dir = problems_root / problem_id
    if not (problem_dir / "problem.json").is_file():
        missing_problem_json.append(problem_id)
    if not (problem_dir / "testcases.json").is_file():
        missing_testcases.append(problem_id)

if missing_problem_json or missing_testcases:
    messages: list[str] = []
    if missing_problem_json:
        messages.append(
            "missing problem.json for: " + ", ".join(sorted(missing_problem_json))
        )
    if missing_testcases:
        messages.append(
            "missing testcases.json for: " + ", ".join(sorted(missing_testcases))
        )
    raise SystemExit("; ".join(messages))

archive_path.parent.mkdir(parents=True, exist_ok=True)

with archive_path.open("wb") as raw:
    with gzip.GzipFile(
        filename="testcases.tar.gz",
        mode="wb",
        fileobj=raw,
        mtime=0,
    ) as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as tf:
            for problem_id in sorted(problem_ids):
                src = problems_root / problem_id / "testcases.json"
                arcname = f"{problem_id}/testcases.json"
                info = tf.gettarinfo(str(src), arcname=arcname)
                info.uid = 0
                info.gid = 0
                info.uname = ""
                info.gname = ""
                info.mtime = 0
                with src.open("rb") as handle:
                    tf.addfile(info, handle)

sha256 = hashlib.sha256()
with archive_path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        sha256.update(chunk)

manifest = {
    "manifest_version": 1,
    "bundle_format_version": 1,
    "bundle_kind": "testcases-only",
    "release_tag": release_tag,
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "catalog_commit": git_output(["rev-parse", "HEAD"], "unknown"),
    "catalog_commit_short": git_output(["rev-parse", "--short", "HEAD"], "unknown"),
    "min_app_version": min_app_version,
    "filename": archive_path.name,
    "sha256": sha256.hexdigest(),
    "size_bytes": archive_path.stat().st_size,
    "problem_count": len(problem_ids),
    "problems": sorted(problem_ids),
}

manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

print(f"wrote {archive_path}")
print(f"wrote {manifest_path}")
print(f"bundle size: {manifest['size_bytes']} bytes")
print(f"problem count: {manifest['problem_count']}")
print(f"sha256: {manifest['sha256']}")
PY
