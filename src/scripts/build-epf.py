#!/usr/bin/env python3
"""Build license.epf from the source src/license-epf/Форма.bsl without Designer.

The epf container (not a zip) is unpacked by v8unpack -PARSE into a temporary
tree, the form module (stream <form-uuid>.0, stored as a single line: CR
separators, quotes doubled) is replaced with the serialized Форма.bsl, then
packed back with v8unpack -BUILD.

GOTCHAS (Sep 15, three days of bisecting):
1. v8unpack — ONLY the xDrivenDevelopment/v8unpack 3.0.1 fork (build:
   debian:12-slim + g++ make zlib1g-dev libboost-*-dev, patch #include
   <iostream> in src/V8File.cpp). e8tools 3.0.43 packs broken containers.
2. The byte length of the module MUST NOT change: the platform silently skips
   /Execute on any change to it (a dependency inside the form stream). Working
   pattern: shrink comment lines of Форма.bsl and pad with an ASCII comment
   up to EXACTLY the original number of bytes.
3. A compile error in the module = the same silent /Execute skip (no dialog) —
   after edits, run with params=DUMP (marker in license-result.txt).
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EPF = ROOT / "src" / "license-epf" / "license.epf"
BSL = ROOT / "src" / "license-epf" / "Форма.bsl"
START = '{50,0},1},"'
END = '\n",'  # the module is stored with CR separators inside the string, closed by LF + ","
V8U_DIR = Path("/tmp/v8unpack-bin")  # v8unpack 3.0.1 binary (see docstring)

V8U_SETUP = (
    "apt-get update -qq >/dev/null;"
    " apt-get install -y -qq --no-install-recommends"
    " libboost-filesystem1.74.0 libboost-system1.74.0 >/dev/null 2>&1;"
    " /bin2/v8unpack"
)


def v8unpack(*args: str) -> None:
    cmd = [
        "docker", "run", "--rm",
        "-v", f"{V8U_DIR}:/bin2:ro",
        "-v", f"{ROOT}:/work", "-w", "/work",
        "debian:12-slim", "bash", "-c",
        V8U_SETUP + " " + " ".join(args),
    ]
    subprocess.run(cmd, check=True)


def serialize_module(text: str) -> str:
    lines = text.replace("\r\n", "\n").split("\n")
    return "\r".join(lines).replace('"', '""')


def fit_to_bytes(src: str, orig_bytes: int) -> str:
    """Shrink by trimming comments and/or pad up to exactly orig_bytes bytes."""
    def size(t: str) -> int:
        return len(serialize_module(t).encode("utf-8"))

    if size(src) > orig_bytes:
        lines, k = src.split("\n"), 0
        while size("\n".join(lines)) > orig_bytes:
            while k < len(lines) and not lines[k].lstrip().startswith("//"):
                k += 1
            if k >= len(lines):
                sys.exit(f"модуль длиннее оригинала на {size(src)-orig_bytes} байт, комментарии кончились")
            del lines[k]
        src = "\n".join(lines)

    ser = serialize_module(src)
    pad = orig_bytes - len(ser.encode("utf-8"))
    if pad >= 3:
        ser += "\r//" + "X" * (pad - 3)
    elif pad > 0:
        ser += " " * pad
    assert len(ser.encode("utf-8")) == orig_bytes, "байтовая длина не сошлась"
    return ser


def main() -> None:
    if not (V8U_DIR / "v8unpack").exists():
        sys.exit("нет /tmp/v8unpack-bin/v8unpack — рецепт сборки в docstring и README")

    tree = ROOT / "src" / "license-epf" / "unpacked"
    if tree.exists():
        shutil.rmtree(tree)
    v8unpack("-PARSE", "/work/src/license-epf/license.epf", "/work/src/license-epf/unpacked")

    form_files = sorted(tree.glob("*.0"))
    assert len(form_files) == 1, f"ожидался один поток формы, найдено {len(form_files)}"
    form = form_files[0]
    data = open(form, encoding="utf-8-sig", newline="").read()

    i = data.index(START) + len(START)
    j = data.index(END, i)
    orig_bytes = len(data[i:j].encode("utf-8"))
    src = open(BSL, encoding="utf-8", newline="").read()
    ser = fit_to_bytes(src, orig_bytes)

    with open(form, "w", encoding="utf-8-sig", newline="") as f:
        f.write(data[:i] + ser + data[j:])

    out = EPF.with_suffix(".epf.new")
    v8unpack("-BUILD", "/work/src/license-epf/unpacked", "/work/src/license-epf/license.epf.new")
    EPF.rename(EPF.with_suffix(".epf.bak")) if EPF.exists() else None
    out.rename(EPF)
    print(f"OK: {EPF} ({EPF.stat().st_size} байт, модуль {orig_bytes} байт — как оригинал)")


if __name__ == "__main__":
    sys.exit(main())
