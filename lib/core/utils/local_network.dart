import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Marker attached to a DioException's `error` field when a request to a
/// private/LAN host was blocked because ACCESS_LOCAL_NETWORK wasn't granted,
/// lets WavelogRemoteDatasource._mapDioException() surface a precise error
/// instead of the generic connect-timeout a blocked socket produces.
class LocalNetworkPermissionDeniedError implements Exception {
  const LocalNetworkPermissionDeniedError();
}

/// Whether [host] is plausibly a private/local-network address, i.e. one
/// Android 17+ (targetSdk 37) blocks without the ACCESS_LOCAL_NETWORK
/// runtime permission. Deliberately cheap and DNS-free (this runs on every
/// request's hot path): does not resolve hostnames, just classifies IP
/// literals and a couple of hostname conventions that can only ever be
/// local.
///
/// IPv4 ranges are exactly Android's own documented "local network"
/// definition (developer.android.com/privacy-and-security/local-network-permission):
/// 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 (link-local),
/// 100.64.0.0/10 (CGNAT). Loopback (127.0.0.0/8) is deliberately excluded,
/// it's not in Android's own list.
///
/// IPv6 handling is best-effort only (link-local fe80::/10, ULA fc00::/7),
/// Android's own documentation hedges this part as "(TBD)".
bool isLikelyLocalNetworkHost(String host) {
  final addr = InternetAddress.tryParse(host);
  if (addr != null) {
    if (addr.type == InternetAddressType.IPv4) {
      return _isLocalIPv4(addr.rawAddress);
    }
    if (addr.type == InternetAddressType.IPv6) {
      return _isLocalIPv6(addr.rawAddress);
    }
    return false;
  }

  // Not an IP literal, apply the two DNS-free heuristics that can only ever
  // be local: mDNS's reserved ".local" suffix, or a bare hostname with no
  // dot at all (can't be a real public FQDN). A normal-looking dotted
  // hostname might still resolve to a LAN address, but telling that apart
  // from a public domain needs a DNS lookup, out of scope here.
  final h = host.toLowerCase();
  return h.endsWith('.local') || !h.contains('.');
}

bool _isLocalIPv4(List<int> b) {
  if (b.length != 4) return false;
  if (b[0] == 10) return true; // 10.0.0.0/8
  if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true; // 172.16.0.0/12
  if (b[0] == 192 && b[1] == 168) return true; // 192.168.0.0/16
  if (b[0] == 169 && b[1] == 254) return true; // 169.254.0.0/16
  if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true; // 100.64.0.0/10
  return false;
}

bool _isLocalIPv6(List<int> b) {
  if (b.length != 16) return false;
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return true; // fe80::/10
  if ((b[0] & 0xfe) == 0xfc) return true; // fc00::/7 (ULA)
  return false;
}

int? _androidSdkIntCache;
bool _androidSdkIntChecked = false;

/// Cached `Build.VERSION.SDK_INT`, null on non-Android platforms or if the
/// query fails. Cached because [ensureLocalNetworkPermission] runs on every
/// local-network request's hot path.
Future<int?> _androidSdkInt() async {
  if (_androidSdkIntChecked) return _androidSdkIntCache;
  _androidSdkIntChecked = true;
  if (!Platform.isAndroid) return null;
  try {
    _androidSdkIntCache =
        (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  } catch (_) {
    _androidSdkIntCache = null;
  }
  return _androidSdkIntCache;
}

/// Ensures [Permission.accessLocalNetwork] is granted, requesting it if
/// needed. Fails open (returns true) on any unexpected plugin/platform
/// error, so a hiccup in the permission check can't make connectivity any
/// worse than the silent block this is fixing in the first place.
///
/// `ACCESS_LOCAL_NETWORK` only exists starting Android 17 (API 37); on
/// older OS versions declaring/checking it is documented as a no-op. In
/// practice `permission_handler`'s status check doesn't reliably mirror
/// that "no-op" on every OEM build, it can resolve as permanently denied
/// instead, which broke local network access entirely on a real Android 13
/// device (regression reported after this permission check first shipped).
/// Skip the check below API 37 rather than trust the plugin there.
Future<bool> ensureLocalNetworkPermission() async {
  try {
    if (Platform.isAndroid) {
      final sdkInt = await _androidSdkInt();
      if (sdkInt != null && sdkInt < 37) return true;
    }
    var status = await Permission.accessLocalNetwork.status;
    if (!status.isGranted) {
      status = await Permission.accessLocalNetwork.request();
    }
    return status.isGranted;
  } catch (_) {
    return true;
  }
}
