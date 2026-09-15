import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../../services/drivers/tv_driver.dart';
import '../theme/app_colors.dart';

/// Diálogo modal moderno para inserção do código PIN de pareamento exibido na tela da TV.
class PairingPinDialog extends StatefulWidget {
  const PairingPinDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PairingPinDialog(),
    );
  }

  @override
  State<PairingPinDialog> createState() => _PairingPinDialogState();
}

class _PairingPinDialogState extends State<PairingPinDialog> {
  late final TextEditingController _pinController;
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _pinController = TextEditingController();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submitPin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final controller = context.read<RemoteController>();
    final pin = _pinController.text.trim();

    try {
      await controller.sendPairingPin(pin);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final brandName = controller.currentBrand.displayName;

    return Dialog(
      backgroundColor: AppColors.remoteChassisOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.borderSubtleOf(context)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevatedOf(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.pin_outlined,
                    color: AppColors.iconHighlightOf(context),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Pareamento $brandName',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Digite o código PIN que está sendo exibido na tela da sua TV:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _pinController,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    hintText: 'PIN',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondaryOf(context).withValues(alpha: 0.4),
                      letterSpacing: 4,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceCardOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.borderSubtleOf(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.borderSubtleOf(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.iconHighlightOf(context), width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor, digite o PIN da TV';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submitPin(),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                controller.disconnect();
                                Navigator.of(context).pop();
                              },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: AppColors.borderSubtleOf(context)),
                        ),
                        child: Text(
                          'Cancelar',
                          style: TextStyle(color: AppColors.textSecondaryOf(context)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitPin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.iconHighlightOf(context),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                ),
                              )
                            : const Text(
                                'Confirmar',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
