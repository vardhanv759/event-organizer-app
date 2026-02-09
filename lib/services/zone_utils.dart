import 'dart:math';

class ZoneUtils {
  static const double wembleyLat = 51.5560;
  static const double wembleyLng = -0.2796;
  static const double radiusMiles = 3.0;

  static double _degToRad(double deg) => deg * pi / 180.0;
  static double _radToDeg(double rad) => rad * 180.0 / pi;

  // Haversine distance in miles
  static double distanceMiles(double lat, double lng) {
    const earthRadiusMiles = 3958.8;
    final dLat = _degToRad(lat - wembleyLat);
    final dLng = _degToRad(lng - wembleyLng);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(wembleyLat)) *
            cos(_degToRad(lat)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMiles * c;
  }

  // Bearing in degrees [0..360)
  static double bearingDeg(double lat, double lng) {
    final lat1 = _degToRad(wembleyLat);
    final lat2 = _degToRad(lat);
    final dLng = _degToRad(lng - wembleyLng);

    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);

    var brng = _radToDeg(atan2(y, x));
    brng = (brng + 360) % 360;
    return brng;
  }

  /// Returns zoneId if within 3 miles, else null.
  /// Zones:
  /// 0-90: NE, 90-180: SE, 180-270: SW, 270-360: NW
  static String? zoneIdFor(double lat, double lng) {
    final dist = distanceMiles(lat, lng);
    if (dist > radiusMiles) return null;

    final b = bearingDeg(lat, lng);

    if (b >= 0 && b < 90) return 'wembley_ne';
    if (b >= 90 && b < 180) return 'wembley_se';
    if (b >= 180 && b < 270) return 'wembley_sw';
    return 'wembley_nw';
  }
}
