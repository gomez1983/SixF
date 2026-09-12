import 'package:shared_preferences/shared_preferences.dart';

/// Serviço de persistência local para salvar parâmetros de conexão e chave de pareamento.
class StorageService {
  static const String _keyIp = 'pref_tv_ip';
  static const String _keyMac = 'pref_tv_mac';
  static const String _keyClientKey = 'pref_tv_client_key';
  static const String _keyThemeMode = 'pref_app_theme_mode';
  static const String _keyTvName = 'pref_tv_name';

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

  String? getClientKey() {
    return _prefs?.getString(_keyClientKey);
  }

  Future<bool> setClientKey(String? key) async {
    await init();
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
}
