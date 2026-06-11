#!/bin/bash

set -e

print_usage() {
  echo >&2 "Usage: $0 [-i IMAGE] [-n NAME] [-H HOME] [-o OPTION]... [-p] [-r] [-s] [-N] [-- COMMAND [ARGS...]]"
}

print_error_usage() {
  print_usage
  echo >&2 "Run '$0 --help' for more information"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage
      cat >&2 <<EOF

Run a command in a Docker container.

Options:
  -i, --image    IMAGE      Image to use
  -n, --name     NAME       Container name
  -H, --home     HOME       Home dir name inside the project (default: .docker-home)
  -o, --option   OPTION     Extra docker run options
  -p, --passwd              Prompt for a password to set for the user and root
  -r, --restart             Recreate the container
  -s, --super               Run as root in the container
  -N, --nopasswd            Make sudo passwordless in the container
  -h, --help                Show this help message

Arguments:
  COMMAND [ARGS...]         Command to run in the container (default: bash)
EOF
      exit 0
      ;;
    -i|--image) IMAGE="$2"; shift 2 ;;
    -n|--name) CONTAINER="$2"; shift 2 ;;
    -H|--home) DOCKER_HOME_DIR="$2"; shift 2 ;;
    -o|--option) EXTRA_DOCKER_OPTS+=("$2"); shift 2 ;;
    -r|--restart) RESTART=1; shift ;;
    -s|--super) SUPER=1; shift ;;
    -p|--passwd) PASSWD=1; shift ;;
    -N|--nopasswd) NOPASSWD=1; shift ;;
    --) shift; break ;;
    -*) echo >&2 "Unknown option: $1"; print_error_usage ;;
    *) break ;;
  esac
done

if [ -z "${CONTAINER+x}" ]; then
  if [ -z "${IMAGE+x}" ]; then
    echo >&2 "ERROR: -i/--image is required when -n/--name is not specified"
    print_error_usage
  fi
  if command -v md5sum >/dev/null 2>&1; then
    _MD5=$(echo "$PWD" | md5sum | cut -b-7)
  else
    _MD5=$(echo "$PWD" | md5 -q | cut -b-7)
  fi
  CONTAINER="$(echo "$IMAGE" | tr -c -s '[:alnum:]' '_')$_MD5"
  unset _MD5
fi

if [ -n "${RESTART+x}" ] && [ -n "$(docker ps -a -q -f name="$CONTAINER")" ]; then
  echo >&2 "INFO: Removing docker container '$CONTAINER'"
  docker rm -f "$CONTAINER" >/dev/null
fi

if [ -z "$(docker ps -a -q -f name="$CONTAINER")" ]; then
  if [ -z "${IMAGE+x}" ]; then
    echo >&2 "ERROR: Container '$CONTAINER' does not exist; -i/--image is required to create it"
    print_error_usage
  fi

  CONTAINER_PASSWORD_B64=""
  if [ -n "${PASSWD+x}" ]; then
    while true; do
      read -rsp "Password: " CONTAINER_PASSWORD </dev/tty
      echo >&2
      read -rsp "Confirm password: " CONTAINER_PASSWORD_CONFIRM </dev/tty
      echo >&2
      if [ "$CONTAINER_PASSWORD" = "$CONTAINER_PASSWORD_CONFIRM" ]; then
        unset CONTAINER_PASSWORD_CONFIRM
        break
      fi
      echo >&2 "ERROR: Passwords do not match, please try again"
      unset CONTAINER_PASSWORD CONTAINER_PASSWORD_CONFIRM
    done
    CONTAINER_PASSWORD_B64=$(printf '%s' "$CONTAINER_PASSWORD" | base64 | tr -d '\n')
    unset CONTAINER_PASSWORD
  fi

  SUDO_ENABLED=""
  if [ -n "${PASSWD+x}" ] || [ -n "${NOPASSWD+x}" ]; then SUDO_ENABLED="1"; fi

  echo >&2 "INFO: Creating docker container '$CONTAINER'"

  XAUTHORITY_ARGS=()
  if [ -n "${XAUTHORITY+x}" ]; then
    XAUTHORITY_ARGS=(--env XAUTHORITY --volume "$XAUTHORITY:$XAUTHORITY")
  fi

  X11_SOCKET="/tmp/.X11-unix"
  X11_SOCKET_ARGS=()
  if [ -e "$X11_SOCKET" ]; then
    X11_SOCKET_ARGS=(--volume "$X11_SOCKET:$X11_SOCKET")
  fi

  XDG_RUNTIME_DIR_ARGS=()
  if [ -n "${XDG_RUNTIME_DIR+x}" ]; then
    XDG_RUNTIME_DIR_ARGS=(--env XDG_RUNTIME_DIR --volume "$XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR")
  fi

  USER_ID=$(id -u)
  GROUP_ID=$(id -g)
  USER=$(id -u -n)
  GROUP=$(id -g -n)

  MOUNT_HOME_ARGS=()
  if [ "$PWD" != "$HOME" ]; then
    DOCKER_HOME="$PWD/${DOCKER_HOME_DIR:-.docker-home}"
    mkdir -p "$DOCKER_HOME"
    case "$PWD" in
      "$HOME"*)
        mkdir -p "$DOCKER_HOME${PWD#"${HOME}"}"
        ;;
    esac
    MOUNT_HOME_ARGS=(--volume "$DOCKER_HOME:$HOME")
  fi

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
    "${EXTRA_DOCKER_OPTS[@]}" \
    "$IMAGE" >/dev/null

  cat <<EOF | docker exec -iu0:0 "$CONTAINER" sh -s
    set -e
    CONFLICT_USER="\$(grep '^[^:]*:[^:]*:$USER_ID:' /etc/passwd | cut -d: -f1)"
    if [ -n "\$CONFLICT_USER" ]; then
      sed -i '/^[^:]*:[^:]*:$USER_ID:/d' /etc/passwd
      sed -i "/^\$CONFLICT_USER:/d; s/\b\$CONFLICT_USER\b//g; s/,,/,/g; s/,$//; s/:,/:/" /etc/group
      sed -i "/^\$CONFLICT_USER:/d" /etc/shadow
    fi
    echo '$USER:x:$USER_ID:$GROUP_ID::$HOME:/usr/bin/bash' >>/etc/passwd
    echo '$GROUP:x:$GROUP_ID:' >>/etc/group
    echo '$USER:*:0:0:99999:7:::' >>/etc/shadow
    if [ -n '$CONTAINER_PASSWORD_B64' ]; then
      _PASS=\$(printf '%s' '$CONTAINER_PASSWORD_B64' | base64 -d)
      printf 'root:%s\n' "\$_PASS" | chpasswd
      printf '$USER:%s\n' "\$_PASS" | chpasswd
      unset _PASS
    fi
    if [ -n '$SUDO_ENABLED' ]; then
      NOPASSWD_PREFIX=""
      if [ '$NOPASSWD' = '1' ]; then NOPASSWD_PREFIX="NOPASSWD:"; fi
      mkdir -p /etc/sudoers.d
      echo "%$GROUP ALL=(ALL) \${NOPASSWD_PREFIX}ALL" >/etc/sudoers.d/user
      chmod 0440 /etc/sudoers.d/user
      if [ -f /etc/pam.d/su ]; then
        if [ '$NOPASSWD' = '1' ]; then
          { printf 'auth sufficient pam_permit.so\n'; cat /etc/pam.d/su; } > /tmp/_pam_su
          mv /tmp/_pam_su /etc/pam.d/su
        fi
        printf '#!/bin/sh\nif [ -x /usr/bin/sudo ]; then exec /usr/bin/sudo "\$@"; fi\nexec su root -c "\$*"\n' > /usr/local/bin/sudo
        chmod +x /usr/local/bin/sudo
      fi
    fi
EOF
fi

if [ -z "$(docker ps -q -f name="$CONTAINER")" ]; then
  echo >&2 "INFO: Starting docker container '$CONTAINER'"
  docker start "$CONTAINER" >/dev/null
fi

echo >&2 "INFO: Running in docker container '$CONTAINER'"

TTY_ARGS=()
if [ -t 0 ]; then TTY_ARGS=(--tty); fi

SUPER_ARGS=()
if [ -n "${SUPER+x}" ]; then SUPER_ARGS=(--user 0:0); fi

if [ "$#" = 0 ]; then set -- bash; fi

docker exec \
  "${TTY_ARGS[@]}" \
  --interactive \
  --env DISPLAY \
  --env TERM \
  "${SUPER_ARGS[@]}" \
  "$CONTAINER" \
  "$@"
