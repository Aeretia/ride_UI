import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_order_ui/new_order_screen.dart';

RiderOrderOffer _offer(DateTime expiry) => RiderOrderOffer(
      id: 'offer-1',
      restaurantName: "Oren's Hummus",
      deliverByLabel: 'Deliver by 6:56 PM',
      itemCount: 8,
      distanceLabel: '4.8 mi total',
      totalEarnings: r'$16.50',
      deliveryPay: r'$8.50',
      customerTip: r'$8.00',
      expiresAt: expiry,
      responseWindow: const Duration(seconds: 30),
    );

Future<void> _show(
  WidgetTester tester, {
  required RiderOrderOffer offer,
  required DateTime Function() now,
  Future<OfferActionResult> Function()? accept,
  Future<OfferActionResult> Function()? decline,
  ValueChanged<OfferOutcome>? resolved,
  double textScale = 1,
}) =>
    tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: NewOrderScreen(
          offer: offer,
          map: const ColoredBox(color: Colors.grey),
          now: now,
          onAccept: accept ?? () async => OfferActionResult.confirmed,
          onDecline: decline ?? () async => OfferActionResult.confirmed,
          onResolved: resolved ?? (_) {},
        ),
      ),
    );

void main() {
  final epoch = DateTime.utc(2026, 10, 30, 12);

  test('deadline uses absolute time, rounds up seconds, and clamps progress',
      () {
    final offer = _offer(epoch.add(const Duration(seconds: 21)));
    expect(OfferTimeLeft.at(offer, epoch).seconds, 21);
    expect(
        OfferTimeLeft.at(offer, epoch.add(const Duration(milliseconds: 1)))
            .seconds,
        21);
    expect(
        OfferTimeLeft.at(offer, epoch.add(const Duration(seconds: 20))).seconds,
        1);
    expect(
        OfferTimeLeft.at(offer, epoch.add(const Duration(seconds: 21))).expired,
        isTrue);
    expect(
        OfferTimeLeft.at(offer, epoch.add(const Duration(minutes: 1))).fraction,
        0);
    expect(
        OfferTimeLeft.at(offer, epoch.subtract(const Duration(minutes: 1)))
            .fraction,
        1);
  });

  testWidgets('double tap submits one claim and waits for confirmation',
      (tester) async {
    final completion = Completer<OfferActionResult>();
    var calls = 0;
    final outcomes = <OfferOutcome>[];
    await _show(tester,
        offer: _offer(epoch.add(const Duration(seconds: 21))),
        now: () => epoch,
        accept: () {
          calls++;
          return completion.future;
        },
        resolved: outcomes.add);
    await tester.tap(find.byKey(const ValueKey('accept-order')));
    await tester.tap(find.byKey(const ValueKey('accept-order')));
    await tester.pump();
    expect(calls, 1);
    expect(outcomes, isEmpty);
    expect(find.text('Accepting…'), findsOneWidget);
    completion.complete(OfferActionResult.confirmed);
    await tester.pump();
    await tester.pump();
    expect(outcomes, [OfferOutcome.accepted]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expired offers resolve once and cannot be accepted',
      (tester) async {
    var now = epoch;
    var calls = 0;
    final outcomes = <OfferOutcome>[];
    await _show(tester,
        offer: _offer(epoch.add(const Duration(seconds: 2))),
        now: () => now,
        accept: () async {
          calls++;
          return OfferActionResult.confirmed;
        },
        resolved: outcomes.add);
    now = epoch.add(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump();
    expect(find.text('Offer expired'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('accept-order')));
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 0);
    expect(outcomes, [OfferOutcome.expired]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a claim confirmed after the local deadline still succeeds',
      (tester) async {
    var now = epoch;
    final completion = Completer<OfferActionResult>();
    final outcomes = <OfferOutcome>[];
    await _show(tester,
        offer: _offer(epoch.add(const Duration(seconds: 2))),
        now: () => now,
        accept: () => completion.future,
        resolved: outcomes.add);
    await tester.tap(find.byKey(const ValueKey('accept-order')));
    await tester.pump();
    now = epoch.add(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 110));
    expect(outcomes, isEmpty);
    completion.complete(OfferActionResult.confirmed);
    await tester.pump();
    await tester.pump();
    expect(outcomes, [OfferOutcome.accepted]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('request failure offers a retry without claiming success',
      (tester) async {
    final outcomes = <OfferOutcome>[];
    await _show(tester,
        offer: _offer(epoch.add(const Duration(seconds: 21))),
        now: () => epoch,
        accept: () async => throw StateError('offline'),
        resolved: outcomes.add);
    await tester.tap(find.byKey(const ValueKey('accept-order')));
    await tester.pump();
    expect(outcomes, isEmpty);
    expect(find.textContaining('Could not confirm'), findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(find.byKey(const ValueKey('accept-order')))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('server-unavailable response does not become accepted',
      (tester) async {
    final outcomes = <OfferOutcome>[];
    await _show(tester,
        offer: _offer(epoch.add(const Duration(seconds: 21))),
        now: () => epoch,
        accept: () async => OfferActionResult.unavailable,
        resolved: outcomes.add);
    await tester.tap(find.byKey(const ValueKey('accept-order')));
    await tester.pump();
    await tester.pump();
    expect(outcomes, [OfferOutcome.unavailable]);
    expect(find.text('Offer unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('decline uses its own callback and resolves once',
      (tester) async {
    var declines = 0;
    final outcomes = <OfferOutcome>[];
    await _show(tester,
        offer: _offer(epoch.add(const Duration(seconds: 21))),
        now: () => epoch,
        decline: () async {
          declines++;
          return OfferActionResult.confirmed;
        },
        resolved: outcomes.add);
    await tester.tap(find.byKey(const ValueKey('decline-order')));
    await tester.pump();
    await tester.pump();
    expect(declines, 1);
    expect(outcomes, [OfferOutcome.declined]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposing during a request ignores its late UI callback',
      (tester) async {
    final completion = Completer<OfferActionResult>();
    final outcomes = <OfferOutcome>[];
    await _show(tester,
        offer: _offer(epoch.add(const Duration(seconds: 21))),
        now: () => epoch,
        accept: () => completion.future,
        resolved: outcomes.add);
    await tester.tap(find.byKey(const ValueKey('accept-order')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    completion.complete(OfferActionResult.confirmed);
    await tester.pump();
    expect(outcomes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short screen and large text keep Accept reachable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _show(tester,
        offer: _offer(epoch.add(const Duration(seconds: 21))),
        now: () => epoch,
        textScale: 2);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('accept-order')).hitTestable(),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'order details sheet can be dragged up to full screen and down to reveal map',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _show(tester,
        offer: _offer(epoch.add(const Duration(seconds: 21))),
        now: () => epoch);
    await tester.pump();

    final titleFinder = find.text("Oren's Hummus").first;
    final defaultY = tester.getTopLeft(titleFinder).dy;

    // Pull the sheet UP to full screen
    await tester.drag(titleFinder, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 500));
    final expandedY = tester.getTopLeft(titleFinder).dy;
    expect(expandedY, lessThan(defaultY - 120));

    // Pull the sheet DOWN to see more of the map
    await tester.drag(titleFinder, const Offset(0, 520));
    await tester.pump(const Duration(milliseconds: 500));
    final collapsedY = tester.getTopLeft(titleFinder).dy;
    expect(collapsedY, greaterThan(defaultY + 80));

    await tester.pumpWidget(const SizedBox());
  });
}
