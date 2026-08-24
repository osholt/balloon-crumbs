# HMLR INSPIRE reference index

`current.sqlite` is an operator-managed, read-only spatial index generated from
the current monthly HM Land Registry INSPIRE files. It is deliberately ignored
by Git: the dataset can be replaced or removed without an application release.

See `docs/hmlr-inspire-reference.md` for the licence decision, build command,
atomic update procedure, verification and limitations. With no valid
`current.sqlite`, the endpoint returns an honest `503` and the recovery app
continues without this optional layer.
