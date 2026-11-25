#!/usr/bin/env python3
"""Per-module records of the alpo.ge archive replay.

build LOG BUILD_TSV CLASSES_TSV SUMMARY
    Parse the Lake build log into one build record per module, the warning
    counts per message class, and a summary with the log's digest. Message
    text is never copied: only counts leave the log.
merge BUILD_TSV EVIDENCE OUT_TSV
    Join the build records with each host's replay verdicts under EVIDENCE.
"""

from __future__ import annotations

import collections
import hashlib
import re
import sys
from pathlib import Path

SYMBOLS = {
    chr(0x2714): "ok",
    chr(0x26A0): "warn",
    chr(0x2139): "info",
    chr(0x2716): "fail",
}
HEADER = re.compile(
    "^(["
    + "".join(SYMBOLS)
    + r"]) \[\d+/\d+\] (Built|Replayed) (\S+?)(?: \(([0-9.]+)(ms|s|m)\))?$"
)
MESSAGE = re.compile(r"^(warning|error|info): \S+?:\d+:\d+: (.*)$")
SECONDS = {"ms": 0.001, "s": 1.0, "m": 60.0}
SORRY = re.compile(r"declaration uses '?sorry'?")
CLASSES = (
    ("unreachable_tactic", re.compile(r"^this tactic is never executed")),
    ("unused_tactic", re.compile(r"^Unused tactic linter:")),
    ("try_this", re.compile(r"^Try this:")),
    (
        "unused_section_variable",
        re.compile(r"^automatically included section variable"),
    ),
    (
        "unused_variable",
        re.compile(r"^(Variable name .* is not explicitly referenced|unused name:)"),
    ),
    ("unused_simp_argument", re.compile(r"^This simp argument is unused")),
    ("deprecated", re.compile(r"has been deprecated")),
    ("overlapping_instances", re.compile(r"^Overlapping instance parameters")),
)
BUILD_COLUMNS = "module\tbuild_status\tjob_seconds\twarnings\tinfos\terrors"
RECORD_COLUMNS = (
    "module\tkind\tbuild_status\tjob_seconds\twarnings\tinfos\terrors"
    "\treplay_hosts\treplay_driver_hosts\treplay_fail_lines"
)


def classify(message: str) -> str:
    for name, pattern in CLASSES:
        if pattern.search(message):
            return name
    return "other"


class Record:
    def __init__(self) -> None:
        self.built = False
        self.status = "replayed"
        self.seconds = 0.0
        self.counts = {"warning": 0, "info": 0, "error": 0}
        self.replay_counts: dict[str, int] | None = None
        self.replay_classes: collections.Counter[str] = collections.Counter()


def build(log: Path, build_tsv: Path, classes_tsv: Path, summary: Path) -> None:
    digest = hashlib.sha256()
    records: dict[str, Record] = {}
    classes: collections.Counter[str] = collections.Counter()
    headers: collections.Counter[str] = collections.Counter()
    sorry = 0
    lines = 0
    size = 0
    current: Record | None = None
    replay_open: Record | None = None
    with log.open("rb") as handle:
        for raw in handle:
            digest.update(raw)
            size += len(raw)
            lines += 1
            line = raw.decode("utf-8", errors="replace").rstrip("\n")
            match = HEADER.match(line)
            if match:
                symbol, verb, name, amount, unit = match.groups()
                headers[SYMBOLS[symbol] + " " + verb] += 1
                record = records.setdefault(name, Record())
                current = None
                replay_open = None
                if verb == "Built":
                    record.built = True
                    record.status = SYMBOLS[symbol]
                    record.seconds = float(amount) * SECONDS[unit]
                    record.counts = {"warning": 0, "info": 0, "error": 0}
                    current = record
                elif not record.built and record.replay_counts is None:
                    record.status = "replayed"
                    record.replay_counts = {"warning": 0, "info": 0, "error": 0}
                    replay_open = record
                continue
            if line[:1] in SYMBOLS and line[1:3] == " [":
                current = None
                replay_open = None
            message = MESSAGE.match(line)
            if not message:
                continue
            kind, text = message.groups()
            if kind == "warning" and SORRY.search(text):
                sorry += 1
            if current is not None:
                current.counts[kind] += 1
                if kind == "warning":
                    classes[classify(text)] += 1
            elif replay_open is not None and replay_open.replay_counts is not None:
                replay_open.replay_counts[kind] += 1
                if kind == "warning":
                    replay_open.replay_classes[classify(text)] += 1
    for record in records.values():
        if not record.built:
            classes.update(record.replay_classes)
    with build_tsv.open("w", encoding="utf-8") as out:
        out.write(BUILD_COLUMNS + "\n")
        for name in sorted(records):
            record = records[name]
            counts = (
                record.counts
                if record.built
                else (record.replay_counts or record.counts)
            )
            seconds = "%.1f" % record.seconds if record.built else "-"
            out.write(
                "%s\t%s\t%s\t%d\t%d\t%d\n"
                % (
                    name,
                    record.status,
                    seconds,
                    counts["warning"],
                    counts["info"],
                    counts["error"],
                )
            )
    with classes_tsv.open("w", encoding="utf-8") as out:
        out.write("warning_class\tcount\n")
        for name, count in sorted(
            classes.items(), key=lambda item: (-item[1], item[0])
        ):
            out.write("%s\t%d\n" % (name, count))
    with summary.open("w", encoding="utf-8") as out:
        out.write("build_log_sha256 %s\n" % digest.hexdigest())
        out.write("build_log_bytes %d\n" % size)
        out.write("build_log_lines %d\n" % lines)
        out.write("modules %d\n" % len(records))
        for key in sorted(headers):
            out.write("headers %s %d\n" % (key, headers[key]))
        out.write("sorry_warnings %d\n" % sorry)


def read_lines(path: Path) -> list[str]:
    if not path.is_file():
        return []
    return path.read_text(encoding="utf-8").splitlines()


def merge(build_tsv: Path, evidence: Path, out_tsv: Path) -> None:
    leaves = set(read_lines(evidence / "modules" / "leaves.txt"))
    parents = set(read_lines(evidence / "modules" / "parents.txt"))
    passed: dict[str, set[str]] = collections.defaultdict(set)
    driver: dict[str, set[str]] = collections.defaultdict(set)
    fails: collections.Counter[str] = collections.Counter()
    for host_dir in sorted((evidence / "hosts").iterdir()):
        host = host_dir.name
        for relative in ("results.txt", "recheck/results.txt"):
            for line in read_lines(host_dir / relative):
                fields = line.split(" ")
                if fields[0] == "PASS":
                    passed[fields[1]].add(host)
                elif fields[0] == "FAIL":
                    fails[fields[1]] += 1
        for relative in ("driver-results.txt", "recheck/driver-results.txt"):
            for line in read_lines(host_dir / relative):
                fields = line.split(" ")
                if fields[0] == "PASS":
                    driver[fields[1]].add(host)
    rows = read_lines(build_tsv)
    if rows[0] != BUILD_COLUMNS:
        sys.exit("unexpected build record header")
    with out_tsv.open("w", encoding="utf-8") as out:
        out.write(RECORD_COLUMNS + "\n")
        for row in rows[1:]:
            name, status, seconds, warnings, infos, errors = row.split("\t")
            kind = (
                "parent"
                if name in parents
                else "leaf"
                if name in leaves
                else "unlisted"
            )
            out.write(
                "\t".join(
                    (
                        name,
                        kind,
                        status,
                        seconds,
                        warnings,
                        infos,
                        errors,
                        ",".join(sorted(passed[name])) or "-",
                        ",".join(sorted(driver[name])) or "-",
                        str(fails[name]),
                    )
                )
                + "\n"
            )


def main(argv: list[str]) -> int:
    if len(argv) == 6 and argv[1] == "build":
        build(Path(argv[2]), Path(argv[3]), Path(argv[4]), Path(argv[5]))
        return 0
    if len(argv) == 5 and argv[1] == "merge":
        merge(Path(argv[2]), Path(argv[3]), Path(argv[4]))
        return 0
    sys.stderr.write(__doc__ or "")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
