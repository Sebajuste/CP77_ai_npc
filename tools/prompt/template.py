# -*- coding: utf-8 -*-
"""Placeholders. Mirrors AiNpcTemplate.reds.

A sheet writes {they}, {them}, {their} and {partner} so that one line of authored text agrees
with V whoever V is, and {time}, {npc}, {language}, {vgender}, {register} for the same
reason. The words themselves come from the corpus -- they are in the prompt, so they are
authored text like any other -- and only the substitution order is mirrored here.

Order matters and is not alphabetical: {Their} is replaced after {their}, and both after the
lowercase pass, exactly as AiNpcExpandTemplateWith does it. Getting that wrong would leave a
capitalised placeholder in a prompt, which reads as a bug in the mod rather than in the
tooling that reproduced it.
"""

from resolve import Env, resolve

# The gendered vocabulary, by the index AiNpcGetGenderedWord answers to.
PARTNER, THEY, THEM, THEIR, GENDER = "1", "2", "3", "4", "5"


def gendered_word(texts, index, is_male):
    table = texts["genderedWords"]
    if index not in table:
        raise KeyError("AiNpcGetGenderedWord has no case %s any more" % index)
    return resolve(table[index], Env(truths={"isMale": is_male}))


def capitalize(text):
    return text[:1].upper() + text[1:] if text else text


def expand(text, sections):
    """Every placeholder in `text`, for the fixture `sections` answers for."""
    if "{" not in text:
        return text

    partner = sections.gendered(PARTNER)
    they = sections.gendered(THEY)
    them = sections.gendered(THEM)
    their = sections.gendered(THEIR)

    replacements = [
        ("{partner}", partner),
        ("{they}", they),
        ("{them}", them),
        ("{their}", their),
        ("{gender}", sections.gendered(GENDER)),
        ("{npc}", sections.character.display_name),
        ("{time}", sections.clock()),
        ("{language}", sections.language_prompt()),
        ("{vgender}", sections.gender_statement()),
        ("{register}", sections.default_speech_style()),
        ("{Partner}", capitalize(partner)),
        ("{They}", capitalize(they)),
        ("{Them}", capitalize(them)),
        ("{Their}", capitalize(their)),
    ]

    result = text
    for placeholder, value in replacements:
        result = result.replace(placeholder, value)
    return result
