"""One-off audit: upstream lines added since the common ancestor that are absent
from the merged working tree. Run from the repo root during the v5.5.5 merge.

Usage: python3 docs/merge-notes/audit_lost_lines.py

A missing line is NOT automatically a bug: upstream may have rewritten the same
behaviour, or the line may be a translation value or a moved import. Every hit
must be judged by a human; the point is to make each one visible.
"""
import subprocess
import sys

BASE = "f26aadb3"
UPSTREAM = "v5.5.5"


def git(*args):
    return subprocess.run(["git", *args], capture_output=True)


def text(ref, path):
    r = git("show", f"{ref}:{path}")
    if r.returncode != 0:
        return None
    return r.stdout.decode("utf-8", "replace")


def main():
    diff = git("diff", "--name-only", BASE, UPSTREAM)
    files = diff.stdout.decode().split()
    total_lost = 0
    report = []
    for path in files:
        up = text(UPSTREAM, path)
        base = text(BASE, path)
        if up is None or base is None:
            continue
        # merged result: prefer the working tree (uncommitted merge), fall back to HEAD
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                merged = fh.read()
        except (OSError, IsADirectoryError):
            merged = text("HEAD", path) or ""
        up_added = set(up.splitlines()) - set(base.splitlines())
        merged_lines = set(merged.splitlines())
        lost = sorted(
            line for line in up_added
            if line.strip() and line not in merged_lines
        )
        if lost:
            total_lost += len(lost)
            report.append((path, lost))
    for path, lost in report:
        print(f"# {path}: {len(lost)} upstream-added line(s) not in merged tree")
        for line in lost[:60]:
            print("    ", line.strip()[:120])
    print(f"\n== {total_lost} candidate lost lines across {len(report)} files ==")
    return 0


if __name__ == "__main__":
    sys.exit(main())
