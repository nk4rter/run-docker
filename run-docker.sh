#!/bin/sh

set -e

[ -z "${IMAGE+x}" ] && {
  echo >&2 "ERROR: IMAGE env var is unset"
  exit 1
}

[ -z "${CONTAINER+x}" ] && {
    CONTAINER="$(echo "$IMAGE" | tr -c -s '[:alnum:]' '_')$(echo "$PWD" | md5sum | cut -b-7)"
}

[ -z "$(docker ps -a -q -f name="$CONTAINER")" ] && {
  echo >&2 "INFO: Creating docker container '$CONTAINER'"

  [ -n "${XAUTHORITY+x}" ] &&
    XAUTHORITY_ARG="--env XAUTHORITY --volume $XAUTHORITY:$XAUTHORITY"

  X11_SOCKET="/tmp/.X11-unix"
  [ -e $X11_SOCKET ] &&
    X11_SOCKET_ARG="--volume $X11_SOCKET:$X11_SOCKET"

  [ -n "${XDG_RUNTIME_DIR+x}" ] &&
    XDG_RUNTIME_DIR_ARG="--env XDG_RUNTIME_DIR --volume "$XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR""

  USER_ID=$(id -u)
  GROUP_ID=$(id -g)
  USER=$(id -u -n)
  GROUP=$(id -g -n)

  [ "$PWD" != "$HOME" ] && {
    DOCKER_HOME="$PWD/.docker-home"
    mkdir -p "$DOCKER_HOME"
    case "$PWD" in
      "$HOME"*)
        mkdir -p "$DOCKER_HOME${PWD#"${HOME}"}"
        ;;
    esac
    MOUNT_HOME_ARG="--volume "$DOCKER_HOME:$HOME""
  }

  docker run \
    --detach \
    --interactive \
    --hostname "$(hostname)" \
    --user "$USER_ID:$GROUP_ID" \
    --workdir "$PWD" \
    --env HOME \
    --env USER \
    $XAUTHORITY_ARG \
    $X11_SOCKET_ARG \
    $XDG_RUNTIME_DIR_ARG \
    $MOUNT_HOME_ARG \
    --volume "$PWD:$PWD" \
    --name "$CONTAINER" \
    $EXTRA_DOCKER_OPTS \
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

[ -t 0 ] && TTY_ARG="--tty"

[ "$#" = 0 ] && set -- bash

docker exec \
  $TTY_ARG \
  --interactive \
  --env DISPLAY \
  --env TERM \
  "$CONTAINER" \
  "$@"
