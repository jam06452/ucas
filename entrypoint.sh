#!/bin/sh
set -e

/app/bin/ucas eval "Ucas.Release.migrate()"

exec "$@"
