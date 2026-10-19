#!/bin/bash
# Run a command inside the course autotest container (Ubuntu 22.04 / GCC 11),
# which matches the CI environment used for grading.
#
# Usage:
#   ./docker-run.sh                 # interactive shell in the container
#   ./docker-run.sh ./build.sh      # run build.sh in the container
#   ./docker-run.sh ./full-test.sh  # run the same test CI runs
#
# The repo is mounted at the same absolute path as on the host, and commands
# run as a user with your host UID/GID so build output stays owned by you.
# Your host ssh-agent is forwarded so buildroot can clone git@github.com repos;
# run `ssh-add` on the host first if `ssh-add -l` shows no identities.

set -e

IMAGE=cuaesd/aesd-autotest:24-assignment4-buildroot

cd "$(dirname "$0")"
repo_dir="$(pwd -P)"
dl_dir="${HOME}/.dl"
mkdir -p "${dl_dir}"

docker_args=(
    --rm
    -v "${repo_dir}:${repo_dir}"
    -w "${repo_dir}"
    -v "${dl_dir}:/home/aesd/.dl"
    -e BR2_DL_DIR=/home/aesd/.dl
    -e HOST_UID="$(id -u)"
    -e HOST_GID="$(id -g)"
    -e GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new"
)

# Interactive terminal when there is one
if [ -t 0 ] && [ -t 1 ]; then
    docker_args+=(-it)
fi

# Forward the ssh-agent socket (resolve symlinks so the bind mount works)
if [ -n "${SSH_AUTH_SOCK}" ] && [ -S "$(readlink -f "${SSH_AUTH_SOCK}")" ]; then
    docker_args+=(-v "$(readlink -f "${SSH_AUTH_SOCK}"):/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent)
    if ! ssh-add -l > /dev/null 2>&1; then
        echo "WARNING: ssh-agent has no keys loaded; run ssh-add so buildroot can clone over ssh" >&2
    fi
else
    echo "WARNING: no ssh-agent found; cloning git@github.com repos will fail" >&2
fi

if [ $# -eq 0 ]; then
    set -- bash
fi

# Create a user matching the host UID/GID, then drop to it to run the command
exec docker run "${docker_args[@]}" "${IMAGE}" bash -c '
    groupadd -o -g "${HOST_GID}" aesd
    useradd -o -u "${HOST_UID}" -g "${HOST_GID}" -d /home/aesd -s /bin/bash aesd
    mkdir -p /home/aesd/.ssh
    chown "${HOST_UID}:${HOST_GID}" /home/aesd /home/aesd/.ssh
    echo "aesd ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/aesd
    exec sudo -E -H -u aesd PATH="${PATH}" "$@"
' bash "$@"
