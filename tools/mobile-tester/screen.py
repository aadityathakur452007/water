"""Capture an Android emulator screenshot, UI element centers, and recent crashes.

Usage:
    python3 tools/mobile-tester/screen.py <out_dir> <NN>
"""

from __future__ import annotations

import io
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image


def adb(*args: str, raw: bool = False) -> bytes | str:
    proc = subprocess.run(["adb", *args], capture_output=True, timeout=60, check=False)
    return proc.stdout if raw else proc.stdout.decode("utf-8", "replace")


def parse_ui_elements(xml_text: str) -> list[str]:
    """Return human-readable element lines with center coordinates in real pixels."""
    if "<" not in xml_text:
        return []
    try:
        root = ET.fromstring(xml_text[xml_text.find("<") :])
    except ET.ParseError:
        return []

    lines: list[str] = []
    for node in root.iter("node"):
        text = (node.get("text") or "").strip()
        desc = (node.get("content-desc") or "").strip()
        is_edit = node.get("class", "").endswith("EditText")
        bounds = re.findall(r"\d+", node.get("bounds", ""))
        if not (text or desc or is_edit) or len(bounds) != 4:
            continue
        x1, y1, x2, y2 = map(int, bounds)
        cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
        kind = "field" if is_edit else ("button" if node.get("clickable") == "true" else "text")
        label = (text or desc)[:70].replace('"', "'")
        lines.append(f'- {kind} "{label}" centre=({cx},{cy})')
    return lines


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: python3 tools/mobile-tester/screen.py <out_dir> <NN>", file=sys.stderr)
        return 2

    out_dir = Path(sys.argv[1])
    nn = sys.argv[2]
    out_dir.mkdir(parents=True, exist_ok=True)

    png = adb("exec-out", "screencap", "-p", raw=True)
    assert isinstance(png, bytes)
    if b"\x89PNG" in png:
        png = png[png.find(b"\x89PNG") :]
    img = Image.open(io.BytesIO(png)).convert("RGB")
    w, h = img.size
    img.resize((max(1, w // 2), max(1, h // 2))).save(out_dir / f"{nn}.png")
    print(f"screenshot: {out_dir}/{nn}.png (screen {w}x{h}; image is half size: multiply image coords by 2)")

    adb("shell", "uiautomator", "dump", "/data/local/tmp/ui.xml")
    xml_text = adb("exec-out", "cat", "/data/local/tmp/ui.xml")
    assert isinstance(xml_text, str)
    if "<" in xml_text:
        (out_dir / f"{nn}.xml").write_text(xml_text[xml_text.find("<") :], encoding="utf-8")

    for line in parse_ui_elements(xml_text):
        print(line)

    crash = str(adb("logcat", "-d", "-b", "crash")) + str(
        adb("logcat", "-d", "AndroidRuntime:E", "flutter:E", "*:S")
    )
    adb("logcat", "-c")
    err_lines = [ln for ln in crash.splitlines() if ln.strip() and not ln.startswith("-----")]
    if err_lines:
        print("ERRORS SINCE LAST SCREENSHOT:\n" + "\n".join(err_lines[-15:]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
