import 'package:flutter/material.dart';

import 'new_order_screen.dart';

/// Call from your existing foreground order listener or notification-tap flow.
/// Before calling, refresh the offer from the server and deduplicate by id.
/// The caller owns navigation to the pickup screen after an accepted result.
Future<OfferOutcome?> showRiderOrderOffer(
  BuildContext context, {
  required RiderOrderOffer offer,
  required Widget map,
  required Future<OfferActionResult> Function() onAccept,
  required Future<OfferActionResult> Function() onDecline,
  DateTime Function()? now,
  Color accentColor = const Color(0xFFFF3509),
}) =>
    Navigator.of(context).push<OfferOutcome>(
      MaterialPageRoute<OfferOutcome>(
        builder: (routeContext) => NewOrderScreen(
          key: ValueKey(offer.id),
          offer: offer,
          map: map,
          now: now,
          accentColor: accentColor,
          onAccept: onAccept,
          onDecline: onDecline,
          onResolved: (outcome) => Navigator.of(routeContext).pop(outcome),
        ),
      ),
    );
