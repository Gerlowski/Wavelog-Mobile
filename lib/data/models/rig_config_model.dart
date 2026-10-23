import '../../core/rig/cat_protocol.dart';

/// How to talk to the radio's CAT port; persisted by SettingsLocalDatasource.
class RigConfig {
  final CatProtocol protocol;
  final int baudRate;

  /// Icom CI-V address of the radio (0x94 = IC-7300 default).
  final int civAddress;

  const RigConfig({
    this.protocol = CatProtocol.icomCiv,
    this.baudRate = 19200,
    this.civAddress = 0x94,
  });

  RigConfig copyWith({CatProtocol? protocol, int? baudRate, int? civAddress}) =>
      RigConfig(
        protocol: protocol ?? this.protocol,
        baudRate: baudRate ?? this.baudRate,
        civAddress: civAddress ?? this.civAddress,
      );
}
