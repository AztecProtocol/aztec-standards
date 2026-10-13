# Contributor conventions

Read by Claude Code (through `CLAUDE.md`), Codex and Cursor. It states what the code cannot: how this repository
names and organizes its tests. Commands and layout are in `README.md`.

## Noir tests

- One file per entrypoint under `src/<crate>/src/test/`, named after it (`transfer_public_to_public.nr`); a feature
  that spans entrypoints gets its own file (`authorization.nr`, `cancel_authwit.nr`). Shared setup and assertions
  live in that crate's `test/utils.nr`.
- Test names: `<op>` for the plain case, `<op>_<variant>` for a variant (`_on_behalf_of_other`, `_multiple_notes`,
  `_after_yield`), and `<op>_failure_<reason>` for a `#[test(should_fail_with = "...")]` test, where `<op>` is the
  entrypoint under test (or the feature the file covers) and `<reason>` names the violated condition. No `_success`
  suffix and no crate prefix: the crate and module already say where a test lives.
- A failure test states the message it expects with `should_fail_with`; a bare `should_fail` passes on any error and
  is never enough.
- A new test must fail when the behaviour it guards is broken. Check that by breaking the behaviour, and say in the
  PR which tests were checked that way.

## Pull requests

The description is read by someone who did not follow the work and will not read the diff first. PR #49's is the
reference. In this order, in plain sentences:

1. One line: what the PR fixes or changes, and why it matters. The title names the operation; this names the problem.
2. **What changed**, grouped by concern, each bullet leading with the effect, then the mechanism, then the reason, in
   one or two sentences. Say what a reviewer should look at hardest.
3. **Breaking changes**, with what an integrator has to do, or the line that says there are none.
4. **Not in this PR**: what was left out and why, and what cannot be verified before merge.

Evidence comes last and stays short: which tests were checked to fail with the bug put back, the one number that
matters. No tables of versions or paths, no logs, no inventory of everything that was checked; that is what the diff
and CI are for. A description is as long as the change needs and no longer; most fit on one screen.
