#!/bin/bash
# Build (if needed) and run the bundled app in the foreground so its NSLog
# output is visible in the terminal. Ctrl-C to quit.
set -euo pipefail
cd "$(dirname "$0")"

[ -d "OnTouch.app" ] || ./build.sh
exec ./OnTouch.app/Contents/MacOS/OnTouch
