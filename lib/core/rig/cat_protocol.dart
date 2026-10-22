import 'dart:convert';
import 'dart:typed_data';

/// CAT command sets the radio link can speak over a USB serial port.
enum CatProtocol {
  /// Icom CI-V (IC-7300, IC-705, IC-7610, IC-9700, …).
  icomCiv,

  /// ASCII `FA;` command set shared by Kenwood, Elecraft and current Yaesu
  /// radios (FT-991/A, FT-710, FTDX10, FTDX101, FT-891, …).
  kenwood,

  /// 5-byte binary CAT of the older Yaesu portables (FT-817/818/857/897).
  yaesuLegacy;

  /// Baud rate the radio ships with, used when the protocol is picked.
  int get defaultBaudRate => switch (this) {
        CatProtocol.icomCiv => 19200,
        CatProtocol.kenwood => 38400,
        CatProtocol.yaesuLegacy => 4800,
      };
}

/// Encodes the frequency poll for one protocol and decodes frequencies from
/// whatever the radio sends back. No I/O here, so it is unit-testable.
abstract class CatCodec {
  factory CatCodec(CatProtocol protocol, {int civAddress = 0x94}) =>
      switch (protocol) {
        CatProtocol.icomCiv => IcomCivCodec(civAddress),
        CatProtocol.kenwood => KenwoodCodec(),
        CatProtocol.yaesuLegacy => YaesuLegacyCodec(),
      };

  /// Bytes that ask the radio for its current (VFO A / main) frequency.
  Uint8List get pollCommand;

  /// Buffers [data] and returns every frequency, in Hz, decoded from the
  /// frames that are now complete.
  List<int> feed(List<int> data);

  /// Called right before each poll. Protocols without framing drop leftover
  /// bytes here so a lost byte can't misalign every reply that follows.
  void beforePoll();
}

/// Icom CI-V: `FE FE <to> <from> <cmd> [data] FD`. Answers to our `03`
/// (read frequency) poll and `00` transceive broadcasts, sent unprompted
/// when the dial moves with CI-V Transceive on, carry the same 5-byte
/// (6 above 10 GHz) little-endian BCD frequency.
class IcomCivCodec implements CatCodec {
  static const _preamble = 0xFE;
  static const _end = 0xFD;
  static const _controller = 0xE0;
  static const _broadcast = 0x00;
  static const _cmdTransceiveFreq = 0x00;
  static const _cmdReadFreq = 0x03;

  final int radioAddress;
  final _buf = <int>[];

  IcomCivCodec(this.radioAddress);

  @override
  Uint8List get pollCommand => Uint8List.fromList(
      [_preamble, _preamble, radioAddress, _controller, _cmdReadFreq, _end]);

  @override
  List<int> feed(List<int> data) {
    _buf.addAll(data);
    final freqs = <int>[];
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

      // Our own poll comes back too when CI-V USB Echo Back is on; it is
      // addressed to the radio, so the `from` check drops it.
      if (frame.length < 8 || frame[1] != radioAddress) continue;
      final isReply = frame[0] == _controller && frame[2] == _cmdReadFreq;
      final isBroadcast =
          frame[0] == _broadcast && frame[2] == _cmdTransceiveFreq;
      if (!isReply && !isBroadcast) continue;
      final hz = _bcdLittleEndian(frame.sublist(3));
      if (hz != null && hz > 0) freqs.add(hz);
    }
    return freqs;
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

  @override
  void beforePoll() {}
}

/// Kenwood / Elecraft / Yaesu ASCII CAT: `FA;` answers `FA<digits>;` with the
/// VFO A frequency in Hz (11 digits on Kenwood/Elecraft, 9 on Yaesu).
class KenwoodCodec implements CatCodec {
  static final _faReply = RegExp(r'^FA(\d{8,11})$');
  final _buf = StringBuffer();

  @override
  Uint8List get pollCommand => Uint8List.fromList(ascii.encode('FA;'));

  @override
  List<int> feed(List<int> data) {
    _buf.write(latin1.decode(data));
    final text = _buf.toString();
    final lastSep = text.lastIndexOf(';');
    if (lastSep < 0) return const [];
    _buf
      ..clear()
      ..write(text.substring(lastSep + 1));

    final freqs = <int>[];
    for (final reply in text.substring(0, lastSep).split(';')) {
      final m = _faReply.firstMatch(reply.trim());
      final hz = m != null ? int.parse(m.group(1)!) : 0;
      if (hz > 0) freqs.add(hz);
    }
    return freqs;
  }

  @override
  void beforePoll() {}
}

/// Yaesu FT-817/818/857/897: the 5-byte command `00 00 00 00 03` answers
/// 4 bytes of big-endian BCD frequency in 10 Hz steps plus a mode byte.
/// The reply has no framing, so the buffer is reset before every poll.
class YaesuLegacyCodec implements CatCodec {
  static const _replyLength = 5;
  final _buf = <int>[];

  @override
  Uint8List get pollCommand => Uint8List.fromList([0, 0, 0, 0, 0x03]);

  @override
  void beforePoll() => _buf.clear();

  @override
  List<int> feed(List<int> data) {
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
    return tensOfHz > 0 ? [tensOfHz * 10] : const [];
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
