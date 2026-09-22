import 'package:shared_preferences/shared_preferences.dart';
import 'drivers/tv_driver.dart';

/// Serviço de persistência local para salvar parâmetros de conexão e chave de pareamento.
class StorageService {
  static const String _keyIp = 'pref_tv_ip';
  static const String _keyMac = 'pref_tv_mac';
  static const String _keyClientKey = 'pref_tv_client_key';
  static const String _keyThemeMode = 'pref_app_theme_mode';
  static const String _keyTvName = 'pref_tv_name';
  static const String _keyBrand = 'pref_tv_brand';
  static const String _keyHapticFeedback = 'pref_haptic_feedback_enabled';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  String getIpAddress({String defaultValue = '192.168.1.150'}) {
    return _prefs?.getString(_keyIp) ?? defaultValue;
  }

  Future<bool> setIpAddress(String ip) async {
    await init();
    return await _prefs?.setString(_keyIp, ip) ?? false;
  }

  String? getTvName() {
    return _prefs?.getString(_keyTvName);
  }

  Future<bool> setTvName(String? name) async {
    await init();
    if (name == null || name.isEmpty) {
      return await _prefs?.remove(_keyTvName) ?? false;
    }
    return await _prefs?.setString(_keyTvName, name) ?? false;
  }

  String getMacAddress({String defaultValue = 'A4:77:33:B2:9C:10'}) {
    return _prefs?.getString(_keyMac) ?? defaultValue;
  }

  Future<bool> setMacAddress(String mac) async {
    await init();
    return await _prefs?.setString(_keyMac, mac) ?? false;
  }

  String? getClientKey({TvBrand? brand, String? ip}) {
    if (brand != null) {
      if (ip != null && ip.isNotEmpty) {
        final ipKey = '${_keyClientKey}_${brand.id}_$ip';
        final val = _prefs?.getString(ipKey);
        if (val != null && val.isNotEmpty) return val;
      }
      final brandKey = '${_keyClientKey}_${brand.id}';
      final val = _prefs?.getString(brandKey);
      if (val != null && val.isNotEmpty) return val;
    }
    // Fallback para chave legada apenas se for LG ou não especificada
    if (brand == null || brand == TvBrand.lgWebOs) {
      return _prefs?.getString(_keyClientKey);
    }
    return null;
  }

  Future<bool> setClientKey(String? key, {TvBrand? brand, String? ip}) async {
    await init();
    if (brand != null) {
      if (ip != null && ip.isNotEmpty) {
        final ipKey = '${_keyClientKey}_${brand.id}_$ip';
        if (key == null || key.isEmpty) {
          await _prefs?.remove(ipKey);
        } else {
          await _prefs?.setString(ipKey, key);
        }
      }
      final brandKey = '${_keyClientKey}_${brand.id}';
      if (key == null || key.isEmpty) {
        return await _prefs?.remove(brandKey) ?? false;
      }
      return await _prefs?.setString(brandKey, key) ?? false;
    }
    if (key == null || key.isEmpty) {
      return await _prefs?.remove(_keyClientKey) ?? false;
    }
    return await _prefs?.setString(_keyClientKey, key) ?? false;
  }

  String getThemeMode({String defaultValue = 'dark'}) {
    return _prefs?.getString(_keyThemeMode) ?? defaultValue;
  }

  Future<bool> setThemeMode(String mode) async {
    await init();
    return await _prefs?.setString(_keyThemeMode, mode) ?? false;
  }

  bool getHapticFeedbackEnabled({bool defaultValue = true}) {
    return _prefs?.getBool(_keyHapticFeedback) ?? defaultValue;
  }

  Future<bool> setHapticFeedbackEnabled(bool enabled) async {
    await init();
    return await _prefs?.setBool(_keyHapticFeedback, enabled) ?? false;
  }

  TvBrand? _cachedBrand;

  TvBrand getBrand({TvBrand defaultValue = TvBrand.lgWebOs}) {
    if (_cachedBrand != null) return _cachedBrand!;
    final raw = _prefs?.getString(_keyBrand);
    if (raw == null) return defaultValue;
    return TvBrand.values.firstWhere(
      (b) => b.name == raw || b.id == raw,
      orElse: () => defaultValue,
    );
  }

  Future<bool> setBrand(TvBrand brand) async {
    _cachedBrand = brand;
    await init();
    return await _prefs?.setString(_keyBrand, brand.name) ?? false;
  }
}
