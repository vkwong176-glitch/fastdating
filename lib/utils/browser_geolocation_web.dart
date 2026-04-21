// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class BrowserGeolocationResult {
  const BrowserGeolocationResult({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

Future<BrowserGeolocationResult?> getBrowserGeolocation({
  Duration timeout = const Duration(seconds: 12),
}) async {
  final completer = Completer<BrowserGeolocationResult?>();
  try {
    html.window.navigator.geolocation
        .getCurrentPosition(
      enableHighAccuracy: true,
      timeout: timeout,
      /// 避免每次重新整理都強制新定位而反覆觸發瀏覽器／系統定位詢問。
      maximumAge: const Duration(minutes: 5),
    )
        .then((pos) {
      if (completer.isCompleted) return;
      final coords = pos.coords;
      final lat = coords?.latitude;
      final lng = coords?.longitude;
      if (lat == null || lng == null) {
        completer.complete(null);
        return;
      }
      completer.complete(
        BrowserGeolocationResult(
          latitude: lat.toDouble(),
          longitude: lng.toDouble(),
        ),
      );
    }).catchError((_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });
  } catch (_) {
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  }
  return completer.future.timeout(timeout, onTimeout: () => null);
}
