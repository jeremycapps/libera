# Method A prompt template

This is the fixed prompt sent to the prompt-only agent for every run of every
fixture. The block below — contract restatement through output instructions —
is pasted **verbatim** into every transcript's `prompt` field in
`runs/*.md`, with only `<ISSUE>` substituted for that round's issue record. It
is never shortened, referenced, or replaced with "see above": restating it in
full, every time, is itself the repeated-instruction cost that `results.md`'s
§6 "Repeated instruction tokens" row measures.

## The literal prompt text

```
You are reviewing a support issue. Decide whether it is complete.

An issue is complete only if it has all three of the following, each with a
real, non-null value:
- root_cause: what actually caused the problem
- owner: who is responsible for resolving it
- resolution_path: the plan to resolve it

If a field is absent, it will appear in the issue record below as `null` —
treat `null` as explicitly missing, never as "not checked yet."

Given the issue, return exactly these four fields:
- verdict: "conforms" if all three required fields are present and non-null,
  otherwise "does not conform"
- finding: one of "complete", "missing_root_cause", "missing_owner",
  "missing_resolution_path". If more than one field is missing, name the
  first missing field in this fixed order: root_cause, then owner, then
  resolution_path.
- next_action: what should happen next to move this issue forward, in prose
- explanation: why you reached this verdict, in prose

Issue:
<ISSUE>
```

## Substitution slot

`<ISSUE>` is replaced with the fixture round's issue record, rendered as
`id`, `title`, `description`, `root_cause`, `owner`, `resolution_path` —
the same six keys every fixture YAML file under `../fixtures/` carries per
round, so a transcript author copies the round's fields directly rather than
reshaping them.

## Token-estimate heuristic

Every transcript records a `token_estimate`, computed identically every time:

```
token_estimate = len(prompt_text.split())
```

That is, the whitespace-split word count of the **full literal prompt text
actually sent** — the block above with `<ISSUE>` substituted, nothing
omitted and nothing added. `prompt_text.split()` splits on any run of
whitespace (spaces, tabs, newlines), matching Python's `str.split()` with no
argument. This is an estimate, not a metered token count from a real model
provider (no LLM API is called for Method A per the experiment's scope), but
it is reproducible: given the same `prompt_text`, every transcript author
gets the same integer.
