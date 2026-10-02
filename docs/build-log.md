# Build Log

My notes while building this project.

## Step 1 - Repo setup (Oct 2)
- Created the repo on GitHub
- Added a .gitignore so passwords and keys can never be uploaded

## Step 1b - Directory design (Oct 2)
- Wrote the directory design doc
- Main decision: admin accounts live in their own folders so the helpdesk can never reset an admin's password
- Learned: the sync server is Tier 0 because it can read every password
