"""Type ASCII-normalized text into the currently focused Android input field.

Usage:
    python3 tools/mobile-tester/type.py "text"
"""

from __future__ import annotations

import re
import subprocess
import sys
import unicodedata


def sanitize_and_escape(text: str) -> str:
    ascii_text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"([\\'\"`$&|;<>()*~#])", r"\\\1", ascii_text).replace(" ", "%s")


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: python3 tools/mobile-tester/type.py \"text\"", file=sys.stderr)
        return 2
    escaped = sanitize_and_escape(sys.argv[1])
    subprocess.run(["adb", "shell", "input", "keyevent", "KEYCODE_MOVE_END"], check=False)
    subprocess.run(["adb", "shell", "input", "keyevent", *(["67"] * 40)], check=False)
    subprocess.run(["adb", "shell", "input", "text", escaped], check=False)
    print("typed: verify on next screenshot")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
