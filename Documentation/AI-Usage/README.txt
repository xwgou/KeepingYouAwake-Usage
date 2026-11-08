AI usage menu — project entry point
2026-11-08 | Development milestone 1: usage bridge and snapshot menu implemented

GitHub fork: https://github.com/xwgou/KeepingYouAwake-Usage
Upstream: https://github.com/newmarcel/KeepingYouAwake
Local folder: /Users/xw/Projects/KeepingYouAwake-Usage
Selected product and repository name: KeepingYouAwake-Usage.

Read DESIGN.txt for the interaction and architecture, PLAN.txt for sequenced
work and release criteria, and RESEARCH.txt for verified facts and uncertainties.
Upstream application source is present alongside these documents. Existing
AwakeGauge/DESIGN.txt was preserved and is superseded for this new project.

The GitHub fork was created through the signed-in browser. Local source was
obtained from the fork's main-branch ZIP because terminal DNS could not resolve
github.com and gh was not installed. This folder is an archive snapshot, not a
Git checkout. FORK_PROVENANCE.txt at the project root records its commit and hash.
Initial menu code is now modified; entitlements and credentials are unchanged.
These planning documents exist locally; they have not been pushed to GitHub.

When terminal networking works, preserve this snapshot and clone separately:
  cd /Users/xw/Projects
  git clone https://github.com/xwgou/KeepingYouAwake-Usage.git KeepingYouAwake-Usage-git
  cd KeepingYouAwake-Usage-git
  git remote add upstream https://github.com/newmarcel/KeepingYouAwake.git
  git switch -c feature/ai-usage-menu
  cp -R ../KeepingYouAwake-Usage/Documentation/AI-Usage Documentation/
Review the plan in that checkout before continuing implementation. Do not initialize a
replacement history or overwrite the downloaded snapshot to simulate a clone.

Update: network access recovered. This folder now has real upstream Git history
on feature/ai-usage-menu; cloning instructions above are historical recovery notes.
Read SETUP.txt for the current development workflow and DEVELOPMENT.txt for tests.
