# Scale test: expected results

Roster: 340 people on day 1 (the original 26 + 314 new), 345 on day 2.

## Day 1: `hr-roster-scale-day1.csv`

| Script | Expected |
|---|---|
| Joiner | **306 CREATE** (6 of them DISABLED until a future start date), **33** program access denials. SKIP: 26 existing, 5 terminated, 3 contracts already ended |
| Mover | **~306 SET MANAGER** (the joiner doesn't set managers, the mover does), **36** NO ACCESS lines (33 new + Samuel, Nathan, Olivia) |
| Leaver | Brian + Erin: already offboarded. 8 people: no account in AD (5 terminated + 3 expired never got accounts) |
| SoD | No conflicts |

## Day 2: `hr-roster-scale-day2.csv` (HR changes overnight)

| Change | People | Expected engine action |
|---|---|---|
| Program transfer, approved | George Richards, Megan Long, Judy Shah, Jack Brown | UPDATE program, REMOVE old program group, ADD new one |
| Program transfer, NOT approved yet | Natalie Duncan, Simone Morgan | UPDATE program, REMOVE old group, NO ACCESS to new one |
| Engineering → Program Management | Evelyn Andrews, Gerald Berry | REMOVE program group + GG-Role-Engineers, ADD GG-Role-ProgramManagers, SET MANAGER → Diane Whitaker |
| Manager change | Denise Ortiz, Ronald Mendez | SET MANAGER → Gregory Okafor |
| Terminated | Jennifer Matthews, Abigail Evans, Richard Duncan, Mateo Diaz, Jack Gibson, Cynthia Hughes | Leaver: disable, revoke, clean up, move |
| Contract ended, HR still shows Active | Andre Ford, Pamela Turner | Leaver: same |
| New hires | Lauren Cruz, Matthew Flores, Hiroshi Henry (start today); Rachel Taylor, Alice Hall (future) | Joiner: 5 CREATE, 2 DISABLED; mover sets their managers |

Totals: joiner 5, mover 10 people changed + 5 managers for new hires, leaver **8** offboarded + **one** sync triggered, SoD no conflicts.
