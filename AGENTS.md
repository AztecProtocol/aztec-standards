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
