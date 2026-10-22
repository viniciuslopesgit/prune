#!/usr/bin/env python3
"""Checks that the app's translations match the source code.

The interface is written in English in the code; each other language has a
Resources/<language>.lproj/Localizable.strings whose keys are those English texts.
This script finds every localizable text in Sources/ and checks, for each language:

  - every text has a translation (otherwise it would show in English);
  - every translation still exists in the code (no forgotten or mistyped keys);
  - the translation keeps the same placeholders (%@, %lld…), in number and type.

Localizable texts are the literals in `String(localized: "…")` and the first,
unlabelled argument of the SwiftUI views and modifiers in SWIFTUI_CALLS
(Text("…"), Button("…"), .help("…"), including both sides of a ternary).
Interpolations (\\(…)) become placeholders; any placeholder type matches them.

Usage: scripts/check_localization.py [project folder]
"""

import json
import re
import subprocess
import sys
from pathlib import Path

SWIFTUI_CALLS = {
    "Text", "Button", "Label", "Toggle", "Section", "Picker", "Menu", "Stepper", "TextField", "Link",
    "LabeledContent", "GroupBox", "help", "navigationTitle", "alert", "confirmationDialog",
}
SPECIFIER = re.compile(r"%(?:(\d+)\$)?(lld|llu|ld|lu|lf|d|u|f|@)")
ANY = "\0"  # marks an interpolation (or a placeholder in a translation key)
MIN_LETTERS = 2  # "%@ · v%@" or "PID %d" do not need translating


class Scanner:
    """Finds the string literals of a Swift file, with the call each one is an argument of."""

    def __init__(self, source):
        self.s = source
        self.found = []  # (key, context, line); context = {"call", "arg", "label"} or None

    def run(self):
        self.code(0)
        return self.found

    def line(self, i):
        return self.s.count("\n", 0, i) + 1

    def label(self, i):
        m = re.match(r"\s*([A-Za-z_]\w*)\s*:(?!:)", self.s[i:i + 80])
        return m.group(1) if m else None

    def code(self, i, interpolation=False):
        s, stack = self.s, []
        while i < len(s):
            c = s[i]
            if s.startswith("//", i):
                j = s.find("\n", i)
                i = len(s) if j < 0 else j
                continue
            if s.startswith("/*", i):
                j = s.find("*/", i + 2)
                i = len(s) if j < 0 else j + 2
                continue
            if s.startswith('"""', i):  # multi-line literals are not used for interface texts
                j = s.find('"""', i + 3)
                i = len(s) if j < 0 else j + 3
                continue
            raw = re.match(r'(#+)"', s[i:i + 10])
            if raw:
                end = '"' + raw.group(1)
                j = s.find(end, i + len(raw.group(0)))
                i = len(s) if j < 0 else j + len(end)
                continue
            if c == '"':
                start = i
                i, key = self.string(i)
                context = dict(stack[-1]) if stack and stack[-1]["call"] is not None else None
                self.found.append((key, context, self.line(start)))
                continue
            if c == "(":
                m = re.search(r"([A-Za-z_]\w*)\s*$", s[max(0, i - 60):i])
                if m:
                    stack.append({"call": m.group(1), "arg": 0, "label": self.label(i + 1)})
                else:  # grouping parentheses, e.g. a nested ternary: same argument as outside
                    stack.append(dict(stack[-1]) if stack else {"call": None})
            elif c in "[{":
                stack.append({"call": None})
            elif c in ")]}":
                if stack:
                    stack.pop()
                elif interpolation and c == ")":
                    return i + 1
            elif c == "," and stack and stack[-1]["call"] is not None:
                stack[-1]["arg"] += 1
                stack[-1]["label"] = self.label(i + 1)
            i += 1
        return i

    def string(self, i):
        s, key = self.s, []
        i += 1
        escapes = {"n": "\n", "t": "\t", "r": "\r", "0": "", '"': '"', "\\": "\\", "'": "'"}
        while i < len(s):
            c = s[i]
            if c == '"':
                return i + 1, "".join(key)
            if c == "\\":
                nxt = s[i + 1]
                if nxt == "(":
                    i = self.code(i + 2, interpolation=True)
                    key.append(ANY)
                    continue
                if nxt == "u":
                    m = re.match(r"u\{([0-9A-Fa-f]+)\}", s[i + 1:])
                    key.append(chr(int(m.group(1), 16)))
                    i += 1 + len(m.group(0))
                    continue
                key.append(escapes.get(nxt, nxt))
                i += 2
                continue
            key.append(c)
            i += 1
        return i, "".join(key)


def is_localized(context):
    if not context or context["arg"] != 0:
        return False
    if context["call"] == "String":
        return context["label"] == "localized"
    return context["call"] in SWIFTUI_CALLS and context["label"] is None


def needs_translation(key):
    return len(re.findall(r"[^\W\d_]", key.replace(ANY, ""))) >= MIN_LETTERS


def source_keys(files):
    """{normalized key: [(file, line), …]} of every localizable text in the given Swift files."""
    keys = {}
    for path in files:
        for key, context, line in Scanner(Path(path).read_text(encoding="utf-8")).run():
            if is_localized(context) and needs_translation(key):
                keys.setdefault(key, []).append((str(path), line))
    return keys


def normalize(key):
    """Translation key → the form source_keys uses (placeholders become ANY; %% becomes %)."""
    return SPECIFIER.sub(ANY, key).replace("%%", "%")


def specifiers(text):
    """Placeholder types in argument order (positional %1$@ placeholders are put back in order)."""
    found = list(SPECIFIER.finditer(text))
    if any(m.group(1) for m in found):
        return [m.group(2) for m in sorted(found, key=lambda m: int(m.group(1) or 0))]
    return [m.group(2) for m in found]


def load_strings(path):
    out = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)], capture_output=True, text=True)
    if out.returncode != 0:
        raise ValueError(f"{path}: {out.stderr.strip() or 'invalid .strings file'}")
    return json.loads(out.stdout)


def compare(code, table):
    """Problems between the texts in the code and one translation table ({key: translation})."""
    problems = []
    translated = {}
    for key, value in table.items():
        n = normalize(key)
        if n in translated:
            problems.append(f'duplicate key once placeholders are ignored: "{key}"')
        translated[n] = key
        if specifiers(key) != specifiers(value):
            problems.append(f'placeholders differ: "{key}" = "{value}"')
    for key, places in sorted(code.items()):
        if key not in translated:
            file, line = places[0]
            problems.append(f'{file}:{line}: no translation for "{key.replace(ANY, "%@")}"')
    for n, key in sorted(translated.items()):
        if n not in code:
            problems.append(f'translation no longer used in the code: "{key}"')
    return problems


def main(root):
    root = Path(root)
    sources = sorted((root / "Sources").rglob("*.swift"))
    code = source_keys(sources)
    tables = sorted(p for p in (root / "Resources").glob("*.lproj/Localizable.strings"))
    if not tables:
        print("No Resources/*.lproj/Localizable.strings found.")
        return 1
    plist_keys = None
    failed = False
    for lproj in sorted((root / "Resources").glob("*.lproj")):
        info = lproj / "InfoPlist.strings"
        keys = set(load_strings(info)) if info.exists() else set()
        if plist_keys is None:
            plist_keys = keys
        elif keys != plist_keys:
            print(f"{info}: keys differ from the other languages ({sorted(keys ^ plist_keys)})")
            failed = True
    for table in tables:
        problems = compare(code, load_strings(table))
        for p in problems:
            print(f"{table.parent.name}: {p}")
        failed |= bool(problems)
    if not failed:
        langs = ", ".join(t.parent.stem for t in tables)
        print(f"{len(code)} texts translated ({langs})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent))
