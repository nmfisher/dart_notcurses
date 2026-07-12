import 'package:test/test.dart';

import 'harness.dart';

// Reproduction attempt for the cocoon bug:
//   "when I /spawn, the spawned panel is missing its │ side borders on the
//    input row; they come back when I cycle focus away."
//
// The input row is the one row where (a) the border is painted with the focus
// accent, (b) the shared input line rewrites the interior every keystroke, and
// (c) the hardware cursor is parked. Cocoon's notcurses backend flushes after
// every putAtAbsolute as `render()` + `cursorEnable(...)` (immediate).
//
// This test drives a real notcurses context through that exact call sequence
// and asks: do the border cells stay '│' in the cell grid through the
// cursor-park + damage-tracked re-render cycle?
//
// Result on a real terminal: PASS — the grid is correct, which rules out a
// binding/lib bug that corrupts the grid. The visible "missing border" is
// therefore a terminal-side effect: notcurses' damage tracker elides the
// unchanged border cells (see the emit:elide stats it prints — ~99.8% elided),
// so once the live terminal drops them during the cursor-parked state they
// stay dropped until a real cell change (the cyan→default shift on blur)
// forces re-emission. That terminal-side loss can't be reproduced in a unit
// test, because notcurses' capability handshake blocks output capture against
// anything but a responding terminal.

const _cyan = 0x00cdcd; // theme.border.focus ('36') → _basicColorRgb[6]

void main() {
  group(
    'cursor-row border retention',
    () {
      test('input-row border cells survive cursor-park + damage-tracked renders',
          () async {
        await withNotcurses((nc, std) async {
          final dim = std.dimyx();
          final row = dim.y ~/ 2;
          final lastCol = dim.x - 1;
          final interiorW = lastCol - 1; // cols 1..lastCol-1
          const inputCol = 3; // cursor sits after '> '

          String glyph(int x) => std.atYX(row, x)?.egc ?? '<null>';

          // Cocoon flushes after every putAtAbsolute as render()+cursorEnable().
          void flush() {
            nc.render();
            nc.cursorEnable(y: row, x: inputCol);
          }

          // -- panel.render() side loop (focused → cyan accent) --------------
          std.setFgRGB(_cyan);
          std.putStrYX(row, 0, '│'); // left border
          flush();
          std.putStrYX(row, lastCol, '│'); // right border
          flush();
          std.setFgDefault();
          std.setBgDefault();

          // -- panel._renderInputRow + InputRegion.render (interior + prompt) -
          std.putStrYX(row, 1, ' ' * interiorW); // erase interior
          std.putStrYX(row, 1, '> '); // prompt
          flush();
          // A second input re-render (mimics one keystroke / cursor blink).
          std.putStrYX(row, 1, ' ' * interiorW);
          std.putStrYX(row, 1, '> hello');
          flush();
          nc.cursorEnable(y: row, x: 8); // cursor advances with the typed text

          // -- assertions: the border cells must still be '│' ----------------
          expect(glyph(0), '│', reason: 'left border survives');
          expect(glyph(lastCol), '│', reason: 'right border survives');
          // And the interior was actually written.
          expect(glyph(1), '>', reason: 'prompt present');
        });
      });
    },
    skip: !notcursesSupported
        ? 'needs a controlling TTY (notcurses opens /dev/tty)'
        : false,
  );
}
