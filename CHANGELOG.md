## Unreleased

- Reset abandoned escape-parser state so a split terminal reply cannot break
  subsequent arrow and shortcut decoding.
- Fix native input crashes on BEL-terminated OSC palette and default-color
  replies. The string extractor now accepts the same BEL/ST terminators as
  the escape automaton.
- Reject palette index 256 and free strings for invalid indices.
- Track native archives in the build hook so rebuilt libraries are relinked.
- Add native parser regression tests with responses ending at a protected
  memory page (`bash tool/build_notcurses.sh`, then
  `bash tool/test_input_parser.sh` on macOS or Linux).

## 1.0.0

- Initial version.
