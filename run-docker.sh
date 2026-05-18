#!/bin/bash

set -e

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") -i IMAGE [-n NAME] [-- COMMAND [ARGS...]]

Run a command in a Docker container.

Options:
  -i, --image IMAGE   Docker image to use (required)
  -n, --name NAME     Container name (default: derived from image and cwd)
  -h, --help          Show this help message

Arguments:
  COMMAND [ARGS...]   Command to run in the container (default: bash)
EOF
      exit 0
      ;;
    -i|--image) IMAGE="$2"; shift 2 ;;
    -n|--name) CONTAINER="$2"; shift 2 ;;
    --) shift; break ;;
    *)
      echo >&2 "ERROR: unknown argument: $1"
      echo >&2 "Run '$(basename "$0") --help' for usage."
      exit 1
      ;;
  esac
done

[ -z "${IMAGE+x}" ] && {
  echo >&2 "ERROR: -i/--image is required"
  echo >&2 "Run '$(basename "$0") --help' for usage."
  exit 1
}

[ -z "${CONTAINER+x}" ] && {
    CONTAINER="$(echo "$IMAGE" | tr -c -s '[:alnum:]' '_')$(echo "$PWD" | md5sum | cut -b-7)"
}

[ -z "$(docker ps -a -q -f name="$CONTAINER")" ] && {
  echo >&2 "INFO: Creating docker container '$CONTAINER'"

  XAUTHORITY_ARGS=()
  [ -n "${XAUTHORITY+x}" ] &&
    XAUTHORITY_ARGS=(--env XAUTHORITY --volume "$XAUTHORITY:$XAUTHORITY")

  X11_SOCKET="/tmp/.X11-unix"
  X11_SOCKET_ARGS=()
  [ -e "$X11_SOCKET" ] &&
    X11_SOCKET_ARGS=(--volume "$X11_SOCKET:$X11_SOCKET")

  XDG_RUNTIME_DIR_ARGS=()
  [ -n "${XDG_RUNTIME_DIR+x}" ] &&
    XDG_RUNTIME_DIR_ARGS=(--env XDG_RUNTIME_DIR --volume "$XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR")

  USER_ID=$(id -u)
  GROUP_ID=$(id -g)
  USER=$(id -u -n)
  GROUP=$(id -g -n)

  MOUNT_HOME_ARGS=()
  [ "$PWD" != "$HOME" ] && {
    DOCKER_HOME="$PWD/.docker-home"
    mkdir -p "$DOCKER_HOME"
    case "$PWD" in
      "$HOME"*)
        mkdir -p "$DOCKER_HOME${PWD#"${HOME}"}"
        ;;
    esac
    MOUNT_HOME_ARGS=(--volume "$DOCKER_HOME:$HOME")
  }

  EXTRA_DOCKER_OPTS_ARGS=()
  [ -n "${EXTRA_DOCKER_OPTS:-}" ] && IFS=' ' read -r -a EXTRA_DOCKER_OPTS_ARGS <<< "$EXTRA_DOCKER_OPTS"

  docker run \
    --detach \
    --interactive \
    --hostname "$(hostname)" \
    --user "$USER_ID:$GROUP_ID" \
    --workdir "$PWD" \
    --env HOME \
    --env USER \
    "${XAUTHORITY_ARGS[@]}" \
    "${X11_SOCKET_ARGS[@]}" \
    "${XDG_RUNTIME_DIR_ARGS[@]}" \
    "${MOUNT_HOME_ARGS[@]}" \
    --volume "$PWD:$PWD" \
    --name "$CONTAINER" \
    "${EXTRA_DOCKER_OPTS_ARGS[@]}" \
    "$IMAGE" >/dev/null

  cat <<EOF | docker exec -iu0:0 "$CONTAINER" sh -s
    set -e
    CONFLICT_USER="\$(grep '^[^:]*:[^:]*:$USER_ID:' /etc/passwd | cut -d: -f1)"
    [ -n "\$CONFLICT_USER" ] && {
      sed -i '/^[^:]*:[^:]*:$USER_ID:/d' /etc/passwd
      sed -i "/^\$CONFLICT_USER:/d; s/\b\$CONFLICT_USER\b//g; s/,,/,/g; s/,$//; s/:,/:/" /etc/group
      sed -i "/^\$CONFLICT_USER:/d" /etc/shadow
    }
    echo '$USER:x:$USER_ID:$GROUP_ID::$HOME:/usr/bin/bash' >>/etc/passwd
    echo '$GROUP:x:$GROUP_ID:' >>/etc/group
    echo '$USER:*:0:0:99999:7:::' >>/etc/shadow
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update
      apt-get install -y --no-install-recommends sudo
      rm -rf /var/lib/apt/lists/*
    elif command -v pacman >/dev/null 2>&1; then
      pacman-key --init
      pacman --noconfirm -Syu sudo
      rm -rf /var/cache/pacman/pkg/*
      rm -rf /var/lib/pacman/sync/*
    fi
    echo '%$GROUP ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/user
    chmod 0440 /etc/sudoers.d/user
EOF
}

[ -z "$(docker ps -q -f name="$CONTAINER")" ] && {
  echo >&2 "INFO: Starting docker container '$CONTAINER'"
  docker start "$CONTAINER" >/dev/null
}

echo >&2 "INFO: Running in docker container '$CONTAINER'"

TTY_ARGS=()
[ -t 0 ] && TTY_ARGS=(--tty)

[ "$#" = 0 ] && set -- bash

docker exec \
  "${TTY_ARGS[@]}" \
  --interactive \
  --env DISPLAY \
  --env TERM \
  "$CONTAINER" \
  "$@"
