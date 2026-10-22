#!/usr/bin/env python3
"""Generate original Q01 provider fixtures in a new directory, never user files."""
import argparse
import hashlib
import json
from pathlib import Path


TEXT = "第一章 起点\n这是文件流程验收专用的原创测试文字。\n同一正文采用不同编码，不能重复建书。\n\n第二章 归途\n取消和失败后，原书、笔记和草稿仍应保留。\n"
CANONICAL = "第一章 起点\n\n这是文件流程验收专用的原创测试文字。\n\n同一正文采用不同编码，不能重复建书。\n\n第二章 归途\n\n取消和失败后，原书、笔记和草稿仍应保留。"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Must not already exist")
    parser.add_argument("--include-oversized", action="store_true", help="Also generate a 20 MiB + 1 byte TXT")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    samples = {
        "q01-utf8.txt": (TEXT.encode("utf-8"), "UTF-8", "valid"),
        "q01-utf16le.txt": (b"\xff\xfe" + TEXT.encode("utf-16-le"), "UTF-16 LE", "valid"),
        "q01-utf16be.txt": (b"\xfe\xff" + TEXT.encode("utf-16-be"), "UTF-16 BE", "valid"),
        "q01-gb18030.txt": (TEXT.encode("gb18030"), "GB18030 / GBK", "valid"),
        "q01-duplicate.txt": (TEXT.encode("utf-8"), "UTF-8", "duplicate of q01-utf8.txt"),
        "q01-empty.txt": (b"", None, "reject empty content"),
        "q01-nul.txt": (b"provider-test\x00invalid", "UTF-8", "reject embedded NUL with explicit UTF-8"),
    }
    if args.include_oversized:
        samples["q01-over-20mib.txt"] = (b"x" * (20 * 1024 * 1024 + 1), "UTF-8", "reject over size limit")
    manifest = {
        "scope": "Fixture expectations only; not evidence of app/provider acceptance",
        "expected_chapters": ["第一章 起点", "第二章 归途"],
        "expected_book_id": "txt-" + hashlib.sha256(CANONICAL.encode("utf-8")).hexdigest(),
        "files": [],
    }
    for name, (data, encoding, expected) in samples.items():
        (args.output / name).write_bytes(data)
        manifest["files"].append({"name": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "encoding": encoding, "expected": expected})
    (args.output / "expected.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(samples)} samples and expected.json in {args.output}")


if __name__ == "__main__":
    main()
