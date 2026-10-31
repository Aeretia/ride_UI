import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// The server decides whether a rider has successfully claimed an offer.
/// Throw from an action callback for a recoverable transport/server error.
enum OfferActionResult { confirmed, unavailable }

enum OfferOutcome { accepted, declined, expired, unavailable }

/// Display-ready data, so this screen has no dependency on your state manager,
/// currency package, backend, or map provider. Money must be formatted by your
/// app from integer minor units / an exact decimal representation.
@immutable
class RiderOrderOffer {
  RiderOrderOffer({
    required this.id,
    required this.restaurantName,
    required this.deliverByLabel,
    required this.itemCount,
    required this.distanceLabel,
    required this.totalEarnings,
    required this.deliveryPay,
    required this.customerTip,
    required this.expiresAt,
    required this.responseWindow,
    this.deliveryPayLabel = 'Delivery pay',
    this.earningsNote,
  }) {
    if (itemCount < 0) throw ArgumentError.value(itemCount, 'itemCount');
    if (responseWindow.inMilliseconds <= 0) {
      throw ArgumentError.value(
          responseWindow, 'responseWindow', 'Must be positive');
    }
  }

  final String id;
  final String restaurantName;
  final String deliverByLabel;
  final int itemCount;

  /// Example: '4.8 mi total' or '7.7 km total'.
  final String distanceLabel;
  final String totalEarnings;
  final String deliveryPay;
  final String customerTip;
  final String deliveryPayLabel;

  /// Only supply a qualification your actual payout policy supports.
  final String? earningsNote;

  /// Absolute server expiry. Do not reset to now + N on each notification.
  final DateTime expiresAt;

  /// The original response window, used as the countdown ring's denominator.
  final Duration responseWindow;
}

/// Pure deadline calculation, also used by the tests. [now] can be a clock
/// corrected with your server's time offset.
@immutable
class OfferTimeLeft {
  const OfferTimeLeft(this.milliseconds, this.fraction);

  factory OfferTimeLeft.at(RiderOrderOffer offer, DateTime now) {
    final milliseconds = math.max(
      0,
      offer.expiresAt.difference(now).inMilliseconds,
    );
    return OfferTimeLeft(
      milliseconds,
      (milliseconds / offer.responseWindow.inMilliseconds)
          .clamp(0.0, 1.0)
          .toDouble(),
    );
  }

  final int milliseconds;
  final double fraction;
  int get seconds => (milliseconds / 1000).ceil();
  bool get expired => milliseconds <= 0;
}

/// Present as a full-screen route. Pass your existing map as [map].
/// Both action callbacks must await the backend's authoritative response.
/// [onResolved] runs once, after the terminal state has rendered.
/// Use a separate keyed route for each offer; do not replace a pending claim.
class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({
    super.key,
    required this.offer,
    required this.map,
    required this.onAccept,
    required this.onDecline,
    required this.onResolved,
    this.now,
    this.accentColor = const Color(0xFFFF3509),
  });

  final RiderOrderOffer offer;
  final Widget map;
  final Future<OfferActionResult> Function() onAccept;
  final Future<OfferActionResult> Function() onDecline;
  final ValueChanged<OfferOutcome> onResolved;
  final DateTime Function()? now;
  final Color accentColor;

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Timer? _timer;
  late final ValueNotifier<OfferTimeLeft> _remaining;

  /// Unbounded spring controller driving the vertical top position (in px)
  /// of the draggable order details sheet.
  late final AnimationController _sheetController;

  /// Entrance choreography controller (staggered scale 0.96 -> 1.0 + opacity).
  late final AnimationController _entranceController;

  final ScrollController _scrollController = ScrollController();

  OfferOutcome? _outcome;
  bool _busy = false;
  bool _accepting = false;
  bool _draggingSheet = false;
  String? _error;

  double? _lastMaxHeight;
  double? _lastMaxWidth;
  double _snapExpandedTop = 16.0;
  double _snapDefaultTop = 320.0;
  double _snapCollapsedTop = 500.0;
  double _rawDragTop = 320.0;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remaining = ValueNotifier(OfferTimeLeft.at(widget.offer, _now));
    _sheetController = AnimationController.unbounded(vsync: this);
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tick();
    });
  }

  @override
  void didUpdateWidget(covariant NewOrderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      widget.offer.id == oldWidget.offer.id,
      'Create a new route with ValueKey(offer.id) for each new offer.',
    );
    // Refresh same-offer server revisions after the current build completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tick();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  void _tick() {
    if (!mounted || _outcome != null) return;
    final remaining = OfferTimeLeft.at(widget.offer, _now);
    _remaining.value = remaining;
    // An already-submitted request may have succeeded before expiry. Wait
    // for its authoritative response instead of reporting a false expiry.
    if (remaining.expired && !_busy) _resolve(OfferOutcome.expired);
  }

  void _resolve(OfferOutcome outcome) {
    if (!mounted || _outcome != null) return;
    _timer?.cancel();
    setState(() {
      _outcome = outcome;
      _busy = false;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onResolved(outcome);
    });
  }

  Future<void> _submit({required bool accepting}) async {
    if (_busy || _outcome != null) return;
    _tick();
    if (_remaining.value.expired || _outcome != null) return;
    setState(() {
      _busy = true;
      _accepting = accepting;
      _error = null;
    });
    unawaited(HapticFeedback.selectionClick());
    try {
      final result = await (accepting ? widget.onAccept() : widget.onDecline());
      if (!mounted || _outcome != null) return;
      _resolve(
        result == OfferActionResult.unavailable
            ? OfferOutcome.unavailable
            : accepting
                ? OfferOutcome.accepted
                : OfferOutcome.declined,
      );
    } catch (_) {
      if (!mounted || _outcome != null) return;
      setState(() {
        _busy = false;
        _error =
            'Could not confirm your response. Check your connection and retry.';
      });
      _tick();
    }
  }

  /// Computes the 3 snap points (Full-screen Expanded, Square-Map Default,
  /// and Map-Peek Collapsed) so the order items sit snugly above the action
  /// buttons and the map fits into the remaining square-like top space.
  void _configureSnapGeometry(
    BoxConstraints constraints,
    double topSafePadding,
  ) {
    final maxH = constraints.maxHeight;
    final maxW = constraints.maxWidth;
    if (_lastMaxHeight == maxH && _lastMaxWidth == maxW) return;
    final isFirstLayout = _lastMaxHeight == null;
    _lastMaxHeight = maxH;
    _lastMaxWidth = maxW;

    if (maxH < 360) {
      _snapExpandedTop = 8.0;
      _snapDefaultTop = 54.0;
      _snapCollapsedTop = 54.0;
      _sheetController.value = _snapDefaultTop;
      _rawDragTop = _snapDefaultTop;
      return;
    }

    // 1. Full-screen pulled-up snap point (just below the status bar)
    _snapExpandedTop = math.max(topSafePadding + 8.0, 12.0);

    // 2. Default resting snap point: pushes the order details down to fill
    // the bottom space (~400px sheet height) while giving the map above it
    // a square-like frame (~85%-95% of width).
    const snugSheetHeight = 404.0;
    final desiredTop = maxH - snugSheetHeight;
    final minDefaultTop = math.max(_snapExpandedTop + 56.0, maxH * 0.28);
    final maxDefaultTop = math.max(minDefaultTop, maxH * 0.52);
    _snapDefaultTop = desiredTop.clamp(minDefaultTop, maxDefaultTop);

    // 3. Pulled-down map inspection snap point: keeps the sheet header and
    // countdown dial visible while revealing ~72% of the map.
    const peekSheetHeight = 168.0;
    _snapCollapsedTop = math.max(
      _snapDefaultTop + 64.0,
      (maxH - peekSheetHeight).clamp(_snapDefaultTop, maxH * 0.78),
    );

    if (isFirstLayout) {
      _sheetController.value = _snapDefaultTop;
      _rawDragTop = _snapDefaultTop;
    } else {
      _sheetController.value = _sheetController.value.clamp(
        _snapExpandedTop,
        _snapCollapsedTop,
      );
      _rawDragTop = _sheetController.value;
    }
  }

  /// Apple's rubber-band resistance curve for dragging past top/bottom bounds.
  static double _rubberBand(double overshoot, double dimension) {
    const constant = 0.55;
    return (overshoot * dimension * constant) /
        (dimension + constant * overshoot.abs());
  }

  void _onSheetDragStart(DragStartDetails details) {
    // Interrupt any in-flight spring immediately at its live presentation value.
    if (_sheetController.isAnimating) {
      _sheetController.stop();
    }
    _rawDragTop = _sheetController.value;
    if (!_draggingSheet) {
      setState(() => _draggingSheet = true);
    }
  }

  void _onSheetDragUpdate(DragUpdateDetails details) {
    final dy = details.primaryDelta ?? 0.0;
    // If the sheet is already expanded full-screen and the user is scrolling
    // inner content upward (or downward while scrolled down), let the inner
    // scroll view move first before pulling the sheet down.
    if (_sheetController.value <= _snapExpandedTop + 0.5 &&
        _scrollController.hasClients) {
      if (dy < 0 &&
          _scrollController.position.pixels <
              _scrollController.position.maxScrollExtent) {
        _scrollController.jumpTo(
          (_scrollController.position.pixels - dy).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
        );
        return;
      }
      if (dy > 0 && _scrollController.position.pixels > 0) {
        _scrollController.jumpTo(
          math.max(0.0, _scrollController.position.pixels - dy),
        );
        return;
      }
    }

    _rawDragTop += dy;
    if (_rawDragTop < _snapExpandedTop) {
      final overshoot = _snapExpandedTop - _rawDragTop;
      _sheetController.value = _snapExpandedTop - _rubberBand(overshoot, 110.0);
    } else if (_rawDragTop > _snapCollapsedTop) {
      final overshoot = _rawDragTop - _snapCollapsedTop;
      _sheetController.value =
          _snapCollapsedTop + _rubberBand(overshoot, 110.0);
    } else {
      _sheetController.value = _rawDragTop;
    }
  }

  void _onSheetDragEnd(DragEndDetails details) {
    if (_draggingSheet) {
      setState(() => _draggingSheet = false);
    }
    final velocity = details.primaryVelocity ?? 0.0;
    final current = _sheetController.value;
    final snaps = <double>[
      _snapExpandedTop,
      _snapDefaultTop,
      _snapCollapsedTop,
    ];

    double target;
    // Momentum projection + directional flick handling (Apple fluid interfaces)
    if (velocity.abs() > 320.0) {
      if (velocity < 0) {
        // Flicked UP: step to the next higher snap point
        target = snaps.lastWhere(
          (s) => s < current - 8.0,
          orElse: () => _snapExpandedTop,
        );
      } else {
        // Flicked DOWN: step to the next lower snap point
        target = snaps.firstWhere(
          (s) => s > current + 8.0,
          orElse: () => _snapCollapsedTop,
        );
      }
    } else {
      // Exponential-decay momentum projection
      const decel = 0.996;
      final projected = current + (velocity / 1000.0) * decel / (1.0 - decel);
      target = snaps.reduce(
        (a, b) => (projected - a).abs() <= (projected - b).abs() ? a : b,
      );
    }

    _animateSheetTo(target, velocity: velocity);
  }

  void _onSheetDragCancel() {
    if (_draggingSheet) {
      setState(() => _draggingSheet = false);
    }
    _animateSheetTo(_snapDefaultTop);
  }

  void _toggleSheetSnap() {
    unawaited(HapticFeedback.selectionClick());
    final current = _sheetController.value;
    final double target;
    if ((current - _snapDefaultTop).abs() < 20.0) {
      target = _snapExpandedTop;
    } else {
      target = _snapDefaultTop;
    }
    _animateSheetTo(target);
  }

  void _animateSheetTo(double target, {double velocity = 0.0}) {
    _rawDragTop = target;
    if (!mounted) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _sheetController.value = target;
      return;
    }
    // Use slight under-damping (0.86) only when a flick carried real momentum;
    // otherwise use a critically damped (1.0) spring so it settles cleanly.
    final hasMomentum = velocity.abs() > 280.0;
    final spring = SpringDescription.withDampingRatio(
      mass: 1.0,
      stiffness: 420.0,
      ratio: hasMomentum ? 0.86 : 1.0,
    );
    final simulation = SpringSimulation(
      spring,
      _sheetController.value,
      target,
      velocity,
    );
    unawaited(_sheetController.animateWith(simulation));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _sheetController.dispose();
    _entranceController.dispose();
    _scrollController.dispose();
    _remaining.dispose();
    super.dispose();
  }

  String get _buttonLabel => switch (_outcome) {
        OfferOutcome.accepted => 'Accepted',
        OfferOutcome.declined => 'Declined',
        OfferOutcome.expired => 'Offer expired',
        OfferOutcome.unavailable => 'Offer unavailable',
        null => _busy ? (_accepting ? 'Accepting…' : 'Declining…') : 'Accept',
      };

  @override
  Widget build(BuildContext context) {
    final enabled = !_busy && _outcome == null;
    final topSafePadding = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _RiderColors.canvas,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: PopScope(
        canPop: _outcome != null,
        child: Scaffold(
          // Unified background color across the sheet and bottom action bar
          backgroundColor: _RiderColors.canvas,
          drawer: const _RiderDrawer(),
          body: LayoutBuilder(
            builder: (context, constraints) {
              _configureSnapGeometry(constraints, topSafePadding);
              final isTinyScreen = constraints.maxHeight < 360;
              return AnimatedBuilder(
                animation: _sheetController,
                builder: (context, sheetChild) {
                  final sheetTop = _sheetController.value.clamp(
                    0.0,
                    constraints.maxHeight - 72.0,
                  );

                  // Progress from default position -> full-screen expanded (0..1)
                  final expandRange =
                      math.max(1.0, _snapDefaultTop - _snapExpandedTop);
                  final expandProgress =
                      ((_snapDefaultTop - sheetTop) / expandRange)
                          .clamp(0.0, 1.0);

                  // The map fills the square-like top area in default state and
                  // dynamically grows downward when the user pulls the sheet down.
                  final mapViewportBottom = isTinyScreen
                      ? 72.0
                      : math
                          .max(sheetTop + 24.0, _snapDefaultTop + 24.0)
                          .clamp(72.0, constraints.maxHeight);

                  // Subtle upward parallax when pulling the sheet to full-screen
                  final mapParallaxY = -expandProgress * 22.0;

                  return Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: mapViewportBottom,
                        child: Transform.translate(
                          offset: Offset(0, mapParallaxY),
                          child: isTinyScreen
                              ? _CompactMapHeader(map: widget.map)
                              : _MapHeader(
                                  map: widget.map,
                                  headerOpacity: (1.0 - expandProgress * 1.35)
                                      .clamp(0.0, 1.0),
                                ),
                        ),
                      ),
                      if (expandProgress > 0.01)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: mapViewportBottom,
                          child: IgnorePointer(
                            child: ColoredBox(
                              color: _RiderColors.ink.withValues(
                                alpha: expandProgress * 0.34,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: sheetTop,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: sheetChild!,
                      ),
                    ],
                  );
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: isTinyScreen ? null : _onSheetDragStart,
                  onVerticalDragUpdate:
                      isTinyScreen ? null : _onSheetDragUpdate,
                  onVerticalDragEnd: isTinyScreen ? null : _onSheetDragEnd,
                  onVerticalDragCancel:
                      isTinyScreen ? null : _onSheetDragCancel,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: _RiderColors.canvas,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x180F172A),
                          blurRadius: 24,
                          offset: Offset(0, -6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Semantics(
                          label: 'Drag or tap to resize order details',
                          button: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: isTinyScreen ? null : _toggleSheetSnap,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: 10,
                                bottom: 6,
                                left: 48,
                                right: 48,
                              ),
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  curve: const Cubic(0.23, 1, 0.32, 1),
                                  width: _draggingSheet ? 48 : 36,
                                  height: 4.5,
                                  decoration: BoxDecoration(
                                    color: _draggingSheet
                                        ? _RiderColors.muted
                                        : _RiderColors.handle,
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            physics: isTinyScreen
                                ? const ClampingScrollPhysics()
                                : const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                            child: _OrderDetails(
                              offer: widget.offer,
                              remaining: _remaining,
                              entrance: _entranceController,
                              outcome: _outcome,
                              error: _error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // Same _RiderColors.canvas background with zero border line so there
          // is no color difference between the sheet and the action buttons.
          bottomNavigationBar: ColoredBox(
            color: _RiderColors.canvas,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _TactilePressable(
                        enabled: enabled,
                        child: OutlinedButton(
                          key: const ValueKey('decline-order'),
                          onPressed:
                              enabled ? () => _submit(accepting: false) : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _RiderColors.ink,
                            disabledForegroundColor: _RiderColors.muted,
                            backgroundColor: _RiderColors.surface,
                            minimumSize: const Size.fromHeight(52),
                            side: const BorderSide(
                                color: _RiderColors.ruleStrong),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Decline',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _TactilePressable(
                        enabled: enabled,
                        child: ElevatedButton(
                          key: const ValueKey('accept-order'),
                          onPressed:
                              enabled ? () => _submit(accepting: true) : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.accentColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFE5E7EB),
                            disabledForegroundColor: const Color(0xFF6B7280),
                            minimumSize: const Size.fromHeight(52),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_busy) ...[
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Flexible(
                                child: Text(
                                  _buttonLabel,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.2),
                                ),
                              ),
                            ],
                          ),
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

/// Applies the 3% physical press-down depression rule (scale 0.97 on pointer-down
/// with a 140ms strong ease-out curve), while honoring system reduced-motion.
class _TactilePressable extends StatefulWidget {
  const _TactilePressable({
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<_TactilePressable> createState() => _TactilePressableState();
}

class _TactilePressableState extends State<_TactilePressable> {
  static const _easeOut = Cubic(0.23, 1, 0.32, 1);
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) {
      if (_pressed) setState(() => _pressed = false);
      return;
    }
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  void didUpdateWidget(covariant _TactilePressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
      onPointerUp: widget.enabled ? (_) => _setPressed(false) : null,
      onPointerCancel: widget.enabled ? (_) => _setPressed(false) : null,
      child: AnimatedScale(
        scale: (_pressed && widget.enabled && !reduceMotion) ? 0.97 : 1.0,
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 140),
        curve: _easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Staggered entrance wrapper that animates from scale(0.96) + translateY(10px)
/// + opacity(0) using a strong ease-out curve, never animating from scale(0).
class _StaggeredEntrance extends StatelessWidget {
  const _StaggeredEntrance({
    required this.animation,
    required this.startInterval,
    required this.child,
  });

  final Animation<double> animation;
  final double startInterval;
  final Widget child;

  static const _easeOut = Cubic(0.23, 1, 0.32, 1);

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, cachedChild) {
        final raw = ((animation.value - startInterval) / (1.0 - startInterval))
            .clamp(0.0, 1.0);
        final t = _easeOut.transform(raw);
        final scale = 0.96 + (0.04 * t);
        final dy = (1.0 - t) * 10.0;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(
              scale: scale,
              child: cachedChild,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class _OrderDetails extends StatelessWidget {
  const _OrderDetails({
    required this.offer,
    required this.remaining,
    required this.entrance,
    this.outcome,
    this.error,
  });

  final RiderOrderOffer offer;
  final ValueListenable<OfferTimeLeft> remaining;
  final Animation<double> entrance;
  final OfferOutcome? outcome;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: DefaultTextStyle.of(context)
          .style
          .copyWith(color: _RiderColors.ink, height: 1.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StaggeredEntrance(
            animation: entrance,
            startInterval: 0.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusBadge(outcome: outcome),
                    Text(
                      offer.deliverByLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _RiderColors.muted,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offer.restaurantName,
                            style: const TextStyle(
                              fontSize: 25,
                              height: 1.12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 14,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _MetaChip(
                                icon: Icons.shopping_bag_outlined,
                                label:
                                    '${offer.itemCount} ${offer.itemCount == 1 ? 'item' : 'items'}',
                              ),
                              _MetaChip(
                                icon: Icons.near_me_outlined,
                                label: offer.distanceLabel,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    _CountdownDial(remaining: remaining),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Dual-surface floating card for Pickup -> Drop-off route hierarchy
          _StaggeredEntrance(
            animation: entrance,
            startInterval: 0.16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _RiderColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _RiderColors.rule),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RouteRow(
                    icon: Icons.storefront_outlined,
                    label: 'Pickup',
                    value: offer.restaurantName,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 17, top: 3, bottom: 3),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 2,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: _RiderColors.ruleStrong,
                          borderRadius: BorderRadius.all(Radius.circular(1)),
                        ),
                      ),
                    ),
                  ),
                  const _RouteRow(
                    icon: Icons.location_on_outlined,
                    label: 'Drop-off',
                    value: 'Destination shared after acceptance',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Financial ledger card with tabular numerals and clear breakdown
          _StaggeredEntrance(
            animation: entrance,
            startInterval: 0.32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _RiderColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _RiderColors.rule),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ESTIMATED EARNINGS',
                    style: TextStyle(
                      color: _RiderColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    offer.totalEarnings,
                    style: const TextStyle(
                      fontSize: 32,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (offer.earningsNote != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      offer.earningsNote!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _RiderColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: _RiderColors.rule),
                  ),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: _PayItem(
                            value: offer.deliveryPay,
                            label: offer.deliveryPayLabel,
                          ),
                        ),
                        const VerticalDivider(
                          width: 24,
                          thickness: 1,
                          color: _RiderColors.rule,
                        ),
                        Expanded(
                          child: _PayItem(
                            value: offer.customerTip,
                            label: 'Customer tip',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _RiderColors.dangerSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _RiderColors.dangerBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: _RiderColors.danger,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: _RiderColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Direct semantic status label using colored text and vector icon (no pill bubble or dot).
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.outcome});

  final OfferOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (outcome) {
      OfferOutcome.accepted => (
          Icons.check_circle_outline_rounded,
          const Color(0xFF067647),
        ),
      OfferOutcome.expired ||
      OfferOutcome.unavailable ||
      OfferOutcome.declined =>
        (
          Icons.remove_circle_outline_rounded,
          _RiderColors.muted,
        ),
      null => (
          Icons.call_received_rounded,
          _RiderColors.accent,
        ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'INCOMING ORDER',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _RiderColors.muted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: _RiderColors.muted,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );
}

class _CountdownDial extends StatelessWidget {
  const _CountdownDial({required this.remaining});

  final ValueListenable<OfferTimeLeft> remaining;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<OfferTimeLeft>(
        valueListenable: remaining,
        builder: (context, time, _) {
          final isUrgent = time.seconds <= 10 && !time.expired;
          final dialColor =
              isUrgent ? _RiderColors.danger : _RiderColors.accent;
          return Semantics(
            label: 'Time remaining',
            value: '${time.seconds} seconds',
            // Not a live region: avoid announcing every countdown tick.
            child: ExcludeSemantics(
              child: Container(
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _RiderColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: _RiderColors.rule),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: time.fraction,
                      strokeWidth: 4,
                      strokeCap: StrokeCap.round,
                      backgroundColor: _RiderColors.canvas,
                      color: dialColor,
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${time.seconds}',
                            key: const ValueKey('offer-seconds'),
                            style: TextStyle(
                              fontSize: 18,
                              height: 1.0,
                              color: isUrgent
                                  ? _RiderColors.danger
                                  : _RiderColors.ink,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                            textScaler: TextScaler.noScaling,
                          ),
                          const Text(
                            'sec',
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.0,
                              color: _RiderColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                            textScaler: TextScaler.noScaling,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _PayItem extends StatelessWidget {
  const _PayItem({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _RiderColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: _RiderColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
}

class _MapHeader extends StatelessWidget {
  const _MapHeader({required this.map, this.headerOpacity = 1.0});
  final Widget map;
  final double headerOpacity;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: map),
          // Top edge gradient scrim so map routes stay crisp while header controls remain legible
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 92,
            child: IgnorePointer(
              child: Opacity(
                opacity: headerOpacity,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x54111827),
                        Color(0x00111827),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Opacity(
              opacity: headerOpacity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (context) => Semantics(
                        label: 'Open navigation menu',
                        button: true,
                        child: _TactilePressable(
                          child: Material(
                            color: _RiderColors.surface,
                            shape: const CircleBorder(
                              side: BorderSide(color: _RiderColors.rule),
                            ),
                            child: IconButton(
                              onPressed: Scaffold.of(context).openDrawer,
                              icon: const Icon(Icons.menu_rounded,
                                  color: _RiderColors.ink),
                              tooltip: 'Menu',
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RIDE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                            ),
                          ),
                          Text(
                            'New offer',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const _MapLegend(),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}

class _CompactMapHeader extends StatelessWidget {
  const _CompactMapHeader({required this.map});
  final Widget map;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: map),
          Positioned(
            top: 8,
            left: 12,
            child: Builder(
              builder: (context) => Material(
                color: _RiderColors.surface,
                shape: const CircleBorder(
                  side: BorderSide(color: _RiderColors.rule),
                ),
                child: IconButton(
                  onPressed: Scaffold.of(context).openDrawer,
                  icon: const Icon(Icons.menu_rounded, color: _RiderColors.ink),
                  tooltip: 'Menu',
                ),
              ),
            ),
          ),
        ],
      );
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: _RiderColors.surface,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.all(color: _RiderColors.rule),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route_outlined, size: 16, color: _RiderColors.ink),
              SizedBox(width: 5),
              Text(
                'Route',
                style: TextStyle(
                  color: _RiderColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
}

class _RouteRow extends StatelessWidget {
  const _RouteRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _RiderColors.canvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _RiderColors.rule),
            ),
            child: Icon(icon, color: _RiderColors.ink, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: _RiderColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: _RiderColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _RiderDrawer extends StatefulWidget {
  const _RiderDrawer();

  @override
  State<_RiderDrawer> createState() => _RiderDrawerState();
}

class _RiderDrawerState extends State<_RiderDrawer> {
  String _selectedLabel = 'Overview';

  void _select(String label) {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _selectedLabel = label);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Drawer(
        width: 288,
        backgroundColor: _RiderColors.surface,
        elevation: 0,
        shape: const Border(
          right: BorderSide(color: _RiderColors.rule, width: 1),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RIDE',
                            style: TextStyle(
                              color: _RiderColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Rider workspace',
                            style: TextStyle(
                              color: _RiderColors.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _TactilePressable(
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: _RiderColors.muted,
                        ),
                        tooltip: 'Close menu',
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _RiderColors.rule),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  children: [
                    _DrawerItem(
                      icon: Icons.grid_view_rounded,
                      label: 'Overview',
                      trailing: null,
                      selected: _selectedLabel == 'Overview',
                      onTap: () => _select('Overview'),
                    ),
                    _DrawerItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'Orders',
                      selected: _selectedLabel == 'Orders',
                      onTap: () => _select('Orders'),
                    ),
                    _DrawerItem(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Earnings',
                      selected: _selectedLabel == 'Earnings',
                      onTap: () => _select('Earnings'),
                    ),
                    _DrawerItem(
                      icon: Icons.calendar_today_outlined,
                      label: 'Schedule',
                      selected: _selectedLabel == 'Schedule',
                      onTap: () => _select('Schedule'),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Divider(height: 1, color: _RiderColors.rule),
                    ),
                    _DrawerItem(
                      icon: Icons.support_agent_outlined,
                      label: 'Support',
                      selected: _selectedLabel == 'Support',
                      onTap: () => _select('Support'),
                    ),
                    _DrawerItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      selected: _selectedLabel == 'Settings',
                      onTap: () => _select('Settings'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _TactilePressable(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: selected ? _RiderColors.canvas : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color:
                          selected ? _RiderColors.accent : _RiderColors.muted,
                      size: 20,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color:
                              selected ? _RiderColors.ink : _RiderColors.muted,
                          fontSize: 15,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (trailing != null)
                      Text(
                        trailing!,
                        style: const TextStyle(
                          color: _RiderColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

abstract final class _RiderColors {
  static const canvas = Color(0xFFF4F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const rule = Color(0xFFE5E7EB);
  static const ruleStrong = Color(0xFFD1D5DB);
  static const handle = Color(0xFFC8CDD5);
  static const accent = Color(0xFFE85D2A);
  static const danger = Color(0xFFB42318);
  static const dangerSurface = Color(0xFFFEF3F2);
  static const dangerBorder = Color(0xFFFECDCA);
}
