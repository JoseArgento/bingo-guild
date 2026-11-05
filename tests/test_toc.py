"""The TOC lists only the files the game should load as code or UI.

Bindings.xml is read by the game on its own, by name; listed in the TOC it is parsed as a UI file and
every <Binding> line becomes a LUA_WARNING (seen in BugGrabber on 5/11).
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def tocs():
    return sorted(p for p in ROOT.glob("*/*.toc") if "Libs" not in p.parts)


def test_there_is_a_toc():
    assert tocs()


def test_no_toc_lists_bindings_xml():
    for toc in tocs():
        lines = [line.strip().lower() for line in toc.read_text(encoding="utf-8").splitlines()]
        assert "bindings.xml" not in lines, f"{toc.name} lists Bindings.xml"


def test_every_listed_file_exists():
    for toc in tocs():
        for line in toc.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            assert (toc.parent / line.replace("\\", "/")).is_file(), f"{toc.name}: {line} is missing"
