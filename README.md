<p align="center">
  <img src="https://raw.githubusercontent.com/lupodevelop/testcontainer_dockerfile/main/assets/img/logo.png" alt="Pago, the paguro mascot, carrying a Docker container on his shell" width="220">
</p>

<h1 align="center">testcontainer_dockerfile</h1>

<p align="center">
  <a href="https://hex.pm/packages/testcontainer_dockerfile"><img src="https://img.shields.io/hexpm/v/testcontainer_dockerfile?color=ffaff3" alt="Hex Package"></a>
  <a href="https://hexdocs.pm/testcontainer_dockerfile/"><img src="https://img.shields.io/badge/hex-docs-ffaff3" alt="Hex Docs"></a>
  <a href="https://github.com/lupodevelop/testcontainer_dockerfile/actions/workflows/test.yml"><img src="https://github.com/lupodevelop/testcontainer_dockerfile/actions/workflows/test.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/lupodevelop/testcontainer_dockerfile/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
  <a href="https://gleam.run"><img src="https://img.shields.io/badge/made%20with-gleam-ffaff3?logo=gleam" alt="Made with Gleam"></a>
</p>

> Build custom Docker images from a `Dockerfile` and use them as typed
> formulas with [`testcontainer`](https://hex.pm/packages/testcontainer).
> Pago handles the build; you get the container.

`testcontainer` is a container **runner**: it does not build images.
This package fills the build-on-test gap by shelling out to
`docker build` and wrapping the resulting image in a `Formula`.

```gleam
let cfg =
  testcontainer_dockerfile.new("./Dockerfile")
  |> testcontainer_dockerfile.with_context(".")
  |> testcontainer_dockerfile.with_build_arg("BUILD_VERSION", "dev")
  |> testcontainer_dockerfile.with_expose_port(port.tcp(3000))
  |> testcontainer_dockerfile.with_env("LOG_LEVEL", "info")
  |> testcontainer_dockerfile.with_wait(wait.health_check())

let assert Ok(formula) = testcontainer_dockerfile.formula(cfg)
use container <- testcontainer.with_formula(formula)
// the image is built once, the container is created from it,
// and torn down on scope exit.
```

## Why use it

- 🛠 **Build-on-test**: real `docker build` driven from your test code,
  layers and all
- 🔒 **Type-safe pipeline**: `with_*` builders compose the resulting
  spec, applied after build
- 🩺 **Validation upfront**: missing files, invalid build-arg keys, and
  unsafe characters caught before invoking Docker
- ⏱ **Configurable timeout**: 10-minute default, override via
  `with_timeout(ms)`
- 📦 **Plays with the ecosystem**: builds images that flow into
  `testcontainer.with_formula` like any other formula

## Install

```sh
gleam add testcontainer_dockerfile@1
```

## API

### Build configuration

- `new(path)` — start with a Dockerfile path
- `with_context(cfg, path)` — build context (default `.`)
- `with_build_arg(cfg, key, value)` — passed as `--build-arg` to docker build
- `with_timeout(cfg, ms)` — override the 10-minute build timeout

### Container shape (applied AFTER build)

Mirror `testcontainer/container` builders, but on the built image:

- `with_expose_port(cfg, port)`
- `with_env(cfg, key, value)`
- `with_label(cfg, key, value)`
- `with_wait(cfg, strategy)`
- `with_command(cfg, cmd)` / `with_entrypoint(cfg, ep)`
- `with_name(cfg, name)` / `with_network(cfg, name)`

### Lifecycle

- `formula(cfg) -> Result(Formula(DockerImage), error.Error)` — runs
  `docker build` eagerly; pass the returned `Formula` to
  `testcontainer.with_formula`.

### Errors (`testcontainer_dockerfile/error`)

```gleam
pub type Error {
  DockerNotFound
  DockerfileNotFound(path: String)
  BuildFailed(path: String, reason: String)
}
```

`BuildFailed.reason` includes full `docker build` output (stdout +
stderr merged), so you see exactly which RUN step broke.

## How it works

`docker build --quiet --no-cache -f <path> [--build-arg ...] <context>`
is invoked via `erlang:open_port` with `{spawn_executable, ...}` (no
shell, no escape risk). With `--quiet`, Docker prints only the final
image ID on stdout — that's what `formula/1` returns.

After build:

1. The image ID becomes a regular `container.new(image_id)` spec.
2. Any `with_expose_port`, `with_env`, `with_wait` etc. accumulated on
   `DockerfileConfig` are applied to that spec via a chain of
   transform functions.
3. The configured spec is wrapped in a `Formula(DockerImage)` that
   returns the image ID as the typed output.

## When to use this vs alternatives

| Workflow | Tool |
| --- | --- |
| Pre-built public image (`postgres:16`, `redis:7`) | `testcontainer` core, `container.new` |
| Custom image, pre-built in CI | `testcontainer` core with image tag |
| Custom image, built inline at test time | **this package** |
| `docker-compose.yml` orchestrating multiple services | [`testcontainer_compose`](https://hex.pm/packages/testcontainer_compose) |

## Development

```sh
gleam run -m testcontainer_dockerfile_dev   # Dev runner (needs Docker)
gleam test                                   # Unit tests (no Docker)
TESTCONTAINERS_INTEGRATION=true gleam test   # Integration tests (Docker required)
```

## See also

- [`testcontainer`](https://github.com/lupodevelop/testcontainer) — the
  core container runner
- [`testcontainer_formulas`](https://github.com/lupodevelop/testcontainer_formulas) —
  pre-built formulas for Postgres / Redis / MySQL / RabbitMQ / Mongo
- [`testcontainer_compose`](https://github.com/lupodevelop/testcontainer_compose) —
  spin up `docker-compose.yml` stacks
- [`testcontainer_formulas_builder`](https://github.com/lupodevelop/testcontainer_formulas_builder) —
  visual builder + codegen, also accepts Dockerfile / compose uploads

Full API docs: <https://hexdocs.pm/testcontainer_dockerfile>

## License

[MIT](LICENSE).
