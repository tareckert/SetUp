#!/bin/sh
# Kompatibilität mit v1: run-project.sh <projekt> öffnet PyCharm im Kerker (jetzt: ki open).
exec "$(dirname "$(readlink -f "$0")")/ki" open "$@"
