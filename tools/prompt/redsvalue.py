# -*- coding: utf-8 -*-
"""Reading redscript literals, and only literals.

The corpus this mod sends to a model -- the cast sheets, <world_lore>, <system_rules>, the
tone tiers, the WORDS tables -- is written by hand inside .reds files. An offline prompt
builder needs that text, and there are exactly two ways to get it: copy it, or read it from
the source. A copy is wrong the first time somebody edits a sheet, and wrong SILENTLY -- the
prompt still comes out, plausible and stale. So nothing here is ever retyped.

WHAT THIS FILE IS, AND IS NOT. It is not a redscript interpreter and must never become one.
It reads the shapes that authored text actually appears in:

    "a" + "b"                         concatenation of literals
    name                              a local bound earlier in the same function
    obj.field                         a field of an object built earlier
    Fn(arg, ...)                      kept as an unevaluated node, resolved by the caller
    cond ? "a" : "b"                  kept as an unevaluated node, likewise

Anything else raises RedsParseError, loudly, naming the file and the line. That is the whole
anti-drift mechanism: a construct this reader has never seen is a construct whose text would
otherwise go missing, and a build that stops is the only honest answer to it.

Values come back as JSON-friendly trees so they can be stored in corpus.json and resolved by
whoever knows what a given call means:

    "plain text"
    {"concat": [ ... ]}
    {"call": "AiNpcWorldLoreWords", "args": [ ... ]}
    {"ternary": {"cond": ..., "then": ..., "else": ...}}
    {"ref": "isFemale"}
    {"member": ["archive", "bio"]}
"""

import re


class RedsParseError(Exception):
    pass


# ── Lexing ───────────────────────────────────────────────────────────────────
#
# Comment stripping happens HERE and not with a regex over the whole file, because "//" is
# ordinary text inside a prompt string and a regex cannot tell the two apart. The lexer
# knows whether it is inside a literal; a regex would silently truncate a sheet.

_IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_NUMBER_RE = re.compile(r"[0-9]+(\.[0-9]+)?")

_ESCAPES = {
    "n": "\n",
    "r": "\r",
    "t": "\t",
    "\\": "\\",
    '"': '"',
    "'": "'",
    "0": "\0",
}


class Token(object):
    __slots__ = ("kind", "value", "line")

    def __init__(self, kind, value, line):
        self.kind = kind      # "str" | "ident" | "punct" | "end"
        self.value = value
        self.line = line

    def __repr__(self):
        return "Token(%s, %r, line %d)" % (self.kind, self.value, self.line)


def tokenize(source, where="<source>"):
    """Every token of a .reds source, comments dropped, string escapes resolved."""
    tokens = []
    i = 0
    line = 1
    size = len(source)

    while i < size:
        char = source[i]

        if char == "\n":
            line += 1
            i += 1
            continue

        if char in " \t\r":
            i += 1
            continue

        if source.startswith("//", i):
            end = source.find("\n", i)
            i = size if end < 0 else end
            continue

        if source.startswith("/*", i):
            end = source.find("*/", i + 2)
            if end < 0:
                raise RedsParseError("%s:%d: unterminated block comment" % (where, line))
            line += source.count("\n", i, end)
            i = end + 2
            continue

        # s"..." is an interpolated string. None of the authored corpus uses one, and
        # guessing at what an interpolation would render to is exactly the kind of quiet
        # invention this reader exists to prevent.
        if char == "s" and i + 1 < size and source[i + 1] == '"':
            raise RedsParseError(
                "%s:%d: interpolated string s\"...\" in extracted text; "
                "this reader only handles plain literals" % (where, line))

        if char == '"':
            text, i, line = _read_string(source, i, line, where)
            tokens.append(Token("str", text, line))
            continue

        match = _NUMBER_RE.match(source, i)
        if match:
            tokens.append(Token("num", match.group(0), line))
            i = match.end()
            continue

        match = _IDENT_RE.match(source, i)
        if match:
            tokens.append(Token("ident", match.group(0), line))
            i = match.end()
            continue

        tokens.append(Token("punct", char, line))
        i += 1

    tokens.append(Token("end", "", line))
    return tokens


def _read_string(source, i, line, where):
    i += 1                                  # past the opening quote
    out = []
    size = len(source)
    while i < size:
        char = source[i]
        if char == "\\":
            if i + 1 >= size:
                break
            escape = source[i + 1]
            if escape not in _ESCAPES:
                raise RedsParseError(
                    "%s:%d: unknown escape \\%s" % (where, line, escape))
            out.append(_ESCAPES[escape])
            i += 2
            continue
        if char == '"':
            return "".join(out), i + 1, line
        if char == "\n":
            line += 1
        out.append(char)
        i += 1
    raise RedsParseError("%s:%d: unterminated string literal" % (where, line))


# ── Expressions ──────────────────────────────────────────────────────────────

class Reader(object):
    """A cursor over tokens, with the expression grammar this file admits."""

    def __init__(self, tokens, where="<source>"):
        self.tokens = tokens
        self.pos = 0
        self.where = where

    # -- cursor --------------------------------------------------------------

    def peek(self, offset=0):
        index = self.pos + offset
        if index >= len(self.tokens):
            return self.tokens[-1]
        return self.tokens[index]

    def next(self):
        token = self.peek()
        self.pos += 1
        return token

    def at_punct(self, char):
        token = self.peek()
        return token.kind == "punct" and token.value == char

    def at_ident(self, name):
        token = self.peek()
        return token.kind == "ident" and token.value == name

    def expect_punct(self, char):
        token = self.next()
        if token.kind != "punct" or token.value != char:
            self.fail("expected '%s', got %r" % (char, token.value), token)
        return token

    def expect_ident(self):
        token = self.next()
        if token.kind != "ident":
            self.fail("expected an identifier, got %r" % (token.value,), token)
        return token.value

    def fail(self, message, token=None):
        token = token or self.peek()
        raise RedsParseError("%s:%d: %s" % (self.where, token.line, message))

    # -- grammar -------------------------------------------------------------

    def expression(self):
        """concat ('?' expression ':' expression)?"""
        value = self.concat()
        if self.at_punct("?"):
            self.next()
            then = self.expression()
            self.expect_punct(":")
            otherwise = self.expression()
            return {"ternary": {"cond": value, "then": then, "else": otherwise}}
        return value

    def concat(self):
        parts = [self.atom()]
        while self.at_punct("+"):
            self.next()
            parts.append(self.atom())
        return join(parts)

    def atom(self):
        value = self.primary()
        # Postfix chains: a call may be followed by a field, a field by a call.
        # AiNpcPromptOverridesFor(contactId).speechStyle is the common one.
        while True:
            if self.at_punct("."):
                self.next()
                value = {"field": [value, self.expect_ident()]}
                continue
            if self.at_punct("("):
                value = {"invoke": [value, self.arguments()]}
                continue
            if self.at_punct("["):
                self.next()
                index = self.expression()
                self.expect_punct("]")
                value = {"index": [value, index]}
                continue
            break
        return value

    def primary(self):
        token = self.next()

        if token.kind == "str":
            return token.value

        if token.kind == "num":
            return {"num": token.value}

        if token.kind == "punct" and token.value == "[":
            items = []
            if not self.at_punct("]"):
                items.append(self.expression())
                while self.at_punct(","):
                    self.next()
                    items.append(self.expression())
            self.expect_punct("]")
            return {"array": items}

        if token.kind == "punct" and token.value == "(":
            inner = self.expression()
            self.expect_punct(")")
            return inner

        if token.kind == "punct" and token.value == "!":
            return {"call": "!", "args": [self.atom()]}

        if token.kind == "ident":
            return self.after_ident(token)

        self.fail("unexpected %r in an extracted expression" % (token.value,), token)

    def after_ident(self, token):
        name = token.value

        # `new AiNpcCharacterDef()` -- a construction, which the sheet reader turns into an
        # empty object of that type. No constructor takes arguments in this codebase.
        if name == "new":
            type_name = self.expect_ident()
            if self.at_punct("("):
                self.next()
                self.expect_punct(")")
            return {"new": type_name}

        if self.at_punct("("):
            return {"call": name, "args": self.arguments()}

        if self.at_punct("."):
            self.next()
            field = self.expect_ident()
            return {"member": [name, field]}

        if name in ("true", "false"):
            return name == "true"

        return {"ref": name}

    def arguments(self):
        self.expect_punct("(")
        args = []
        if not self.at_punct(")"):
            args.append(self.expression())
            while self.at_punct(","):
                self.next()
                args.append(self.expression())
        self.expect_punct(")")
        return args

    # -- statements ----------------------------------------------------------

    def skip_to_statement_end(self):
        """Past the next ';' at depth zero. For statements nothing extracts from."""
        depth = 0
        while True:
            token = self.next()
            if token.kind == "end":
                self.fail("unterminated statement", token)
            if token.kind != "punct":
                continue
            if token.value in "([{":
                depth += 1
            elif token.value in ")]}":
                if depth == 0:
                    self.pos -= 1
                    return
                depth -= 1
            elif token.value == ";" and depth == 0:
                return


def join(parts):
    """Flattens a concatenation, merging adjacent literals."""
    flat = []
    for part in parts:
        if isinstance(part, dict) and "concat" in part:
            flat.extend(part["concat"])
        else:
            flat.append(part)

    merged = []
    for part in flat:
        if isinstance(part, str) and merged and isinstance(merged[-1], str):
            merged[-1] += part
        elif part != "":
            merged.append(part)

    if not merged:
        return ""
    if len(merged) == 1:
        return merged[0]
    return {"concat": merged}


def function_body(source, name, where="<source>"):
    """The tokens between the braces of `func name(...)`, as a Reader.

    Returns None when the function is not in this source, so a caller can ask several files
    for the same name without knowing which one holds it.
    """
    match = re.search(r"func\s+" + re.escape(name) + r"\s*\(", source)
    if not match:
        return None

    open_brace = source.find("{", match.end())
    if open_brace < 0:
        raise RedsParseError("%s: no body for %s" % (where, name))

    depth = 0
    i = open_brace
    size = len(source)
    in_string = False
    while i < size:
        char = source[i]
        if in_string:
            if char == "\\":
                i += 2
                continue
            if char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif source.startswith("//", i):
            end = source.find("\n", i)
            i = size if end < 0 else end
            continue
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                body = source[open_brace + 1:i]
                return Reader(tokenize(body, where), where)
        i += 1

    raise RedsParseError("%s: unbalanced braces in %s" % (where, name))
