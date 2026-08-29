# -*- coding: utf-8 -*-
"""Turning an extracted expression back into text.

corpus.json stores what the sources say, not what a prompt says: a section can be a plain
string, or a concatenation with a call in the middle, or a branch on V's gender. This file
walks such a tree with an environment -- the locals it may read and the functions it may
call -- and returns the string.

The environment is deliberately closed. A name the caller did not provide is an error naming
the name, never an empty string: an unresolved piece of a prompt has to stop the build, since
the alternative is a prompt that is quietly missing a paragraph.
"""


class ResolveError(Exception):
    pass


class Env(object):
    def __init__(self, values=None, calls=None, truths=None):
        # Kept as handed in rather than copied: a caller may pass a lazy mapping so that a
        # section nobody asks for is never built.
        self.values = {} if values is None else values
        self.calls = {} if calls is None else calls
        self.truths = {} if truths is None else truths

    def value(self, name):
        if name not in self.values:
            raise ResolveError("nothing bound to %r" % (name,))
        return self.values[name]

    def call(self, name, args):
        if name not in self.calls:
            raise ResolveError(
                "the sources call %s(), which the offline builder does not implement. "
                "Either it is new, or it moved -- teach build.py what it means." % name)
        return self.calls[name](*args)

    def truth(self, key):
        if key not in self.truths:
            raise ResolveError("no truth value bound for %r" % (key,))
        return self.truths[key]


def resolve(tree, env):
    """The tree as text."""
    value = evaluate(tree, env)
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return ""
    if not isinstance(value, str):
        raise ResolveError("expected text, got %r" % (value,))
    return value


def evaluate(tree, env):
    if isinstance(tree, str):
        return tree
    if isinstance(tree, bool) or tree is None:
        return tree

    if not isinstance(tree, dict):
        raise ResolveError("unreadable node %r" % (tree,))

    if "concat" in tree:
        return "".join(resolve(part, env) for part in tree["concat"])

    if "ref" in tree:
        return env.value(tree["ref"])

    if "num" in tree:
        return tree["num"]

    if "member" in tree:
        owner, field = tree["member"]
        return _field(env.value(owner), field, "%s.%s" % (owner, field))

    if "field" in tree:
        owner, field = tree["field"]
        return _field(evaluate(owner, env), field, field)

    if "index" in tree:
        owner, index = tree["index"]
        return evaluate(owner, env)[int(evaluate(index, env))]

    if "call" in tree:
        return env.call(tree["call"], [evaluate(arg, env) for arg in tree["args"]])

    if "invoke" in tree:
        owner, args = tree["invoke"]
        return evaluate({"call": _invoke_name(owner), "args": args}, env)

    if "ternary" in tree:
        branch = tree["ternary"]
        return evaluate(branch["then"] if condition(branch["cond"], env) else branch["else"],
                        env)

    if "array" in tree:
        return [evaluate(item, env) for item in tree["array"]]

    if "new" in tree:
        raise ResolveError("a construction reached the resolver: %r" % (tree,))

    raise ResolveError("unreadable node %r" % (tree,))


def condition(tree, env):
    """The truth of a branch, by the name the sources gave it.

    Conditions are not evaluated -- they are LOOKED UP. `isMale`, `Equals(gender, Female)`
    and their kind are decisions the fixture already made, and re-deriving them here would
    be a second implementation of the same rule, free to disagree with the first.
    """
    return env.truth(condition_key(tree))


def condition_key(tree):
    if isinstance(tree, str):
        return tree
    if isinstance(tree, dict):
        if "ref" in tree:
            return tree["ref"]
        if "call" in tree:
            inner = ",".join(condition_key(arg) for arg in tree["args"])
            return "%s(%s)" % (tree["call"], inner)
        if "member" in tree:
            return "%s.%s" % tuple(tree["member"])
        if "field" in tree:
            return "%s.%s" % (condition_key(tree["field"][0]), tree["field"][1])
    raise ResolveError("unreadable condition %r" % (tree,))


def _field(owner, field, label):
    if isinstance(owner, dict):
        if field not in owner:
            raise ResolveError("no field %r on %s" % (field, label))
        return owner[field]
    raise ResolveError("field access on something that is not an object: %s" % label)


def _invoke_name(owner):
    if isinstance(owner, dict) and "member" in owner:
        return "%s.%s" % tuple(owner["member"])
    raise ResolveError("unreadable method call on %r" % (owner,))
