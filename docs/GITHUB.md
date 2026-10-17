# GitHub setup and the life of a change

Everything here is free for a public repository: GitHub Actions on standard runners (including macOS) has no minute limit for public repositories, and Pages, Releases, CodeQL, Dependabot, secret scanning and rulesets cost nothing. The optional Claude review uses a Claude subscription token, not a paid API key.

## The pipeline

| Stage | In Saidright | Where |
| --- | --- | --- |
| **Before the pull request** — the work is verified | `scripts/check.sh` runs the same checks as CI locally; in Claude Code, `/code-review` and `/security-review` review the diff in a fresh context | your Mac |
| **Required CI** | Unit tests, release build, app bundle assembly, string tables in four languages, Python and shell syntax, actions pinned to commits, scan for secrets and personal paths. Red blocks the merge | `.github/workflows/ci.yml` |
| **Claude code review** | A code-review pass and a separate security pass on every pull request; findings are verified against the code, ranked by severity and posted as comments | `.github/workflows/claude-review.yml` |
| **Security review** | CodeQL (`security-extended`) for Swift, Python and the workflows on every pull request and weekly; Dependabot alerts; secret scanning with push protection | `.github/workflows/codeql.yml`, repository settings |
| **Risk-based approval** | CI sets a review tier from the touched files: *low* (docs, site) → checks are enough; *normal* (app code) → read the diff and the review; *high* (hotkeys, recording, delivery, session, keys, recognizer worker, runtimes, signing, workflows) → a person tests the build on a Mac before merging | job “Review tier” in `ci.yml` |
| **Merging** | The ruleset requires the branch to be up to date with `main`, so checks always ran on the latest `main` with the change applied (the merge queue itself is only offered to organisation-owned repositories) | ruleset |
| **Used internally first** | A version tag builds the DMG and publishes it as a **pre-release**. Pre-releases are not “latest”, so the product page keeps offering the previous version while you use the new one | `.github/workflows/release.yml` |
| **Gradual release** | Actions → *Promote* → `promote` makes the tested pre-release the latest release; the page's download button follows automatically | `.github/workflows/promote.yml` |
| **Watch, fix forward or roll back** | Issues and crash reports come in through the issue templates. Actions → *Promote* → `rollback` turns a broken release back into a pre-release, and “latest” falls back to the previous version (for the very first release there is none, so the page offers nothing until the fix); then fix forward with a new tag | `.github/workflows/promote.yml` |

## One-time setup

1. **Account and repository.** Create a free GitHub account, then an empty **public** repository named `saidright` (no README, no licence; the project has them).
2. **Command line.** `brew install gh`, then `gh auth login` (GitHub.com → HTTPS → log in with a browser).
3. **First push.** Give the maintainer session your GitHub user name. It runs `scripts/set-bundle-id.sh <user>`, sets `REPO` in `site/index.html`, rebuilds, runs `scripts/check.sh`, refreshes the `public` branch, asks for a final yes and pushes `public` to `main`.
4. **Repository settings** (on github.com, in the repository):
   - **Settings → Pages → Build and deployment → Source: GitHub Actions.**
   - **Settings → Actions → General → Workflow permissions: “Read repository contents and packages permissions”**; leave “Allow GitHub Actions to create and approve pull requests” off. Under *Fork pull request workflows* keep “Require approval for first-time contributors”.
   - **Settings → Advanced Security** (called *Code security* on some accounts): turn on *Dependency graph*, *Dependabot alerts*, *Dependabot security updates*, *Secret protection* (secret scanning) with *Push protection*, and *Private vulnerability reporting*. For *Code scanning* choose nothing: the CodeQL workflow is the “advanced setup”, and turning on “default setup” as well would conflict with it.
   - **Settings → Rules → Rulesets → New branch ruleset**: name `main`, enforcement *Active*, target *Default branch*. Enable *Restrict deletions*, *Block force pushes*, *Require a pull request before merging* (required approvals: 0 while you are the only maintainer; tick *Require conversation resolution*), *Require status checks to pass* with *Require branches to be up to date* and the checks `Tests and build`, `Strings, scripts and hygiene`, `Analyze (swift)`, `Analyze (python)`, `Analyze (actions)` (they appear in the list after the first run), and *Require code scanning results* (CodeQL, alerts “High or higher”). Add a check to the list only after it has passed once on GitHub: the workflows have not run there yet, and a check that never turns green would block every merge. Leave the bypass list empty, or add yourself only for emergencies.
5. **Claude review (optional).** In Claude Code run `/install-github-app` and choose this repository: it installs the Claude GitHub app and stores a subscription token as the secret `CLAUDE_CODE_OAUTH_TOKEN`. Manually: install https://github.com/apps/claude on the repository, run `claude setup-token` in a terminal, and add the printed token under **Settings → Secrets and variables → Actions → New repository secret** with the name `CLAUDE_CODE_OAUTH_TOKEN`. Reviews then count against your subscription's usage limits. Without the secret the review jobs are skipped.
6. **First release.** `git tag v0.5.0 && git push origin v0.5.0` → wait for *Release* → install the pre-release from the Releases page and try it → Actions → *Promote* → tag `v0.5.0`, action `promote`.

## Everyday flow

```
git switch -c fix/short-name
# … change, then:
scripts/check.sh
git commit -am "Describe the change"
git push -u origin fix/short-name
gh pr create --fill
```

Wait for the checks and the review comments, answer or fix every finding, follow the review tier, then merge on GitHub (squash). Delete the branch.

## Releasing a new version

1. Update `VERSION`, `CHANGELOG.md` and `docs/release-notes/<version>.md` in a pull request.
2. After it is merged: `git switch main && git pull && git tag v<version> && git push origin v<version>`. The workflow refuses a tag that does not match `VERSION`.
3. Try the pre-release, then *Promote*. If something is wrong after promotion: *Promote* → `rollback`, fix, and tag the next patch version.

Users verify a download with `shasum -a 256 -c Saidright.dmg.sha256` in the folder that holds both files.

## Website address

The product page is served by GitHub Pages at **https://gomin1i.github.io/saidright/** (HTTPS, indexed by search engines, no cost, no renewal).

Free custom domains were considered and not used (2026-10-17):

- **is-a.dev / js.org** and similar community subdomains (`saidright.is-a.dev`): free, but registered through a pull request to a volunteer project, read as a hobby address, and js.org is only for JavaScript projects.
- **eu.org**: free since 1996 and reputable, but approval is manual and takes weeks to months, and it needs separate DNS hosting.
- **Free TLD promotions** (Freenom and successors): stopped or turned into paid renewals; not trustworthy for a product.

A real domain (`saidright.app` and `saidright.io` looked unregistered; `saidright.com` is parked by a third party) costs about $10–20 a year. To use one later: buy it, add a `site/CNAME` file with the domain, point a `CNAME` DNS record to `gomin1i.github.io`, then set it in Settings → Pages → Custom domain and tick *Enforce HTTPS*.
