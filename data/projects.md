# Projects

One line per project:
`name` — mode (`local-only` | `pr` | `no-mistakes`), optional `base: <branch>`, notes.

`name` must match the directory under `projects/`. When `base:` is absent the
base is `develop` if the project has one, otherwise the remote's default branch.
Railyard cuts every siding from the base and merges back into it; it never
touches the release branch.

- `test` — pr, base: develop, notes: first real run
