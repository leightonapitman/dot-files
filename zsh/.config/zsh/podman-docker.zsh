# Route Docker-compatible commands to a local Podman machine when Podman is in use.
# Set PODMAN_DOCKER_AUTOSTART=0 before this file is sourced to opt out.

podman_docker_configure() {
  [[ -o interactive ]] || return 0
  [[ "${PODMAN_DOCKER_AUTOSTART:-1}" == "1" ]] || return 0
  [[ "${PODMAN_DOCKER_ENV_INITIALIZED:-}" != "1" ]] || return 0
  command -v podman >/dev/null 2>&1 || return 0

  # Preserve an explicitly configured Docker Desktop or remote Docker endpoint.
  [[ -z "${DOCKER_HOST:-}" ]] || return 0

  local machine="podman-machine-default"
  local running_machine
  local memory
  local socket

  running_machine="$(podman machine list --format '{{range .}}{{if .Running}}{{.Name}}{{"\n"}}{{end}}{{end}}' 2>/dev/null | head -n 1)"
  # `podman machine list` marks the default machine with a trailing asterisk.
  running_machine="${running_machine%\*}"

  if [[ -n "${running_machine}" ]]; then
    machine="${running_machine}"
  elif ! podman machine inspect "${machine}" >/dev/null 2>&1; then
    if ! podman machine init --memory 8192 "${machine}" >/dev/null; then
      print -u2 "podman-docker: could not create ${machine}"
      return 0
    fi
  else
    memory="$(podman machine inspect "${machine}" --format '{{.Resources.Memory}}' 2>/dev/null)"
    if [[ "${memory}" =~ '^[0-9]+$' ]] && (( memory < 8192 )); then
      if ! podman machine set --memory 8192 "${machine}" >/dev/null; then
        print -u2 "podman-docker: could not set ${machine} memory to 8192 MiB"
        return 0
      fi
    fi
  fi

  if [[ -z "${running_machine}" ]] && ! podman machine start "${machine}" >/dev/null; then
    print -u2 "podman-docker: could not start ${machine}"
    return 0
  fi

  socket="$(podman machine inspect "${machine}" --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null)"
  if [[ -z "${socket}" ]]; then
    print -u2 "podman-docker: could not determine ${machine}'s API socket"
    return 0
  fi

  export DOCKER_HOST="unix://${socket}"
  export PODMAN_DOCKER_ENV_INITIALIZED=1
}

podman_docker_configure
