#!/usr/bin/env python3
"""Lists the CloudKit record types and fields in a wanted schema that another schema lacks.

Usage: cloudkit-schema-diff.py WANTED.ckdb ACTUAL.ckdb

Used by the CloudKit schema workflow to say what still needs deploying to production
(docs/ICLOUD_SYNC.md). Prints one line per missing or mistyped field and exits 0 either way;
the summary says whether anything is left to deploy.
"""
import re
import sys

RECORD = re.compile(r'^\s*RECORD TYPE\s+("?[\w]+"?)')
FIELD = re.compile(r'^\s*("?[A-Za-z_][\w]*"?)\s+([A-Z0-9<>]+)')


def parse(path):
    fields = {}
    record = None
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("--"):
                continue
            match = RECORD.match(line)
            if match:
                record = match.group(1).strip('"')
                fields.setdefault(record, {})
                continue
            if stripped.startswith(");"):
                record = None
                continue
            if record is None or stripped.startswith("GRANT"):
                continue
            match = FIELD.match(line)
            if match:
                fields[record][match.group(1).strip('"')] = match.group(2)
    return fields


def main():
    wanted, actual = parse(sys.argv[1]), parse(sys.argv[2])
    problems = []
    for record, record_fields in sorted(wanted.items()):
        if record not in actual:
            problems.append(f"record type {record} is missing")
            continue
        for name, kind in sorted(record_fields.items()):
            have = actual[record].get(name)
            if have is None:
                problems.append(f"{record}.{name} ({kind}) is missing")
            elif have != kind:
                problems.append(f"{record}.{name} is {have}, expected {kind}")
    for problem in problems:
        print(problem)
    return problems


if __name__ == "__main__":
    main()
