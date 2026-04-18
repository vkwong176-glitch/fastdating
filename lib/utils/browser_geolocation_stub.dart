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
  return null;
}
