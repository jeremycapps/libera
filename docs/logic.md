# Logic

Libera defines replayable workstream paths.

The YAML vocabulary stays small. The logic explains why the vocabulary exists.

## Path

```text
{type}/{id}/{field} -> value
```

## Execution and governance

Libera v1 has two mirrored paths.

```text
Execution path  = how work flows
Governance path = how work is allowed, aligned, and triaged
```

## Workstream pressures

```text
Boundary  = work enters or exits the stream
Movement  = work advances or changes inside the stream
Exception = work deviates from expected state
```

## Type mapping

```text
Boundary
Execution: request, deliverable
Governance: approval, acceptance

Movement
Execution: task, change
Governance: review, decision

Exception
Execution: issue, incident
Governance: validation, escalation
```

## Pairing logic

```text
request     <-> approval
deliverable <-> acceptance

task        <-> review
change      <-> decision

issue       <-> validation
incident    <-> escalation
```

Pairs are part of the ontology. Counterpart records are not required to exist at all times.

Missing counterparts are meaningful.

```text
request exists, approval missing -> inbound work has not been admitted
task exists, review missing -> planned work has not been aligned
issue exists, validation missing -> exception has not been validated
incident exists, escalation missing -> urgent exception has not been governed
```

## Triage

The governance of an exception is triage.

```text
Execution exception = something is wrong.
Governance triage = decide how wrong, who owns it, and how fast it must move.
```

A non-urgent exception maps to validation.

An urgent exception maps to escalation.
