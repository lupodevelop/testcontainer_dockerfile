//// Build custom Docker images from a Dockerfile and use them as typed
//// formulas with [`testcontainer`](https://hex.pm/packages/testcontainer).
////
//// `testcontainer` is a container runner: it does not build images.
//// This package fills the gap by shelling out to `docker build` and
//// wrapping the resulting image in a `Formula`.

import cowl
import fio
import gleam/list
import gleam/result
import gleam/string
import testcontainer/container
import testcontainer/formula
import testcontainer/port
import testcontainer/wait
import testcontainer_dockerfile/error

/// Default build timeout (10 minutes). Can be overridden via
/// [`with_timeout`](#with_timeout).
pub const default_timeout_ms: Int = 600_000

/// Maximum allowed build timeout (1 hour). `with_timeout` clamps to this.
pub const max_timeout_ms: Int = 3_600_000

/// Opaque builder for a Dockerfile build configuration.
/// Construct via [`new`](#new) and refine with `with_*` builders.
pub opaque type DockerfileConfig {
  DockerfileConfig(
    dockerfile_path: String,
    context_path: String,
    build_args: List(#(String, String)),
    spec_transforms: List(
      fn(container.ContainerSpec) -> container.ContainerSpec,
    ),
    timeout_ms: Int,
  )
}

/// The typed output yielded after a successful build + container start.
/// Carries the running `Container` (so callers can use
/// `container.host_port`, `container.host`, etc.) plus the built image ID.
pub opaque type DockerImage {
  DockerImage(container: container.Container, image_id: String)
}

/// Start a new Dockerfile build configuration.
///
/// `dockerfile_path` should point to a readable Dockerfile, e.g.
/// `"./Dockerfile"` or `"docker/api.Dockerfile"`. The path is trimmed
/// before being passed to `docker build -f`.
pub fn new(dockerfile_path: String) -> DockerfileConfig {
  DockerfileConfig(
    dockerfile_path: dockerfile_path,
    context_path: ".",
    build_args: [],
    spec_transforms: [],
    timeout_ms: default_timeout_ms,
  )
}

/// Set the build context (sent to the Docker daemon as the build root).
/// Defaults to the current directory (`.`).
pub fn with_context(
  cfg: DockerfileConfig,
  context_path: String,
) -> DockerfileConfig {
  DockerfileConfig(..cfg, context_path: context_path)
}

/// Add a `--build-arg` flag passed to `docker build`. Use for `ARG`
/// directives inside the Dockerfile.
///
/// Note: build args are visible in the host's process list (`ps aux`)
/// during the build window. Do **not** pass real secrets via build args;
/// use [`with_secret_env`](#with_secret_env) for runtime secrets, or
/// Docker BuildKit secret mounts for build-time secrets.
pub fn with_build_arg(
  cfg: DockerfileConfig,
  key: String,
  value: String,
) -> DockerfileConfig {
  let args = list.append(cfg.build_args, [#(key, value)])
  DockerfileConfig(..cfg, build_args: args)
}

/// Override the default 10-minute build timeout. Clamped to the inclusive
/// range `[1000, max_timeout_ms]`.
pub fn with_timeout(cfg: DockerfileConfig, ms: Int) -> DockerfileConfig {
  let clamped = case ms < 1000, ms > max_timeout_ms {
    True, _ -> 1000
    False, True -> max_timeout_ms
    False, False -> ms
  }
  DockerfileConfig(..cfg, timeout_ms: clamped)
}

// ---------------------------------------------------------------------------
// Container spec builders (applied AFTER build)
// ---------------------------------------------------------------------------

/// Map a port that should be exposed when the container runs.
pub fn with_expose_port(
  cfg: DockerfileConfig,
  p: port.Port,
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.expose_port(spec, p) })
}

/// Map several exposed ports at once.
pub fn with_expose_ports(
  cfg: DockerfileConfig,
  ports: List(port.Port),
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.expose_ports(spec, ports) })
}

/// Add an environment variable injected at container start. Overrides
/// any `ENV` baked into the image.
pub fn with_env(
  cfg: DockerfileConfig,
  key: String,
  value: String,
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.with_env(spec, key, value) })
}

/// Add many env vars at once.
pub fn with_envs(
  cfg: DockerfileConfig,
  pairs: List(#(String, String)),
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.with_envs(spec, pairs) })
}

/// Add an env var whose value is wrapped in `cowl.Secret` and never
/// appears in `string.inspect` output.
pub fn with_secret_env(
  cfg: DockerfileConfig,
  key: String,
  secret: cowl.Secret(String),
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.with_secret_env(spec, key, secret) })
}

/// Add a Docker label to the running container.
pub fn with_label(
  cfg: DockerfileConfig,
  key: String,
  value: String,
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.with_label(spec, key, value) })
}

/// Set the wait strategy used after the container starts. Replaces any
/// previous wait strategy.
pub fn with_wait(
  cfg: DockerfileConfig,
  strategy: wait.WaitStrategy,
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.wait_for(spec, strategy) })
}

/// Combine an additional wait strategy with whatever is already configured
/// using `wait.all_of`. Useful to layer e.g. `wait.health_check()` on top
/// of a base port wait.
pub fn with_extra_wait(
  cfg: DockerfileConfig,
  extra: wait.WaitStrategy,
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) {
    let current = container.wait_strategy(spec)
    container.wait_for(spec, wait.all_of([current, extra]))
  })
}

/// Override the image's CMD when running the container.
pub fn with_command(
  cfg: DockerfileConfig,
  cmd: List(String),
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.with_command(spec, cmd) })
}

/// Override the image's ENTRYPOINT.
pub fn with_entrypoint(
  cfg: DockerfileConfig,
  ep: List(String),
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.with_entrypoint(spec, ep) })
}

/// Set a fixed container name.
pub fn with_name(cfg: DockerfileConfig, name: String) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.with_name(spec, name) })
}

/// Attach the container to a Docker network by name.
pub fn with_network(
  cfg: DockerfileConfig,
  network: String,
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.on_network(spec, network) })
}

/// Bind-mount a host path read-write into the container.
pub fn with_bind_mount(
  cfg: DockerfileConfig,
  host_path: String,
  container_path: String,
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) {
    container.with_bind_mount(spec, host_path, container_path)
  })
}

/// Bind-mount a host path read-only into the container.
pub fn with_readonly_bind(
  cfg: DockerfileConfig,
  host_path: String,
  container_path: String,
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) {
    container.with_readonly_bind(spec, host_path, container_path)
  })
}

/// Mount an in-memory tmpfs at the given container path.
pub fn with_tmpfs(
  cfg: DockerfileConfig,
  container_path: String,
) -> DockerfileConfig {
  add_transform(cfg, fn(spec) { container.with_tmpfs(spec, container_path) })
}

/// Run the container as privileged. **Use with extreme caution**: a
/// privileged container has full access to host devices and can escape
/// most isolation. Naming alone (`with_privileged`) is the security
/// signal — there is no runtime warning.
pub fn with_privileged(cfg: DockerfileConfig) -> DockerfileConfig {
  add_transform(cfg, container.with_privileged)
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Run `docker build` and return a `Formula` that wraps the resulting
/// image. The build happens eagerly when this function is called.
///
/// On success, the returned `Formula` can be passed straight to
/// `testcontainer.with_formula` (see the README for an end-to-end example).
///
/// Failure modes (`error.Error` variants):
/// - `DockerNotFound` — the `docker` CLI is not on PATH
/// - `DockerfileNotFound(path)` — the configured Dockerfile path is
///   empty, contains invalid characters, points to a directory, or does
///   not exist on disk
/// - `BuildFailed(path, reason)` — `docker build` returned non-zero
///   or invalid build-arg keys were rejected. `reason` carries full
///   stdout+stderr for diagnostics
pub fn formula(
  cfg: DockerfileConfig,
) -> Result(formula.Formula(DockerImage), error.Error) {
  use trimmed_cfg <- result.try(validate_and_normalize(cfg))
  use image_id <- result.try(build_dockerfile(trimmed_cfg))
  let spec =
    apply_transforms(container.new(image_id), trimmed_cfg.spec_transforms)
  Ok(
    formula.new(spec, fn(running) {
      Ok(DockerImage(container: running, image_id: image_id))
    }),
  )
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

/// Get the Docker image ID (e.g. `sha256:abcd...`) of a built image.
pub fn image_id(img: DockerImage) -> String {
  img.image_id
}

/// Get the running `Container` so you can use `container.host_port`,
/// `container.host`, `container.mapped_url`, etc.
pub fn container(img: DockerImage) -> container.Container {
  img.container
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

fn validate_and_normalize(
  cfg: DockerfileConfig,
) -> Result(DockerfileConfig, error.Error) {
  let trimmed_dockerfile = string.trim(cfg.dockerfile_path)
  let trimmed_context = string.trim(cfg.context_path)
  use _ <- result.try(validate_path_string(trimmed_dockerfile, "dockerfile"))
  use _ <- result.try(validate_path_string(trimmed_context, "context"))
  use _ <- result.try(validate_dockerfile_is_file(trimmed_dockerfile))
  use _ <- result.try(validate_build_args(cfg.build_args))
  Ok(
    DockerfileConfig(
      ..cfg,
      dockerfile_path: trimmed_dockerfile,
      context_path: trimmed_context,
    ),
  )
}

fn validate_path_string(
  path: String,
  kind: String,
) -> Result(Nil, error.Error) {
  case path {
    "" ->
      case kind {
        "dockerfile" -> Error(error.DockerfileNotFound(path: ""))
        _ ->
          Error(error.BuildFailed(path: path, reason: "context path is empty"))
      }
    _ ->
      case has_unsafe_char(path) {
        True ->
          Error(error.BuildFailed(
            path: path,
            reason: kind <> " path contains NUL or CR/LF characters",
          ))
        False -> Ok(Nil)
      }
  }
}

fn validate_dockerfile_is_file(path: String) -> Result(Nil, error.Error) {
  case fio.is_file(path) {
    Ok(True) -> Ok(Nil)
    Ok(False) -> Error(error.DockerfileNotFound(path: path))
    Error(_) -> Error(error.DockerfileNotFound(path: path))
  }
}

fn validate_build_args(
  args: List(#(String, String)),
) -> Result(Nil, error.Error) {
  case args {
    [] -> Ok(Nil)
    [#(key, value), ..rest] ->
      case is_valid_build_arg_key(key) {
        False ->
          Error(error.BuildFailed(
            path: "",
            reason: "invalid build-arg key: "
              <> key
              <> " (must match [A-Za-z_][A-Za-z0-9_]*)",
          ))
        True ->
          case has_unsafe_char(value) {
            True ->
              Error(error.BuildFailed(
                path: "",
                reason: "build-arg value for "
                  <> key
                  <> " contains NUL or CR/LF characters",
              ))
            False -> validate_build_args(rest)
          }
      }
  }
}

fn has_unsafe_char(s: String) -> Bool {
  string.contains(s, "\u{0000}")
  || string.contains(s, "\n")
  || string.contains(s, "\r")
}

fn is_valid_build_arg_key(key: String) -> Bool {
  case string.to_graphemes(key) {
    [] -> False
    [first, ..rest] ->
      is_valid_first_char(first) && list.all(rest, is_valid_arg_char)
  }
}

fn is_valid_first_char(c: String) -> Bool {
  is_alpha(c) || c == "_"
}

fn is_valid_arg_char(c: String) -> Bool {
  is_alpha(c) || is_digit(c) || c == "_"
}

fn is_alpha(c: String) -> Bool {
  case c {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    _ -> False
  }
}

fn is_digit(c: String) -> Bool {
  case c {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

fn add_transform(
  cfg: DockerfileConfig,
  t: fn(container.ContainerSpec) -> container.ContainerSpec,
) -> DockerfileConfig {
  DockerfileConfig(
    ..cfg,
    spec_transforms: list.append(cfg.spec_transforms, [t]),
  )
}

fn apply_transforms(
  spec: container.ContainerSpec,
  transforms: List(fn(container.ContainerSpec) -> container.ContainerSpec),
) -> container.ContainerSpec {
  list.fold(transforms, spec, fn(s, t) { t(s) })
}

@external(erlang, "testcontainer_dockerfile_ffi", "run_docker_build")
fn ffi_build(
  dockerfile: String,
  context: String,
  args: List(#(String, String)),
  timeout_ms: Int,
) -> Result(String, String)

fn build_dockerfile(cfg: DockerfileConfig) -> Result(String, error.Error) {
  case
    ffi_build(
      cfg.dockerfile_path,
      cfg.context_path,
      cfg.build_args,
      cfg.timeout_ms,
    )
  {
    Ok(image_id) -> Ok(image_id)
    Error("DOCKER_NOT_FOUND") -> Error(error.DockerNotFound)
    Error(reason) ->
      Error(error.BuildFailed(path: cfg.dockerfile_path, reason: reason))
  }
}
