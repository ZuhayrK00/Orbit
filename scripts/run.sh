#!/bin/bash
set -euo pipefail
ORBIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ORBIT_ROOT/scripts/build-app.sh" debug
open "$ORBIT_ROOT/build/Orbit.app"
