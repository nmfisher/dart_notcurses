// ignore_for_file: library_prefixes
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import './extensions/int.dart';
import './ffi/notcurses_inline_g.dart' as ncInline;

// Channel encoding (mirrors notcurses channel.h). A 64-bit channel pair packs a
// background channel in the low 32 bits and a foreground channel in the high 32
// bits. The masks below are 64-bit-positioned; _CH_* are the unshifted 32-bit
// forms used when operating on a single channel (class Channel).
const int NC_NOBACKGROUND_MASK = 0x8700000000000000;
// if this bit is set, we are *not* using the default background color
const int NC_BGDEFAULT_MASK = 0x0000000040000000;
// extract these bits to get the background RGB value
const int NC_BG_RGB_MASK = 0x0000000000ffffff;
// if this bit *and* NC_BGDEFAULT_MASK are set, we're using a
// palette-indexed background color
const int NC_BG_PALETTE = 0x0000000008000000;
// extract these bits to get the background alpha mask
const int NC_BG_ALPHA_MASK = 0x30000000;

// Foreground occupies the high 32 bits of the 64-bit channel pair.
const int NC_FGDEFAULT_MASK = 0x4000000000000000;
const int NC_FG_RGB_MASK = 0xffffff0000000000;
const int NC_FG_PALETTE = 0x0800000000000000;
const int NC_FG_ALPHA_MASK = 0x3000000000000000;

// Single 32-bit channel masks (class Channel; value is one channel).
const int _CH_DEFAULT = 0x40000000;
const int _CH_RGB = 0x00ffffff;
const int _CH_PALETTE = 0x08000000;
const int _CH_ALPHA = 0x30000000;
const int _NCPALETTESIZE = 256; // NCPALETTESIZE in notcurses.h

class RGB {
  final int r, g, b;
  const RGB(this.r, this.g, this.b);

  RGB copyWith({int? r, int? g, int? b}) {
    return RGB(
      r ?? this.r,
      g ?? this.g,
      b ?? this.b,
    );
  }

  @override
  String toString() {
    return 'RGB: $r/${r.toStrHex()} $g/${g.toStrHex()} $b/${b.toStrHex()}';
  }
}

class Channels {
  int _value;

  Channels._(this._value);

  int get value => _value;

  /// initialize a 64-bit channel pair with specified RGB fg/bg
  factory Channels.initializer(int fr, int fg, int fb, int br, int bg, int bb) {
    return Channels._((Channel.initializer(fr, fg, fb).value << 32) + (Channel.initializer(br, bg, bb).value));
  }

  /// Initialize a 64-bit channel pair but only the BG
  factory Channels.initializerBg(int br, int bg, int bb) {
    return Channels._((Channel.initializer(br, bg, bb).value));
  }

  /// Initialize a 64-bit channel pair but only the FG
  factory Channels.initializerFg(int br, int bg, int bb) {
    return Channels._((Channel.initializer(br, bg, bb).value) << 32);
  }

  factory Channels.from(int value) {
    return Channels._(value);
  }

  factory Channels.zero() {
    return Channels._(0);
  }

  /// Initialize a Channels with default FG/BG colors
  factory Channels.defaultColors() {
    return Channels._(0)
      ..setBgDefault()
      ..setFgDefault();
  }

  /// Returns a new Channels with the same values
  Channels copy() {
    return Channels._(_value);
  }

  /// Creates a new channel pair using 'fchan' as the foreground channel
  /// and 'bchan' as the background channel.
  factory Channels.combine(Channel fchan, Channel bchan) {
    return Channels._(ncInline.ncchannels_combine(fchan.value, bchan.value));
  }

  /// Extract the 32-bit background channel from a channel pair.
  int bchannel() {
    return ncInline.ncchannels_bchannel(_value);
  }

  /// Extract the 32-bit foreground channel from a channel pair.
  int fchannel() {
    return ncInline.ncchannels_fchannel(_value);
  }

  /// Set the r, g, and b channels for the foreground component of this 64-bit
  /// 'channels' variable, and mark it as not using the default color.
  bool setFgRGB8(int r, int g, int b) {
    if (r >= 256 || g >= 256 || b >= 256) return false;
    final fg = ((_value >> 32) & 0xffffffff) & ~(_CH_RGB | _CH_PALETTE) |
        _CH_DEFAULT |
        ((r << 16) | (g << 8) | b);
    _value = (fg << 32) | (_value & 0xffffffff);
    return true;
  }

  /// Set the r, g, and b channels for the background component of this 64-bit
  /// 'channels' variable, and mark it as not using the default color.
  bool setBgRGB8(int r, int g, int b) {
    if (r >= 256 || g >= 256 || b >= 256) return false;
    final bg = (_value & 0xffffffff) & ~(_CH_RGB | _CH_PALETTE) |
        _CH_DEFAULT |
        ((r << 16) | (g << 8) | b);
    _value = (_value & ~0xffffffff) | bg;
    return true;
  }

  /// Set an assembled 24 bit channel at once.
  bool setFgRGB(int rgb) {
    if (rgb > 0xffffff) return false;
    final fg = ((_value >> 32) & 0xffffffff) & ~(_CH_RGB | _CH_PALETTE) |
        _CH_DEFAULT |
        (rgb & 0xffffff);
    _value = (fg << 32) | (_value & 0xffffffff);
    return true;
  }

  /// assembled 24-bit RGB value. A value over 0xffffff
  /// will be rejected, with a non-zero return value.
  bool setBgRGB(int rgb) {
    if (rgb > 0xffffff) return false;
    final bg = (_value & 0xffffffff) & ~(_CH_RGB | _CH_PALETTE) |
        _CH_DEFAULT |
        (rgb & 0xffffff);
    _value = (_value & ~0xffffffff) | bg;
    return true;
  }

  /// Extract 24 bits of foreground RGB from 'channels', split into subchannels.
  RGB fgRGB8() {
    return using<RGB>((Arena alloc) {
      final r = alloc<UnsignedInt>();
      final g = alloc<UnsignedInt>();
      final b = alloc<UnsignedInt>();

      ncInline.ncchannels_fg_rgb8(_value, r, g, b);
      return RGB(r.value, g.value, b.value);
    });
  }

  /// Extract 24 bits of background RGB from 'channels', split into subchannels.
  RGB bgRGB8() {
    return using<RGB>((Arena alloc) {
      final r = alloc<UnsignedInt>();
      final g = alloc<UnsignedInt>();
      final b = alloc<UnsignedInt>();
      ncInline.ncchannels_bg_rgb8(_value, r, g, b);
      return RGB(r.value, g.value, b.value);
    });
  }

  /// Extract 24 bits of foreground RGB from 'channels', shifted to LSBs.
  int fgRGB() {
    return ncInline.ncchannels_fg_rgb(_value);
  }

  /// Extract 24 bits of background RGB from 'channels', shifted to LSBs.
  int bgRGB() {
    return ncInline.ncchannels_bg_rgb(_value);
  }

  /// Estract palette index foreground color
  int fgPalindex() {
    return ncInline.ncchannels_fg_palindex(_value);
  }

  /// Estract palette index background color
  int bgPalindex() {
    return ncInline.ncchannels_bg_palindex(_value);
  }

  /// Set the cell's foreground palette index, set the foreground palette index
  /// bit, set it foreground-opaque, and clear the foreground default color bit.
  bool setFgPalindex(int ndx) {
    if (ndx >= _NCPALETTESIZE) return false;
    final fg = ((_value >> 32) & 0xffffffff) & 0xff000000 |
        _CH_DEFAULT |
        _CH_PALETTE |
        (ndx & 0xff);
    _value = (fg << 32) | (_value & 0xffffffff);
    return true;
  }

  /// Set the cell's background palette index, set the background palette index
  /// bit, set it background-opaque, and clear the background default color bit.
  bool setBgPalindex(int ndx) {
    if (ndx >= _NCPALETTESIZE) return false;
    final bg = (_value & 0xffffffff) & 0xff000000 |
        _CH_DEFAULT |
        _CH_PALETTE |
        (ndx & 0xff);
    _value = (_value & ~0xffffffff) | bg;
    return true;
  }

  /// Set the 2-bit alpha component of the foreground channel.
  bool setFgAlpha(int alpha) {
    if (alpha & ~_CH_ALPHA != 0) return false;
    var fg = ((_value >> 32) & 0xffffffff);
    fg = (alpha & 0xffffffff) | (fg & ~_CH_ALPHA);
    if (alpha != 0) fg |= _CH_DEFAULT;
    _value = (fg << 32) | (_value & 0xffffffff);
    return true;
  }

  /// Set the 2-bit alpha component of the background channel.
  bool setBgAlpha(int alpha) {
    if (alpha & ~_CH_ALPHA != 0) return false;
    var bg = (_value & 0xffffffff);
    bg = (alpha & 0xffffffff) | (bg & ~_CH_ALPHA);
    if (alpha != 0) bg |= _CH_DEFAULT;
    _value = (_value & ~0xffffffff) | bg;
    return true;
  }

  /// Extract 2 bits of foreground alpha from 'channels', shifted to LSBs.
  int fgAlpha() {
    return ncInline.ncchannels_fg_alpha(_value);
  }

  /// Extract 2 bits of background alpha from 'cl', shifted to LSBs.
  int bgAlpha() {
    return ncInline.ncchannels_bg_alpha(_value);
  }

  /// Mark the background channel as using its default color.
  void setBgDefault() {
    final bg = (_value & 0xffffffff) & ~(_CH_DEFAULT | _CH_ALPHA);
    _value = (_value & ~0xffffffff) | bg;
  }

  /// Mark the foreground channel as using its default color.
  void setFgDefault() {
    final fg = ((_value >> 32) & 0xffffffff) & ~(_CH_DEFAULT | _CH_ALPHA);
    _value = (fg << 32) | (_value & 0xffffffff);
  }

  /// Returns the channels with the fore- and background's color information
  /// swapped, but without touching housekeeping bits. Alpha is retained unless
  /// it would lead to an illegal state: HIGHCONTRAST, TRANSPARENT, and BLEND
  /// are taken to OPAQUE unless the new value is RGB.
  int reverse() {
    return ncInline.ncchannels_reverse(_value);
  }

  /// Set the alpha and coloring bits of a channel pair from another channel pair.
  void setChannels(int channel) {
    _value = (((channel >> 32) & 0xffffffff) << 32) | (channel & 0xffffffff);
  }

  /// Extract the background alpha and coloring bits from a 64-bit channel pair.
  int channels() {
    return ncInline.ncchannels_channels(_value);
  }
}

class Channel {
  int _value;
  Channel._(this._value);
  int get value => _value;

  /// initialize a 32-bit channel pair with specified RGB
  factory Channel.initializer(int r, int g, int b) {
    return Channel._((r << 16) + (g << 8) + b + NC_BGDEFAULT_MASK);
  }

  /// Extract the 8-bit red component from a 32-bit channel. Only valid if
  /// ncchannel_rgb_p() would return true for the channel.
  int get r => ncInline.ncchannel_r(_value);

  /// Extract the 8-bit green component from a 32-bit channel. Only valid if
  /// ncchannel_rgb_p() would return true for the channel.
  int get g => ncInline.ncchannel_g(_value);

  /// Extract the 8-bit blue component from a 32-bit channel. Only valid if
  /// ncchannel_rgb_p() would return true for the channel.
  int get b => ncInline.ncchannel_b(_value);

  /// Extract the 24-bit RGB value from a 32-bit channel.
  /// Only valid if ncchannel_rgb_p() would return true for the channel.
  int get rgb => ncInline.ncchannel_rgb(_value);

  /// Is this channel using the "default color" rather than RGB/palette-indexed?
  bool get isUsingDefault => ncInline.ncchannel_default_p(_value);

  /// Is this channel using palette-indexed color?
  bool get isUsingPalindex => ncInline.ncchannel_palindex_p(_value);

  /// Is this channel using RGB color?
  bool get isUsingRGB => ncInline.ncchannel_rgb_p(_value);

  /// Extract the three 8-bit R/G/B components from a 32-bit channel.
  /// Only valid if ncchannel_rgb_p() would return true for the channel.
  RGB rgb8() {
    return using<RGB>((Arena alloc) {
      final r = alloc<UnsignedInt>();
      final g = alloc<UnsignedInt>();
      final b = alloc<UnsignedInt>();
      ncInline.ncchannel_rgb8(_value, r, g, b);
      return RGB(r.value, g.value, b.value);
    });
  }

  /// Set the three 8-bit components of a 32-bit channel, and mark it as not using
  /// the default color. Retain the other bits unchanged. Any value greater than
  /// 255 will result in a return of -1 and no change to the channel.
  bool setRGB8(int r, int g, int b) {
    if (r >= 256 || g >= 256 || b >= 256) return false;
    _value = (_value & ~(_CH_RGB | _CH_PALETTE)) |
        _CH_DEFAULT |
        ((r << 16) | (g << 8) | b);
    return true;
  }

  /// Set the 32-bit rgb of a 32-bit channel, and mark it as not using
  /// the default color. Retain the other bits unchanged. Any value greater than
  /// 0xffffff will result in a return of -1 and no change to the channel.
  bool setRGB32(int rgb) {
    if (rgb > 0xffffff) return false;
    _value = (_value & ~(_CH_RGB | _CH_PALETTE)) | _CH_DEFAULT | (rgb & 0xffffff);
    return true;
  }

  /// Set the three 8-bit components of a 32-bit channel, and mark it as not using
  /// the default color. Retain the other bits unchanged. r, g, and b will be
  /// clipped to the range [0..255].
  void setRgb8Clipped(int r, int g, int b) {
    if (r >= 256) r = 255;
    if (g >= 256) g = 255;
    if (b >= 256) b = 255;
    _value = (_value & ~(_CH_RGB | _CH_PALETTE)) |
        _CH_DEFAULT |
        ((r << 16) | (g << 8) | b);
  }

  /// Extract the 2-bit alpha component from a 32-bit channel. It is not
  /// shifted down, and can be directly compared to NCALPHA_* values.
  int alpha() {
    return ncInline.ncchannel_alpha(_value);
  }

  /// Set the 2-bit alpha component of the 32-bit channel. Background channels
  /// must not be set to NCALPHA_HIGHCONTRAST. It is an error if alpha contains
  /// any bits other than NCALPHA_*.
  bool setAlpha(int alpha) {
    if (alpha & ~_CH_ALPHA != 0) return false;
    _value = (alpha & 0xffffffff) | (_value & ~_CH_ALPHA);
    if (alpha != 0) _value |= _CH_DEFAULT;
    return true;
  }

  /// Mark the channel as using its default color. Alpha is set opaque.
  void setDefault() {
    _value &= ~(_CH_DEFAULT | _CH_ALPHA);
  }

  /// Extract the palette index from a channel. Only valid if
  /// ncchannel_palindex_p() would return true for the channel.
  int palindex() {
    return ncInline.ncchannel_palindex(_value);
  }

  /// Mark the channel as using the specified palette color. It is an error if
  /// the index is greater than NCPALETTESIZE. Alpha is set opaque.
  bool setPalindex(int idx) {
    if (idx >= _NCPALETTESIZE) return false;
    _value = (_value & 0xff000000) | _CH_DEFAULT | _CH_PALETTE | (idx & 0xff);
    return true;
  }
}
