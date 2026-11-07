# AGENTS.md

Guidance for AI agents (and the people steering them) contributing to this repository. Read this before opening an issue or pull request. Human contributors are welcome to follow it too.

## What this project is

`synology-docker` updates Docker Engine and Docker Compose on Synology NAS devices running DSM 6 or 7, and helps users move containers off Synology's removed `db` log driver.

Most users are Container Manager users following a guide. They are not shell experts. They copy commands from the README, run them over SSH, and need the script to either work or stop safely with a clear message. Judge every change from their point of view.

## Scope

**In scope:**

- Updating, staging, installing, and restoring Docker Engine and Compose on DSM 6/7
- The prerequisites the update needs (kernel modules, AppArmor, forwarding, the log driver switch)
- Simple helpers for finding and recreating containers still on the `db` logger
- Tests and CI for the above

**Out of scope** (belongs in a separate project, such as [stateful-docker-migration-flow](https://github.com/gundestrup/stateful-docker-migration-flow)):

- Container migration, export, or Compose generation
- Recovery tooling beyond the existing backup and restore
- Anything that adds new setup steps for users, such as env files, config files, or extra tools to install

If you are unsure whether something is in scope, open an issue and ask before writing code.

## Rules for pull requests

1. **One change per PR.** One bug fix, one feature, or one test area. If your branch touches several unrelated things, split it before asking for review. Large PRs will be sent back to be split, not reviewed.
2. **Keep it small.** Prefer the smallest change that fixes the problem. Do not refactor, rename, reformat, or "modernize" code you didn't need to touch.
3. **No new tools, languages, or dependencies without asking first.** This is a Bash project. Do not add Python, Node, new CI jobs, linters, scanners, or package manifests without an issue where a maintainer has agreed.
4. **No style-only churn.** Do not mix formatting or syntax conversions (for example `[` to `[[`) into behavior changes.
5. **Don't change user-facing behavior silently.** If a change makes a previously working run stop or behave differently, say so plainly in the PR description.
6. **Link an issue.** Reference the issue the PR fixes (`Fixes #123`). For anything beyond a small bug fix, the issue should exist and be agreed upon before the PR.
7. **Use conventional commit titles**, such as `fix(update): ...`, `feat(logger): ...`, `test: ...`, `docs: ...`, `ci: ...`.
8. **Don't add a CHANGELOG entry.** Release notes are generated from PR titles (`.github/release.yml`), so write a clear PR title instead.

## AI disclosure

- Tick the AI box in the PR template and say which tool you used and how.
- Say what a human actually checked: what was read, what was run, and what was not.
- Non-maintainers may have only one AI-assisted PR open at a time.
- An agent must not approve or merge its own PR.

## Writing the scripts

- Scripts with a `#!/bin/bash` shebang may use Bash features. Generated `/bin/sh` helpers and DSM startup snippets must stay POSIX `sh`.
- Stay compatible with **Bash 4.3** (DSM 6). In particular, with `set -u`, expanding an empty array as `"${arr[@]}"` is an error on Bash older than 4.4. Guard it with `${arr[@]+"${arr[@]}"}`.
- Use only the tools DSM ships, as listed under "Testing" in the README (`jq`, `curl`, `realpath`, `timeout`, and so on). Don't assume GNU-only options beyond the ones already used.
- Use 2-space indentation.
- The code must pass ShellCheck with no new warnings.

## Safety rules

The updater replaces binaries on someone's NAS. A half-finished update can leave Docker unusable.

- **Fail closed.** If a lookup, download, check, copy, or write fails, stop with a clear error. Never fall back to a guessed version or carry on after a failed step.
- **Don't leave Docker half-updated.** Check and prepare everything you can before stopping Container Manager.
- **Don't touch files you didn't create.** Use private temp directories, never overwrite backups, and don't delete files in the user's working directory.
- **Keep `--force` meaningful.** Don't add new ways to bypass safety checks without maintainer agreement.

## Output for users

- Messages should say what happened and what to do next, in plain words.
- Any command the script prints for users to copy must work when pasted as-is: quote paths and values (for example with `printf %q`).
- Keep output short. Don't add banners, emoji, promotional links, or extra links without maintainer agreement.

## Tests

The README's "Testing" section is the full guide. The short version:

- Run the suite in the disposable test image, never on a NAS:
  ```bash
  docker build -t synology-docker-tests -f tests/Dockerfile .
  docker run --rm -v "$PWD:/workspace:ro" synology-docker-tests
  ```
- Add or update a case in `tests/cases/` for any behavior you change. One file per behavior, named after what it protects, written as arrange → act → expect, using the named assertions in `tests/lib/test_env.sh`.
- Test the production script or function that actually enforces the behavior, not a copy or a probe.
- Run your case on its own and with the full suite.
- Don't change existing assertions to make them pass. If a test fails, fix the code or explain in the PR why the expected behavior changed.

## Being honest about testing

- Mocked tests are not NAS tests. Never claim DSM compatibility you haven't verified on real hardware.
- In the PR description, say exactly what you ran (tests, ShellCheck, a NAS model and DSM version) and what you didn't.
- If CI hasn't run yet (fork workflows need maintainer approval), say so rather than reporting it as passing.

## Before you open a PR

- [ ] It's in scope, and it's one change
- [ ] There's an agreed issue, and the PR links it
- [ ] No new tools, languages, or dependencies, unless agreed
- [ ] Tests added or updated, and the full suite passes
- [ ] ShellCheck passes
- [ ] The PR description says what changed, why, how it was tested, and how AI was used
