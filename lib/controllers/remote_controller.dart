import '../services/drivers/google_tv_driver.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../services/network_operation.dart';
import '../models/device_session.dart';
import '../models/saved_device.dart';
import '../services/drivers/driver_factory.dart';
import '../services/drivers/lg_webos_driver.dart';
import '../services/drivers/tv_driver.dart';
import '../services/haptic_service.dart';
import '../services/ssdp_discovery_service.dart';
import '../services/storage_service.dart';
import '../services/voice_service.dart';
import '../services/wake_on_lan_service.dart';

export '../models/device_session.dart';
export '../models/saved_device.dart';

/// Controlador de estado do controle remoto universal SixF.
///
/// Integra a interface gráfica com os serviços de back-end e suporta:
/// - Padrão Driver / Adapter ([TvDriver]) para marcas como LG webOS e Samsung Tizen.
/// - **Conexões Simultâneas (Multi-Device)**: mantém múltiplas Smart TVs conectadas
///   ativamente em segundo plano através de instâncias isoladas de [DeviceSession].
/// - **Múltiplos Dispositivos Salvos**: persistência de aparelhos com apelidos customizados
///   e chave de autenticação individual por IP.
/// - Alternância instantânea de dispositivo com 1 clique (Hot-Switching sem re-handshake).
/// - Wake-on-LAN ([WakeOnLanService]), Descoberta SSDP ([SsdpDiscoveryService]),
///   Ditado por Voz ([VoiceService]) e Feedback Háptico ([HapticService]).
class RemoteController extends ChangeNotifier {
  // Serviços de Back-End
  final StorageService storageService = StorageService();
  final VoiceService voiceService;
  final TvDriver Function(TvBrand) _driverFactory;
  final Future<List<DiscoveredTv>> Function({Duration timeout, String? knownIp}) _discoveryRunner;
  final bool _hasCustomDiscoveryRunner;
  bool _disposed = false;
  late final Future<void> ready;
  final Map<DeviceSession, NetworkOperation> _sessionOperations = {};
  NetworkOperation _discoveryOperation = NetworkOperation();

  bool _isCurrent(DeviceSession session, NetworkOperation operation) =>
      !_disposed && !operation.isCancelled && identical(_sessions[session.device.id], session);

  void _detachDriver(TvDriver driver) {
    driver.onStateChanged = null;
    driver.onPinPromptRequested = null;
    driver.onAuthTokenReceived = null;
    driver.onError = null;
    driver.onDeviceNameResolved = null;
    driver.onVolumeStatusChanged = null;
  }

  void _endSession(DeviceSession session) {
    _sessionOperations.remove(session)?.cancel();
    _detachDriver(session.driver);
    session.driver.disconnect();
    session.shouldMaintainConnection = false;
    session.isPoweredOn = false;
    session.isLoadingApps = false;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _discoveryOperation.cancel();
    final fallbackOnly = !_sessions.values.any((session) => identical(session.driver, _driver));
    for (final session in _sessions.values) {
      _endSession(session);
    }
    if (fallbackOnly) {
      _detachDriver(_driver);
      _driver.disconnect();
    }
    _sessions.clear();
    onPinPromptRequested = null;
    voiceService.dispose();
    super.dispose();
  }

  // Driver e Sessão de Fallback/Legado
  late TvDriver _driver;
  final TvDriver? _injectedDriver;

  // Estado de Tema e Preferências Globais
  ThemeMode _themeMode = ThemeMode.dark;
  bool _isHapticEnabled = true;
  bool _backButtonOnRight=false;
  bool get backButtonOnRight => _backButtonOnRight;
  Future<void> setBackButtonOnRight(bool value) async {
    _backButtonOnRight=value; notifyListeners();
    await storageService.setBackButtonOnRight(value);
  }

  // Estado Multi-Device e Sessões Concorrentes
  final Map<String, DeviceSession> _sessions = {};
  List<SavedDevice> _savedDevices = [];
  String? _activeDeviceId;

  // Variáveis espelho para compatibilidade retroativa com UI existente
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isPoweredOn = false;
  bool _isMuted = false;
  bool _isWaitingPairing = false;
  bool _isScanningTvs = false;
  String? _discoveryError;
  String? get discoveryError => _discoveryError;
  bool _shouldMaintainConnection = false;

  int _volumeLevel = 18;
  int _currentChannel = 5;
  String _ipAddress = '192.168.1.150';
  String _macAddress = 'A4:77:33:B2:9C:10';
  String? _connectedTvName;
  String _lastActionMessage = 'Aguardando conexão com o dispositivo';
  List<DiscoveredTv> _discoveredTvs = [];
  List<TvAppInfo> _installedApps = [];
  bool _isLoadingApps = false;
  String? _appsError;

  /// Driver do dispositivo ativo no momento.
  TvDriver get driver => activeSession?.driver ?? _driver;

  /// Marca/ecossistema do dispositivo atualmente selecionado.
  TvBrand get currentBrand => activeSession?.device.brand ?? _driver.brand;

  /// Se o dispositivo ativo suporta Magic Pointer / Trackpad livre.
  bool get supportsTrackpad => driver.supportsTrackpad;
  bool get supportsDirectInputs => driver is LgWebOsDriver;

  /// Se o dispositivo ativo exige pareamento com código PIN de 4 a 6 dígitos na tela.
  bool get supportsPairingPin => driver.supportsPairingPin;

  // --- Getters do Dispositivo Ativo ---
  bool get isConnected => activeSession?.isConnected ?? _isConnected;
  bool get isConnecting => activeSession?.isConnecting ?? _isConnecting;
  bool get isPoweredOn => activeSession?.isPoweredOn ?? _isPoweredOn;
  bool get isMuted => _volumeSession?.isMuted ?? _isMuted;
  bool get isWaitingPairing => activeSession?.isWaitingPairing ?? _isWaitingPairing;
  bool get isScanningTvs => _isScanningTvs;
  bool get shouldMaintainConnection => activeSession?.shouldMaintainConnection ?? _shouldMaintainConnection;
  int get volumeLevel => _volumeSession?.volumeLevel ?? _volumeLevel;
  int get currentChannel => activeSession?.currentChannel ?? _currentChannel;
  String get ipAddress => activeSession?.device.ip ?? _ipAddress;
  String get macAddress => activeSession?.device.mac ?? _macAddress;
  String? get connectedTvName => activeSession?.device.name ?? _connectedTvName;
  String get lastActionMessage => _lastActionMessage;
  List<DiscoveredTv> get discoveredTvs => _discoveredTvs;
  List<TvAppInfo> get installedApps => activeSession?.installedApps ?? _installedApps;
  bool get isLoadingApps => activeSession?.isLoadingApps ?? _isLoadingApps;
  bool isFavoriteApp(String appId) {
    final device = activeDevice;
    return device != null && storageService.getFavoriteApps(device.id, device.brand).contains(appId);
  }

  Future<void> _favoriteWrites = Future<void>.value();
  Future<void> toggleFavoriteApp(String appId) {
    final device = activeDevice;
    if (device == null) return Future<void>.value();
    return _favoriteWrites = _favoriteWrites.catchError((_) {}).then((_) async {
      await ready;
      if (_disposed || _sessions[device.id]?.device.brand != device.brand) return;
      final favorites = storageService.getFavoriteApps(device.id, device.brand);
      if (!favorites.remove(appId)) favorites.add(appId);
      await storageService.setFavoriteApps(device.id, device.brand, favorites);
      notifyListeners();
    });
  }

  String get connectionStatusLabel {
    if (isWaitingPairing) return 'Confirme na tela da TV';
    if (isConnecting) return activeSession?.reconnecting == true ? 'Reconectando...' : 'Conectando...';
    if (isConnected) return 'Conectado';
    if (activeSession?.connectionError != null) return 'TV indisponível';
    return 'Desconectado';
  }
  String get connectionGuidance {
    if (isWaitingPairing) return 'Aceite o pedido na TV ou informe o PIN solicitado. Mantenha a TV ligada.';
    if (isConnected) return 'Conexão ativa. Os recursos disponíveis dependem da TV e da mídia.';
    if (isConnecting) return 'Aguardando a TV responder. Confira se ela está ligada na mesma rede.';
    return '${activeSession?.connectionError ?? 'Não há conexão ativa.'}\n\nConfira o IP, a rede local e a permissão de controle remoto na TV. No Windows, permita o SixF na rede privada do firewall.';
  }

  String? get appsError => activeSession?.appsError ?? _appsError;

  // --- Getters de Múltiplos Dispositivos (Multi-Device) ---
  List<SavedDevice> get savedDevices => List.unmodifiable(_savedDevices);
  String? get activeDeviceId => _activeDeviceId;
  DeviceSession? get activeSession =>
      _activeDeviceId != null ? _sessions[_activeDeviceId] : null;
  SavedDevice? get activeDevice => activeSession?.device;

  /// Verifica se um dispositivo específico está conectado.
  bool isDeviceConnected(String deviceId) =>
      _sessions[deviceId]?.isConnected ?? false;

  /// Verifica se um dispositivo específico está em processo de conexão.
  bool isDeviceConnecting(String deviceId) =>
      _sessions[deviceId]?.isConnecting ?? false;

  /// Obtém o estado de conexão de um dispositivo salvo específico.
  DeviceConnectionState getDeviceConnectionState(String deviceId) =>
      _sessions[deviceId]?.connectionState ?? DeviceConnectionState.disconnected;

  /// Retorna a sessão ativa de um dispositivo salvo.
  DeviceSession? getSession(String deviceId) => _sessions[deviceId];

  RemoteController({
    TvDriver? initialDriver,
    VoiceService? voiceService,
    TvDriver Function(TvBrand)? driverFactory,
    Future<List<DiscoveredTv>> Function({Duration timeout, String? knownIp})? discoveryRunner,
  })
      : _injectedDriver = initialDriver,
        _driverFactory = driverFactory ?? DriverFactory.create,
        _discoveryRunner = discoveryRunner ?? SsdpDiscoveryService.discoverTvs,
        _hasCustomDiscoveryRunner = discoveryRunner != null,
        voiceService = voiceService ?? VoiceService() {
    _driver = initialDriver ?? _driverFactory(TvBrand.lgWebOs);

    // Inicialização síncrona imediata da sessão padrão
    final defaultDev = SavedDevice(
      id: SavedDevice.generateId(_driver.brand, _ipAddress),
      name: _connectedTvName ?? 'Smart TV',
      ip: _ipAddress,
      mac: _macAddress,
      brand: _driver.brand,
      isDefault: true,
    );
    _savedDevices = [defaultDev];
    final session = DeviceSession(device: defaultDev, driver: _driver);
    _sessions[defaultDev.id] = session;
    _activeDeviceId = defaultDev.id;
    _bindSessionDriverCallbacks(session);

    ready = _initServices();
  }

  Future<void> _initServices() async {
    try {
      await storageService.init();
      if (_disposed) return;

      _backButtonOnRight=storageService.getBackButtonOnRight();
      // Carrega preferências de tema e haptic
      final savedTheme = storageService.getThemeMode();
      _themeMode = (savedTheme == 'light') ? ThemeMode.light : ThemeMode.dark;

      final savedHaptic = storageService.getHapticFeedbackEnabled();
      _isHapticEnabled = savedHaptic;
      HapticService.isEnabled = savedHaptic;

      // Se um driver customizado foi injetado (testes unitários), preserva a sessão intacta
      if (_injectedDriver != null) {
        _syncActiveFields();
        notifyListeners();
        return;
      }

      // Carrega dispositivos salvos do StorageService
      final loaded = storageService.getSavedDevices();
      if (loaded.isNotEmpty) {
        _savedDevices = loaded;
      } else {
        _ipAddress = storageService.getIpAddress(defaultValue: _ipAddress);
        _macAddress = storageService.getMacAddress(defaultValue: _macAddress);
        _connectedTvName = storageService.getTvName();
        final savedBrand = storageService.getBrand();

        final defaultDev = SavedDevice(
          id: SavedDevice.generateId(savedBrand, _ipAddress),
          name: _connectedTvName ?? 'Smart TV',
          ip: _ipAddress,
          mac: _macAddress,
          brand: savedBrand,
          isDefault: true,
        );
        _savedDevices = [defaultDev];
        await storageService.saveDevice(defaultDev);
        if (_disposed) return;
      }

      // Remove sessões provisórias do construtor que não estão na lista carregada
      final validIds = _savedDevices.map((d) => d.id).toSet();
      for (final staleId in _sessions.keys.where((id) => !validIds.contains(id)).toList()) {
        final staleSession = _sessions.remove(staleId);
        if (staleSession != null) {
          _endSession(staleSession);
        }
      }

      // Inicializa as sessões para todos os dispositivos salvos
      for (final dev in _savedDevices) {
        _getOrCreateSession(dev);
      }

      // Determina o dispositivo ativo inicial
      final savedActiveId = storageService.getActiveDeviceId();
      if (savedActiveId != null && _sessions.containsKey(savedActiveId)) {
        _activeDeviceId = savedActiveId;
      } else {
        final defaultDev = _savedDevices.firstWhere(
          (d) => d.isDefault,
          orElse: () => _savedDevices.first,
        );
        _activeDeviceId = defaultDev.id;
      }

      _syncActiveFields();
      notifyListeners();

      final activeDev = activeDevice;
      if (activeDev != null && !Platform.environment.containsKey('FLUTTER_TEST')) {
        final savedKey = storageService.getClientKey(
          brand: activeDev.brand,
          ip: activeDev.ip,
          deviceId: activeDev.id,
        );
        if (savedKey != null && savedKey.isNotEmpty) {
          unawaited(connectDevice(activeDev.id));
        }
      }
    } catch (e) {
      debugPrint('[RemoteController] Erro ao inicializar serviços: $e');
    }
  }

  /// Obtém ou instancia a sessão isolada para um [SavedDevice].
  DeviceSession _getOrCreateSession(SavedDevice device, {TvDriver? customDriver}) {
    if (_sessions.containsKey(device.id)) {
      final existing = _sessions[device.id]!;
      existing.device = device;
      return existing;
    }

    final driver = customDriver ?? _driverFactory(device.brand);

    final session = DeviceSession(device: device, driver: driver);
    _sessions[device.id] = session;
    _bindSessionDriverCallbacks(session);
    return session;
  }

  /// Callback disparado quando um dispositivo (Android TV / Tizen) exige digitação de PIN
  Function(bool prompt)? onPinPromptRequested;

  /// Vincula os callbacks de ciclo de vida de uma [DeviceSession].
  void _bindSessionDriverCallbacks(DeviceSession session) {
    final driver = session.driver;
    final operation = _sessionOperations.putIfAbsent(session, NetworkOperation.new);

    driver.onStateChanged = (state) {
      if (!_isCurrent(session, operation)) return;
      final isNowConnected = state == DeviceConnectionState.connected;
      final isNowConnecting = state == DeviceConnectionState.connecting;
      final isNowPairing = state == DeviceConnectionState.pairingPrompt;

      if (isNowConnected) {
        session.connectionError = null;
        session.reconnecting = false;
        session.isPoweredOn = driver is GoogleTvDriver ? driver.isOn : true;
        session.shouldMaintainConnection = true;
        _logAction('${driver.brandDisplayName} Conectada e Autenticada', {
          'dispositivo': session.device.name,
          'ip': session.device.ip,
        });
        _fetchAppsForSession(session);
      } else if (state == DeviceConnectionState.disconnected && session.shouldMaintainConnection) {
        session.connectionError ??= 'A conexão com a TV foi interrompida.';
      } else if (isNowPairing) {
        _logAction('Confirmação pendente na tela da TV (${session.device.name})');
      }

      if (_activeDeviceId == session.device.id) {
        _isConnected = isNowConnected;
        _isConnecting = isNowConnecting;
        _isWaitingPairing = isNowPairing;
        if (isNowConnected) _isPoweredOn = session.isPoweredOn;
      }

      notifyListeners();
    };

    driver.onPinPromptRequested = (prompt) {
      if (!_isCurrent(session, operation)) return;
      if (_activeDeviceId == session.device.id) {
        _isWaitingPairing = true;
        onPinPromptRequested?.call(prompt);
      }
      notifyListeners();
    };

    driver.onAuthTokenReceived = (key) {
      if (!_isCurrent(session, operation)) return;
      storageService.setClientKey(
        key,
        brand: session.device.brand,
        ip: session.device.ip,
        deviceId: session.device.id,
      );
      _logAction('Chave de autenticação salva', {
        'marca': driver.brandDisplayName,
        'dispositivo': session.device.name,
      });
    };

    driver.onError = (err) {
      if (!_isCurrent(session, operation)) return;
      session.connectionError = err;
      _logAction('Erro de conexão [${session.device.name}]', {'msg': err});
    };

    driver.onDeviceNameResolved = (name, model) {
      if (!_isCurrent(session, operation)) return;
      final isGenericName = session.device.name == 'Smart TV' ||
          session.device.name.startsWith('LG Smart TV (') ||
          session.device.name.startsWith('Samsung Smart TV (');
      final resolvedName = name.trim().isNotEmpty
          ? name.trim()
          : (model != null && model.trim().isNotEmpty ? model.trim() : null);
      session.device = session.device.copyWith(
        name: (isGenericName && resolvedName != null) ? resolvedName : null,
        modelName: (model != null && model.trim().isNotEmpty) ? model.trim() : null,
      );
      storageService.saveDevice(session.device);

      final idx = _savedDevices.indexWhere((d) => d.id == session.device.id);
      if (idx >= 0) {
        _savedDevices[idx] = session.device;
      }

      if (_activeDeviceId == session.device.id) {
        _connectedTvName = session.device.name;
        _syncActiveFields();
      }

      _logAction('Nome da TV identificado', {
        'nome': session.device.name,
        'modelo': model,
      });
      notifyListeners();
    };

    driver.onVolumeStatusChanged = (volume, isMuted) {
      if (!_isCurrent(session, operation)) return;
      session.volumeLevel = volume;
      session.isMuted = isMuted;

      if (_activeDeviceId == session.device.id) {
        _volumeLevel = volume;
        _isMuted = isMuted;
      }

      _logAction('Volume sincronizado [${session.device.name}]', {
        'volume': volume,
        'mudo': isMuted,
      });
      notifyListeners();
    };
  }

  /// Vincula callbacks do driver padrão para retrocompatibilidade.
  void _bindDriverCallbacks(TvDriver driver) {
    driver.onStateChanged = (state) {
      if (_disposed || !identical(_driver, driver)) return;
      _isConnecting = state == DeviceConnectionState.connecting;
      _isConnected = state == DeviceConnectionState.connected;
      _isWaitingPairing = state == DeviceConnectionState.pairingPrompt;

      if (_isConnected) {
        _isPoweredOn = true;
        _logAction('${driver.brandDisplayName} Conectada e Autenticada', {
          'ip': _ipAddress,
          'nome': _connectedTvName,
        });
        fetchInstalledApps();
      } else if (_isWaitingPairing) {
        _logAction('Confirmação pendente na tela do dispositivo ou código PIN');
      }
      notifyListeners();
    };

    driver.onPinPromptRequested = (prompt) {
      if (_disposed || !identical(_driver, driver)) return;
      _isWaitingPairing = true;
      onPinPromptRequested?.call(prompt);
      notifyListeners();
    };

    driver.onAuthTokenReceived = (key) {
      if (_disposed || !identical(_driver, driver)) return;
      storageService.setClientKey(key, brand: driver.brand, ip: _ipAddress);
      _logAction('Chave de autenticação salva com sucesso', {
        'marca': driver.brandDisplayName,
      });
    };

    driver.onError = (err) {
      if (_disposed || !identical(_driver, driver)) return;
      _logAction('Erro de conexão', {'msg': err});
    };

    driver.onDeviceNameResolved = (name, model) {
      if (_disposed || !identical(_driver, driver)) return;
      _connectedTvName = name;
      storageService.setTvName(name);
      _logAction('Nome da TV identificado', {
        'nome': name,
        'modelo': model,
      });
      notifyListeners();
    };

    driver.onVolumeStatusChanged = (volume, isMuted) {
      if (_disposed || !identical(_driver, driver)) return;
      _volumeLevel = volume;
      _isMuted = isMuted;
      _logAction('Volume da TV sincronizado', {
        'volume': volume,
        'mudo': isMuted,
      });
      notifyListeners();
    };
  }

  /// Sincroniza as variáveis de conveniência com o estado da sessão ativa.
  void _syncActiveFields() {
    final session = activeSession;
    if (session != null) {
      _ipAddress = session.device.ip;
      _macAddress = session.device.mac;
      _connectedTvName = session.device.name;
      _isConnected = session.isConnected;
      _isConnecting = session.isConnecting;
      _isWaitingPairing = session.isWaitingPairing;
      _isPoweredOn = session.isPoweredOn;
      _volumeLevel = session.volumeLevel;
      _isMuted = session.isMuted;
      _currentChannel = session.currentChannel;
      _installedApps = session.installedApps;
      _isLoadingApps = session.isLoadingApps;
      _appsError = session.appsError;
      _driver = session.driver;
    }
  }

  // --- Gerenciamento Multi-Device: Alternância e Conexões Simultâneas ---

  /// Alterna instantaneamente o controle ativo para outro dispositivo salvo (Hot-Switching).
  void setActiveDevice(String deviceId) {
    if (!_sessions.containsKey(deviceId)) return;
    storageService.setActiveDeviceId(deviceId);
    if (_activeDeviceId == deviceId) return;

    _activeDeviceId = deviceId;
    final session = _sessions[deviceId]!;
    _driver = session.driver;
    _syncActiveFields();
    if (session.isWaitingPairing && session.driver.supportsPairingPin) {
      onPinPromptRequested?.call(true);
    }

    HapticService.selectionClick();
    _logAction('Controle alternado para: ${session.device.name}', {
      'ip': session.device.ip,
      'marca': session.device.brand.displayName,
      'conectado': session.isConnected,
    });
    notifyListeners();
  }

  /// Verifica se uma TV descoberta na rede já corresponde a um dispositivo salvo.
  bool isTvSaved(DiscoveredTv tv) => _findMatchingSavedDevice(tv) != null;

  static String _normalizeTvName(String raw) {
    return raw.trim().replaceFirst(RegExp(r'\s*\(\d+\.\d+\.\d+\.\d+\)\s*$'), '').toLowerCase();
  }

  /// Localiza um dispositivo salvo compatível com uma TV descoberta na rede,
  /// reconciliando mudanças de IP via DHCP (por modelo, nome amigável ou único aparelho pareado da marca).
  SavedDevice? _findMatchingSavedDevice(DiscoveredTv tv) {
    final deviceId = SavedDevice.generateId(tv.brand, tv.ip);
    for (final d in _savedDevices) {
      if (d.id == deviceId || d.ip == tv.ip) return d;
    }
    final sameBrand = _savedDevices.where((d) => d.brand == tv.brand).toList();
    if (sameBrand.isEmpty) return null;

    bool hasSavedKey(SavedDevice d) {
      final key = storageService.getClientKey(
        brand: d.brand,
        ip: d.ip,
        deviceId: d.id,
      );
      return key != null && key.isNotEmpty;
    }

    if (tv.modelName != null && tv.modelName!.isNotEmpty) {
      for (final d in sameBrand) {
        if (d.modelName != null &&
            d.modelName!.toLowerCase() == tv.modelName!.toLowerCase()) {
          return d;
        }
      }
    }

    final normalizedDiscovered = _normalizeTvName(tv.name);
    for (final d in sameBrand) {
      if (d.ip == '192.168.1.150' && !hasSavedKey(d)) continue;
      if (_normalizeTvName(d.name) == normalizedDiscovered) {
        return d;
      }
    }

    final pairedSameBrand = sameBrand.where(hasSavedKey).toList();
    if (pairedSameBrand.length == 1) {
      return pairedSameBrand.first;
    }
    return null;
  }

  /// Conecta um dispositivo salvo específico sem desconectar os outros.
  Future<void> connectDevice(String deviceId, {bool allowDiscoveryFallback = true}) async {
    await ready;
    if (_disposed) return;
    final session = _sessions[deviceId];
    if (_disposed || session == null || session.isConnecting || session.isWaitingPairing) return;
    _sessionOperations.remove(session)?.cancel();
    session.isLoadingApps = false;
    session.connectionError = null;
    session.reconnecting = session.shouldMaintainConnection;
    _bindSessionDriverCallbacks(session);
    final operation = _sessionOperations[session]!;

    final driver = session.driver;
    var savedKey = storageService.getClientKey(
      brand: session.device.brand,
      ip: session.device.ip,
      deviceId: session.device.id,
    );
    final timeoutDuration = session.device.brand != TvBrand.lgWebOs
        ? const Duration(seconds: 10)
        : const Duration(seconds: 4);

    _logAction('Conectando a ${session.device.name}', {
      'ip': session.device.ip,
      'marca': session.device.brand.displayName,
    });
    notifyListeners();

    try {
      var success = await operation.wait(driver.connect(
        ipAddress: session.device.ip,
        authToken: savedKey,
        timeout: timeoutDuration,
      ));
      if (!_isCurrent(session, operation)) return;

      // Se falhou em conectar no IP antigo (ex: DHCP mudou o IP da TV na LAN) e temos credencial salva,
      // faz uma varredura rápida para reconciliar o novo IP mantendo a credencial pareada.
      if (!success &&
          !session.isWaitingPairing &&
          allowDiscoveryFallback &&
          savedKey != null &&
          savedKey.isNotEmpty &&
          (_injectedDriver == null || _hasCustomDiscoveryRunner)) {
        final discovered = await operation.run(() => _discoveryRunner(
              timeout: const Duration(seconds: 2),
            ));
        if (!_isCurrent(session, operation)) return;

        DiscoveredTv? matchedTv;
        for (final tv in discovered.where((t) => t.brand == session.device.brand)) {
          final matched = _findMatchingSavedDevice(tv);
          if (matched != null && matched.id == session.device.id && tv.ip != session.device.ip) {
            matchedTv = tv;
            break;
          }
        }

        if (matchedTv != null) {
          final updatedDevice = session.device.copyWith(
            ip: matchedTv.ip,
            modelName: matchedTv.modelName ?? session.device.modelName,
          );
          session.device = updatedDevice;
          final idx = _savedDevices.indexWhere((d) => d.id == updatedDevice.id);
          if (idx >= 0) _savedDevices[idx] = updatedDevice;
          await storageService.saveDevice(updatedDevice);
          if (!_isCurrent(session, operation)) return;

          session.connectionError = null;
          savedKey = storageService.getClientKey(
            brand: updatedDevice.brand,
            ip: updatedDevice.ip,
            deviceId: updatedDevice.id,
          );
          success = await operation.wait(driver.connect(
            ipAddress: updatedDevice.ip,
            authToken: savedKey,
            timeout: timeoutDuration,
          ));
          if (!_isCurrent(session, operation)) return;
        }
      }

      if (success && driver.isConnected) {
        session.isPoweredOn = driver is GoogleTvDriver ? driver.isOn : true;
        session.shouldMaintainConnection = true;
        _fetchAppsForSession(session);
      } else if (!success && !session.isWaitingPairing) {
        session.connectionError ??= 'A TV não respondeu à tentativa de conexão.';
      }
    } catch (e) {
      if (!_isCurrent(session, operation)) return;
      session.connectionError = 'Falha ao estabelecer a conexão. Tente novamente.';
      _logAction('Falha ao conectar ${session.device.name}', {'erro': '$e'});
    }

    if (_activeDeviceId == deviceId) {
      _syncActiveFields();
    }
    notifyListeners();
  }

  /// Desconecta um dispositivo específico mantendo as outras conexões ativas.
  void disconnectDevice(String deviceId) {
    final session = _sessions[deviceId];
    if (session == null) return;

    _endSession(session);
    session.connectionError = null;
    session.reconnecting = false;

    if (_activeDeviceId == deviceId) {
      _isConnected = false;
      _isConnecting = false;
      _isWaitingPairing = false;
    }

    _logAction('Dispositivo desconectado: ${session.device.name}');
    notifyListeners();
  }

  /// Conecta todos os dispositivos salvos em paralelo na rede local.
  Future<void> connectAllDevices() async {
    _logAction('Conectando a todos os dispositivos salvos...');
    final futures = _savedDevices.map((d) => connectDevice(d.id));
    await Future.wait(futures);
  }

  /// Desconecta todos os dispositivos conectados.
  void disconnectAllDevices() {
    for (final session in _sessions.values) {
      _endSession(session);
    }
    _isConnected = false;
    _isConnecting = false;
    _isWaitingPairing = false;
    _shouldMaintainConnection = false;
    _logAction('Todos os dispositivos foram desconectados');
    notifyListeners();
  }

  /// Salva ou atualiza um dispositivo na lista persistente e no mapa de sessões.
  Future<void> saveOrUpdateDevice(SavedDevice device, {bool makeActive = false}) async {
    await ready;
    if (_disposed) return;
    final idx = _savedDevices.indexWhere((d) => d.id == device.id || d.ip == device.ip);
    if (idx >= 0) {
      _savedDevices[idx] = device;
    } else {
      _savedDevices.add(device);
    }
    await storageService.saveDevice(device);
    if (_disposed) return;

    final session = _getOrCreateSession(device);
    session.device = device;

    if (makeActive || _activeDeviceId == null || _savedDevices.length == 1) {
      setActiveDevice(device.id);
    }

    _logAction('Dispositivo salvo', {'nome': device.name, 'ip': device.ip});
    notifyListeners();
  }

  /// Remove um dispositivo do histórico, desconectando sua sessão.
  Future<void> removeSavedDevice(String deviceId) async {
    await ready;
    if (_disposed) return;
    disconnectDevice(deviceId);
    _sessions.remove(deviceId);
    _savedDevices.removeWhere((d) => d.id == deviceId);
    await storageService.removeDevice(deviceId);
    if (_disposed) return;

    if (_activeDeviceId == deviceId) {
      if (_savedDevices.isNotEmpty) {
        setActiveDevice(_savedDevices.first.id);
      } else {
        _activeDeviceId = null;
        _isConnected = false;
      }
    }

    _logAction('Dispositivo removido do histórico');
    notifyListeners();
  }

  /// Define um dispositivo como padrão inicial do aplicativo.
  Future<void> setDefaultDevice(String deviceId) async {
    await ready;
    if (_disposed) return;
    for (var i = 0; i < _savedDevices.length; i++) {
      final isDef = _savedDevices[i].id == deviceId;
      _savedDevices[i] = _savedDevices[i].copyWith(isDefault: isDef);
    }
    await storageService.saveDevices(_savedDevices);
    notifyListeners();
  }

  /// Alterna a marca ativa do dispositivo e inicializa o driver correspondente.
  void selectBrand(TvBrand brand, {bool notify = true}) {
    if (currentBrand == brand) return;

    final session = activeSession;
    if (session != null) {
      _endSession(session);
      final newDriver = _driverFactory(brand);

      final updatedDevice = session.device.copyWith(brand: brand);
      session.device = updatedDevice;
      final newSession = DeviceSession(device: updatedDevice, driver: newDriver);
      _sessions[updatedDevice.id] = newSession;
      _bindSessionDriverCallbacks(newSession);

      final idx = _savedDevices.indexWhere((d) => d.id == session.device.id);
      if (idx >= 0) _savedDevices[idx] = updatedDevice;
      storageService.saveDevice(updatedDevice);

      _driver = newDriver;
      _syncActiveFields();
    } else {
      _driver.disconnect();
      _driver = _driverFactory(brand);
      _bindDriverCallbacks(_driver);
    }

    _installedApps = [];
    storageService.setBrand(brand);
    _logAction('Marca selecionada', {'marca': brand.displayName});
    if (notify) notifyListeners();
  }

  // --- Gerenciamento de Conexão Geral (Retrocompatível) ---

  Future<void> connect({
    String? ip,
    String? mac,
    String? tvName,
    TvBrand? brand,
  }) async {
    await ready;
    if (_disposed) return;
    final targetBrand = brand ?? currentBrand;
    final targetIp = (ip != null && ip.trim().isNotEmpty) ? ip.trim() : _ipAddress;
    final targetMac = (mac != null && mac.trim().isNotEmpty) ? mac.trim() : _macAddress;
    final targetName = (tvName != null && tvName.trim().isNotEmpty)
        ? tvName.trim()
        : (activeSession?.device.name ?? _connectedTvName ?? 'Smart TV');

    final deviceId = SavedDevice.generateId(targetBrand, targetIp);

    // Se temos um driver injetado (testes unitários), preserva a referência do mockDriver
    if (_injectedDriver != null && activeSession != null) {
      final currentSession = activeSession!;
      currentSession.device = currentSession.device.copyWith(
        ip: targetIp,
        mac: targetMac,
        name: targetName,
        brand: targetBrand,
      );
      _ipAddress = targetIp;
      _macAddress = targetMac;
      _connectedTvName = targetName;
      await connectDevice(currentSession.device.id);
      return;
    }

    // Busca ou cria o SavedDevice correspondente
    SavedDevice device;
    final existingIdx = _savedDevices.indexWhere((d) => d.id == deviceId || d.ip == targetIp);
    if (existingIdx >= 0) {
      device = _savedDevices[existingIdx].copyWith(
        mac: targetMac.isNotEmpty ? targetMac : _savedDevices[existingIdx].mac,
        name: targetName,
        brand: targetBrand,
      );
      _savedDevices[existingIdx] = device;
    } else {
      device = SavedDevice(
        id: deviceId,
        name: targetName,
        ip: targetIp,
        mac: targetMac,
        brand: targetBrand,
        isDefault: _savedDevices.isEmpty,
      );
      _savedDevices.add(device);
    }

    await storageService.saveDevice(device);
    await storageService.setIpAddress(targetIp);
    if (targetMac.isNotEmpty) await storageService.setMacAddress(targetMac);
    await storageService.setTvName(targetName);
    if (_disposed) return;

    _getOrCreateSession(device);
    setActiveDevice(device.id);
    await connectDevice(device.id);
  }

  void disconnect() {
    if (_activeDeviceId != null) {
      disconnectDevice(_activeDeviceId!);
    } else {
      _shouldMaintainConnection = false;
      _driver.disconnect();
      _isConnected = false;
      _isConnecting = false;
      _isWaitingPairing = false;
      _logAction('Desconectado');
      notifyListeners();
    }
  }

  /// Reconecta de forma transparente quando o usuário retorna ao aplicativo
  Future<void> autoReconnectIfNeeded() async {
    for (final session in _sessions.values.toList()) {
      if (_disposed) return;
      if (session.shouldMaintainConnection && !session.isConnected && !session.isConnecting) {
        await connectDevice(session.device.id);
      }
    }
    if (_sessions.isEmpty && _shouldMaintainConnection && !_isConnected && !_isConnecting) {
      await connect();
    }
  }

  // --- Descoberta Automática de TVs na Rede (SSDP e Probes) ---

  Future<List<DiscoveredTv>> scanForTvs() async {
    if (_disposed || _isScanningTvs) return _discoveredTvs;
    _discoveryOperation = NetworkOperation();
    _isScanningTvs = true;
    _discoveryError = null;
    _logAction('Buscando TVs na rede local (SSDP)...');
    notifyListeners();

    try {
      final discovered = await _discoveryOperation.run(() => _discoveryRunner(
        timeout: const Duration(seconds: 4),
        knownIp: _ipAddress,
      ));
      if (_disposed) return [];
      _discoveredTvs = List<DiscoveredTv>.from(discovered);

      // Reconcilia alterações de IP via DHCP para dispositivos já salvos/pareados
      for (final tv in _discoveredTvs) {
        final matched = _findMatchingSavedDevice(tv);
        if (matched != null &&
            (matched.ip != tv.ip || (tv.modelName != null && matched.modelName != tv.modelName))) {
          final updated = matched.copyWith(
            ip: tv.ip,
            modelName: tv.modelName ?? matched.modelName,
          );
          final idx = _savedDevices.indexWhere((d) => d.id == matched.id);
          if (idx >= 0) _savedDevices[idx] = updated;
          final session = _sessions[matched.id];
          if (session != null) session.device = updated;
          await storageService.saveDevice(updated);
          if (_disposed) return [];
          if (_activeDeviceId == updated.id) {
            _syncActiveFields();
          }
        }
      }

      // Adiciona o dispositivo ativo se não foi localizado (exceto placeholder inicial não pareado)
      if (_ipAddress.isNotEmpty && _connectedTvName != null && _ipAddress != '192.168.1.150') {
        if (!_discoveredTvs.any((t) => t.ip == _ipAddress)) {
          _discoveredTvs.add(DiscoveredTv(
            ip: _ipAddress,
            name: _connectedTvName!,
            brand: currentBrand,
          ));
        }
      }

      _logAction('Busca concluída', {'encontradas': _discoveredTvs.length});
    } catch (e) {
      _discoveryError = 'Não foi possível concluir a busca. Confira a rede e tente novamente.';
      _logAction('Erro na busca SSDP', {'erro': '$e'});
    } finally {
      _discoveryOperation.cancel();
      _isScanningTvs = false;
      notifyListeners();
    }

    return _discoveredTvs;
  }

  Future<SavedDevice> selectDiscoveredTv(DiscoveredTv tv) async {
    await ready;
    final existing = _findMatchingSavedDevice(tv);
    final SavedDevice device;
    if (existing != null) {
      device = existing.copyWith(
        ip: tv.ip,
        modelName: tv.modelName ?? existing.modelName,
      );
    } else {
      final deviceId = SavedDevice.generateId(tv.brand, tv.ip);
      device = SavedDevice(
        id: deviceId,
        name: tv.name,
        ip: tv.ip,
        brand: tv.brand,
        modelName: tv.modelName,
      );
    }

    await saveOrUpdateDevice(device, makeActive: true);
    _logAction('TV selecionada', {'nome': tv.name, 'ip': tv.ip});
    notifyListeners();
    return device;
  }

  Future<void> connectToTv(DiscoveredTv tv) async {
    final device = await selectDiscoveredTv(tv);
    await connectDevice(device.id, allowDiscoveryFallback: false);
  }

  // --- Controle de Energia ---

  void powerToggle() {
    HapticService.heavyPress();
    final session = activeSession;
    final targetMac = session?.device.mac ?? _macAddress;

    if (currentBrand == TvBrand.googleTv) {
      driver.sendKey(RemoteKey.power);
      _logAction('Energia do Google TV acionada');
      return;
    }

    if (isPoweredOn) {
      _shouldMaintainConnection = false;
      if (session != null) session.shouldMaintainConnection = false;
      driver.sendKey(RemoteKey.power);
      if (session != null) session.isPoweredOn = false;
      _isPoweredOn = false;
      _isConnected = false;
    } else {
      _logAction('Enviando Wake-on-LAN para ligar a TV', {'mac': targetMac});
      WakeOnLanService.wake(targetMac);
      if (session != null) session.isPoweredOn = true;
      _isPoweredOn = true;
    }

    _logAction('Power Toggle', {'isPoweredOn': _isPoweredOn});
    notifyListeners();
  }

  String? get volumeTargetId {
    final active = activeSession;
    if(active == null || currentBrand != TvBrand.googleTv) return activeDeviceId;
    final saved = storageService.getVolumeTarget(active.device.id);
    if(saved != null && _sessions.containsKey(saved)) return saved;
    final televisions = _sessions.values.where((s)=>s.device.brand != TvBrand.googleTv).toList();
    return televisions.length == 1 ? televisions.single.device.id : activeDeviceId;
  }
  DeviceSession? get _volumeSession => _sessions[volumeTargetId];
  Future<void> setVolumeTarget(String id) async {
    final active=activeDeviceId;
    if(active==null || !_sessions.containsKey(id)) return;
    await storageService.setVolumeTarget(active,id); notifyListeners();
  }
  bool _prepareVolume() {
    final target=_volumeSession;
    if(target==null || !target.isConnected) {
      _logAction('Conecte o aparelho escolhido para controlar o volume.'); return false;
    }
    return true;
  }

  // --- Volume, Canal e Mudo ---

  void volumeUp() {
    if (currentBrand == TvBrand.googleTv && !_prepareVolume()) return;
    final session = _volumeSession;
    if (session != null) {
      if (session.volumeLevel < 100) {
        session.volumeLevel++;
        if (session.isMuted) session.isMuted = false;
      }
      _volumeLevel = session.volumeLevel;
      _isMuted = session.isMuted;
    } else {
      if (_volumeLevel < 100) {
        _volumeLevel++;
        if (_isMuted) _isMuted = false;
      }
    }
    (session?.driver ?? driver).sendKey(RemoteKey.volumeUp);
    _logAction('Volume Up', {'level': volumeLevel, 'muted': isMuted});
    notifyListeners();
  }

  void volumeDown() {
    if (currentBrand == TvBrand.googleTv && !_prepareVolume()) return;
    final session = _volumeSession;
    if (session != null) {
      if (session.volumeLevel > 0) {
        session.volumeLevel--;
        if (session.isMuted) session.isMuted = false;
      }
      _volumeLevel = session.volumeLevel;
      _isMuted = session.isMuted;
    } else {
      if (_volumeLevel > 0) {
        _volumeLevel--;
        if (_isMuted) _isMuted = false;
      }
    }
    (session?.driver ?? driver).sendKey(RemoteKey.volumeDown);
    _logAction('Volume Down', {'level': volumeLevel, 'muted': isMuted});
    notifyListeners();
  }

  void toggleMute() {
    if (currentBrand == TvBrand.googleTv && !_prepareVolume()) return;
    final session = _volumeSession;
    final newMute = !isMuted;
    if (session != null) {
      session.isMuted = newMute;
    }
    _isMuted = newMute;
    (session?.driver ?? driver).setMute(newMute);
    _logAction('Mute Toggle', {'isMuted': newMute});
    notifyListeners();
  }

  void muteToggle() => toggleMute();

  void triggerVoice() {
    HapticService.buttonPress();
    if (driver is! GoogleTvDriver) driver.triggerVoice();
    _logAction('Comando de Voz / Microfone acionado', {
      'marca': driver.brandDisplayName,
    });
    notifyListeners();
  }

  void voiceCommand() => triggerVoice();

  void channelUp() {
    final session = activeSession;
    if (session != null) {
      session.currentChannel++;
      _currentChannel = session.currentChannel;
    } else {
      _currentChannel++;
    }
    driver.sendKey(RemoteKey.channelUp);
    _logAction('Channel Up', {'channel': currentChannel});
    notifyListeners();
  }

  void channelDown() {
    final session = activeSession;
    if (session != null) {
      if (session.currentChannel > 1) {
        session.currentChannel--;
      }
      _currentChannel = session.currentChannel;
    } else {
      if (_currentChannel > 1) {
        _currentChannel--;
      }
    }
    driver.sendKey(RemoteKey.channelDown);
    _logAction('Channel Down', {'channel': currentChannel});
    notifyListeners();
  }

  // --- Navegação D-Pad ---

  void dpadUp() {
    driver.sendKey(RemoteKey.dpadUp);
    _logAction('D-Pad UP');
  }

  void dpadDown() {
    driver.sendKey(RemoteKey.dpadDown);
    _logAction('D-Pad DOWN');
  }

  void dpadLeft() {
    driver.sendKey(RemoteKey.dpadLeft);
    _logAction('D-Pad LEFT');
  }

  void dpadRight() {
    driver.sendKey(RemoteKey.dpadRight);
    _logAction('D-Pad RIGHT');
  }

  void dpadOk() {
    driver.sendKey(RemoteKey.dpadOk);
    _logAction('D-Pad OK / Enter');
  }

  // --- Navegação de Sistema ---

  void pressHome() {
    driver.sendKey(RemoteKey.home);
    _logAction('Nav Home');
  }

  void navHome() => pressHome();

  void pressMenu() {
    driver.sendKey(RemoteKey.menu);
    _logAction('Nav Settings (Menu)');
  }

  void navSettings() => pressMenu();

  void pressBack() {
    driver.sendKey(RemoteKey.back);
    _logAction('Nav Back');
  }

  void navBack() => pressBack();

  void pressExit() {
    driver.sendKey(RemoteKey.exit);
    _logAction('Nav Exit');
  }

  void navInput() {
    driver.sendKey(RemoteKey.input);
    _logAction('Nav Input / Source');
  }

  void switchHdmi1() {
    if (!supportsDirectInputs) return;
    final active = driver;
    if (active is LgWebOsDriver) {
      active.webOsService.switchToInput('HDMI_1');
    }
    _logAction('Entrada: HDMI 1');
  }

  void switchTvDigital() {
    if (!supportsDirectInputs) return;
    final active = driver;
    if (active is LgWebOsDriver) {
      active.webOsService.launchLiveTv();
    }
    _logAction('Entrada: TV Digital');
  }

  // --- Controles Multimídia ---

  final Map<String, String> _mediaSelections = {};
  String? get selectedMediaAction => _mediaSelections['${currentBrand.id}:$ipAddress'];
  void selectMediaAction(String action) {
    _mediaSelections['${currentBrand.id}:$ipAddress'] = action;
    notifyListeners();
  }

  void mediaPlay() {
    driver.sendKey(RemoteKey.play);
    _logAction('Media Play');
  }

  void mediaPause() {
    driver.sendKey(RemoteKey.pause);
    _logAction('Media Pause');
  }

  void mediaStop() {
    driver.sendKey(RemoteKey.stop);
    _logAction('Media Stop');
  }

  void mediaRewind() {
    driver.sendKey(RemoteKey.rewind);
    _logAction('Media Rewind');
  }

  void mediaFastForward() {
    driver.sendKey(RemoteKey.fastForward);
    _logAction('Media Fast Forward');
  }

  // --- Botões de Cores WebOS ---

  void pressColorRed() {
    driver.sendKey(RemoteKey.colorRed);
    _logAction('Color RED');
  }

  void colorRed() => pressColorRed();

  void pressColorGreen() {
    driver.sendKey(RemoteKey.colorGreen);
    _logAction('Color GREEN');
  }

  void colorGreen() => pressColorGreen();

  void pressColorYellow() {
    driver.sendKey(RemoteKey.colorYellow);
    _logAction('Color YELLOW');
  }

  void colorYellow() => pressColorYellow();

  void pressColorBlue() {
    driver.sendKey(RemoteKey.colorBlue);
    _logAction('Color BLUE');
  }

  void colorBlue() => pressColorBlue();

  // --- Teclado Numérico ---

  void sendDigit(int digit) {
    driver.sendDigit(digit);
    _logAction('Keypad Digit', {'digit': digit});
  }

  void inputDigit(int digit) => sendDigit(digit);

  void sendDash() {
    driver.sendKey(RemoteKey.dash);
    _logAction('Keypad Dash (-)');
  }

  void sendBackspace() {
    driver.sendKey(RemoteKey.back);
    _logAction('Keypad Backspace');
  }

  // --- Magic Remote: Trackpad e Ponteiro ---

  void sendTrackpadDelta(double dx, double dy) {
    if (!supportsTrackpad) return;
    driver.sendTrackpadDelta(dx, dy);
    _logAction('Trackpad Move', {'dx': dx, 'dy': dy});
  }

  void onTrackpadPan(double dx, double dy) => sendTrackpadDelta(dx, dy);

  void sendTrackpadClick() {
    if (!supportsTrackpad) return;
    driver.sendTrackpadClick();
    _logAction('Trackpad Click / Confirmação');
  }

  void onTrackpadTap() => sendTrackpadClick();

  // --- Entrada de Texto Remota ---

  void sendText(String text) {
    driver.sendText(text);
    _logAction('Texto enviado', {'text': text});
  }

  /// Executa comandos de voz diretos (volume +/- 5 passos, mudo, desligar e abrir apps).
  Future<bool> executeVoiceIntent(VoiceIntent intent) async {
    if (_disposed || !intent.isCommand) return false;

    switch (intent.type) {
      case VoiceIntentType.volumeUp:
        HapticService.buttonPress();
        for (var i = 0; i < 5; i++) {
          if (_disposed) return false;
          volumeUp();
          if (i < 4) await Future.delayed(const Duration(milliseconds: 65));
        }
        _logAction('Comando de Voz: Volume +5');
        return true;

      case VoiceIntentType.volumeDown:
        HapticService.buttonPress();
        for (var i = 0; i < 5; i++) {
          if (_disposed) return false;
          volumeDown();
          if (i < 4) await Future.delayed(const Duration(milliseconds: 65));
        }
        _logAction('Comando de Voz: Volume -5');
        return true;

      case VoiceIntentType.toggleMute:
        HapticService.buttonPress();
        toggleMute();
        _logAction('Comando de Voz: Alternar Mudo');
        return true;

      case VoiceIntentType.powerOff:
        HapticService.heavyPress();
        if (isPoweredOn) {
          powerToggle();
        }
        _logAction('Comando de Voz: Desligar TV');
        return true;

      case VoiceIntentType.openApp:
        HapticService.buttonPress();
        final appId = intent.targetAppId ?? intent.targetApp ?? '';
        if (appId.isNotEmpty) {
          openApp(appId, appName: intent.targetApp);
          _logAction('Comando de Voz: Abrir App', {'app': intent.targetApp, 'id': appId});
          return true;
        }
        return false;

      case VoiceIntentType.textSearch:
        return false;
    }
  }

  // --- Pareamento com PIN (Android TV) ---

  Future<void> sendPairingPin(String pin) async {
    await driver.sendPairingPin(pin);
    _logAction('Código de pareamento enviado');
  }

  // --- Gerenciamento e Atalhos de Aplicativos ---

  /// Busca a lista de aplicativos instalados ou atalhos disponíveis no dispositivo conectado.
  Future<void> fetchInstalledApps({bool forceRefresh = false}) async {
    final session = activeSession;
    if (session != null) {
      await _fetchAppsForSession(session, forceRefresh: forceRefresh);
    } else {
      if (!forceRefresh && _installedApps.isNotEmpty && _isLoadingApps) return;
      _isLoadingApps = true;
      _appsError = null;
      notifyListeners();

      try {
        final apps = await driver.getInstalledApps();
        _installedApps = apps;
        _logAction('Aplicativos sincronizados', {'total': apps.length});
      } catch (e) {
        _appsError = 'Falha ao carregar aplicativos: $e';
        _logAction('Erro ao buscar aplicativos', {'erro': e.toString()});
      } finally {
        _isLoadingApps = false;
        notifyListeners();
      }
    }
  }

  Future<void> _fetchAppsForSession(DeviceSession session, {bool forceRefresh = false}) async {
    final operation = _sessionOperations[session];
    if (operation == null || !_isCurrent(session, operation) || session.isLoadingApps) return;
    if (!forceRefresh && session.installedApps.isNotEmpty) return;
    session.isLoadingApps = true;
    session.appsError = null;
    notifyListeners();
    try {
      final apps = await operation.wait(session.driver.getInstalledApps());
      if (!_isCurrent(session, operation)) return;
      session.installedApps = apps;
    } catch (e) {
      if (_isCurrent(session, operation)) session.appsError = 'Falha ao carregar aplicativos: $e';
    } finally {
      if (_isCurrent(session, operation)) {
        session.isLoadingApps = false;
        if (_activeDeviceId == session.device.id) _syncActiveFields();
        notifyListeners();
      }
    }
  }

  /// Abre um aplicativo específico pelo seu identificador ou pacote.
  void openApp(String appId, {String? appName}) {
    HapticService.buttonPress();
    driver.openApp(appId);
    final params = <String, dynamic>{'appId': appId};
    if (appName != null) {
      params['app'] = appName;
    }
    _logAction('Abrindo aplicativo', params);
  }

  // --- Gerenciamento de Tema ---

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode = (_themeMode == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
    storageService.setThemeMode(_themeMode.name);
    _logAction('Tema alternado', {'modo': _themeMode.name});
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    storageService.setThemeMode(_themeMode.name);
    _logAction('Tema definido', {'modo': _themeMode.name});
    notifyListeners();
  }

  // --- Feedback Háptico (Vibração Tátil) ---

  bool get isHapticEnabled => _isHapticEnabled;

  void toggleHapticFeedback() {
    setHapticFeedback(!_isHapticEnabled);
  }

  void setHapticFeedback(bool enabled) {
    if (_isHapticEnabled == enabled) return;
    _isHapticEnabled = enabled;
    HapticService.isEnabled = enabled;
    storageService.setHapticFeedbackEnabled(enabled);
    if (enabled) {
      HapticService.buttonPress();
    }
    _logAction('Feedback háptico alterado', {'ativo': enabled});
    notifyListeners();
  }

  void _logAction(String action, [Map<String, dynamic>? params]) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final paramsStr = (params != null && params.isNotEmpty) ? ' -> $params' : '';
    _lastActionMessage = '[$timestamp] $action$paramsStr';
    debugPrint('[LG_REMOTE] $timestamp | Ação: $action$paramsStr');
    notifyListeners();
  }
}
