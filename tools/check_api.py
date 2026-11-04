#!/usr/bin/env python3
"""Checks that every global and every method Bingo de la Guild uses exists in WoW Forever.

forever-lint only reports APIs that exist in other clients and not in Forever; a typo or an invented
name would slip through. This script lists every global the addon reads and every `:Method(` it calls,
and looks each one up in:

  * Ketho/BlizzardInterfaceResources (branch forever): GlobalAPI, FrameXML, Frames, LuaEnum, WidgetAPI,
    GlobalStrings, Events;
  * Gethe/wow-ui-source (branch forever): top-level assignments and `function X:Method` / `X.Method`
    definitions in Blizzard's own Lua and XML (mixins such as ScrollingEditBoxMixin, MenuUtil, SOUNDKIT).

  python tools/check_api.py --bir ../BlizzardInterfaceResources --ui ../wow-ui-source [--scanner ../addon-sentry/src]

It uses Addon Sentry's scope-aware Lua scanner (pip install addon-sentry, or --scanner path).
Exit code 1 when something is not found.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "BingoDeLaGuild"

STRING_METHODS = set("byte find format gmatch gsub len lower match rep reverse sub upper".split())
LUA_STD = set(
    """assert collectgarbage date error getmetatable ipairs next pairs pcall print rawequal rawget rawset select
    setmetatable tonumber tostring type unpack xpcall math string table os coroutine bit time _G""".split()
)


def strings_in(path: Path) -> set[str]:
    return set(re.findall(r'"([^"]+)"', path.read_text(encoding="utf-8", errors="replace")))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bir", type=Path, required=True, help="BlizzardInterfaceResources checkout (branch forever)")
    ap.add_argument("--ui", type=Path, required=True, help="wow-ui-source checkout (branch forever)")
    ap.add_argument("--addon", type=Path, default=ADDON, help="addon folder (default: BingoDeLaGuild/)")
    ap.add_argument("--scanner", type=Path, help="addon-sentry src folder, if it is not installed")
    args = ap.parse_args()
    if args.scanner:
        sys.path.insert(0, str(args.scanner))
    from addon_sentry.lua import scan  # noqa: PLC0415  (scope-aware: locals and parameters are not refs)

    res = args.bir / "Resources"
    known_globals: set[str] = set(LUA_STD)
    for name in ("GlobalAPI.lua", "FrameXML.lua", "Frames.lua", "Mixins.lua"):
        known_globals |= strings_in(res / name)
    known_globals |= set(re.findall(r"^(\w+) = ", (res / "GlobalStrings" / "enUS.lua").read_text(encoding="utf-8"), re.M))
    enum_text = (res / "LuaEnum.lua").read_text(encoding="utf-8")
    known_globals |= {"Enum"} | {f"Enum.{m}" for m in re.findall(r"^\t(\w+) = \{", enum_text, re.M)}
    known_globals |= {n.split(".")[0] for n in known_globals if "." in n}  # C_DateAndTime on its own, as in `C_DateAndTime and ...`
    known_methods: set[str] = set(re.findall(r'"(\w+)"', (res / "WidgetAPI.lua").read_text(encoding="utf-8")))

    # Blizzard UI code: globals it defines and methods its mixins and utility tables have.
    top_assign = re.compile(r"^(\w+)\s*=", re.M)
    func_def = re.compile(r"^\s*function\s+([\w.]+)[.:](\w+)\s*\(", re.M)
    table_field = re.compile(r"^\s*(\w+)\s*=\s*function", re.M)
    xml_name = re.compile(r'<\w+[^>]*\bname="(\w+)"')
    for p in args.ui.rglob("*.lua"):
        text = p.read_text(encoding="utf-8", errors="replace")
        known_globals |= set(top_assign.findall(text))
        known_globals |= set(re.findall(r"^_G\.(\w+)\s*=", text, re.M))  # _G.SlashCmdList = {}
        for owner, method in func_def.findall(text):
            known_globals.add(owner.split(".")[0])
            known_globals.add(f"{owner}.{method}")
            known_methods.add(method)
        known_methods |= set(table_field.findall(text))
    for p in args.ui.rglob("*.xml"):
        known_globals |= set(xml_name.findall(p.read_text(encoding="utf-8", errors="replace")))
    fields = set()  # names assigned as table fields anywhere in Blizzard's code (ScrollBoxConstants.RetainScrollPosition)
    for p in args.ui.rglob("*.lua"):
        fields |= set(re.findall(r"^\s*(\w+)\s*=", p.read_text(encoding="utf-8", errors="replace"), re.M))
    soundkit = set()
    for p in args.ui.rglob("SoundKitConstants*.lua"):
        soundkit |= set(re.findall(r"^\s*(\w+)\s*=\s*\d+", p.read_text(encoding="utf-8"), re.M))

    own_globals: set[str] = set()
    addon = args.addon
    tocs = list(addon.glob("*.toc"))
    for toc in list(tocs):  # SavedVariables of addons it depends on are its globals too (Bitacora_Datos)
        for dep in re.findall(r"^## (?:Dependencies|RequiredDeps|Dep\w*):\s*(.+)$", toc.read_text(encoding="utf-8"), re.MULTILINE):
            for name in (d.strip() for d in dep.split(",")):
                tocs += list((addon.parent / name).glob("*.toc"))
    for toc in tocs:
        for m in re.finditer(r"^## SavedVariables(?:PerCharacter)?:\s*(.+)$", toc.read_text(encoding="utf-8"), re.M):
            own_globals |= {v.strip() for v in m.group(1).split(",")}
    own_methods: set[str] = set()
    files = sorted(addon.rglob("*.lua"))
    for p in files:
        text = p.read_text(encoding="utf-8")
        own_globals |= set(re.findall(r"^(\w+)\s*=", text, re.M)) | set(re.findall(r"^function\s+(\w+)\s*\(", text, re.M))
        own_methods |= set(re.findall(r"function\s+[\w.]+[:.](\w+)\s*\(", text))
        own_methods |= set(re.findall(r"\b(?:list|view|row|b)\.(\w+)\s*=", text))

    missing: list[str] = []
    for p in files:
        text = p.read_text(encoding="utf-8")
        s = scan(str(p), text)
        rel = p.relative_to(addon.parent)
        for r in s.refs:
            first = r.name.split(".")[0]
            if r.name in known_globals or r.name in own_globals:
                continue
            if first in own_globals or first in LUA_STD:
                continue
            if first in ("SOUNDKIT",) and r.name.split(".")[-1] in soundkit:
                continue
            if first in known_globals and "." in r.name and not first.startswith("C_"):
                # a Blizzard table; its fields are checked when the table is a known namespace
                if r.name in known_globals or any(r.name.endswith("." + m) and m in known_methods for m in [r.name.split(".")[-1]]):
                    continue
            if first in known_globals and "." not in r.name:
                continue
            if first in known_globals and r.name.split(".")[-1] in fields and not first.startswith("C_"):
                continue
            missing.append(f"{rel}:{r.tok.line}: global {r.name}")
        for m in re.finditer(r":(\w+)\s*\(", text):
            method = m.group(1)
            if method in known_methods or method in own_methods or method in STRING_METHODS:
                continue
            line = text.count("\n", 0, m.start()) + 1
            missing.append(f"{rel}:{line}: method :{method}()")
    # templates and font objects: CreateFrame(type, name, parent, "Template"), font strings and UI.Label(..., "Font")
    templates = set(re.findall(r'^\t\["(\w+)"\]', (res / "Templates.lua").read_text(encoding="utf-8"), re.MULTILINE))
    used = re.compile(
        r'CreateFrame\([^)]*?,\s*"(\w+)"\s*\)|CreateFontString\([^)]*?"(\w+)"\s*\)|UI\.Label\([^)]*?"(GameFont\w+)"|"(GameFont\w+)"'
    )
    for p in files:
        text = p.read_text(encoding="utf-8")
        for m in used.finditer(text):
            name = next(g for g in m.groups() if g)
            if name not in templates and name not in (
                "Frame",
                "Button",
                "EditBox",
                "CheckButton",
                "EventFrame",
                "OVERLAY",
                "ARTWORK",
                "BACKGROUND",
            ):
                missing.append(f"{p.relative_to(addon.parent)}:{text.count(chr(10), 0, m.start()) + 1}: template or font {name}")
    for line in sorted(set(missing)):
        print(line)
    print(f"{len(files)} files, {len(set(missing))} names not found in Forever", file=sys.stderr)
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
