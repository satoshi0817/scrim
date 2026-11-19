#!/bin/zsh
# Compatibility entry point for older handoff commands.
exec "$(dirname "$0")/build-scrim.sh" "$@"
