#!/usr/bin/env python3
"""Turn one version's entry in site/changelog.html into GitHub release notes.

    ./scripts/release-notes.py 0.9.2              # prints Markdown to stdout
    ./scripts/release-notes.py 0.9.2 --headline   # "Choose how much the notch bounces"

The changelog on the site is the one place release notes are written. This
reads the <h2>VERSION — date</h2> block and its list, and converts the small
amount of markup the changelog uses (<strong>, <em>, <code>, <a>, entities)
into Markdown, framed the same way earlier GitHub releases were: the system
requirement first, a link to the full history last.

Exits non-zero if the version has no entry, so release.sh can't publish an
empty release.
"""
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "site" / "changelog.html"


def inline(fragment: str) -> str:
    s = re.sub(r"\s+", " ", fragment).strip()
    s = re.sub(r"</?strong>", "**", s)
    s = re.sub(r"</?b>", "**", s)
    s = re.sub(r"</?em>", "*", s)
    s = re.sub(r"</?i>", "*", s)
    s = re.sub(r"</?code>", "`", s)
    s = re.sub(r'<a [^>]*href="([^"]+)"[^>]*>(.*?)</a>', r"[\2](\1)", s)
    s = re.sub(r"<[^>]+>", "", s)
    return html.unescape(s)


def entry(version: str) -> str:
    text = CHANGELOG.read_text(encoding="utf-8")
    start = re.search(r"<h2>" + re.escape(version) + r"\s", text)
    if not start:
        raise SystemExit(f"error: no changelog entry for {version}")
    rest = text[start.end():]
    end = re.search(r"<h2>|</main>|</article>", rest)
    return rest[: end.start()] if end else rest


def headline(version: str) -> str:
    """The first item's bold lead-in, for the release title."""
    m = re.search(r"<strong>(.*?)</strong>", entry(version), re.S)
    return inline(m.group(1)).rstrip(".") if m else ""


def notes(version: str) -> str:
    block = entry(version)
    items = [inline(li) for li in re.findall(r"<li>(.*?)</li>", block, re.S)]
    paras = [inline(p) for p in re.findall(r"<p>(.*?)</p>", block, re.S)]
    if not items and not paras:
        raise SystemExit(f"error: the {version} entry has no content")

    out = [
        "Requires **Apple Silicon and macOS 26**. On an Intel Mac or macOS 15? "
        "Use [0.6.0](https://github.com/xnucade/AloeNotch/releases/tag/v0.6.0), "
        "the final release for those machines.",
        "",
        "### What's new",
        "",
    ]
    out += [f"- {i}" for i in items]
    if paras:
        out += [""] + paras
    out += ["", "Full history: https://aloenotch.com/changelog"]
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) == 2 and args[1] == "--headline":
        print(headline(args[0]))
    elif len(args) == 1:
        sys.stdout.write(notes(args[0]))
    else:
        raise SystemExit("usage: release-notes.py <version> [--headline]")
