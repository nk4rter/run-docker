Run commands in a persistent docker container.

# Overview

[TODO] Write overview

# Running as superuser

[TODO] Write about superuser

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
