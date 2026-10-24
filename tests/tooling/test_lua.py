import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("pentad_lua", ROOT / "tools/pentad_lua.py")
lua = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = lua
SPEC.loader.exec_module(lua)

def kinds(text: str) -> list[tuple[str, str]]:
    return [(token.kind, token.text) for token in lua.lex(text).tokens]

class LexerTests(unittest.TestCase):
    def test_strings_with_escapes_and_quotes(self):
        text = r'''a = "q\"uote" .. 'it\'s' .. "tab\tnew\
line" .. "\z
   joined" .. [[long
string]] .. [==[with ]] inside]==]'''
        tokens = kinds(text)
        strings = [token for token in tokens if token[0] in ("string", "long_string")]
        self.assertEqual(strings, [("string", r'"q\"uote"'), ("string", r"'it\'s'"), ("string", '"tab\\tnew\\\nline"'),
                                   ("string", '"\\z\n   joined"'), ("long_string", "[[long\nstring]]"),
                                   ("long_string", "[==[with ]] inside]==]")])
        self.assertEqual(lua.lex(text).errors, [])
        self.assertEqual(lua.unquote(lua.lex('x("qs -c ii")').tokens[2]), "qs -c ii")
        self.assertIsNone(lua.unquote(lua.lex(r'x("qs \"ii\"")').tokens[2]))
        self.assertIsNone(lua.unquote(lua.lex("x([[qs]])").tokens[2]))

    def test_comments_numbers_names_keywords_and_operators(self):
        text = "#!/usr/bin/lua\nlocal x = 0x1p4 + 3.5e-2 - .5 -- note\n--[==[ long ]] comment ]==] y = x // 2 .. '' ~= a::b ... <<"
        tokens = kinds(text)
        self.assertEqual(tokens[0], ("comment", "#!/usr/bin/lua"))
        self.assertEqual(tokens[1:9], [("keyword", "local"), ("name", "x"), ("op", "="), ("number", "0x1p4"), ("op", "+"),
                                       ("number", "3.5e-2"), ("op", "-"), ("number", ".5")])
        self.assertEqual(tokens[9], ("comment", "-- note"))
        self.assertEqual(tokens[10], ("long_comment", "--[==[ long ]] comment ]==]"))
        self.assertEqual([text for _, text in tokens[11:]], ["y", "=", "x", "//", "2", "..", "''", "~=", "a", "::", "b", "...", "<<"])
        self.assertEqual(lua.lex(text).errors, [])

    def test_unfinished_strings_and_brackets_are_errors_but_still_lexed(self):
        lexed = lua.lex('x = "open\ny = 1\n')
        self.assertEqual(lexed.errors, ["line 1: unfinished string"])
        self.assertEqual([token.text for token in lexed.tokens], ["x", "=", '"open', "y", "=", "1"])
        lexed = lua.lex('f("a") --[[ never closed\nx = 1\n')
        self.assertEqual(lexed.errors, ["line 1: unfinished long comment"])
        self.assertEqual(lexed.code(2), "")
        self.assertFalse(lexed.balanced)
        lexed = lua.lex("x = [[open\n")
        self.assertEqual(lexed.errors, ["line 1: unfinished long string"])
        lexed = lua.lex("x = 1 @ 2\n")
        self.assertEqual(lexed.errors, ["line 1: unexpected character '@'"])

    def test_lines_inside_long_comments_and_strings_have_no_code(self):
        text = ('a = 1 --[[ start\n'
                'hl.exec_cmd("qs -c ii")\n'
                ']] b = 2\n'
                'c = [==[\n'
                'hl.exec_cmd("qs -c ii")\n'
                ']==]\n'
                'd = 3 -- hl.exec_cmd("qs -c ii")\n'
                'e = 4\n')
        lexed = lua.lex(text)
        self.assertEqual(lua.code_lines(text), ["a = 1 ", "", " b = 2", "c = [==[", "", "]==]", "d = 3 ", "e = 4"])
        self.assertEqual([lexed.inside_long(number) for number in range(1, 9)],
                         [False, True, False, False, True, False, False, False])
        self.assertEqual(lexed.code(0), "")
        self.assertEqual(lexed.code(9), "")

    def test_block_depth_follows_every_opener_and_closer(self):
        text = ("function f()\n"
                "  if a then\n"
                "    while b do x() end\n"
                "    for i = 1, 3 do y() end\n"
                "    repeat z() until c\n"
                "    do w() end\n"
                "  elseif d then\n"
                "    v()\n"
                "  else\n"
                "    u()\n"
                "  end\n"
                "end\n"
                "t = {}\n")
        lexed = lua.lex(text)
        depth = {token.text: token.depth for token in lexed.significant() if token.kind == "name"}
        # A block opens at its keyword, so a condition already sits inside the block it guards.
        self.assertEqual(depth, {"f": 1, "a": 2, "b": 2, "x": 3, "i": 2, "y": 3, "z": 3, "c": 2, "w": 3, "d": 2, "v": 2, "u": 2, "t": 0})
        self.assertTrue(lexed.balanced)
        self.assertFalse(lexed.top_level_return)
        self.assertEqual(lua.lex("while x do end end").errors, ["line 1: unexpected end"])
        self.assertEqual(lua.lex("f(").errors, ["unclosed bracket"])
        self.assertEqual(lua.lex("if x then").errors, ["unclosed block"])
        self.assertFalse(lua.lex("x = )").balanced)

    def test_top_level_return_is_seen_anywhere_at_depth_zero(self):
        self.assertTrue(lua.lex("x = 1\n  return { a = 1 }\n").top_level_return)
        self.assertTrue(lua.lex("do end return\n").top_level_return)
        self.assertFalse(lua.lex("function f() return 1 end\n").top_level_return)
        self.assertFalse(lua.lex("x = (function() return 1 end)()\n").top_level_return)
        self.assertFalse(lua.lex("-- return\n").top_level_return)
        self.assertFalse(lua.lex("x = [[\nreturn\n]]\n").top_level_return)

    def test_a_line_is_one_statement_only_at_a_boundary_in_a_block(self):
        call = 'hl.exec_cmd("qs -c ii")'
        hook = 'hl.on("hyprland.start", function () hl.exec_cmd("noctalia") end)'
        accepted = {
            "first line": call + "\n",
            "after a statement": "x = 1\n" + call + "\n",
            "after a call": "f()\n" + call + "\nend_marker = 1\n",
            "inside a hook body": 'hl.on("hyprland.start", function ()\n    ' + call + '\n    hl.exec_cmd("hypridle")\nend)\n',
            "last in a block": "if x then\n  " + call + "\nend\n",
            "before else": "if x then\n  " + call + "\nelse\n  y()\nend\n",
            "before until": "repeat\n  " + call + "\nuntil done\n",
            "after a comment line": "-- note\n" + call + " -- trailing\n",
            "after a semicolon": "x = 1;\n" + call + ";\n",
            "after a long string": "x = [[\nmany\n]]\n" + call + "\n",
            "after a label": "::top::\n" + call + "\n",
            "the one-line hook": hook + "\n",
            "the hook after code": 'require("a")\n' + hook + " -- bar\n",
        }
        for label, text in accepted.items():
            with self.subTest(label):
                number = next(number for number, line in enumerate(text.splitlines(), 1) if call in line or hook in line)
                tokens = lua.lex(text).statement_on(number)
                self.assertIsNotNone(tokens, label)
                self.assertEqual(tokens[0].text, "hl")
                self.assertEqual(tokens[-1].text, ";" if label == "after a semicolon" else ")")
        refused = {
            "a continued assignment": "local start =\n" + call + "\n",
            "a continued assignment past a comment and a blank line": "local x =\n\n-- note\n    " + call + "\n",
            "inside a table": "t = {\n  " + call + ",\n}\n",
            "inside a table after a semicolon": "t = { a = 1;\n  " + call + "\n}\n",
            "inside call parentheses": "wrap(\n  " + call + "\n)\n",
            "inside a for header": "for i = 1,\n  " + call + " do end\n",
            "after return": "return\n" + call + "\n",
            "after an operator": "x = y ..\n" + call + "\n",
            "after and": "x = y and\n" + call + "\n",
            "continued by a call": call + "\n(\"again\")\n",
            "continued by a field": call + "\n.field()\n",
            "continued by a method": call + "\n:method()\n",
            "two statements on the line": call + " hl.exec_cmd(\"waybar\")\n",
            "two statements separated by a long comment": 'hl.exec_cmd("qs") --[[x]] hl.exec_cmd("waybar")\n',
            "a hook opened on the line": 'hl.on("hyprland.start", function () ' + call + "\nend)\n",
            "a string that continues": 'hl.exec_cmd([[qs\n-c ii]])\n',
            "inside a long comment": "--[[\n" + call + "\n]]\n",
            "inside a long string": "x = [[\n" + call + "\n]]\n",
            "a commented line": "-- " + call + "\n",
        }
        for label, text in refused.items():
            with self.subTest(label):
                number = next((number for number, line in enumerate(text.splitlines(), 1) if call in line), 1)
                self.assertIsNone(lua.lex(text).statement_on(number), label)
        tokens = lua.lex("if x then " + call + " end\n").statement_on(1)  # one statement, just not a plain call
        self.assertEqual((tokens[0].text, tokens[-1].text), ("if", "end"))
        self.assertIsNone(lua.lex("\n\n").statement_on(2))

    def test_a_comment_or_string_crossing_the_line_edge_ties_the_line_to_its_neighbours(self):
        # Commenting line 1 out would swallow the `--[[` and bring swaync back to life.
        self.assertIsNone(lua.lex('hl.exec_cmd("waybar") --[[ old:\nhl.exec_cmd("swaync")\n--]]\n').statement_on(1))
        # Line 2 only looks live: it opens inside the long comment that line 1 started.
        self.assertIsNone(lua.lex('--[[ note\n]] hl.exec_cmd("waybar")\n').statement_on(2))
        self.assertIsNone(lua.lex('x = [[\n]] hl.exec_cmd("waybar")\n').statement_on(2))
        self.assertIsNotNone(lua.lex('hl.exec_cmd("waybar") --[[ old ]]\n').statement_on(1))

    def test_a_return_reachable_without_a_function_boundary_counts_as_top_level(self):
        for text in ("do return end\n", "if x then return end\n", "while x do return end\n", "for i = 1, 2 do\n  return\nend\n",
                     "repeat return until x\n", "if a then elseif b then return else end\n"):
            with self.subTest(text=text):
                self.assertTrue(lua.lex(text).top_level_return)
        for text in ("if x then local f = function() return 1 end end\n", "do local function f() return end end\n"):
            with self.subTest(text=text):
                self.assertFalse(lua.lex(text).top_level_return)
        depth = {token.text: token.depth for token in lua.lex("function f() if a then x() end end\n").significant() if token.kind == "name"}
        self.assertEqual(depth, {"f": 1, "a": 2, "x": 2})

    def test_an_if_on_one_line_is_one_statement(self):
        text = 'x = 1\nif package.searchpath("pentad", package.path) then package.loaded.pentad = nil require("pentad") end\ny = 2\n'
        tokens = lua.lex(text).statement_on(2)
        self.assertEqual((tokens[0].text, tokens[-1].text), ("if", "end"))
        self.assertTrue(lua.lex(text).balanced)

if __name__ == "__main__":
    unittest.main()
