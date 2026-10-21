import 'dart:io';

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

/// Ensures [Permission.accessLocalNetwork] is granted, requesting it if
/// needed. Fails open (returns true) on any unexpected plugin/platform
/// error, so a hiccup in the permission check can't make connectivity any
/// worse than the silent block this is fixing in the first place. On
/// Android versions below 17 (API 37) where this permission doesn't apply,
/// permission_handler's own status check already resolves as granted, no
/// separate SDK-version check is done here.
Future<bool> ensureLocalNetworkPermission() async {
  try {
    var status = await Permission.accessLocalNetwork.status;
    if (!status.isGranted) {
      status = await Permission.accessLocalNetwork.request();
    }
    return status.isGranted;
  } catch (_) {
    return true;
  }
}
