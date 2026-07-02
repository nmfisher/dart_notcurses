#!/bin/sh
# Run the test suite and unconditionally restore the controlling terminal
# afterwards. In-process restoration (test/harness.dart restoreTty) covers
# normal and failing tests, but not suites killed mid-handshake (timeouts,
# ^C) — only a wrapper at this level survives those.
cd "$(dirname "$0")/.."

dart test "$@"
status=$?

# Reset SGR attributes, show the cursor, pop the kitty keyboard protocol.
printf '\033[0m\033[?25h\033[<u' > /dev/tty 2>/dev/null || true

exit $status
