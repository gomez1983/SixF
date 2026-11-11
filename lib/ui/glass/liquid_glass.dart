import 'dart:ui';

import 'package:flutter/material.dart';

import '../../services/haptic_service.dart';
import '../widgets/repeat_press.dart';

/// Tokens de cor do estilo "Liquid Glass" (iOS 26) para os dois brilhos.
///
/// Protótipo isolado: não depende de [AppColors] nem do RemoteController, para
/// poder ser avaliado (e depois adotado aos poucos) sem tocar no app atual.
class GlassTokens {
  const GlassTokens._({
    required this.fill,
    required this.fillStrong,
    required this.rimLight,
    required this.rimDark,
    required this.shadow,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.accent,
    required this.tintBlue,
    required this.tintRed,
    required this.tabFill,
    required this.success,
  });

  final Color fill;
  final Color fillStrong;
  final Color rimLight;
  final Color rimDark;
  final Color shadow;
  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color accent;
  final Color tintBlue;
  final Color tintRed;
  final Color tabFill;
  final Color success;

  static const dark = GlassTokens._(
    fill: Color(0x14FFFFFF),
    fillStrong: Color(0x24FFFFFF),
    rimLight: Color(0x8CFFFFFF),
    rimDark: Color(0x14FFFFFF),
    shadow: Color(0x59000000),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0x9EEBEBF5),
    tertiaryLabel: Color(0x57EBEBF5),
    accent: Color(0xFF0A84FF),
    tintBlue: Color(0x610A84FF),
    tintRed: Color(0x80FF453A),
    tabFill: Color(0x61282A3C),
    success: Color(0xFF30D158),
  );

  static const light = GlassTokens._(
    fill: Color(0x6BFFFFFF),
    fillStrong: Color(0x99FFFFFF),
    rimLight: Color(0xF2FFFFFF),
    rimDark: Color(0x59FFFFFF),
    shadow: Color(0x2E3C4678),
    label: Color(0xFF101319),
    secondaryLabel: Color(0xA83C3C43),
    tertiaryLabel: Color(0x5C3C3C43),
    accent: Color(0xFF0A84FF),
    tintBlue: Color(0x380A84FF),
    tintRed: Color(0x33FF453A),
    tabFill: Color(0x80FFFFFF),
    success: Color(0xFF30D158),
  );

  static GlassTokens of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Forma padrão dos cartões: cantos contínuos (superelipse), como no iOS.
ShapeBorder glassRounded(double radius) => RoundedSuperellipseBorder(
  borderRadius: BorderRadius.all(Radius.circular(radius)),
);

/// Vidro "leve" para cartões, listas e grades: véu translúcido, reflexo e
/// borda de luz, sem [BackdropFilter]. É o que o [AppColors] devolve no modo
/// Liquid Glass para as superfícies de conteúdo.
BoxDecoration glassFlatDecoration(
  BuildContext context, {
  double radius = 18,
  bool strong = false,
}) {
  final t = GlassTokens.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    color: strong ? t.fillStrong : t.fill,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: dark ? 0.12 : 0.5),
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: dark ? 0.04 : 0.2),
      ],
      stops: const [0, 0.4, 0.7, 1],
    ),
    border: Border.all(
      color: t.rimLight.withValues(alpha: dark ? 0.28 : 0.85),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: t.shadow.withValues(alpha: t.shadow.a * 0.6),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

/// Superfície de vidro: desfoca o que está atrás, aplica um véu translúcido,
/// um reflexo de luz e uma borda de brilho (mais clara no canto superior
/// esquerdo). É a aproximação em Flutter do Liquid Glass; a refração real do
/// iOS 26 só existe nativamente.
///
/// Evite aninhar vários [LiquidGlass]: cada um cria um [BackdropFilter].
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    this.child,
    this.shape,
    this.tint,
    this.blurSigma = 18,
    this.strong = false,
    this.shadow = true,
    this.blur = true,
    this.padding,
    this.width,
    this.height,
  });

  final Widget? child;

  /// Desligue em botões e itens de lista: sobre o fundo liso o desfoque não
  /// muda a aparência e dezenas de [BackdropFilter] pesariam no celular.
  final bool blur;

  /// Padrão: superelipse de raio 22.
  final ShapeBorder? shape;

  /// Cor sobreposta ao véu (ex.: azul do sistema para o item ativo).
  final Color? tint;
  final double blurSigma;
  final bool strong;
  final bool shadow;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    final shape = this.shape ?? glassRounded(22);
    final base = strong ? t.fillStrong : t.fill;
    final fill = tint == null ? base : Color.alphaBlend(tint!, base);
    final dark = Theme.of(context).brightness == Brightness.dark;

    // ShapeDecoration não aceita cor e gradiente juntos: duas camadas.
    Widget content = DecoratedBox(
      decoration: ShapeDecoration(shape: shape, color: fill),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: dark ? 0.16 : 0.55),
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: dark ? 0.05 : 0.22),
            ],
            stops: const [0, 0.38, 0.7, 1],
          ),
        ),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );

    content = CustomPaint(
      foregroundPainter: _RimPainter(shape, t.rimLight, t.rimDark),
      child: content,
    );

    if (blur) {
      content = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
          tileMode: TileMode.clamp,
        ),
        child: content,
      );
    }

    content = ClipPath(clipper: ShapeBorderClipper(shape: shape), child: content);

    return Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(
        shape: shape,
        shadows: shadow
            ? [
                BoxShadow(
                  color: t.shadow,
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: content,
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter(this.shape, this.light, this.dark);

  final ShapeBorder shape;
  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [light, dark, dark, light.withValues(alpha: light.a * 0.35)],
        stops: const [0, 0.35, 0.65, 1],
      ).createShader(rect);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.shape != shape || old.light != light || old.dark != dark;
}

/// Toque com resposta de "mola".
///
/// Sem [builder] (botões sem vidro próprio) encolhe levemente. Com [builder],
/// o filho decide como reagir ao [pressed]; use [pressedScale] > 1 para o
/// efeito do iOS 26, em que o vidro "incha" e se inclina na direção do dedo
/// ([lean] é a fração do tamanho do botão que ele desloca).
class GlassTap extends StatefulWidget {
  const GlassTap({
    super.key,
    required this.onPressed,
    this.child,
    this.builder,
    this.pressedScale = 0.94,
    this.lean = 0,
    this.haptic = true,
    this.semanticLabel,
    this.onLongPress,
  }) : assert(child != null || builder != null);

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Widget? child;
  final Widget Function(BuildContext context, bool pressed)? builder;
  final double pressedScale;
  final double lean;
  final bool haptic;
  final String? semanticLabel;

  @override
  State<GlassTap> createState() => _GlassTapState();
}

class _GlassTapState extends State<GlassTap> {
  bool _down = false;
  Offset _lean = Offset.zero;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  void _onDown(TapDownDetails d) {
    final box = context.findRenderObject();
    if (widget.lean > 0 && box is RenderBox && box.hasSize) {
      final half = box.size.center(Offset.zero);
      final v = d.localPosition - half;
      _lean = Offset(
        (v.dx / half.dx).clamp(-1.0, 1.0) * widget.lean,
        (v.dy / half.dy).clamp(-1.0, 1.0) * widget.lean,
      );
    }
    _set(true);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.builder != null
        ? widget.builder!(context, _down)
        : AnimatedOpacity(
            opacity: _down ? 0.82 : 1,
            duration: const Duration(milliseconds: 100),
            child: widget.child,
          );
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onPressed == null ? null : _onDown,
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onLongPress: widget.onLongPress,
        onTap: widget.onPressed == null
            ? null
            : () {
                // Respeita a preferência de vibração do usuário.
                if (widget.haptic) HapticService.buttonPress();
                widget.onPressed!();
              },
        child: AnimatedSlide(
          offset: _down ? _lean : Offset.zero,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: _down ? widget.pressedScale : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Repete a ação enquanto o dedo estiver pressionado (volume, canal, setas),
/// reaproveitando o [RepeatPress] do app. Só repete com o aparelho conectado e
/// para sozinho se o aparelho ativo mudar ([token]).
class GlassRepeat extends StatelessWidget {
  const GlassRepeat({
    super.key,
    required this.enabled,
    required this.onRepeat,
    required this.token,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onRepeat;
  final Object? token;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return RepeatPress(
      sessionToken: token,
      onRepeat: () {
        HapticService.buttonPress();
        onRepeat();
      },
      child: child,
    );
  }
}

/// Botão de vidro: [LiquidGlass] + [GlassTap]. Ao pressionar, o vidro cresce,
/// clareia e se inclina para o ponto tocado.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.shape,
    this.tint,
    this.strong = false,
    this.width,
    this.height,
    this.semanticLabel,
    this.onLongPress,
  });

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Widget child;
  final ShapeBorder? shape;
  final Color? tint;
  final bool strong;
  final double? width;
  final double? height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return GlassTap(
      onPressed: onPressed,
      onLongPress: onLongPress,
      semanticLabel: semanticLabel,
      pressedScale: 1.07,
      lean: 0.06,
      builder: (context, pressed) => LiquidGlass(
        shape: shape,
        tint: tint,
        strong: strong || pressed,
        width: width,
        height: height,
        child: Center(child: child),
      ),
    );
  }
}

/// Fundo ambiente: o vidro só aparece de verdade sobre algo colorido.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _BackdropPainter(dark),
      child: child ?? const SizedBox.expand(),
    );
  }
}

class _Blob {
  const _Blob(this.dx, this.dy, this.radius, this.color);
  final double dx; // fração da largura
  final double dy; // fração da altura
  final double radius; // em larguras
  final Color color;
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.dark);

  final bool dark;

  static const _darkBlobs = [
    _Blob(0.12, 0.08, 0.66, Color(0xBF0A84FF)),
    _Blob(1.00, 0.38, 0.76, Color(0x525E5CE6)),
    _Blob(0.00, 0.70, 0.71, Color(0x7338BDF8)),
    _Blob(0.90, 1.00, 0.81, Color(0x66BF5AF2)),
  ];
  static const _lightBlobs = [
    _Blob(0.10, 0.06, 0.71, Color(0xF278BEFF)),
    _Blob(1.00, 0.40, 0.76, Color(0xCCBEAAFF)),
    _Blob(0.00, 0.72, 0.76, Color(0xD996E1FF)),
    _Blob(0.95, 1.00, 0.81, Color(0xB3FFBEE1)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF0B0D1C), Color(0xFF0F1226), Color(0xFF0A0B17)]
              : const [Color(0xFFE9F0FF), Color(0xFFEEF0FB), Color(0xFFE6EBFA)],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
    for (final b in dark ? _darkBlobs : _lightBlobs) {
      final center = Offset(b.dx * size.width, b.dy * size.height);
      final radius = b.radius * size.width;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [b.color, b.color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.dark != dark;
}
