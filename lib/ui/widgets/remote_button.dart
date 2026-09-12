import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// Botão modular estilizado para o controle remoto desktop.
///
/// Oferece suporte a feedback visual imediato (highlight e splash sutil),
/// acionamento de [HapticFeedback.selectionClick] e estados de hover desktop.
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
  });

  void _handlePress() {
    // Chamada nativa estruturada para resposta tátil multiplataforma
    HapticFeedback.selectionClick();
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
