# Build Log

My notes while building this project.

## Step 1 - Repo setup (Oct 2)
- Created the repo on GitHub
- Added a .gitignore so passwords and keys can never be uploaded

## Step 1b - Directory design (Oct 2)
- Wrote the directory design doc
- Main decision: admin accounts live in their own folders so the helpdesk can never reset an admin's password
- Learned: the sync server is Tier 0 because it can read every password

## Step 2 — Role map

**Did:** Wrote `docs/02-role-map.md`. Split access into birthright (by job role) and conditional (program data). Defined the checks for program data, the Finance/AP separation-of-duties conflict, and an exception process. Created programs Radar, Satellite and Shipboard so the names describe the work.

**Why:** Copying a coworker's access ("make her like Bob") gives people access they don't need. A role map makes day-one access predictable and keeps program data need-to-know.

**Broke:** My first draft gave every engineer the program CUI share on day one and tied program membership to an OU. It also let one person hold both Finance and Accounts Payable.

**Fixed:**
- Program access now requires a program assignment, CUI training, US-person status (for export-controlled data) and program manager approval.
- Program comes from an account attribute instead of an OU, so moving between programs is an attribute change, not an account move.
- Finance + AP is a toxic combination: one person could create a fake vendor and approve its invoice. The JML engine denies it by default. Exceptions need approval from outside the conflict, a time limit and a compensating control.
