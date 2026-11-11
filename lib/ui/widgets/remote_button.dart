import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/haptic_service.dart';
import '../glass/glass_flags.dart';
import '../glass/liquid_glass.dart';
import '../theme/app_colors.dart';
import 'repeat_press.dart';

/// Intensidade e padrão do feedback háptico (vibração) ao pressionar um botão.
enum HapticType {
  /// Clique leve de impacto mecânico (padrão ergonômico para teclas).
  light,

  /// Impacto médio com pulso mais firme (ações primárias como Power).
  medium,

  /// Clique sutil e discreto (seleções secundárias ou abas).
  selection,

  /// Sem vibração.
  none,
}

/// Botão modular com acabamento Liquid Glass para o controle remoto universal SixF.
///
/// Oferece suporte a feedback visual imediato (gradiente vítreo, reflexo superior e splash sutil),
/// resposta tátil de vibração via [HapticService] e estados de hover desktop.
class RemoteButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget? child;
  final IconData? icon;
  final String? label;
  final String? tooltip;
  final double? width;
  final double? height;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final ShapeBorder? customShape;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool isSelected;
  final bool isCircular;
  final HapticType hapticType;
  final bool repeatOnHold;
  final Object? repeatToken;

  const RemoteButton({
    super.key,
    required this.onPressed,
    this.child,
    this.icon,
    this.label,
    this.tooltip,
    this.width,
    this.height,
    this.iconSize = 20,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.customShape,
    this.borderRadius = 13,
    this.padding,
    this.isSelected = false,
    this.isCircular = false,
    this.hapticType = HapticType.light,
    this.repeatOnHold = false,
    this.repeatToken,
  });

  void _handlePress() {
    switch (hapticType) {
      case HapticType.light:
        HapticService.buttonPress();
        break;
      case HapticType.medium:
        HapticService.heavyPress();
        break;
      case HapticType.selection:
        HapticService.selectionClick();
        break;
      case HapticType.none:
        break;
    }
    onPressed?.call();
  }

  Widget _buildGlass(BuildContext context, Widget content) {
    final t = GlassTokens.of(context);
    final bg = backgroundColor;
    // Fundos neutros (padrão, superfícies do tema, transparente) viram vidro
    // simples; fundos coloridos (botões de cor, Mudo ativo...) viram vidro
    // tingido com a mesma cor.
    final neutral =
        bg == null ||
        bg.a == 0 ||
        bg == AppColors.surfaceInteractiveOf(context) ||
        bg == AppColors.surfaceElevatedOf(context);
    final tint = isSelected
        ? t.tintBlue
        : (neutral ? null : bg.withValues(alpha: math.min(bg.a * 1.9, 0.55)));
    final ShapeBorder shape = customShape ??
        (isCircular
            ? const CircleBorder()
            : glassRounded(math.min(borderRadius * 1.5 + 2, (height ?? 999) / 2)));

    Widget core = GlassTap(
      onPressed: onPressed == null ? null : _handlePress,
      haptic: false, // _handlePress já vibra conforme [hapticType].
      pressedScale: 1.06,
      lean: 0.05,
      semanticLabel: tooltip,
      builder: (context, pressed) => Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: LiquidGlass(
          shape: shape,
          tint: tint,
          strong: pressed,
          blur: false,
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(8),
          child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: content)),
        ),
      ),
    );
    if (repeatOnHold && onPressed != null) {
      core = RepeatPress(
        onRepeat: _handlePress,
        sessionToken: repeatToken,
        child: core,
      );
    }
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: core);
    }
    return core;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final bg = backgroundColor ?? AppColors.surfaceInteractiveOf(context);
    final fg = foregroundColor ??
        (isSelected
            ? AppColors.iconHighlightOf(context)
            : AppColors.textPrimaryOf(context));
    final border = borderColor ??
        (isSelected
            ? AppColors.iconHighlightOf(context).withValues(alpha: isDark ? 0.55 : 0.65)
            : AppColors.borderSubtleOf(context));

    final isTransparent = bg.a == 0 && (borderColor?.a ?? 1) == 0;

    final shape = customShape ??
        (isCircular
            ? CircleBorder(side: BorderSide(color: border, width: 1))
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius),
                side: BorderSide(color: border, width: 1),
              ));

    Widget content;
    if (child != null) {
      content = child!;
    } else if (icon != null && label != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: iconSize, color: fg),
          const SizedBox(height: 2),
          Text(
            label!,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    } else if (icon != null) {
      content = Icon(icon, size: iconSize, color: fg);
    } else if (label != null) {
      content = Text(
        label!,
        style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      );
    } else {
      content = const SizedBox.shrink();
    }

    // Modo Liquid Glass (experimental): mesmo botão, mesmas ações, outro visual.
    if (kGlassUi) {
      return _buildGlass(context, content);
    }

    Gradient? glassGradient;
    List<BoxShadow>? glassShadows;

    if (!isTransparent) {
      if (isSelected) {
        glassGradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0x4038BDF8), Color(0x350EA5E9), Color(0x240E8FF1)]
              : const [Color(0xE8FFFFFF), Color(0x48BAE6FD), Color(0x300EA5E9)],
        );
        glassShadows = [
          BoxShadow(
            color: isDark ? const Color(0x28000000) : const Color(0x1E0284C7),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ];
      } else if (backgroundColor == null) {
        glassGradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF342E44), Color(0xFF272234)]
              : const [Color(0xFAFFFFFF), Color(0xE8F1ECF9)],
        );
        glassShadows = [
          BoxShadow(
            color: isDark ? const Color(0x26000000) : const Color(0x0A48406C),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];
      }
    }

    Widget buttonCore = DecoratedBox(
      decoration: BoxDecoration(
        shape: isCircular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircular ? null : BorderRadius.circular(borderRadius),
        gradient: glassGradient,
        color: glassGradient == null ? bg : null,
        boxShadow: glassShadows,
      ),
      child: Material(
        color: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed != null ? _handlePress : null,
          hoverColor: AppColors.surfaceInteractiveHoverOf(context),
          splashColor: (foregroundColor ?? AppColors.iconHighlightOf(context))
              .withValues(alpha: 0.18),
          highlightColor: (foregroundColor ?? AppColors.iconHighlightOf(context))
              .withValues(alpha: 0.10),
          customBorder: shape,
          child: Container(
            width: width,
            height: height,
            padding: padding ?? const EdgeInsets.all(8),
            alignment: Alignment.center,
            child: FittedBox(fit: BoxFit.scaleDown, child: content),
          ),
        ),
      ),
    );

    if (repeatOnHold && onPressed != null) {
      buttonCore = RepeatPress(
        onRepeat: _handlePress,
        sessionToken: repeatToken,
        child: buttonCore,
      );
    }

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: buttonCore);
    }

    return buttonCore;
  }
}
