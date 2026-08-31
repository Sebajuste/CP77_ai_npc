# Roadmap

Ideas that are **not** being built, described in general terms only: what the feature is, what
it would buy, and why it is not being done now.

**No detail here.** No file layout, no step order, no measurement protocol, no API shape. The
moment an idea has those, it has a `PLAN_*.md` and this file links to it in one line. An entry
that grows past a dozen lines is a plan wearing the wrong hat.

---

## Recall over the archive

The archive keeps every evicted fact verbatim and never sends it, so an old fact returns to
the prompt only dissolved into the chronicle's prose. The idea is to bring an exact old line
back when the conversation touches it — what a long quest arc needs from a character who has
to remember one precise detail from three hundred turns ago.

Deferred because the cheap attempt has not been made. The archive is capped and fits in one
call, so the first thing to try is asking a model to pick from it, not building an index. A
semantic index only earns its place when the candidates stop fitting in a prompt, and nothing
we have today comes close.

Related: `docs/MEMORY.md` § the archive's backstop.

## The action selector on its own call

Today a command is a bracket the character writes inside its reply, so one generation carries
the voice, the language, the tier and an exact syntax at once. Small and free models fail at
that composite, not at choosing the action. The idea is to let the character speak in plain
prose and give the selection its own short call, which would also take the command block out
of the dialogue prompt entirely.

Deferred until measured. It depends on `PLAN_MODEL_SLOTS.md`: without a cheap mechanical slot
it is a second full-price request per message.

Briefed in `docs/PLAN_ACTION_SELECTOR.md`.

## Render depths for a character sheet

One sheet, rendered at several depths — the full bio, the way an interlocutor is described,
a one-line summary, the speech style alone, a form carrying only what decides an action.
Today every consumer gets the same bio, whatever it needs it for.

It would buy a reduced prompt for anything that is not dialogue, a summary line for the
contact list, and an answer for a third-party mod asking who a character is. Small, with no
open design question, and it sits inside a structure that already exists — the `cast/` sheets
and the contact provider.

## World knowledge that is bigger than one character

A fact the whole cast should know — an arc that ended, a district that changed hands, someone
who died — scoped by a condition and entering the world when that condition becomes true.
Today the only place a fact like that can live is inside each character's sheet, so making
the cast react to one event means editing every sheet.

It would also give a quest mod a way to hand its own lore to characters it does not own, as a
bundle the player can switch on and off. The condition vocabulary has to stay a closed list
evaluated in code, the way sheet variants already work: data carries the text, never the
predicate.
