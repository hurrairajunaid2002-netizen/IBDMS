import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Cross-platform GPS helper for flutter_map viewports (mobile + web).
class MapLocationService {
  MapLocationService._();

  static const defaultLocation = LatLng(24.8607, 67.0011);

  /// Premium fly-in camera defaults for the GPS crosshair recenter action.
  static const double flyInZoom = 16.5;
  static const Duration flyInDuration = Duration(milliseconds: 1350);
  static const Curve flyInCurve = Curves.easeInOutCubic;

  /// Requests permission and returns high-accuracy coordinates, or null on denial.
  static Future<({LatLng location, String? message})> fetchMyLocation({
    bool highAccuracy = true,
  }) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission().timeout(
          const Duration(seconds: 8),
          onTimeout: () => LocationPermission.denied,
        );
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return (
          location: defaultLocation,
          message:
              'Location permission blocked. Enable GPS in browser or device settings.',
        );
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy:
            highAccuracy ? LocationAccuracy.best : LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 15));

      return (location: LatLng(pos.latitude, pos.longitude), message: null);
    } catch (_) {
      return (
        location: defaultLocation,
        message: 'GPS unavailable — showing default map region.',
      );
    }
  }

  /// Smooth, premium "fly-in" camera glide — swoops from city view down to
  /// block-level detail without an instant snap.
  static Future<void> animateMapTo(
    MapController controller, {
    required LatLng target,
    double zoom = flyInZoom,
    Duration duration = flyInDuration,
    Curve curve = flyInCurve,
  }) async {
    if (!controller.camera.center.latitude.isFinite) {
      controller.move(target, zoom);
      return;
    }

    final start = controller.camera.center;
    final startZoom = controller.camera.zoom;
    final completer = Completer<void>();
    final startTime = DateTime.now().millisecondsSinceEpoch;

    void tick(Duration _) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - startTime;
      final rawT = (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);
      final t = curve.transform(rawT);

      final lat = start.latitude + (target.latitude - start.latitude) * t;
      final lng = start.longitude + (target.longitude - start.longitude) * t;
      final z = startZoom + (zoom - startZoom) * t;
      controller.move(LatLng(lat, lng), z);

      if (rawT >= 1.0) {
        controller.move(target, zoom);
        if (!completer.isCompleted) completer.complete();
        return;
      }
      SchedulerBinding.instance.scheduleFrameCallback(tick);
    }

    SchedulerBinding.instance.scheduleFrameCallback(tick);
    return completer.future;
  }

  /// GPS crosshair action — high-accuracy fix + premium fly-in zoom.
  static Future<void> flyToMyLocation(
    MapController controller, {
    required LatLng target,
  }) =>
      animateMapTo(
        controller,
        target: target,
        zoom: flyInZoom,
        duration: flyInDuration,
        curve: flyInCurve,
      );
}
