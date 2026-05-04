pub type Error {
  DockerNotFound
  DockerfileNotFound(path: String)
  BuildFailed(path: String, reason: String)
}
