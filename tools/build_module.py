#!/usr/bin/env python3
"""Build Mudlet XML module from src/petria_eqsearch_mudlet.lua.

Usage:
    python tools/build_module.py

Output:
    dist/PetriaEQSearch.xml
"""

from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "petria_eqsearch_mudlet.lua"
DIST = ROOT / "dist"
XML = DIST / "PetriaEQSearch.xml"
MODULE_NAME = "PetriaEQSearch"


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"Source not found: {SRC}")

    lua_code = SRC.read_text(encoding="utf-8")
    DIST.mkdir(parents=True, exist_ok=True)

    xml = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE MudletPackage>
<MudletPackage version="1.001">
  <TriggerPackage />
  <TimerPackage />
  <AliasPackage />
  <ActionPackage />
  <ScriptPackage>
    <ScriptGroup isActive="yes" isFolder="yes">
      <name>{escape(MODULE_NAME)}</name>
      <packageName>{escape(MODULE_NAME)}</packageName>
      <script></script>
      <eventHandlerList />
      <Script isActive="yes" isFolder="no">
        <name>PetriaEQSearch Core</name>
        <packageName>{escape(MODULE_NAME)}</packageName>
        <script>{escape(lua_code)}</script>
        <eventHandlerList />
      </Script>
    </ScriptGroup>
  </ScriptPackage>
  <KeyPackage />
  <HelpPackage>
    <helpURL></helpURL>
  </HelpPackage>
</MudletPackage>
'''

    XML.write_text(xml, encoding="utf-8")
    print(f"Wrote {XML}")


if __name__ == "__main__":
    main()
