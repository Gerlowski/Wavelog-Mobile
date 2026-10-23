import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/rig/cat_protocol.dart';
import '../core/services/rig_serial_service.dart';
import '../data/datasources/local/settings_local_datasource.dart';
import '../data/models/rig_config_model.dart';
import 'settings_provider.dart';

enum RigStatus { disconnected, connecting, connected }

class RigState {
  final RigConfig config;
  final RigStatus status;
  final RigUsbDevice? device;

  /// Last frequency the radio reported, in Hz. Null until the first reply.
  final int? frequencyHz;

  /// Platform error code of the last failed connection or lost link
  /// (`PERMISSION_DENIED`, `DETACHED`, …), cleared on the next connect.
  final String? errorCode;

  const RigState({
    this.config = const RigConfig(),
    this.status = RigStatus.disconnected,
    this.device,
    this.frequencyHz,
    this.errorCode,
  });
}

/// App-wide radio link: stays connected while the user moves between
/// screens, so every QSO form can follow the radio's dial.
final rigProvider = StateNotifierProvider<RigNotifier, RigState>((ref) {
  return RigNotifier(RigSerialService(), ref.watch(settingsLocalDatasourceProvider));
});

class RigNotifier extends StateNotifier<RigState> {
  static const _pollInterval = Duration(milliseconds: 500);

  final RigSerialService _serial;
  final SettingsLocalDatasource _settings;

  StreamSubscription<Uint8List>? _dataSub;
  Timer? _pollTimer;
  CatCodec? _codec;

  RigNotifier(this._serial, this._settings) : super(const RigState()) {
    _settings.getRigConfig().then((config) {
      if (mounted) state = RigState(config: config);
    });
  }

  /// Changing protocol or baud rate drops the link; reconnect to apply.
  Future<void> setConfig(RigConfig config) async {
    if (state.status != RigStatus.disconnected) await disconnect();
    state = RigState(config: config);
    await _settings.saveRigConfig(config);
  }

  Future<List<RigUsbDevice>> listDevices() => _serial.listDevices();

  Future<void> connect(RigUsbDevice device) async {
    await disconnect();
    final config = state.config;
    state = RigState(config: config, status: RigStatus.connecting, device: device);
    try {
      await _serial.open(device, baudRate: config.baudRate);
    } on PlatformException catch (e) {
      if (mounted) state = RigState(config: config, errorCode: e.code);
      return;
    }
    final codec = CatCodec(config.protocol, civAddress: config.civAddress);
    _codec = codec;
    _dataSub = _serial.data.listen(
      (bytes) {
        final freqs = codec.feed(bytes);
        if (freqs.isNotEmpty && freqs.last != state.frequencyHz) {
          state = RigState(
            config: config,
            status: RigStatus.connected,
            device: device,
            frequencyHz: freqs.last,
          );
        }
      },
      onError: (Object e) => _lost(e is PlatformException ? e.code : 'IO_ERROR'),
    );
    state = RigState(config: config, status: RigStatus.connected, device: device);
    _poll();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> disconnect() async {
    _stop();
    state = RigState(config: state.config);
    await _serial.close();
  }

  void _poll() {
    final codec = _codec;
    if (codec == null) return;
    codec.beforePoll();
    _serial.write(codec.pollCommand).catchError((Object e) {
      _lost(e is PlatformException ? e.code : 'IO_ERROR');
    });
  }

  void _lost(String code) {
    _stop();
    if (mounted) state = RigState(config: state.config, errorCode: code);
  }

  void _stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _dataSub?.cancel();
    _dataSub = null;
    _codec = null;
  }

  @override
  void dispose() {
    _stop();
    _serial.close();
    super.dispose();
  }
}
