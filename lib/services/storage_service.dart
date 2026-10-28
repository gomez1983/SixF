import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_device.dart';
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
  static const String _keySavedDevices = 'pref_saved_devices_v1';
  static const String _keyActiveDeviceId = 'pref_active_device_id';

  SharedPreferences? _prefs;

  Future<void>? _initializing;

  Future<void> init() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    if (_prefs!.getBool('pref_client_keys_migrated_v2') == true) return;

    // Só o cadastro legado de um único aparelho permite atribuição inequívoca.
    final ip = _prefs!.getString(_keyIp);
    final brand = getBrand();
    if (_prefs!.getString(_keySavedDevices) == null && ip != null && ip.isNotEmpty) {
      final target = '${_keyClientKey}_${brand.id}_$ip';
      final legacy = _prefs!.getString('${_keyClientKey}_${brand.id}') ??
          (brand == TvBrand.lgWebOs ? _prefs!.getString(_keyClientKey) : null);
      if (!_prefs!.containsKey(target) && legacy != null && legacy.isNotEmpty) {
        await _prefs!.setString(target, legacy);
      }
    }
    for (final brand in TvBrand.values) {
      await _prefs!.remove('${_keyClientKey}_${brand.id}');
    }
    await _prefs!.remove(_keyClientKey);
    await _prefs!.setBool('pref_client_keys_migrated_v2', true);
  }

  bool getBackButtonOnRight() => _prefs?.getBool('back_button_on_right') ?? false;
  Future<void> setBackButtonOnRight(bool value) async { await init(); await _prefs!.setBool('back_button_on_right',value); }
  String? getVolumeTarget(String deviceId) => _prefs?.getString('volume_target_$deviceId');
  Future<void> setVolumeTarget(String deviceId, String targetId) async {
    await init(); await _prefs!.setString('volume_target_$deviceId',targetId);
  }
  Set<String> getFavoriteApps(String deviceId, TvBrand brand) =>
      (_prefs?.getStringList('pref_favorites_${brand.id}_$deviceId') ?? []).toSet();

  Future<void> setFavoriteApps(String deviceId, TvBrand brand, Set<String> apps) async {
    await init();
    await _prefs!.setStringList('pref_favorites_${brand.id}_$deviceId', apps.toList()..sort());
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

  String? getClientKey({TvBrand? brand, String? ip, String? deviceId}) {
    final resolvedBrand = brand ?? getBrand();
    if (deviceId != null && deviceId.isNotEmpty) {
      final byId = _prefs?.getString('${_keyClientKey}_id_${resolvedBrand.id}_$deviceId');
      if (byId != null && byId.isNotEmpty) return byId;
    }
    final targetIp = ip ?? getIpAddress(defaultValue: '');
    if (targetIp.isEmpty) return null;
    return _prefs?.getString('${_keyClientKey}_${resolvedBrand.id}_$targetIp');
  }

  Future<bool> setClientKey(String? key, {TvBrand? brand, String? ip, String? deviceId}) async {
    await init();
    final resolvedBrand = brand ?? getBrand();
    final targetIp = ip ?? getIpAddress(defaultValue: '');
    bool result = false;

    if (deviceId != null && deviceId.isNotEmpty) {
      final idTarget = '${_keyClientKey}_id_${resolvedBrand.id}_$deviceId';
      if (key == null || key.isEmpty) {
        result = await _prefs!.remove(idTarget);
      } else {
        result = await _prefs!.setString(idTarget, key);
      }
    }

    if (targetIp.isNotEmpty) {
      final ipTarget = '${_keyClientKey}_${resolvedBrand.id}_$targetIp';
      if (key == null || key.isEmpty) {
        result = (await _prefs!.remove(ipTarget)) || result;
      } else {
        result = (await _prefs!.setString(ipTarget, key)) || result;
      }
    }
    return result;
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

  // --- Gerenciamento de Múltiplos Dispositivos Salvos (Multi-Device) ---

  /// Retorna todos os dispositivos salvos pelo usuário com migração transparente de legado.
  List<SavedDevice> getSavedDevices() {
    final raw = _prefs?.getString(_keySavedDevices);
    if (raw == null || raw.isEmpty) {
      // Migração automática de dispositivo legado se houver IP configurado
      final legacyIp = _prefs?.getString(_keyIp);
      if (legacyIp != null && legacyIp.isNotEmpty) {
        final legacyName = _prefs?.getString(_keyTvName) ?? 'Smart TV';
        final legacyMac = _prefs?.getString(_keyMac) ?? '';
        final legacyBrand = getBrand();
        final defaultDev = SavedDevice(
          id: SavedDevice.generateId(legacyBrand, legacyIp),
          name: legacyName,
          ip: legacyIp,
          mac: legacyMac,
          brand: legacyBrand,
          isDefault: true,
        );
        return [defaultDev];
      }
      return [];
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((item) => SavedDevice.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Salva a lista completa de dispositivos.
  Future<bool> saveDevices(List<SavedDevice> devices) async {
    await init();
    final raw = jsonEncode(devices.map((d) => d.toJson()).toList());
    return await _prefs?.setString(_keySavedDevices, raw) ?? false;
  }

  /// Adiciona ou atualiza um dispositivo na lista de dispositivos salvos.
  Future<bool> saveDevice(SavedDevice device) async {
    await init();
    final current = getSavedDevices();
    final index = current.indexWhere((d) => d.id == device.id || d.ip == device.ip);
    if (index >= 0) {
      final previous = current[index];
      final existingKey = getClientKey(
        brand: previous.brand,
        ip: previous.ip,
        deviceId: previous.id,
      );
      if (existingKey != null && existingKey.isNotEmpty && previous.brand == device.brand) {
        if (previous.ip != device.ip) {
          await _prefs!.remove('${_keyClientKey}_${previous.brand.id}_${previous.ip}');
        }
        if (previous.id != device.id) {
          await _prefs!.remove('${_keyClientKey}_id_${previous.brand.id}_${previous.id}');
        }
        await setClientKey(
          existingKey,
          brand: device.brand,
          ip: device.ip,
          deviceId: device.id,
        );
      }
      current[index] = device;
    } else {
      current.add(device);
    }
    return _prefs!.setString(_keySavedDevices, jsonEncode(current.map((d) => d.toJson()).toList()));
  }

  /// Remove um dispositivo da lista pelo seu [id].
  Future<bool> removeDevice(String id) async {
    await init();
    final current = getSavedDevices();
    for (final device in current.where((d) => d.id == id)) {
      await setClientKey(null, brand: device.brand, ip: device.ip, deviceId: device.id);
      await _prefs!.remove('pref_favorites_${device.brand.id}_${device.id}');
    }
    final remaining = getSavedDevices()..removeWhere((d) => d.id == id);
    return _prefs!.setString(_keySavedDevices, jsonEncode(remaining.map((d) => d.toJson()).toList()));
  }

  /// Identificador do dispositivo atualmente selecionado como ativo.
  String? getActiveDeviceId() {
    return _prefs?.getString(_keyActiveDeviceId);
  }

  /// Salva o identificador do dispositivo ativo.
  Future<bool> setActiveDeviceId(String? id) async {
    await init();
    if (id == null) {
      return await _prefs?.remove(_keyActiveDeviceId) ?? false;
    }
    return await _prefs?.setString(_keyActiveDeviceId, id) ?? false;
  }
}

