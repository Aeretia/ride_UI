// Optional: run `flutter pub add google_maps_flutter` before importing this file.
// Keep integrations/ beside lib/, or update the import below if moving it.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../lib/order_map_art.dart';

/// A real map using caller-provided positions and road-route coordinates.
/// This displays routes; it does not calculate them or acquire GPS permission.
/// Supply a new routePoints list when your server returns a new route.
class GoogleOrderMap extends StatefulWidget {
  const GoogleOrderMap({
    super.key,
    required this.pickup,
    required this.dropoff,
    required this.rider,
    required this.routePoints,
  });

  final LatLng pickup;
  final LatLng dropoff;
  final LatLng rider;
  /// Actual road geometry from rider -> pickup -> customer, from your server.
  /// An empty list intentionally draws no route instead of inventing one.
  final List<LatLng> routePoints;

  @override
  State<GoogleOrderMap> createState() => _GoogleOrderMapState();
}

class _GoogleOrderMapState extends State<GoogleOrderMap> {
  GoogleMapController? _controller;
  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _dropoffIcon;
  BitmapDescriptor? _riderIcon;

  @override
  void initState() {
    super.initState();
    unawaited(_createIcons());
  }

  Future<BitmapDescriptor> _pin(OrderPinKind kind) async {
    const logicalSize = Size(44, 62);
    const ratio = 3.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    paintOrderPin(canvas, logicalSize, kind);
    final picture = recorder.endRecording();
    final image = await picture.toImage(132, 186);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes == null) throw StateError('Could not render map pin');
    return BitmapDescriptor.bytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      imagePixelRatio: ratio,
      width: logicalSize.width,
      height: logicalSize.height,
    );
  }

  Future<BitmapDescriptor> _dot() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(3);
    canvas.drawCircle(const Offset(14, 14), 13, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(14, 14), 9, Paint()..color = const Color(0xFF008BFF));
    final picture = recorder.endRecording();
    final image = await picture.toImage(84, 84);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes == null) throw StateError('Could not render rider marker');
    return BitmapDescriptor.bytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      imagePixelRatio: 3,
      width: 28,
      height: 28,
    );
  }

  Future<void> _createIcons() async {
    try {
      final icons = await Future.wait([
        _pin(OrderPinKind.pickup),
        _pin(OrderPinKind.dropoff),
        _dot(),
      ]);
      if (!mounted) return;
      setState(() {
        _pickupIcon = icons[0];
        _dropoffIcon = icons[1];
        _riderIcon = icons[2];
      });
    } catch (error) {
      // Default markers still identify all three locations if art fails.
      debugPrint('Could not create order map icons: $error');
    }
  }

  List<LatLng> get _allPoints => [widget.pickup, widget.dropoff, widget.rider, ...widget.routePoints];

  @override
  void didUpdateWidget(covariant GoogleOrderMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickup != widget.pickup ||
        oldWidget.dropoff != widget.dropoff ||
        !listEquals(oldWidget.routePoints, widget.routePoints)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_fitRoute());
      });
    }
    // Rider-only updates move its marker without repeatedly moving the camera.
  }

  Future<void> _fitRoute() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final points = _allPoints;
    final south = points.map((p) => p.latitude).reduce(math.min);
    final north = points.map((p) => p.latitude).reduce(math.max);
    final west = points.map((p) => p.longitude).reduce(math.min);
    final east = points.map((p) => p.longitude).reduce(math.max);
    // Small padding also makes coincident coordinates into nonempty bounds.
    // This adapter targets local deliveries that do not cross the dateline.
    final bounds = LatLngBounds(
      southwest: LatLng((south - 0.0003).clamp(-90.0, 90.0).toDouble(), (west - 0.0003).clamp(-180.0, 180.0).toDouble()),
      northeast: LatLng((north + 0.0003).clamp(-90.0, 90.0).toDouble(), (east + 0.0003).clamp(-180.0, 180.0).toDouble()),
    );
    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 46));
    } catch (error) {
      if (mounted) debugPrint('Could not fit order route: $error');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GoogleMap(
    initialCameraPosition: CameraPosition(target: widget.pickup, zoom: 13.5),
    onMapCreated: (controller) {
      _controller = controller;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_fitRoute());
      });
    },
    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 64, bottom: 8),
    zoomControlsEnabled: false,
    myLocationButtonEnabled: false,
    myLocationEnabled: false,
    mapToolbarEnabled: false,
    compassEnabled: false,
    tiltGesturesEnabled: false,
    rotateGesturesEnabled: false,
    markers: {
      Marker(
        markerId: const MarkerId('pickup'),
        position: widget.pickup,
        icon: _pickupIcon ?? BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 1),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ),
      Marker(
        markerId: const MarkerId('dropoff'),
        position: widget.dropoff,
        icon: _dropoffIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        anchor: const Offset(0.5, 1),
        infoWindow: const InfoWindow(title: 'Delivery'),
      ),
      Marker(
        markerId: const MarkerId('rider'),
        position: widget.rider,
        icon: _riderIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: _riderIcon == null ? const Offset(0.5, 1) : const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: 'You'),
      ),
    },
    polylines: {
      if (widget.routePoints.length >= 2)
        Polyline(
          polylineId: const PolylineId('delivery-route'),
          points: widget.routePoints,
          color: const Color(0xFF202020),
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
    },
  );
}
