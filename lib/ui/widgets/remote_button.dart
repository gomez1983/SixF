import 'package:flutter/material.dart';
import '../../services/haptic_service.dart';
import '../theme/app_colors.dart';

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

/// Botão modular estilizado para o controle remoto universal SixF.
///
/// Oferece suporte a feedback visual imediato (highlight e splash sutil),
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
    this.borderRadius = 12,
    this.padding,
    this.isSelected = false,
    this.isCircular = false,
    this.hapticType = HapticType.light,
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

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.surfaceInteractiveOf(context);
    final fg = foregroundColor ?? AppColors.textPrimaryOf(context);
    final border = borderColor ?? (isSelected ? AppColors.iconHighlightOf(context) : AppColors.borderSubtleOf(context));

    final shape = customShape ??
        (isCircular
            ? const CircleBorder()
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
        style: TextStyle(
          color: fg,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      );
    } else {
      content = const SizedBox.shrink();
    }

    final buttonCore = Material(
      color: isSelected ? AppColors.surfaceElevatedOf(context) : bg,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed != null ? _handlePress : null,
        hoverColor: AppColors.surfaceInteractiveHoverOf(context),
        splashColor: (foregroundColor ?? AppColors.iconHighlightOf(context)).withValues(alpha: 0.2),
        highlightColor: (foregroundColor ?? AppColors.iconHighlightOf(context)).withValues(alpha: 0.1),
        customBorder: shape,
        child: Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(8),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: content,
          ),
        ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(
        message: tooltip!,
        child: buttonCore,
      );
    }

    return buttonCore;
  }
}
