#!/usr/bin/env python3
"""GODKIT installer helper: pure text work, no side effects beyond the output path it is given.

  stage.py render IN OUT KEY=VALUE...   literal token replacement (no sed: a model id may hold & | \\ ")
  stage.py block  FILE BLOCK OUT        FILE with the godkit BLOCK replaced in place, or appended once
  stage.py sha    FILE                  sha256 of the file (empty line when absent)

`block` is what makes the law/harness patches updatable: a block is delimited by
`<!-- GODKIT:begin NAME -->` ... `<!-- GODKIT:end NAME -->` (NAME read from BLOCK's first line). A file
patched by an older kit has no markers: its block started at a known line and ran to the end of the file
(the kit only ever appended), so that tail is cut and replaced.
"""
import hashlib
import re
import sys

LEGACY_HEADS = ("## GODKIT additions", "- GODKIT pointer")


def die(msg):
    sys.stderr.write(f"stage.py: {msg}\n")
    sys.exit(1)


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def render(src, dst, pairs):
    text = read(src)
    for pair in pairs:
        key, sep, value = pair.partition("=")
        if not sep or not key:
            die(f"bad KEY=VALUE: {pair!r}")
        text = text.replace(key, value)
    left = re.findall(r"_[A-Z]+_MODEL_|<ROOM_DIR>", text)
    if left:
        die(f"a placeholder survived rendering in {src}: {sorted(set(left))}")
    write(dst, text)


def block(path, block_path, out):
    existing = read(path)
    new = read(block_path).rstrip("\n") + "\n"
    first = new.splitlines()[0]
    m = re.fullmatch(r"<!-- GODKIT:begin (\S+) -->", first)
    if not m:
        die(f"{block_path}: first line must be '<!-- GODKIT:begin NAME -->'")
    end = f"<!-- GODKIT:end {m.group(1)} -->"
    if new.splitlines()[-1] != end:
        die(f"{block_path}: last line must be '{end}'")
    b, e = existing.find(first), existing.find(end)
    if b != -1 and e != -1 and e > b:
        result = existing[:b] + new.rstrip("\n") + existing[e + len(end):]
    else:
        cut = len(existing)
        for head in LEGACY_HEADS:
            if existing.startswith(head):
                cut = 0
                break
            idx = existing.find("\n" + head)
            if idx != -1:
                cut = min(cut, idx + 1)
        base = existing[:cut].rstrip("\n")
        result = (base + "\n\n" if base else "") + new
    if not result.endswith("\n"):
        result += "\n"
    write(out, result)


def sha(path):
    try:
        with open(path, "rb") as fh:
            print(hashlib.sha256(fh.read()).hexdigest())
    except FileNotFoundError:
        print("")


def main(argv):
    if len(argv) < 2:
        die(__doc__)
    cmd = argv[1]
    if cmd == "render" and len(argv) >= 4:
        render(argv[2], argv[3], argv[4:])
    elif cmd == "block" and len(argv) == 5:
        block(argv[2], argv[3], argv[4])
    elif cmd == "sha" and len(argv) == 3:
        sha(argv[2])
    else:
        die(__doc__)


main(sys.argv)
