import gleam/io
import testcontainer
import testcontainer/exec
import testcontainer/formula
import testcontainer_dockerfile
import testcontainer_dockerfile/error

pub fn main() {
  io.println("━━━ testcontainer_dockerfile dev runner ━━━")

  let cfg =
    testcontainer_dockerfile.new("dev/Dockerfile.sample")
    |> testcontainer_dockerfile.with_context("dev")
    |> testcontainer_dockerfile.with_build_arg("GREETING", "ciao")

  case testcontainer_dockerfile.formula(cfg) {
    Ok(formula) -> {
      io.println("step 1: image built")
      let res = run_with_container(formula)
      case res {
        Ok(_) -> io.println("done: container ran and was torn down")
        Error(_) -> io.println("error during container run")
      }
    }
    Error(err) -> print_error(err)
  }
}

fn run_with_container(
  f: formula.Formula(testcontainer_dockerfile.DockerImage),
) -> Result(Nil, _) {
  use img <- testcontainer.with_formula(f)
  io.println(
    "step 2: container running, image_id="
    <> testcontainer_dockerfile.image_id(img),
  )

  let c = testcontainer_dockerfile.container(img)
  case testcontainer.exec(c, ["cat", "/greeting.txt"]) {
    Ok(result) -> {
      io.println("step 3: exec output:")
      io.println("  " <> exec.output(result))
    }
    Error(_) -> io.println("step 3: exec failed")
  }
  Ok(Nil)
}

fn print_error(err: error.Error) -> Nil {
  let msg = case err {
    error.DockerNotFound -> "docker not found in PATH"
    error.DockerfileNotFound(p) -> "dockerfile not found: " <> p
    error.BuildFailed(p, r) -> "build failed for " <> p <> ": " <> r
  }
  io.println("error: " <> msg)
}
