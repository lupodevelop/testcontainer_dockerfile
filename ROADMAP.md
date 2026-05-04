# Roadmap

This document tracks planned work for `testcontainer_dockerfile` after
the initial 1.0.0 release.

Items are grouped by target release. Order within a release is roughly
priority, top-first.

---

## 1.1.0 — feature additions (non-breaking)

- [ ] `with_volume/2` — pass an opaque `container.Volume` value
  (currently we cover the three volume shapes via dedicated builders
  but not the generic constructor).
- [ ] `with_user/2` — explicit Docker `User` field, mirroring the
  planned `container.with_user` in testcontainer 1.1.0.
- [ ] `with_workdir/2` — set `WorkingDir` on the spec.
- [ ] BuildKit secret mounts: `with_secret_mount(id, source_path)`
  → `--secret id=...,src=...` to pass build-time secrets without
  leaking them into image layers or the host process list.
- [ ] `with_buildx_args(args)` — escape hatch for
  cache-from / cache-to, multi-platform, and other Buildx-only flags.
