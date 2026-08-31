# This yard

Which app hosts this yard's terminals. One line, read by `ry_backend()` in
`bin/ry-backend-lib.sh`:

- `backend: tmux`

Valid values are tmux, orca, cmux, herdr and none. `RY_BACKEND` in the
environment wins over this file, so a one-off override still works; with
neither, a yard is a tmux yard.

A yard runs on one backend at a time — engines are welded to the app that
launched them (`ry_backend_no_split`). To look at a tmux yard from another app,
use `bin/ry-view.sh` rather than changing this line.
