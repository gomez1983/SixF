import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Componentes do padrão visual Payno (ver `docs/design/mockups/`):
/// fundo ambiente, card com cabeçalho, barra hachurada e número em destaque.

/// Fundo cinza-azulado com a mancha azul-aço difusa no topo da tela.
class PaynoBackdrop extends StatelessWidget {
  const PaynoBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.ambientPrimaryOf(context);
    final secondary = AppColors.ambientSecondaryOf(context);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(color: AppColors.backgroundOf(context)),
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            Widget blob(double left, double top, double size, Color c) =>
                Positioned(
                  left: left - size / 2,
                  top: top - size / 2,
                  width: size,
                  height: size,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [c, c.withValues(alpha: 0)],
                        stops: const [0, 1],
                      ),
                    ),
                  ),
                );
            final base = w < h ? w : h;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                blob(w * 0.38, h * 0.04, base * 1.25, primary),
                blob(w * 0.66, -h * 0.02, base * 0.95, secondary),
                blob(w * 0.12, -h * 0.04, base * 0.8, secondary),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Card translúcido com cabeçalho opcional (ícone, título e ação à direita),
/// equivalente aos cards "Available Balance", "Upcoming Payments" etc.
class PaynoCard extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double headerGap;

  const PaynoCard({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
    this.radius = 20,
    this.headerGap = 12,
  });

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || trailing != null;
    return Container(
      padding: padding,
      decoration: AppColors.paynoCardDecoration(context, radius: radius),
      child: hasHeader
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                PaynoCardHeader(title: title, icon: icon, trailing: trailing),
                SizedBox(height: headerGap),
                Flexible(fit: FlexFit.loose, child: child),
              ],
            )
          : child,
    );
  }
}

class PaynoCardHeader extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget? trailing;

  const PaynoCardHeader({super.key, this.title, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AppColors.textMutedOf(context)),
          const SizedBox(width: 8),
        ],
        if (title != null)
          Expanded(
            child: Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ),
        if (title == null) const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// Número grande e fino com unidade pequena ao lado ("24 /100").
class PaynoBigValue extends StatelessWidget {
  final String value;
  final String? unit;
  final double size;

  const PaynoBigValue(this.value, {super.key, this.unit, this.size = 38});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: size,
              height: 1.0,
              fontWeight: FontWeight.w300,
              letterSpacing: -size * 0.03,
              color: AppColors.textPrimaryOf(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (unit != null) ...[
            const SizedBox(width: 5),
            Text(
              unit!,
              style: TextStyle(
                fontSize: (size * 0.36).clamp(10, 16),
                color: AppColors.textMutedOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Barra de progresso com o preenchimento hachurado em diagonal.
class PaynoHatchedBar extends StatelessWidget {
  final double value;
  final double height;

  const PaynoHatchedBar({super.key, required this.value, this.height = 10});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.isDark(context)
        ? const Color(0xFF86A5DC)
        : const Color(0xFF4A6698);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceInteractiveOf(context),
        borderRadius: BorderRadius.circular(height),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            heightFactor: 1,
            child: CustomPaint(painter: _HatchPainter(color)),
          ),
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  final Color color;
  _HatchPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (double x = -size.height; x < size.width + size.height; x += 4.5) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.drawLine(
      Offset(size.width - 1, 0),
      Offset(size.width - 1, size.height),
      paint..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}

/// Botão circular com rótulo abaixo (padrão "Quick Actions").
class PaynoActionCircle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double size;
  final bool filled;

  const PaynoActionCircle({
    super.key,
    required this.icon,
    required this.label,
    this.tooltip,
    this.onPressed,
    this.size = 48,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppColors.textPrimaryOf(context);
    Widget circle = Material(
      color: filled ? AppColors.accentFillOf(context) : AppColors.circleOf(context),
      shape: CircleBorder(
        side: BorderSide(
          color: filled ? Colors.transparent : AppColors.borderSubtleOf(context),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.42, color: fg),
        ),
      ),
    );
    circle = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppColors.softShadowOf(context),
      ),
      child: circle,
    );
    if (tooltip != null) circle = Tooltip(message: tooltip!, child: circle);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        const SizedBox(height: 7),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.3,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
      ],
    );
  }
}

/// Chip discreto (tag de status, fonte, filtro).
class PaynoChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final bool accent;
  final VoidCallback? onTap;

  const PaynoChip(
    this.label, {
    super.key,
    this.icon,
    this.selected = false,
    this.accent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? Colors.white
        : accent
        ? AppColors.iconHighlightOf(context)
        : AppColors.textMutedOf(context);
    final bg = selected
        ? AppColors.accentFillOf(context)
        : accent
        ? AppColors.accentSoftOf(context)
        : AppColors.surfaceInteractiveOf(context);
    return Material(
      color: bg,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected || accent
              ? Colors.transparent
              : AppColors.borderSubtleOf(context),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 5),
              ],
              Text(label, style: TextStyle(fontSize: 11, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logotipo circular do SixF (fundo azul-marinho do ícone do app).
class PaynoLogo extends StatelessWidget {
  final double size;
  const PaynoLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1B0D4D),
        boxShadow: [
          BoxShadow(
            color: AppColors.lightAccentFill.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/icons/SixF_Logo_01.png',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
