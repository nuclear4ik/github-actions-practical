#!/usr/bin/env bash
# Source this file before working with the lab on any Mac.
export PRACTICE_HOME="${PRACTICE_HOME:-$HOME/Library/Application Support/DevOpsPractices}"
if [ -d /Applications/Docker.app ]; then
  export DOCKER_APP=/Applications/Docker.app
else
  export DOCKER_APP="$HOME/Applications/Docker.app"
fi
export PATH="$PRACTICE_HOME/bin:$DOCKER_APP/Contents/Resources/bin:$HOME/.docker/bin:$PATH"
