import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../utils/map_location_service.dart';

const _red = Color(0xFFDC2626);

/// Floating crosshair button — recenters the map on the user's GPS fix with
/// a premium animated fly-in zoom.
class MyLocationFab extends StatefulWidget {
  final MapController mapController;
  final bool mapReady;
  final void Function(String? banner)? onLocationResolved;
  final ValueChanged<LatLng>? onLocationUpdated;

  const MyLocationFab({
    super.key,
    required this.mapController,
    required this.mapReady,
    this.onLocationResolved,
    this.onLocationUpdated,
  });

  @override
  State<MyLocationFab> createState() => _MyLocationFabState();
}

class _MyLocationFabState extends State<MyLocationFab>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    if (_busy) return;
    setState(() => _busy = true);
    _spinCtrl.repeat();

    try {
      final result =
          await MapLocationService.fetchMyLocation(highAccuracy: true);

      if (!mounted) return;

      widget.onLocationUpdated?.call(result.location);
      widget.onLocationResolved?.call(result.message);

      if (widget.mapReady) {
        await MapLocationService.flyToMyLocation(
          widget.mapController,
          target: result.location,
        );
      }
    } finally {
      _spinCtrl.stop();
      _spinCtrl.reset();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: InkWell(
        onTap: _busy ? null : _goToMyLocation,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: _busy
              ? RotationTransition(
                  turns: _spinCtrl,
                  child: const Icon(
                    Icons.my_location,
                    color: _red,
                    size: 24,
                  ),
                )
              : const Icon(Icons.my_location, color: _red, size: 24),
        ),
      ),
    );
  }
}
