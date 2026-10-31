import 'package:flutter/material.dart';

import 'new_order_screen.dart';
import 'order_map_art.dart';

void main() => runApp(const RiderOfferDemo());

class RiderOfferDemo extends StatelessWidget {
  const RiderOfferDemo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Rider order UI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: false,
          brightness: Brightness.light,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF3509)),
        ),
        home: const _DemoHome(),
      );
}

class _DemoHome extends StatefulWidget {
  const _DemoHome();

  @override
  State<_DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<_DemoHome> {
  late RiderOrderOffer _offer;
  OfferOutcome? _outcome;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    _offer = _createOffer(tzs: false);
  }

  RiderOrderOffer _createOffer({required bool tzs}) => RiderOrderOffer(
        id: 'demo-${_serial++}',
        restaurantName: tzs ? 'Restaurant name' : "Oren's Hummus",
        deliverByLabel: tzs ? 'Deliver by 7:05 PM' : 'Deliver by 6:56 PM',
        itemCount: 8,
        distanceLabel: tzs ? '7.7 km total' : '4.8 mi total',
        totalEarnings: tzs ? 'TZS 8,500' : r'$16.50',
        deliveryPay: tzs ? 'TZS 6,000' : r'$8.50',
        customerTip: tzs ? 'TZS 2,500' : r'$8.00',
        deliveryPayLabel: tzs ? 'Delivery pay' : 'DoorDash pay',
        earningsNote: tzs ? null : '(Total may be higher)',
        expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 21)),
        responseWindow: const Duration(seconds: 45),
      );

  Future<OfferActionResult> _simulateResponse() async {
    // Demo only. Replace with a server-confirmed claim or decline operation.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return OfferActionResult.confirmed;
  }

  void _replay({required bool tzs}) {
    setState(() {
      _offer = _createOffer(tzs: tzs);
      _outcome = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_outcome == null) {
      return NewOrderScreen(
        key: ValueKey(_offer.id),
        offer: _offer,
        map: const DemoOrderMap(),
        onAccept: _simulateResponse,
        onDecline: _simulateResponse,
        onResolved: (outcome) => setState(() => _outcome = outcome),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: const Icon(
                            Icons.delivery_dining_outlined,
                            size: 24,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'SIMULATION RESULT',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.9,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Demo: ${_outcome!.name}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'This demo does not send or accept real orders.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => _replay(tzs: false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3509),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Replay reference screen',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => _replay(tzs: true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF111827),
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Try TZS + kilometres example',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
