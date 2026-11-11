#!/usr/bin/env python3
"""Checks that a Mach-O binary can load on an older macOS.

    check-macos-sdk.py <binary> <MacOSX<ver>.sdk>

Fails if the binary hard-links (non-weak) a system library that the SDK
doesn't have, or binds a non-weak symbol that no library in the SDK exports.
dyld refuses to launch an app with either, so this catches APIs that are newer
than the SDK's macOS. Weak imports are fine: they resolve to NULL when missing.
"""
import re
import subprocess
import sys
from pathlib import Path

BLOCK = re.compile(
    r"(symbols|weak-symbols|thread-local-symbols|objc-classes|objc-eh-types|objc-ivars):\s*\[(.*?)\]",
    re.S,
)


def sdk_exports(sdk: Path) -> set[str]:
    names: set[str] = set()
    for tbd in sdk.rglob("*.tbd"):
        text = tbd.read_text(errors="replace")
        for kind, body in BLOCK.findall(text):
            for raw in body.split(","):
                name = raw.strip().strip("'\"")
                if not name:
                    continue
                if kind == "objc-classes":
                    base = name.lstrip("_")
                    names.update({f"_OBJC_CLASS_$_{base}", f"_OBJC_METACLASS_$_{base}"})
                elif kind == "objc-eh-types":
                    names.add(f"_OBJC_EHTYPE_$_{name.lstrip('_')}")
                elif kind == "objc-ivars":
                    names.add(f"_OBJC_IVAR_$_{name.lstrip('_')}")
                else:
                    names.add(name)
    return names


def load_commands(binary: str) -> list[tuple[str, str]]:
    out = subprocess.run(["otool", "-l", binary], capture_output=True, text=True, check=True).stdout
    loads, cmd = [], None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("cmd "):
            cmd = line.split()[1]
        elif line.startswith("name ") and cmd in ("LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB"):
            loads.append((cmd, line.split()[1]))
    return loads


def in_sdk(sdk: Path, path: str) -> bool:
    if not path.startswith(("/System/", "/usr/lib/")):
        return True  # not a system library; checked elsewhere
    p = Path(path)
    candidates = [sdk / p.relative_to("/").with_suffix(".tbd"), sdk / (str(p.relative_to("/")) + ".tbd")]
    # .../Foo.framework/Versions/A/Foo -> .../Foo.framework/Foo.tbd
    m = re.match(r"(.*/[^/]+\.framework)/Versions/[^/]+/([^/]+)$", path)
    if m:
        candidates.append(sdk / m.group(1).lstrip("/") / f"{m.group(2)}.tbd")
    return any(c.exists() for c in candidates)


def strong_imports(binary: str) -> list[tuple[str, str]]:
    out = subprocess.run(["nm", "-m", "-u", binary], capture_output=True, text=True, check=True).stdout
    found = []
    for line in out.splitlines():
        m = re.match(r"\s*\(undefined\)\s+(weak\s+)?(?:external\s+)?(\S+)(?:\s+\(from ([^)]+)\))?", line)
        if m and not m.group(1):
            found.append((m.group(2), m.group(3)))
    return found


def main() -> int:
    binary, sdk = sys.argv[1], Path(sys.argv[2])
    problems = []
    for cmd, path in load_commands(binary):
        state = "weak" if cmd == "LC_LOAD_WEAK_DYLIB" else "strong"
        print(f"{state:6} {path}")
        if cmd != "LC_LOAD_WEAK_DYLIB" and not in_sdk(sdk, path):
            problems.append(f"hard-links {path}, which {sdk.name} doesn't have")
    exports = sdk_exports(sdk)
    imports = strong_imports(binary)
    for name, lib in imports:
        if name not in exports:
            src = f" (from {lib})" if lib else ""
            problems.append(f"needs {name}{src}, which {sdk.name} doesn't export")
    print(f"{len(imports)} non-weak imports checked against {len(exports)} symbols in {sdk.name}")
    for p in problems:
        print(f"::error::{p}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
