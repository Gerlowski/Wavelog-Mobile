import 'package:flutter/services.dart';

/// A USB serial adapter (or a radio's built-in USB-serial bridge) seen by
/// Android's USB host stack.
class RigUsbDevice {
  final int deviceId;
  final String name;
  final String driver;

  const RigUsbDevice({
    required this.deviceId,
    required this.name,
    required this.driver,
  });
}

/// Thin wrapper over the native USB serial channel, see RigSerialPlugin.kt.
/// One port is open at a time; incoming bytes arrive on [data].
class RigSerialService {
  static const _ch = MethodChannel('com.wavelog_mobile/rig_serial');
  static const _events = EventChannel('com.wavelog_mobile/rig_serial/data');

  Future<List<RigUsbDevice>> listDevices() async {
    final list = await _ch.invokeListMethod<Map>('listDevices') ?? const [];
    return [
      for (final d in list)
        RigUsbDevice(
          deviceId: d['deviceId'] as int,
          name: d['name'] as String,
          driver: d['driver'] as String,
        ),
    ];
  }

  /// Opens the device at [baudRate], 8N2. Asks the user for USB permission
  /// first when Android hasn't granted it yet.
  Future<void> open(RigUsbDevice device, {required int baudRate}) =>
      _ch.invokeMethod<void>('open', {
        'deviceId': device.deviceId,
        'baudRate': baudRate,
      });

  Future<void> write(Uint8List bytes) =>
      _ch.invokeMethod<void>('write', bytes);

  Future<void> close() => _ch.invokeMethod<void>('close');

  /// Bytes read from the open port. Errors with code `DETACHED` when the
  /// cable is pulled and `IO_ERROR` when reading fails.
  Stream<Uint8List> get data =>
      _events.receiveBroadcastStream().map((e) => e as Uint8List);
}
