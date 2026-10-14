"""Structural sanity check for the Kotlin and Swift sources.

    python shared/tools/check_source_syntax.py

There is no Kotlin or Swift compiler on the development machine, so this script
does the cheap half of a compile: it walks every .kt and .swift file, skips
comments and string literals (including Kotlin raw strings and Swift multi line
strings) and verifies that brackets, parentheses and braces are balanced and
correctly nested. It catches truncated or mis-pasted files, which is the failure
mode that hand written patches have.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    ROOT / "Android" / "app" / "src",
    ROOT / "Android-ARIndoorNav" / "app" / "src",
    ROOT / "IOS",
]
SUFFIXES = (".kt", ".swift")
PAIRS = {")": "(", "]": "[", "}": "{"}


def check(path: Path):
    text = path.read_text(encoding="utf-8")
    index = 0
    length = len(text)
    line = 1
    stack = []
    while index < length:
        char = text[index]
        if char == "\n":
            line += 1
            index += 1
            continue
        if text.startswith("//", index):
            while index < length and text[index] != "\n":
                index += 1
            continue
        if text.startswith("/*", index):
            depth = 1
            index += 2
            while index < length and depth:
                if text[index] == "\n":
                    line += 1
                if text.startswith("/*", index):
                    depth += 1
                    index += 2
                    continue
                if text.startswith("*/", index):
                    depth -= 1
                    index += 2
                    continue
                index += 1
            continue
        if text.startswith('"""', index):
            index += 3
            while index < length and not text.startswith('"""', index):
                if text[index] == "\n":
                    line += 1
                index += 1
            index += 3
            continue
        if char == '"':
            index += 1
            while index < length:
                if text[index] == "\\":
                    index += 2
                    continue
                if text[index] == '"':
                    index += 1
                    break
                if text[index] == "\n":
                    line += 1
                index += 1
            continue
        if char == "'":
            index += 1
            while index < length:
                if text[index] == "\\":
                    index += 2
                    continue
                if text[index] == "'":
                    index += 1
                    break
                if text[index] == "\n":
                    break
                index += 1
            continue
        if char in "([{":
            stack.append((char, line))
            index += 1
            continue
        if char in ")]}":
            if not stack or stack[-1][0] != PAIRS[char]:
                return "unexpected '" + char + "'"
            stack.pop()
            index += 1
            continue
        index += 1
    if stack:
        return "unclosed '" + stack[-1][0] + "' opened on line " + str(stack[-1][1])
    return None


def main() -> int:
    checked = 0
    problems = 0
    for source_root in SOURCES:
        for path in sorted(source_root.rglob("*")):
            if path.suffix not in SUFFIXES:
                continue
            if "build" in path.parts:
                continue
            checked += 1
            problem = check(path)
            if problem:
                problems += 1
                print("problem: " + os.path.relpath(path, ROOT) + ": " + problem)
    print("checked {} Kotlin and Swift files, {} problems".format(checked, problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

