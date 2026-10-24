#!/usr/bin/env python3
"""A small Lua 5.x lexer for `pentad doctor` and `pentad setup`.

Setup comments out another shell's start line only when that line is one complete statement, and it
appends its include line only to a file that is balanced and has no top-level return. Regular
expressions cannot tell a call inside a long comment, a long string or a table constructor from a real
statement; the token stream can. Hyprland 0.56 links Lua 5.5, so the 5.5 keyword `global` is known.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

KEYWORDS = frozenset("and break do else elseif end false for function global goto if in local nil not or "
                     "repeat return then true until while".split())
# A statement may start right after these: the previous one is complete, or a block has just opened.
STATEMENT_END_KEYWORDS = frozenset({"end", "true", "false", "nil", "break", "do", "then", "else", "repeat"})
STATEMENT_END_OPS = frozenset({")", "]", "}", ";", "::", "..."})
STATEMENT_START_KEYWORDS = frozenset({"local", "global", "function", "if", "while", "for", "repeat", "return", "break",
                                      "goto", "do"})
CLOSERS = frozenset({"end", "until", "else", "elseif"})
OPERATORS = ("...", "..", "::", "<<", ">>", "//", "==", "~=", "<=", ">=",
             "+", "-", "*", "/", "%", "^", "#", "&", "~", "|", "<", ">", "=", "(", ")", "{", "}", "[", "]", ";", ":", ",", ".")
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUMBER = re.compile(r"0[xX][0-9A-Fa-f]*(?:\.[0-9A-Fa-f]*)?(?:[pP][+-]?[0-9]+)?|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?")
LONG_OPEN = re.compile(r"\[(=*)\[")

@dataclass(frozen=True)
class Token:
    kind: str  # name, keyword, number, string, long_string, comment, long_comment, op, error
    text: str
    start: int  # offset into the text
    end: int  # offset one past the token
    line: int  # 1-based line where the token starts
    end_line: int  # 1-based line where the token ends
    context: str  # innermost syntactic context before the token: chunk, block, function, bracket or header
    depth: int  # open blocks (function, if, do, repeat, while … do, for … do) before the token
    stack: int  # open contexts of every kind before the token
    boundary: bool  # a statement may start at this token

    @property
    def significant(self) -> bool:
        return self.kind not in ("comment", "long_comment")

@dataclass
class Lexed:
    text: str
    tokens: list[Token] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)  # unfinished strings or brackets, stray closers
    final_stack: int = 0  # open contexts at the end of the text
    top_level_return: bool = False  # a return outside every function, even inside do/if/loop blocks
    line_starts: list[int] = field(default_factory=list)
    _codes: list[str | None] | None = None

    @property
    def balanced(self) -> bool:
        return not self.errors and self.final_stack == 0

    def significant(self) -> list[Token]:
        return [token for token in self.tokens if token.significant]

    def line_span(self, line: int) -> tuple[int, int]:
        start = self.line_starts[line - 1]
        if line < len(self.line_starts):
            return start, self.line_starts[line] - 1
        return start, len(self.text) - 1 if self.text.endswith("\n") else len(self.text)

    def inside_long(self, line: int) -> bool:
        """True when the whole line lies inside a long comment or a long string."""
        return 1 <= line <= len(self.line_starts) and self.codes()[line - 1] is None

    def code(self, line: int) -> str:
        """The line without its comments; empty when it lies inside a long comment or string."""
        if line < 1 or line > len(self.line_starts):
            return ""
        return self.codes()[line - 1] or ""

    def codes(self) -> list[str | None]:
        """Every line without comments, None for lines inside a long comment or string; computed once."""
        if self._codes is None:
            lines: list[str | None] = [self.text[self.line_span(number)[0]:self.line_span(number)[1]]
                                       for number in range(1, len(self.line_starts) + 1)]
            for token in self.tokens:
                if token.kind in ("long_comment", "long_string"):
                    for number in range(token.line + 1, token.end_line):
                        lines[number - 1] = None
                if token.kind in ("comment", "long_comment"):
                    for number in range(token.line, token.end_line + 1):
                        if lines[number - 1] is None:
                            continue
                        start, end = self.line_span(number)
                        cut_start, cut_end = max(token.start, start) - start, min(token.end, end) - start
                        lines[number - 1] = lines[number - 1][:cut_start] + lines[number - 1][cut_end:]
            self._codes = lines
        return self._codes

    def statement_on(self, line: int) -> list[Token] | None:
        """The significant tokens of the line when they form exactly one complete statement, else None.

        The statement must start at a statement boundary in a block (not inside brackets or a loop header),
        every token must start and end on the line, no comment or string may cross the line's edges, the
        contexts it opens must close on the line, and the token after it must be able to start a statement
        or close the block.
        """
        significant = self.significant()
        indexes = [index for index, token in enumerate(significant) if token.line == line]
        if not indexes:
            return None
        tokens = [significant[index] for index in indexes]
        first, last = tokens[0], tokens[-1]
        if not first.boundary or first.context not in ("chunk", "block", "function"):
            return None
        if any(token.end_line != line for token in tokens):
            return None
        # A comment or string that starts before the line or runs past it ties the line to its neighbours:
        # commenting the line out would swallow a `--[[` opener, and a line that opens inside `]]` is not live code.
        if any(token.line <= line <= token.end_line and (token.line < line or token.end_line > line) for token in self.tokens):
            return None
        after = significant[indexes[-1] + 1] if indexes[-1] + 1 < len(significant) else None
        stack_after = after.stack if after else self.final_stack
        if stack_after != first.stack:
            return None
        if after is not None and not after.boundary and not (after.kind == "keyword" and after.text in CLOSERS):
            return None
        if any(token.boundary and token.stack == first.stack and token.text != ";" for token in tokens[1:]):
            return None  # a second statement at the same level; a trailing `;` is an empty one
        return tokens

def ends_statement(token: Token | None) -> bool:
    if token is None:
        return True
    if token.kind in ("name", "number", "string", "long_string"):
        return True
    if token.kind == "keyword":
        return token.text in STATEMENT_END_KEYWORDS
    return token.kind == "op" and token.text in STATEMENT_END_OPS

def starts_statement(kind: str, text: str) -> bool:
    if kind == "name":
        return True
    if kind == "keyword":
        return text in STATEMENT_START_KEYWORDS
    return kind == "op" and text in ("::", ";")

def lex(text: str) -> Lexed:
    """Tokenize a whole Lua chunk, tolerating errors so that a broken file still yields its lines."""
    result = Lexed(text)
    # Lines are numbered like str.splitlines(): a final newline does not open an extra line.
    result.line_starts = [0] + [match.end() for match in re.finditer(r"\n", text) if match.end() < len(text)]
    stack: list[str] = []  # block, function, bracket or header
    previous: Token | None = None
    position, line = 0, 1
    length = len(text)

    def add(kind: str, start: int, end: int) -> None:
        nonlocal previous, line
        end_line = line + text.count("\n", start, max(start, end - 1))  # the line of the token's last character
        context = stack[-1] if stack else "chunk"
        depth = stack.count("block") + stack.count("function")
        significant = kind not in ("comment", "long_comment")
        boundary = significant and ends_statement(previous) and starts_statement(kind, text[start:end])
        token = Token(kind, text[start:end], start, end, line, end_line, context, depth, len(stack), boundary)
        result.tokens.append(token)
        line = end_line
        if not significant:
            return
        word = token.text
        if kind == "keyword":
            if word == "function":
                stack.append("function")
            elif word in ("if", "repeat"):
                stack.append("block")
            elif word in ("while", "for"):
                stack.append("header")
            elif word == "do":
                if stack and stack[-1] == "header":
                    stack[-1] = "block"
                else:
                    stack.append("block")
            elif word in ("end", "until"):
                if stack and stack[-1] in ("block", "function"):
                    stack.pop()
                else:
                    result.errors.append(f"line {token.line}: unexpected {word}")
            elif word == "return" and "function" not in stack:
                # Inside do/if/loop blocks the return may or may not run; either way a line appended after
                # it is not guaranteed to run, so the file is treated as ending in a return.
                result.top_level_return = True
        elif kind == "op":
            if word in ("(", "{", "["):
                stack.append("bracket")
            elif word in (")", "}", "]"):
                if stack and stack[-1] == "bracket":
                    stack.pop()
                else:
                    result.errors.append(f"line {token.line}: unexpected {word}")
        previous = token

    if text.startswith("#"):  # a shebang line is skipped by the loader
        end = text.find("\n")
        end = length if end < 0 else end
        add("comment", 0, end)
        position = end
    while position < length:
        char = text[position]
        if char == "\n":
            line += 1
            position += 1
            continue
        if char in " \t\r\f\v":
            position += 1
            continue
        if text.startswith("--", position):
            opening = LONG_OPEN.match(text, position + 2)
            if opening:
                end = long_bracket_end(text, opening.end(), len(opening.group(1)))
                if end is None:
                    result.errors.append(f"line {line}: unfinished long comment")
                    end = length
                add("long_comment", position, end)
            else:
                end = text.find("\n", position)
                add("comment", position, length if end < 0 else end)
            position = result.tokens[-1].end
            continue
        if char == "[" and (opening := LONG_OPEN.match(text, position)):
            end = long_bracket_end(text, opening.end(), len(opening.group(1)))
            if end is None:
                result.errors.append(f"line {line}: unfinished long string")
                end = length
            add("long_string", position, end)
            position = end
            continue
        if char in "\"'":
            end, finished = short_string_end(text, position)
            if not finished:
                result.errors.append(f"line {line}: unfinished string")
            add("string", position, end)
            position = end
            continue
        if char.isdigit() or (char == "." and position + 1 < length and text[position + 1].isdigit()):
            match = NUMBER.match(text, position)
            add("number", position, match.end())
            position = match.end()
            continue
        if match := NAME.match(text, position):
            add("keyword" if match.group() in KEYWORDS else "name", position, match.end())
            position = match.end()
            continue
        for operator in OPERATORS:
            if text.startswith(operator, position):
                add("op", position, position + len(operator))
                position += len(operator)
                break
        else:
            result.errors.append(f"line {line}: unexpected character {char!r}")
            add("error", position, position + 1)
            position += 1
    result.final_stack = len(stack)
    if stack:
        result.errors.append("unclosed " + ", ".join(stack))
    return result

def long_bracket_end(text: str, start: int, level: int) -> int | None:
    """The offset one past the closing bracket of the same level, or None when it never closes."""
    closing = "]" + "=" * level + "]"
    end = text.find(closing, start)
    return None if end < 0 else end + len(closing)

def short_string_end(text: str, start: int) -> tuple[int, bool]:
    """The offset one past the closing quote; an unfinished string ends at the newline or the end of text."""
    quote = text[start]
    position = start + 1
    while position < len(text):
        char = text[position]
        if char == "\\":
            if text.startswith("z", position + 1):  # \z skips the following whitespace, newlines included
                position += 2
                while position < len(text) and text[position] in " \t\r\n\f\v":
                    position += 1
                continue
            position += 2
            continue
        if char == quote:
            return position + 1, True
        if char == "\n":
            return position, False
        position += 1
    return len(text), False

def code_lines(text: str) -> list[str]:
    """Every line of the chunk without comments, in order; lines inside long comments or strings are empty."""
    lexed = lex(text)
    return [lexed.code(number) for number in range(1, len(lexed.line_starts) + 1)]

def unquote(token: Token) -> str | None:
    """The value of a plain short string, or None when it has escapes or is a long string."""
    if token.kind != "string" or "\\" in token.text or len(token.text) < 2:
        return None
    return token.text[1:-1]
