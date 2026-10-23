import 'dart:convert';
import 'dart:typed_data';

/// CAT command sets the radio link can speak over a USB serial port.
enum CatProtocol {
  /// Icom CI-V (IC-7300, IC-705, IC-7610, IC-9700, …).
  icomCiv,

  /// Xiegu G90 (and other Xiegu radios): the Icom CI-V command set with its
  /// own default address and speed.
  xieguCiv,

  /// ASCII `FA;` command set shared by Kenwood, Elecraft and current Yaesu
  /// radios (FT-991/A, FT-710, FTDX10, FTDX101, FT-891, …).
  kenwood,

  /// 5-byte binary CAT of the older Yaesu portables (FT-817/818/857/897).
  yaesuLegacy;

  /// Baud rate the radio ships with, used when the protocol is picked.
  int get defaultBaudRate => switch (this) {
        CatProtocol.icomCiv => 19200,
        CatProtocol.xieguCiv => 19200,
        CatProtocol.kenwood => 38400,
        CatProtocol.yaesuLegacy => 4800,
      };

  /// Whether the radio is addressed by a CI-V address.
  bool get usesCiv =>
      this == CatProtocol.icomCiv || this == CatProtocol.xieguCiv;

  /// CI-V address the radio ships with (IC-7300 for Icom, G90 for Xiegu).
  int get defaultCivAddress => this == CatProtocol.xieguCiv ? 0x88 : 0x94;
}

/// Operating mode as the radio reports it, reduced to what the log needs.
/// Data/packet modes (USB-D, DATA-U, PKT, …) are left out: they don't say
/// whether the operator runs FT8, FT4 or PSK, so the log keeps its own.
enum RigMode {
  lsb('SSB', 'LSB'),
  usb('SSB', 'USB'),
  cw('CW', null),
  am('AM', null),
  fm('FM', null),
  rtty('RTTY', null);

  const RigMode(this.appMode, this.appSubmode);

  /// The matching entry of kCommonModes, and its kSubmodes entry if any.
  final String appMode;
  final String? appSubmode;

  /// Whether this radio mode should replace the log's [current] mode.
  /// Digital modes (FT8, PSK31, JS8, …) are run with the radio in USB/LSB,
  /// so a sideband report never overrides them.
  bool appliesTo(String current) =>
      appMode != 'SSB' ||
      const {'SSB', 'CW', 'AM', 'FM', 'RTTY'}.contains(current);
}

/// One value decoded from the radio: a frequency in Hz or a mode.
class CatUpdate {
  final int? frequencyHz;
  final RigMode? mode;

  const CatUpdate.frequency(int hz)
      : frequencyHz = hz,
        mode = null;
  const CatUpdate.mode(RigMode this.mode) : frequencyHz = null;
}

/// Encodes the polls for one protocol and decodes the frequency and mode
/// from whatever the radio sends back. No I/O here, so it is unit-testable.
abstract class CatCodec {
  factory CatCodec(CatProtocol protocol, {int civAddress = 0x94}) =>
      switch (protocol) {
        CatProtocol.icomCiv || CatProtocol.xieguCiv => IcomCivCodec(civAddress),
        CatProtocol.kenwood => KenwoodCodec(),
        CatProtocol.yaesuLegacy => YaesuLegacyCodec(),
      };

  /// Bytes to send for the next poll; called on every poll tick.
  Uint8List nextPoll();

  /// Buffers [data] and returns every value decoded from the frames that
  /// are now complete.
  List<CatUpdate> feed(List<int> data);
}

/// Icom CI-V: `FE FE <to> <from> <cmd> [data] FD`. Polls alternate between
/// `03` (read frequency, 5-byte little-endian BCD, 6 above 10 GHz) and `04`
/// (read mode). With CI-V Transceive on the radio also broadcasts `00`
/// (frequency) and `01` (mode) unprompted when they change.
class IcomCivCodec implements CatCodec {
  static const _preamble = 0xFE;
  static const _end = 0xFD;
  static const _controller = 0xE0;
  static const _broadcast = 0x00;
  static const _cmdTransceiveFreq = 0x00;
  static const _cmdTransceiveMode = 0x01;
  static const _cmdReadFreq = 0x03;
  static const _cmdReadMode = 0x04;

  static const _modes = {
    0x00: RigMode.lsb,
    0x01: RigMode.usb,
    0x02: RigMode.am,
    0x03: RigMode.cw,
    0x04: RigMode.rtty,
    0x05: RigMode.fm,
    0x06: RigMode.fm, // WFM
    0x07: RigMode.cw, // CW-R
    0x08: RigMode.rtty, // RTTY-R
  };

  final int radioAddress;
  final _buf = <int>[];
  var _askedFreq = false;

  IcomCivCodec(this.radioAddress);

  // One command per poll: on a one-wire CI-V bus (G90, CT-17) a second
  // command sent right behind the first would collide with its reply.
  @override
  Uint8List nextPoll() {
    _askedFreq = !_askedFreq;
    final cmd = _askedFreq ? _cmdReadFreq : _cmdReadMode;
    return Uint8List.fromList(
        [_preamble, _preamble, radioAddress, _controller, cmd, _end]);
  }

  @override
  List<CatUpdate> feed(List<int> data) {
    _buf.addAll(data);
    final updates = <CatUpdate>[];
    while (true) {
      var start = _indexOfPreamble();
      if (start < 0) {
        // Keep a trailing FE — it may be the first half of the next preamble.
        final keep = _buf.isNotEmpty && _buf.last == _preamble;
        _buf.clear();
        if (keep) _buf.add(_preamble);
        break;
      }
      // Collisions on the CI-V bus can leave extra FEs before a frame.
      while (start < _buf.length && _buf[start] == _preamble) {
        start++;
      }
      final end = _buf.indexOf(_end, start);
      if (end < 0) {
        _buf.removeRange(0, start - 2);
        break;
      }
      final frame = _buf.sublist(start, end); // to, from, cmd, data…
      _buf.removeRange(0, end + 1);

      // Our own poll comes back too when CI-V USB Echo Back is on (and
      // always on a one-wire bus); it is addressed to the radio, so the
      // `from` check drops it.
      if (frame.length < 4 || frame[1] != radioAddress) continue;
      final to = frame[0], cmd = frame[2];
      final isFreq = (to == _controller && cmd == _cmdReadFreq) ||
          (to == _broadcast && cmd == _cmdTransceiveFreq);
      final isMode = (to == _controller && cmd == _cmdReadMode) ||
          (to == _broadcast && cmd == _cmdTransceiveMode);
      if (isFreq && frame.length >= 8) {
        final hz = _bcdLittleEndian(frame.sublist(3));
        if (hz != null && hz > 0) updates.add(CatUpdate.frequency(hz));
      } else if (isMode) {
        final mode = _modes[frame[3]];
        if (mode != null) updates.add(CatUpdate.mode(mode));
      }
    }
    return updates;
  }

  int _indexOfPreamble() {
    for (var i = 0; i + 1 < _buf.length; i++) {
      if (_buf[i] == _preamble && _buf[i + 1] == _preamble) return i;
    }
    return -1;
  }

  static int? _bcdLittleEndian(List<int> bytes) {
    var value = 0;
    var scale = 1;
    for (final b in bytes) {
      final hi = b >> 4, lo = b & 0x0F;
      if (hi > 9 || lo > 9) return null;
      value += (hi * 10 + lo) * scale;
      scale *= 100;
    }
    return value;
  }
}

/// Kenwood / Elecraft / Yaesu ASCII CAT: `FA;` answers `FA<digits>;` with the
/// VFO A frequency in Hz — 11 digits on Kenwood/Elecraft, 9 on Yaesu. The
/// mode query differs between the two (`MD;` → `MDn;` vs `MD0;` → `MD0n;`,
/// and `MD0;` would be a set command on a Kenwood), so the mode is only
/// asked for once the first `FA` reply's digit count tells them apart.
class KenwoodCodec implements CatCodec {
  static final _faReply = RegExp(r'^FA(\d{8,11})$');
  static final _mdReply = RegExp(r'^MD0?([0-9A-F])$');

  static const _kenwoodModes = {
    '1': RigMode.lsb,
    '2': RigMode.usb,
    '3': RigMode.cw,
    '4': RigMode.fm,
    '5': RigMode.am,
    '6': RigMode.rtty, // FSK
    '7': RigMode.cw, // CW-R
    '9': RigMode.rtty, // FSK-R
  };
  static const _yaesuModes = {
    '1': RigMode.lsb,
    '2': RigMode.usb,
    '3': RigMode.cw, // CW-U
    '4': RigMode.fm,
    '5': RigMode.am,
    '6': RigMode.rtty, // RTTY-LSB
    '7': RigMode.cw, // CW-L
    '9': RigMode.rtty, // RTTY-USB
    'B': RigMode.fm, // FM-N
    'D': RigMode.am, // AM-N
  };

  final _buf = StringBuffer();
  bool? _isYaesu;

  @override
  Uint8List nextPoll() => Uint8List.fromList(ascii.encode(switch (_isYaesu) {
        null => 'FA;',
        true => 'FA;MD0;',
        false => 'FA;MD;',
      }));

  @override
  List<CatUpdate> feed(List<int> data) {
    _buf.write(latin1.decode(data));
    final text = _buf.toString();
    final lastSep = text.lastIndexOf(';');
    if (lastSep < 0) return const [];
    _buf
      ..clear()
      ..write(text.substring(lastSep + 1));

    final updates = <CatUpdate>[];
    for (final raw in text.substring(0, lastSep).split(';')) {
      final reply = raw.trim();
      final fa = _faReply.firstMatch(reply);
      if (fa != null) {
        final digits = fa.group(1)!;
        _isYaesu ??= digits.length < 11;
        final hz = int.parse(digits);
        if (hz > 0) updates.add(CatUpdate.frequency(hz));
        continue;
      }
      final md = _mdReply.firstMatch(reply);
      final isYaesu = _isYaesu;
      if (md != null && isYaesu != null) {
        final mode = (isYaesu ? _yaesuModes : _kenwoodModes)[md.group(1)!];
        if (mode != null) updates.add(CatUpdate.mode(mode));
      }
    }
    return updates;
  }
}

/// Yaesu FT-817/818/857/897: the 5-byte command `00 00 00 00 03` answers
/// 4 bytes of big-endian BCD frequency in 10 Hz steps plus a mode byte.
/// The reply has no framing, so the buffer is reset before every poll.
class YaesuLegacyCodec implements CatCodec {
  static const _replyLength = 5;
  static const _modes = {
    0x00: RigMode.lsb,
    0x01: RigMode.usb,
    0x02: RigMode.cw,
    0x03: RigMode.cw, // CW-R
    0x04: RigMode.am,
    0x06: RigMode.fm, // WFM
    0x08: RigMode.fm,
    0x88: RigMode.fm, // FM-N
  };
  final _buf = <int>[];

  @override
  Uint8List nextPoll() {
    _buf.clear();
    return Uint8List.fromList([0, 0, 0, 0, 0x03]);
  }

  @override
  List<CatUpdate> feed(List<int> data) {
    _buf.addAll(data);
    if (_buf.length < _replyLength) return const [];
    final reply = _buf.sublist(0, _replyLength);
    _buf.clear();

    var tensOfHz = 0;
    for (final b in reply.take(4)) {
      final hi = b >> 4, lo = b & 0x0F;
      if (hi > 9 || lo > 9) return const [];
      tensOfHz = tensOfHz * 100 + hi * 10 + lo;
    }
    final mode = _modes[reply[4]];
    return [
      if (tensOfHz > 0) CatUpdate.frequency(tensOfHz * 10),
      if (mode != null) CatUpdate.mode(mode),
    ];
  }
}

/// Formats a radio frequency for the MHz text fields: Hz precision, trailing
/// zeros trimmed but never below the app's usual 3 decimals (kHz).
String formatRigFreqMhz(int hz) {
  var s = (hz / 1e6).toStringAsFixed(6);
  while (s.endsWith('0') && s.length - s.indexOf('.') > 4) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}
