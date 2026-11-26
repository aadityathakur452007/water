"""Runnable unit checks for tools/mobile-tester scripts."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "tools" / "mobile-tester"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


verify = load_module("verify_free_model", ROOT / "verify_free_model.py")
screen = load_module("screen", ROOT / "screen.py")
typer = load_module("type_mod", ROOT / "type.py")


class MobileTesterTests(unittest.TestCase):
    def test_parse_opencode_models_filters_opencode_prefix(self) -> None:
        sample = """
        anthropic/claude-sonnet-4-5
        opencode/big-pickle
        openai/gpt-4o
        opencode/gpt-5-nano
        opencode/big-pickle
        """
        self.assertEqual(
            verify.parse_opencode_models(sample),
            ["opencode/big-pickle", "opencode/gpt-5-nano"],
        )

    def test_rank_candidates_rejects_paid_override(self) -> None:
        with self.assertRaises(ValueError):
            verify.rank_candidates(["opencode/big-pickle"], primary_override="anthropic/claude-sonnet-4-5")

    def test_check_clean_env_rejects_paid_keys(self) -> None:
        with self.assertRaises(RuntimeError):
            verify.check_clean_env({"ANTHROPIC_API_KEY": "sk-ant-123"})

    def test_parse_ui_elements(self) -> None:
        xml = """<hierarchy><node text="Login" class="android.widget.Button" clickable="true" bounds="[100,200][300,260]" /></hierarchy>"""
        self.assertEqual(screen.parse_ui_elements(xml), ['- button "Login" centre=(200,230)'])

    def test_sanitize_and_escape(self) -> None:
        self.assertEqual(typer.sanitize_and_escape("Café 123!"), "Cafe%s123!")

    def test_parse_verbose_free_vision_models(self) -> None:
        sample = """opencode/big-pickle
{"cost":{"input":0,"output":0},"capabilities":{"toolcall":true,"input":{"image":false}}}
opencode/deepseek-v4.1-flash-free
{"cost":{"input":0,"output":0},"capabilities":{"toolcall":true,"input":{"image":true}}}
opencode/paid-model
{"cost":{"input":1,"output":2},"capabilities":{"toolcall":true,"input":{"image":true}}}
"""
        vision, text_only = verify.parse_verbose_free_vision_models(sample)
        self.assertEqual(vision, ["opencode/deepseek-v4.1-flash-free"])
        self.assertEqual(text_only, ["opencode/big-pickle"])


if __name__ == "__main__":
    unittest.main()
