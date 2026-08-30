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

## Still open: which backend a yard uses

Four backends are supported and nothing records which one a yard should use
beyond `RY_BACKEND` in the environment. Now that the claim names its backend, a
mismatch is at least *reported* — but the dispatcher still has to set the
variable correctly every time. If more than one backend is normal for you,
`data/` should record a default per yard so `bin/ry-yard.sh` needs no env var.
Worth deciding before the count reaches five.

## Free upside, not taken

`herdr agent wait --until blocked` would let the watcher notice a blocked engine
without going through the Stop hook. The status-file contract is deliberately
left alone; this is a later option, not a pending task.
