import gleeunit
import testcontainer_dockerfile
import testcontainer_dockerfile/error

@external(erlang, "test_helpers_ffi", "getenv")
fn getenv(name: String) -> Result(String, Nil)

pub fn main() -> Nil {
  gleeunit.main()
}

fn integration_enabled() -> Bool {
  case getenv("TESTCONTAINERS_INTEGRATION") {
    Ok("true") -> True
    Ok("1") -> True
    _ -> False
  }
}

// ---------------------------------------------------------------------------
// Builder API tests (no docker required)
// ---------------------------------------------------------------------------

pub fn new_returns_config_test() {
  let _cfg = testcontainer_dockerfile.new("./Dockerfile")
  Nil
}

pub fn with_context_test() {
  let _cfg =
    testcontainer_dockerfile.new("./Dockerfile")
    |> testcontainer_dockerfile.with_context("./app")
  Nil
}

pub fn with_build_arg_chain_test() {
  let _cfg =
    testcontainer_dockerfile.new("./Dockerfile")
    |> testcontainer_dockerfile.with_build_arg("VERSION", "1.0.0")
    |> testcontainer_dockerfile.with_build_arg("REGISTRY", "docker.io")
  Nil
}

pub fn with_env_chain_test() {
  let _cfg =
    testcontainer_dockerfile.new("./Dockerfile")
    |> testcontainer_dockerfile.with_env("LOG_LEVEL", "info")
    |> testcontainer_dockerfile.with_env("PORT", "3000")
  Nil
}

pub fn with_label_test() {
  let _cfg =
    testcontainer_dockerfile.new("./Dockerfile")
    |> testcontainer_dockerfile.with_label("team", "platform")
  Nil
}

pub fn with_command_test() {
  let _cfg =
    testcontainer_dockerfile.new("./Dockerfile")
    |> testcontainer_dockerfile.with_command(["sh", "-c", "echo ok"])
  Nil
}

pub fn with_entrypoint_test() {
  let _cfg =
    testcontainer_dockerfile.new("./Dockerfile")
    |> testcontainer_dockerfile.with_entrypoint(["/usr/bin/tini", "--"])
  Nil
}

pub fn formula_rejects_empty_path_test() {
  let cfg = testcontainer_dockerfile.new("")
  case testcontainer_dockerfile.formula(cfg) {
    Error(error.DockerfileNotFound(_)) -> Nil
    _ -> panic as "expected DockerfileNotFound on empty path"
  }
}

pub fn formula_rejects_whitespace_path_test() {
  let cfg = testcontainer_dockerfile.new("   ")
  case testcontainer_dockerfile.formula(cfg) {
    Error(error.DockerfileNotFound(_)) -> Nil
    _ -> panic as "expected DockerfileNotFound on whitespace path"
  }
}

pub fn formula_rejects_nonexistent_file_test() {
  let cfg = testcontainer_dockerfile.new("/tmp/definitely_does_not_exist.xyz")
  case testcontainer_dockerfile.formula(cfg) {
    Error(error.DockerfileNotFound(_)) -> Nil
    _ -> panic as "expected DockerfileNotFound on missing file"
  }
}

pub fn formula_rejects_invalid_build_arg_key_test() {
  let cfg =
    testcontainer_dockerfile.new("./test/fixtures/Dockerfile")
    |> testcontainer_dockerfile.with_build_arg("--malicious", "value")
  case testcontainer_dockerfile.formula(cfg) {
    Error(error.BuildFailed(_, reason)) -> {
      case reason {
        "invalid build-arg key:" <> _ -> Nil
        _ -> panic as "wrong reason: should mention invalid key"
      }
    }
    _ -> panic as "expected BuildFailed on invalid build-arg key"
  }
}

pub fn formula_rejects_build_arg_key_with_equals_test() {
  let cfg =
    testcontainer_dockerfile.new("./test/fixtures/Dockerfile")
    |> testcontainer_dockerfile.with_build_arg("KEY=INJECT", "value")
  case testcontainer_dockerfile.formula(cfg) {
    Error(error.BuildFailed(_, _)) -> Nil
    _ -> panic as "expected BuildFailed on key with ="
  }
}

pub fn formula_rejects_build_arg_value_with_newline_test() {
  let cfg =
    testcontainer_dockerfile.new("./test/fixtures/Dockerfile")
    |> testcontainer_dockerfile.with_build_arg("VALID_KEY", "line1\nline2")
  case testcontainer_dockerfile.formula(cfg) {
    Error(error.BuildFailed(_, _)) -> Nil
    _ -> panic as "expected BuildFailed on value with newline"
  }
}

pub fn formula_rejects_path_with_newline_test() {
  let cfg = testcontainer_dockerfile.new("./Docker\nfile")
  case testcontainer_dockerfile.formula(cfg) {
    Error(error.BuildFailed(_, _)) -> Nil
    Error(error.DockerfileNotFound(_)) -> Nil
    _ -> panic as "expected validation rejection on path with newline"
  }
}

pub fn with_timeout_clamps_below_minimum_test() {
  let _cfg =
    testcontainer_dockerfile.new("./Dockerfile")
    |> testcontainer_dockerfile.with_timeout(0)
  Nil
}

// ---------------------------------------------------------------------------
// Integration tests (require Docker daemon)
// ---------------------------------------------------------------------------

pub fn integration_build_minimal_dockerfile_test() {
  case integration_enabled() {
    False -> Nil
    True -> {
      let cfg =
        testcontainer_dockerfile.new("./test/fixtures/Dockerfile")
        |> testcontainer_dockerfile.with_context("./test/fixtures")
        |> testcontainer_dockerfile.with_build_arg("GREETING", "ciao")

      case testcontainer_dockerfile.formula(cfg) {
        Ok(_formula) -> Nil
        Error(error.BuildFailed(_, _)) ->
          panic as "build failed (check docker daemon and Dockerfile)"
        Error(_) -> panic as "unexpected dockerfile error"
      }
    }
  }
}
