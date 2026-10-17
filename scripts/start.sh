#!/bin/sh
set -eu

# Bunny has no separate release command. Fail startup if migrations fail.
if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
  /app/bin/imaedge eval 'Imaedge.Release.migrate()'
fi

exec /app/bin/imaedge start
