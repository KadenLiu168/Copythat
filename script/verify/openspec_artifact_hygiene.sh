#!/usr/bin/env bash
set -euo pipefail

# Read-only path gate: openspec/changes/ may only contain the official OpenSpec
# artifacts. Defaults to this checkout; a checkout root may be passed to scan a
# fixture tree. Exit 0 = clean, 1 = unexpected artifacts or symlinks, 2 = the
# gate could not complete a full scan.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKOUT="${1:-$ROOT_DIR}"

exec python3 - "$CHECKOUT" <<'PY'
"""Reject `.md` and `.txt` documents that are not an official OpenSpec artifact.

A change directory holds proposal.md, design.md, tasks.md, and
specs/<capability>/spec.md, in active changes and archived ones alike.
`archive` is the reserved archive container, never a change name. The scan
stays inside openspec/changes/, follows no symlink, and never reads file
contents, so it judges paths only.
"""

import os
import re
import sys

ALLOWED = re.compile(
    r"^openspec/changes/"
    r"(?:archive/)?"
    r"(?!archive(?:/|$))[^/]+/"
    r"(?:proposal\.md|design\.md|tasks\.md|specs/(?:[^/]+/)+spec\.md)$"
)
# Document extensions the gate polices: a change directory may hold the four
# OpenSpec artifact forms and no other `.md` or `.txt` document.
POLICED = (".md", ".txt")
# macOS keeps trailing spaces, tabs and dots in names that other tools drop, so
# `verification.txt ` is still a document rather than an unrelated file.
INVISIBLE_TRAILING = " .\t\n\r"

GUIDANCE = (
    "Only <change>/proposal.md, <change>/design.md, <change>/tasks.md, and "
    "<change>/specs/<capability>/spec.md are allowed, also under archive/.\n"
    "Move durable information into those artifacts, openspec/specs, or docs/ "
    "and keep ephemeral evidence in .build/ or /tmp/ or report it in the agent "
    "response."
)


def safe(path):
    """Render a path unambiguously on one line, escaping what a reader cannot see."""
    trailing = len(path) - len(path.rstrip(" "))
    rendered = []
    for index, char in enumerate(path):
        if char == "\\":
            rendered.append("\\\\")
        elif char == "\n":
            rendered.append("\\n")
        elif char == "\r":
            rendered.append("\\r")
        elif char == "\t":
            rendered.append("\\t")
        elif char == " " and index >= len(path) - trailing:
            rendered.append("\\x20")
        elif char.isprintable():
            rendered.append(char)
        else:
            rendered.append("\\x%02x" % ord(char))
    return "".join(rendered)


def scan(directory, relative, unsupported, links, failures):
    try:
        entries = list(os.scandir(directory))
    except OSError as error:
        failures.append((relative, str(error)))
        return
    for entry in entries:
        entry_relative = relative + "/" + entry.name
        try:
            if entry.is_symlink():
                links.append((entry_relative, os.readlink(entry.path)))
            elif entry.is_dir(follow_symlinks=False):
                scan(entry.path, entry_relative, unsupported, links, failures)
            elif entry.is_file(follow_symlinks=False):
                if entry.name.rstrip(INVISIBLE_TRAILING).lower().endswith(POLICED) and not ALLOWED.fullmatch(entry_relative):
                    unsupported.append(entry_relative)
        except OSError as error:
            failures.append((entry_relative, str(error)))


def main():
    checkout = sys.argv[1]
    openspec = os.path.join(checkout, "openspec")
    changes = os.path.join(openspec, "changes")
    failures = []
    if os.path.islink(openspec):
        failures.append(("openspec", "scan root is a symlink"))
    elif not os.path.exists(openspec):
        failures.append(("openspec", "missing directory"))
    if os.path.islink(changes):
        failures.append(("openspec/changes", "scan root is a symlink"))
    elif not os.path.exists(changes):
        failures.append(("openspec/changes", "missing scan root"))
    elif not os.path.isdir(changes):
        failures.append(("openspec/changes", "scan root is not a directory"))

    if failures:
        for relative, reason in sorted(failures):
            print(
                "ERROR openspec artifact hygiene: cannot scan %s: %s"
                % (safe(relative), safe(reason)),
                file=sys.stderr,
            )
        return 2

    unsupported = []
    links = []
    scan(changes, "openspec/changes", unsupported, links, failures)

    if failures:
        print(
            "FAIL openspec artifact hygiene: the scan of openspec/changes was incomplete",
            file=sys.stderr,
        )
        for relative, reason in sorted(failures):
            print("  %s: %s" % (safe(relative), safe(reason)), file=sys.stderr)
        return 2

    if not unsupported and not links:
        print("PASS openspec artifact hygiene")
        return 0

    print("FAIL openspec artifact hygiene")
    if unsupported:
        print("Unexpected documents under openspec/changes:")
        for relative in sorted(unsupported):
            print("  " + safe(relative))
    if links:
        print("Symlinks are not allowed under openspec/changes, and are never followed:")
        for relative, target in sorted(links):
            print("  %s -> %s" % (safe(relative), safe(target)))
    for line in GUIDANCE.splitlines():
        print(line)
    return 1


if __name__ == "__main__":
    sys.exit(main())
PY
