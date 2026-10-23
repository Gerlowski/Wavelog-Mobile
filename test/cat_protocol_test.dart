import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavelog_mobile/core/rig/cat_protocol.dart';

void main() {
  group('IcomCivCodec', () {
    // 14.074.000 Hz → BCD little-endian 00 40 07 14 00
    const freq = [0x00, 0x40, 0x07, 0x14, 0x00];

    test('poll command addresses the radio', () {
      expect(IcomCivCodec(0x94).pollCommand,
          [0xFE, 0xFE, 0x94, 0xE0, 0x03, 0xFD]);
    });

    test('decodes a read-frequency reply', () {
      final codec = IcomCivCodec(0x94);
      expect(codec.feed([0xFE, 0xFE, 0xE0, 0x94, 0x03, ...freq, 0xFD]),
          [14074000]);
    });

    test('decodes a transceive broadcast', () {
      final codec = IcomCivCodec(0xA4);
      // 7.155.120 Hz
      expect(
          codec.feed([0xFE, 0xFE, 0x00, 0xA4, 0x00, 0x20, 0x51, 0x15, 0x07, 0x00, 0xFD]),
          [7155120]);
    });

    test('ignores the echo of our own poll and other radios', () {
      final codec = IcomCivCodec(0x94);
      expect(codec.feed([0xFE, 0xFE, 0x94, 0xE0, 0x03, 0xFD]), isEmpty);
      expect(codec.feed([0xFE, 0xFE, 0xE0, 0x98, 0x03, ...freq, 0xFD]), isEmpty);
    });

    test('Xiegu G90: one-wire CI-V echo, then the reply from 0x88', () {
      expect(CatProtocol.xieguCiv.defaultCivAddress, 0x88);
      final codec = CatCodec(CatProtocol.xieguCiv,
          civAddress: CatProtocol.xieguCiv.defaultCivAddress);
      expect(codec.pollCommand, [0xFE, 0xFE, 0x88, 0xE0, 0x03, 0xFD]);
      expect(
          codec.feed([
            0xFE, 0xFE, 0x88, 0xE0, 0x03, 0xFD, // our poll echoed back
            0xFE, 0xFE, 0xE0, 0x88, 0x03, ...freq, 0xFD,
          ]),
          [14074000]);
    });

    test('reassembles a frame split across reads, with leading noise', () {
      final codec = IcomCivCodec(0x94);
      expect(codec.feed([0x12, 0xFE]), isEmpty);
      expect(codec.feed([0xFE, 0xFE, 0xE0, 0x94, 0x03, 0x00, 0x40]), isEmpty);
      expect(codec.feed([0x07, 0x14, 0x00, 0xFD]), [14074000]);
    });
  });

  group('KenwoodCodec', () {
    test('decodes Kenwood 11-digit and Yaesu 9-digit replies', () {
      final codec = KenwoodCodec();
      expect(codec.pollCommand, ascii.encode('FA;'));
      expect(codec.feed(ascii.encode('FA00014074000;')), [14074000]);
      expect(codec.feed(ascii.encode('FA007074000;')), [7074000]);
    });

    test('reassembles split replies and skips unrelated ones', () {
      final codec = KenwoodCodec();
      expect(codec.feed(ascii.encode('?;MD02;FA0002')), isEmpty);
      expect(codec.feed(ascii.encode('8074000;FA00028075000;')),
          [28074000, 28075000]);
    });
  });

  group('YaesuLegacyCodec', () {
    test('decodes the 5-byte reply in 10 Hz steps', () {
      final codec = YaesuLegacyCodec();
      expect(codec.pollCommand, [0, 0, 0, 0, 0x03]);
      codec.beforePoll();
      expect(codec.feed([0x01, 0x40]), isEmpty);
      expect(codec.feed([0x74, 0x50, 0x01]), [14074500]);
    });

    test('beforePoll drops a partial reply', () {
      final codec = YaesuLegacyCodec();
      codec.feed([0x99]);
      codec.beforePoll();
      expect(codec.feed([0x00, 0x70, 0x74, 0x00, 0x0C]), [7074000]);
    });
  });

  test('formatRigFreqMhz keeps Hz precision, at least kHz', () {
    expect(formatRigFreqMhz(14074000), '14.074');
    expect(formatRigFreqMhz(14285500), '14.2855');
    expect(formatRigFreqMhz(7155123), '7.155123');
  });
}
