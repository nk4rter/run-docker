Run commands in a persistent docker container.

# Overview

`run-docker.sh` runs a command (default `bash`) inside a long-lived container,
as your own user, with the current directory bind-mounted at the same path and
`$HOME` mounted from `./.docker-home`. `$DISPLAY`, `$XAUTHORITY`, the X11 socket
and `$XDG_RUNTIME_DIR` are passed through when present, so GUI apps work.

Your user must be able to talk to the Docker daemon, i.e. be in the `docker`
group (log out and back in afterwards):

```sh
sudo usermod -aG docker "$USER"
```

The container is created on first use and reused afterwards. Without `-n`, its
name is derived from the image plus a hash of the current directory, so each
project directory gets its own container.

```sh
./run-docker.sh -i ubuntu:latest                 # shell in the container
./run-docker.sh -i ubuntu:latest -- make test    # run one command
./run-docker.sh -n ubuntu_latest_1a2b3c4         # reuse an existing container
./run-docker.sh -i ubuntu:latest -r              # recreate from scratch
./run-docker.sh -i ubuntu:latest -o --network=host -- curl localhost:8080
```

Run `./run-docker.sh --help` for all options.

# Running as superuser

`-s` runs the command as root instead of your user — use it to install packages
in a fresh image, which normally has no sudo.

To get `sudo` for your own user instead, install the `sudo` package (see below),
then pass `-N` (passwordless) or `-p` (prompts for a password, set for both your
user and root). Either flag also installs a `sudo` shim falling back to `su` for
images without the real thing.

```sh
./run-docker.sh -i ubuntu:latest -N -- sudo whoami
```

## Create an Ubuntu container with sudo

```sh
./run-docker.sh -i ubuntu:latest -s -- sh -c "apt update && apt install -y sudo"
```

## Create an Arch Linux container with sudo

```sh
./run-docker.sh -i archlinux:latest -s -- sh -c "
  pacman-key --init &&
  pacman-key --populate archlinux &&
  pacman --noconfirm -Sy archlinux-keyring &&
  pacman --noconfirm -Syu sudo"
```
