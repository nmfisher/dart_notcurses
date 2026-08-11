import 'dart:io';
import 'dart:math';
import 'package:dart_notcurses/dart_notcurses.dart';

import 'image_loader.dart';

const int max_rand = 0x7ffff;

int main(List<String> args) {
  var rc = 0;
  NotCurses? nc;

  try {
    if (args.isEmpty) {
      print('pixel: need an image file name');
      return -1;
    }

    nc = NotCurses(CursesOptions(
      marginT: 2,
      marginR: 2,
      marginB: 2,
      marginL: 2,
      flags: OptionFlags.inhibitSetlocale,
    ));

    if (nc.checkPixelSupport() <= 0) {
      print('pixel graphics not supported');
      rc = -1;
    }
    rc = handle(nc, args[0]);
  } catch (e, s) {
    if (nc != null) nc.stop();
    print(e);
    print(s);
    rc = -1;
  } finally {
    if (nc != null) nc.stop();
    rc = 0;
  }

  return rc;
}

int handle(NotCurses nc, String fname) {
  final rnd = Random();
  final visual = loadImageFromFile(fname);

  final std = nc.stdplane();
  final dim = std.dimyx();

  // Pixel blits refuse a visual larger than the destination plane ("sprixel
  // too tall/wide for plane" in ncvisual_geom_inner), so scale the image down
  // to the terminal before the grid loop. Query the geometry without a plane:
  // only scaley/scalex are needed, and passing the plane would trip that same
  // size check.
  final fit = VisualOptions(scaling: Scale.noneHires, blitter: Blitter.pixel);
  final fg = visual.geom(nc, fit);
  if (fg == null || fg.scaley == null || fg.scalex == null) {
    stderr.writeln('pixel: unable to determine pixel geometry');
    visual.destroy();
    return -1;
  }
  if (!visual.resize(dim.y * fg.scaley!, dim.x * fg.scalex!)) {
    stderr.writeln('pixel: unable to scale image to terminal');
    visual.destroy();
    return -1;
  }

  for (var y = 0; y < dim.y; y += 15) {
    for (var x = 0; x < dim.x; x += 15) {
      var channels = Channels.initializer(
        rnd.nextInt(max_rand) % 256,
        rnd.nextInt(max_rand) % 256,
        100,
        rnd.nextInt(max_rand) % 256,
        100,
        140,
      );
      std.setBase('a', 0, channels);

      final vopts = VisualOptions(
        plane: std,
        y: y,
        x: x,
        scaling: Scale.noneHires,
        blitter: Blitter.pixel,
        flags: VisualOptionFlags.childplane | VisualOptionFlags.nodegrade,
      );

      final nv = visual.blit(nc, vopts);
      if (nv == null) {
        stderr.writeln('pixel: blit failed at $y,$x');
        visual.destroy();
        return -1;
      }

      nc.render();
      sleep(Duration(milliseconds: 500));
      channels = Channels.initializer(
        rnd.nextInt(max_rand) % 256,
        rnd.nextInt(max_rand) % 256,
        100,
        rnd.nextInt(max_rand) % 256,
        100,
        140,
      );
      std.setBase('a', 0, channels);
      nc.render();
      sleep(Duration(milliseconds: 500));
      nv.destroy();
    }
  }

  return 0;
}
