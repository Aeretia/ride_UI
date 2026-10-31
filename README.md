# Rider new-order screen — Flutter source

This recreates the **left, single-order screen** from your reference: a map above a white offer panel, a floating Decline pill, delivery time, restaurant name, item count, distance, circular countdown, large earnings total, a two-column pay breakdown, and a red-orange Accept button.

The screen is made from editable Flutter widgets. It is not a screenshot placed over the app. The demo preserves the reference wording and dollar amounts. A second sample uses TZS and kilometres. The OS supplies its own status bar, notch, and navigation indicator.

**Visual limitation:** the bundled map is an original illustrated stand-in. The optional Google Maps adapter supplies real tiles, route geometry, and markers after configuration. It will not reproduce the reference's Apple Maps tiles exactly. Font metrics and spacing can also vary by platform; a pixel-for-pixel match has not been verified.

## Files

| File | Purpose |
| --- | --- |
| `lib/new_order_screen.dart` | Reusable order model, countdown, layout, action handling |
| `lib/show_order_offer.dart` | Helper that presents the screen and returns the outcome |
| `lib/order_map_art.dart` | Offline demo map and shared vector pin artwork |
| `lib/main.dart` | Standalone reference demo, with an optional TZS example |
| `integrations/google_order_map.dart` | Optional live Google Maps widget |
| `test/new_order_screen_test.dart` | Deadline, action, retry, disposal, and small-screen tests |

## Run the demo

The archive contains source files, not generated Android/iOS build folders.

1. Install Flutter in your usual development environment, then create a scaffold:

   ```bash
   flutter create --empty --project-name rider_order_ui rider_order_demo
   ```

2. Copy this archive's `lib`, `test`, `integrations`, `pubspec.yaml`, and `analysis_options.yaml` into `rider_order_demo`. Replace the scaffold's `lib/main.dart`. Keep its platform folders.

3. Open that folder in VS Code and run:

   ```bash
   flutter pub get
   dart format lib test
   flutter analyze
   flutter test
   flutter run
   ```

The offline demo has no third-party dependencies or API keys. It starts at 21 seconds, as shown in the reference; its original response window is 45 seconds. Accept and Decline simulate a response and show a demo result. The result page can replay the reference or show an illustrative TZS version. No real order is created, accepted, or declined.

## Add it to your existing rider app

Copy `new_order_screen.dart` and `show_order_offer.dart` into the same directory in your app. Keep your own `main.dart`, state management, routing setup, notification service, and map implementation. Copy `order_map_art.dart` only if using the demo or the included Google adapter.

Import the two screen files, then call the helper after receiving and validating a new order:

```dart
// `offer` is a RiderOrderOffer built from your refreshed server response.
// `yourExistingMap` is a bounded map widget with the actual order route.
// These repository method names are illustrative: adapt them to your app.
final outcome = await showRiderOrderOffer(
  context,
  offer: offer,
  map: yourExistingMap,
  onAccept: () async {
    final claimed = await orders.claimOffer(offer.id);
    return claimed
        ? OfferActionResult.confirmed
        : OfferActionResult.unavailable;
  },
  onDecline: () async {
    final declined = await orders.declineOffer(offer.id);
    return declined
        ? OfferActionResult.confirmed
        : OfferActionResult.unavailable;
  },
);

if (!context.mounted) return;
if (outcome == OfferOutcome.accepted) {
  // Refresh the assigned delivery, then navigate to your pickup screen.
}
```

In these callbacks, `false` should mean the server confirms the offer is unavailable. A connection failure must throw; do not convert a timeout into an unavailable response. Supply bounded network operations in your repository, and reconcile uncertain responses with the server before retrying. Idempotent backend actions prevent duplicate claims when a response is lost.

An example model for a Tanzanian rider app:

```dart
final offer = RiderOrderOffer(
  id: serverOfferId,
  restaurantName: restaurantName,
  deliverByLabel: 'Deliver by $formattedDeliveryTime',
  itemCount: itemCount,
  distanceLabel: '$formattedDistanceKm km total',
  totalEarnings: 'TZS $formattedTotal',
  deliveryPay: 'TZS $formattedDeliveryPay',
  customerTip: 'TZS $formattedTip',
  deliveryPayLabel: 'Delivery pay',
  expiresAt: serverExpiryUtc,
  responseWindow: serverResponseWindow,
);
```

All variables in this integration example come from your application. Currency strings are display values: compute and validate money using your app's exact monetary representation, then format it. The displayed total must be the rider's earnings, not the customer's full food bill. Only set `earningsNote` if the statement is true for your payment rules. Show a zero tip when appropriate; do not invent one.

Use a UTC deadline supplied by the server. Reopening the screen must not grant another response window. If your client maintains a measured server-clock offset, pass `now: () => DateTime.now().toUtc().add(serverOffset)`. The backend remains authoritative regardless of the displayed timer.

## Connect a real map

You can pass your app's existing map directly as `map:`. To use the supplied adapter:

1. From the demo/project root, run `flutter pub add google_maps_flutter`.
2. Follow Google's current platform setup instructions below for the Maps SDKs, billing, API key, platform requirements, and key restrictions. Android and iOS require their own platform configuration.
3. Keep `integrations/` beside `lib/` so its relative artwork import resolves. If you move the adapter into `lib/`, change its artwork import to `import 'order_map_art.dart';`.
4. Once the package is installed, remove `integrations/**` from `analysis_options.yaml` so the adapter is included in analysis, then format and analyze it.
5. Replace `DemoOrderMap` with the adapter:

   ```dart
   GoogleOrderMap(
     rider: LatLng(riderLatitude, riderLongitude),
     pickup: LatLng(pickupLatitude, pickupLongitude),
     dropoff: LatLng(customerLatitude, customerLongitude),
     routePoints: roadRouteFromBackend,
   )
   ```

`roadRouteFromBackend` must be a `List<LatLng>` following actual roads, covering rider → pickup → customer. A map polyline displays the points you provide; this adapter does not call a routing API. It also does not request location access or track GPS: supply those coordinates from your existing location service. Use a new points list when updating the route. This bounds implementation assumes local deliveries that do not cross the international date line.

The shared artwork produces black pickup/home pins and a blue rider dot. Provider attribution remains visible because the live map occupies its own area above the order panel. Follow the provider's app attribution requirements as part of your existing About/legal screen.

## Recommended new-order flow

1. Receive an offer event through your existing socket, database listener, or push service.
2. Fetch the current offer from the server. Check the assigned rider, availability, expiry, and whether the rider already has an active delivery. Deduplicate repeated events by offer ID and keep only one offer route open at a time.
3. While the app is foregrounded, show this screen. An optional short alert sound/vibration can help; stop it as soon as the rider responds or the offer expires. This starter includes button haptics only, not incoming-alert audio.
4. When the app is backgrounded or closed, use a notification. On tap, open the app, refresh the offer, and show the screen only if still valid. Do not attempt Navigator calls in a background message handler.
5. Accept calls the backend. The backend must atomically verify that the offer is still available and assign it to this rider. Wait for confirmation before showing the pickup/navigation screen.
6. Decline informs the backend and returns to the rider dashboard. Expiry closes this offer; the backend's dispatch process decides reassignment. A local timer alone must not reassign an order.

If using Firebase Messaging, foreground events arrive through `onMessage`; notification taps use `onMessageOpenedApp` for background launches and `getInitialMessage()` for a terminated launch. The service configuration, permission flow, subscriptions, and delivery guarantees belong to your existing app and are not included in this UI starter.

Also listen for server cancellation/reassignment and refresh on app resume. If the server revokes an offer, dismiss its route and update your central order state. During a pending claim, reconcile that request before displaying a different offer. A disposed screen ignores late UI callbacks; the repository must still retain any confirmed assignment globally.

For your first version, I recommend this single-order layout, TZS, kilometres, your own pay label, and a server-defined 30–45 second response window. Confirm the operational window with your dispatch rules. Add the right-hand, multiple-pickup layout only when your app actually supports bundled orders.

## Validation status

The source and integration contracts were reviewed, but this environment did not have Flutter or Dart installed. **The demo has not been compiled or rendered, and the supplied tests have not been executed.** Run the commands above before merging. Inspect the screen on your actual Android/iOS targets and verify real map keys and backend responses.

The included tests cover absolute expiry, duplicate Accept taps, server confirmation after the local deadline, retry after a request failure, unavailable offers, Decline, disposal during a request, and small screens with large text. The live-map adapter requires separate device testing with your configured Maps project.

## Official references

- [Google Maps Flutter setup](https://developers.google.com/maps/flutter-package/config)
- [Google Maps Flutter polylines](https://developers.google.com/maps/flutter-package/samples/polylines)
- [Custom map marker bitmap API](https://pub.dev/documentation/google_maps_flutter/latest/google_maps_flutter/BitmapDescriptor-class.html)
- [Flutter app lifecycle observer](https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver-class.html)
- [Firebase Messaging: receive messages in Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)

Reference design: the screenshot supplied in this conversation. The sample brand text is present only to match that reference; change it to your app's own wording for release.
# ride_UI
