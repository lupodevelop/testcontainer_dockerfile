<!-- markdownlint-disable MD024 -->

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-05-04

First public release.

### Build configuration

- `new(path)` to start a build configuration.
- `with_context(path)` — build context root (default `.`).
- `with_build_arg(key, value)` — passed as `--build-arg`. Build-arg
  keys are validated against `[A-Za-z_][A-Za-z0-9_]*`; values are
  rejected if they contain NUL or CR/LF.
- `with_timeout(ms)` — override the 10-minute default timeout. Clamped
  to the inclusive range `[1000, max_timeout_ms]` (1 hour upper bound)
  to reject pathological values.
- Public constants: `default_timeout_ms` (600_000) and `max_timeout_ms`
  (3_600_000).

### Container spec builders (applied AFTER build)

Full parity with `testcontainer/container` (modulo `with_volume`,
deferred to 1.1.0):

- `with_expose_port(port)` / `with_expose_ports(ports)`
- `with_env(key, value)` / `with_envs(pairs)` / `with_secret_env(key, secret)`
  (the latter wraps the value in `cowl.Secret` so it never leaks via
  `string.inspect`)
- `with_label(key, value)`
- `with_wait(strategy)` — replaces the wait strategy
- `with_extra_wait(strategy)` — combines with the current wait strategy
  via `wait.all_of`
- `with_command(cmd)` / `with_entrypoint(ep)`
- `with_name(name)` / `with_network(network)`
- `with_bind_mount(host, container)` / `with_readonly_bind(host, container)`
- `with_tmpfs(path)`
- `with_privileged()` (use with caution; naming alone is the security
  signal)

### Lifecycle and output

- `formula(cfg) -> Result(Formula(DockerImage), error.Error)` —
  validates input, runs `docker build`, and wraps the result in a
  `Formula(DockerImage)` ready for `testcontainer.with_formula`.
- `DockerImage` carries both the running `Container` (so callers can
  use `container.host_port`, `container.host`, `container.mapped_url`)
  and the built image ID. Accessors: `image_id/1`, `container/1`.

### Validation

- `dockerfile_path` and `context_path` are trimmed before they reach
  the FFI; leading/trailing whitespace cannot leak into `docker build`
  args.
- `fio.is_file` is used to confirm the Dockerfile is a regular file —
  a directory named `./Dockerfile` is rejected as `DockerfileNotFound`
  rather than being silently passed to Docker.
- Paths and build-arg values are rejected if they contain NUL or
  CR/LF.

### FFI hardening

- Subprocess invoked via `erlang:open_port` with
  `{spawn_executable, ...}` and `{args, ...}` (no shell, no
  metacharacter expansion). Build args are joined into single argv
  elements, so an attacker-controlled value cannot escape into a
  separate Docker flag.
- `try/catch` around `port spawn` to surface OS-level failures with
  context.
- 10 MB cap on accumulated build output (`MAX_OUTPUT_BYTES`) to bound
  memory; truncation is marked inline.
- Configurable timeout enforced via `receive ... after` with explicit
  `port_close` cleanup.
- Exit-code mapping: 125 → `docker daemon error`, 126 → `docker not
  executable`, 127 → `docker not found`, others → generic prefix.
- `DOCKER_NOT_FOUND` sentinel from FFI maps to typed
  `error.DockerNotFound` on the Gleam side.

### Errors (`testcontainer_dockerfile/error`)

```gleam
pub type Error {
  DockerNotFound
  DockerfileNotFound(path: String)
  BuildFailed(path: String, reason: String)
}
```

`BuildFailed.reason` carries full `docker build` output (stdout +
stderr merged) for diagnostics.

