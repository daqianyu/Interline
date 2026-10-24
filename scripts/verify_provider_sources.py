#!/usr/bin/env python3
"""Independently check original Q01 files after system-provider UI tests."""
import argparse
import hashlib
import json
import plistlib
from pathlib import Path


def simulator_documents(data_root: Path) -> Path:
    """Read the selected CI simulator's retained container without booting it.

    Fail on a missing/ambiguous bundle identity instead of checking another app.
    This host-side inspection is only used on the disposable CI simulator.
    """
    containers = data_root / "Containers" / "Data" / "Application"
    matches = []
    for metadata in containers.glob("*/.com.apple.mobile_container_manager.metadata.plist"):
        with metadata.open("rb") as handle:
            identity = plistlib.load(handle).get("MCMMetadataIdentifier")
        if identity == "com.interline.app":
            matches.append(metadata.parent / "Documents")
    if len(matches) != 1:
        raise ValueError(f"Expected one Interline data container, found {len(matches)}")
    return matches[0]


def verify(documents: Path, manifest: Path, minimum_suites: int) -> dict:
    expected = json.loads(manifest.read_text(encoding="utf-8"))
    suites = sorted(documents.glob("InterlineQ01-*"))
    if len(suites) < minimum_suites:
        raise ValueError(f"Expected at least {minimum_suites} suites, found {len(suites)}")
    records = []
    for suite in suites:
        for entry in expected["files"]:
            name = entry["name"]
            if Path(name).name != name:
                raise ValueError("Invalid fixture filename")
            data = (suite / name).read_bytes()
            actual = hashlib.sha256(data).hexdigest()
            if len(data) != entry["bytes"] or actual != entry["sha256"]:
                raise ValueError(f"Source file changed: {suite.name}/{name}")
            records.append({"suite": suite.name, "file": name, "bytes": len(data), "sha256": actual})
    return {"result": "passed", "suites": len(suites), "files": records,
            "scope": "Original source bytes only; UI assertions separately establish import behavior"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--documents", type=Path)
    source.add_argument("--simulator-data-root", type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--minimum-suites", type=int, default=5)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    documents = args.documents if args.documents is not None else simulator_documents(args.simulator_data_root)
    result = verify(documents, args.manifest, args.minimum_suites)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {len(result['files'])} source files in {result['suites']} suites")


if __name__ == "__main__":
    main()
