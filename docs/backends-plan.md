# Backends beyond tmux: what shipped, and what is still open

*For the dispatcher. Backend design: [`design.md`](design.md#backends). This
began as a plan for cmux and herdr; all of it is now built, and what remains is
the one decision it deferred.*

## Shipped

- **One claim file.** `state/yardmaster.claim` holds `backend=` and `target=`,
  replacing the per-backend `yardmaster.pane`/`.orca`/`.cmux`/`.herdr` files.
  The watcher reads one place, and a yard opened in two backends is now a
  collision the session-start hook reports instead of two claims that never see
  each other.
- **herdr.** One tab per engine (`tab create --cwd <siding> --label ry-<id>`,
  then `pane run`). Both ids travel in one `target=` as
  `tab:<tab_id>/pane:<pane_id>`: the pane to read and type into, the tab to
  close. Everything answers in the socket API's JSON envelope, so nothing is
  screen-scraped.
- **cmux.** One workspace per engine, targeted by stable uuid rather than the
  positional `workspace:N` refs cmux prints.
- **Orca.** One terminal per engine on the siding, after the project clone is
  registered as an Orca repo.

Each is covered by a fake CLI on `PATH` (`tests/fakebin/<name>`) and a bats file
that mirrors `tests/ry-orca.bats`, so CI needs none of the real apps.

## Settled: which backend a yard uses

`data/yard.md` records it — a `backend:` line, read by `ry_backend()`, sitting
between `RY_BACKEND` and the `tmux` default. The environment still wins, so
the test suite and one-off runs are untouched; a yard that records nothing is
still a tmux yard. Backend errors now name where the answer came from, so a
typo in the file does not read as a typo in your shell.

## Taken: herdr's early warning

`herdr agent wait --until blocked` is used, and the status-file contract is
still untouched. herdr does not get to report turn ends — that would give one
backend its own path into the status file. It answers a narrower question
through `ry_backend_blocked()`: is this engine sitting at a prompt right now.
The only thing that answer does is raise the watcher's existing "running, and
silent" inbox line in seconds rather than after `RY_STALL_MIN` minutes. Every
other backend returns false and the timer does the work, as before.
