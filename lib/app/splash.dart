import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tokens.dart';
import '../core/nav.dart';
import '../data/config.dart';
import '../data/session.dart';
import 'launcher.dart';
import '../data/push.dart';

/// Hero tag shared by the splash lockup and the launcher's header logo.
const kLogoHeroTag = 'medpin-logo';

const _logo = 'assets/images/medpin_logo.png';
const _wordmark = 'assets/images/splash_wordmark.png';
const _markDark = 'assets/images/splash_mark_dark.png';
const _markHeart = 'assets/images/splash_mark_heart.png';
const _markFlow = 'assets/images/splash_mark_flow.png';
const _revealShader = 'shaders/mark_reveal.frag';

// Geometry of medpin_logo.png (1646×609) that the splash assets were cut from.
const _logoW = 1646.0, _logoH = 609.0;
// The mark layers keep a 4px transparent margin so the logo never touches the
// image edge (an edge pixel would leave a faint line under the dstIn mask).
const _markLeft = 4.0, _markTop = 4.0, _markW = 522.0, _markH = 601.0;
const _wordLeft = 600.0, _wordW = 1046.0;
// Heart centre and half-size inside the mark (pixels of the 522×601 layers).
const _heartCx = 261.5 / _markW, _heartCy = 461.0 / _markH, _heartR = 161.5 / _markW;

const _heartBlue = Color(0xFF5199FE);

/// Animated launch screen: the MedPin mark draws itself stroke by stroke, the
/// heart beats once, the wordmark slides in to form the logo, and the logo
/// flies into the launcher's header. Tap anywhere to skip.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  // 0 → 1 over the whole sequence; the phases below are slices of it.
  // 2750 ms: draw 0–1250 · beat 1150–1650 · ripple 1200–1900 ·
  // lockup 1500–2150 · wordmark 1950–2500 · Hero swap 2560 · leave 2750.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2750));

  static const _draw = Interval(0.000, 0.455, curve: Curves.easeInOutCubic);
  static const _glowIn = Interval(0.000, 0.236, curve: Curves.easeOut);
  static const _glowOut = Interval(0.527, 0.709, curve: Curves.easeIn);
  static const _beat = Interval(0.418, 0.600);
  static const _ripple = Interval(0.436, 0.691, curve: Curves.easeOutCubic);
  static const _lockup = Interval(0.545, 0.782, curve: Curves.easeInOutCubic);
  // Starts once the mark has almost reached the lockup, so the two never overlap.
  static const _word = Interval(0.709, 0.909, curve: Curves.easeOutCubic);

  /// Heart beat: up, a small rebound, settle.
  static final _beatScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12).chain(CurveTween(curve: Curves.easeOut)), weight: 38),
    TweenSequenceItem(tween: Tween(begin: 1.12, end: 0.97).chain(CurveTween(curve: Curves.easeInOut)), weight: 32),
    TweenSequenceItem(tween: Tween(begin: 0.97, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
  ]);

  ui.Image? _dark, _heart, _flow;

  /// GPU reveal (same on Impeller and Skia); null → the blend-mode fallback.
  ui.FragmentProgram? _reveal;
  bool _left = false;
  Timer? _fallback;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _goNext();
    });
    // Never strand the user on the splash if an asset fails to load.
    _fallback = Timer(const Duration(seconds: 4), _goNext);
    unawaited(_next); // check the saved session while the animation plays
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dark == null) _load();
  }

  Future<void> _load() async {
    try {
      // The logo and wordmark are decoded up front so the final swap to the
      // Hero image and the wordmark reveal never flash.
      final results = await Future.wait([
        _decode(_markDark),
        _decode(_markHeart),
        _decode(_markFlow),
        precacheImage(const AssetImage(_logo), context),
        precacheImage(const AssetImage(_wordmark), context),
      ]);
      ui.FragmentProgram? reveal;
      try {
        reveal = await ui.FragmentProgram.fromAsset(_revealShader);
      } catch (e) {
        debugPrint('Splash shader unavailable, using fallback: $e');
      }
      if (!mounted) return;
      setState(() {
        _reveal = reveal;
        _dark = results[0] as ui.Image;
        _heart = results[1] as ui.Image;
        _flow = results[2] as ui.Image;
      });
      _fallback?.cancel();
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1; // reduced motion: show the logo, then continue
      } else {
        _c.forward();
      }
    } catch (_) {
      _goNext();
    }
  }

  static Future<ui.Image> _decode(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  void _skip() {
    if (_dark == null || _left) return;
    _c.value = 1;
  }

  /// Where to go after the splash: the design launcher (preview builds), the
  /// signed-in account's home, or sign-in. Checked while the animation plays.
  late final Future<String?> _next = _decideNext();

  static Future<String?> _decideNext() async {
    if (AppConfig.previewLauncher) return null;
    final signedIn = await Session.I.restore();
    return signedIn ? Session.I.landing : 'Auth-Login';
  }

  Future<void> _goNext() async {
    if (_left || !mounted) return;
    _left = true;
    _fallback?.cancel();
    final stem = await _next;
    if (!mounted) return;
    final spec = stem == null ? null : Nav.spec(stem);
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      settings: RouteSettings(name: spec?.stem),
      transitionDuration: const Duration(milliseconds: 700),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, __, ___) => spec == null ? const LauncherScreen() : spec.builder(context),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: const Interval(0.15, 1, curve: Curves.easeOut)),
        child: child,
      ),
    ));
    // A notification tapped while the app was closed opens once the first screen shows.
    if (spec != null) Future.delayed(const Duration(milliseconds: 900), Push.I.flushPending);
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _c.dispose();
    for (final i in [_dark, _heart, _flow]) {
      i?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: MP.white,
      ),
      child: Semantics(
        label: 'MedPin, Care Connected',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _skip,
          child: ColoredBox(
            color: MP.white,
            child: LayoutBuilder(builder: (context, box) {
              if (_dark == null) return const SizedBox.expand();
              return AnimatedBuilder(
                animation: _c,
                builder: (context, _) => _frame(box.biggest),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _frame(Size screen) {
    final t = _c.value;

    // Final lockup: the logo as it appears in headers, centred on screen.
    final lockW = (screen.width - 96).clamp(180.0, 264.0);
    final lockH = lockW * 36 / 97; // MpLogo's box ratio, so the Hero matches it
    final s = lockW / _logoW; // contain → width-limited (1646/609 > 97/36)
    final lock = Rect.fromCenter(center: screen.center(Offset.zero), width: lockW, height: lockH);
    final imgTop = lock.top + (lockH - _logoH * s) / 2;
    final markEnd = Rect.fromLTWH(lock.left + _markLeft * s, imgTop + _markTop * s, _markW * s, _markH * s);
    final wordRect = Rect.fromLTWH(lock.left + _wordLeft * s, imgTop, _wordW * s, _logoH * s);

    // While drawing, the mark sits large in the middle of the screen.
    final bigW = (screen.width * 0.38).clamp(112.0, 148.0);
    final markStart = Rect.fromCenter(center: screen.center(Offset.zero), width: bigW, height: bigW * _markH / _markW);
    final mark = Rect.lerp(markStart, markEnd, _lockup.transform(t))!;

    // Once everything has settled, show the real logo image inside the Hero
    // (pixel-identical to the layers above) so it can fly to the launcher.
    if (t >= 0.93) {
      return Stack(children: [
        Positioned.fromRect(
          rect: lock,
          child: Hero(
            tag: kLogoHeroTag,
            child: Image.asset(_logo, fit: BoxFit.contain, gaplessPlayback: true),
          ),
        ),
      ]);
    }

    final glow = _glowIn.transform(t) * (1 - _glowOut.transform(t));
    final word = _word.transform(t);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Soft brand-tinted halo behind the mark while it draws.
        if (glow > 0)
          Positioned.fromRect(
            rect: Rect.fromCenter(center: mark.center, width: mark.width * 2.2, height: mark.width * 2.2),
            child: Opacity(
              opacity: glow * 0.9,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0xFFEBF1FB), Color(0x00EBF1FB)],
                    stops: [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
        if (word > 0)
          Positioned.fromRect(
            rect: wordRect.shift(Offset(12 * (1 - word), 0)),
            child: Opacity(
              opacity: word.clamp(0.0, 1.0),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => LinearGradient(
                  colors: const [Colors.white, Colors.white, Color(0x00FFFFFF)],
                  stops: [0, (word * 1.15 - 0.08).clamp(0.0, 1.0), (word * 1.15).clamp(0.0, 1.0)],
                ).createShader(r),
                child: Image.asset(_wordmark, fit: BoxFit.fill, gaplessPlayback: true),
              ),
            ),
          ),
        Positioned.fromRect(
          rect: mark,
          child: CustomPaint(
            painter: _MarkPainter(
              program: _reveal,
              dark: _dark!,
              heart: _heart!,
              flow: _flow!,
              reveal: _draw.transform(t) * (1 + 2 / _MarkPainter.k) - 1 / _MarkPainter.k,
              heartScale: _beatScale.transform(_beat.transform(t)),
              ripple: t < _ripple.begin ? 0 : _ripple.transform(t),
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints the mark from the logo's own pixels, revealed along the strokes by
/// the flow map (each pixel's R = when it appears), plus the heart beat and
/// its ripple.
class _MarkPainter extends CustomPainter {
  final ui.FragmentProgram? program;
  final ui.Image dark, heart, flow;
  final double reveal, heartScale, ripple;
  _MarkPainter({
    required this.program,
    required this.dark,
    required this.heart,
    required this.flow,
    required this.reveal,
    required this.heartScale,
    required this.ripple,
  });

  /// Softness of the drawing edge: it fades in over 1/k of the timeline.
  static const k = 26.0;

  /// alpha = k · (reveal − flow), so pixels whose time has come show up with a
  /// soft leading edge. Only alpha matters (the map is used with dstIn).
  static ColorFilter _mask(double reveal) => ColorFilter.matrix(<double>[
        0, 0, 0, 0, 0, //
        0, 0, 0, 0, 0, //
        0, 0, 0, 0, 0, //
        -k, 0, 0, 0, k * 255 * reveal,
      ]);

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final src = Rect.fromLTWH(0, 0, dark.width.toDouble(), dark.height.toDouble());
    final image = Paint()..filterQuality = FilterQuality.medium;
    final done = reveal >= 1 + 1 / k;

    void layer(ui.Image im) {
      if (done) {
        canvas.drawImageRect(im, src, dst, image);
        return;
      }
      final p = program;
      if (p != null) {
        // Shader reveal: one draw, no offscreen layer or blend modes.
        final shader = p.fragmentShader()
          ..setFloat(0, size.width)
          ..setFloat(1, size.height)
          ..setFloat(2, reveal)
          ..setFloat(3, k)
          ..setImageSampler(0, im)
          ..setImageSampler(1, flow);
        canvas.drawRect(dst, Paint()..shader = shader);
        shader.dispose();
        return;
      }
      // Fallback: alpha mask via dstIn (renders wrongly on some Impeller GPUs).
      canvas.saveLayer(dst.inflate(2), Paint());
      canvas.drawImageRect(im, src, dst, image);
      canvas.drawImageRect(
        flow,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = BlendMode.dstIn
          ..colorFilter = _mask(reveal),
      );
      canvas.restore();
    }

    // The ripple goes out from behind the mark.
    final hc = Offset(size.width * _heartCx, size.height * _heartCy);
    if (ripple > 0 && ripple < 1) {
      final r = size.width * _heartR * (1.0 + 0.75 * ripple);
      canvas.drawCircle(
        hc,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 + 2.0 * (1 - ripple)
          ..color = _heartBlue.withValues(alpha: 0.42 * (1 - ripple)),
      );
    }

    layer(dark);

    canvas.save();
    canvas.translate(hc.dx, hc.dy);
    canvas.scale(heartScale);
    canvas.translate(-hc.dx, -hc.dy);
    layer(heart);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.reveal != reveal || old.heartScale != heartScale || old.ripple != ripple || old.dark != dark;
}
