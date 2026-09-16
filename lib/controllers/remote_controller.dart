import 'package:flutter/material.dart';
import '../services/drivers/driver_factory.dart';
import '../services/drivers/lg_webos_driver.dart';
import '../services/drivers/tv_driver.dart';
import '../services/haptic_service.dart';
import '../services/ssdp_discovery_service.dart';
import '../services/storage_service.dart';
import '../services/wake_on_lan_service.dart';
import '../services/webos_service.dart';

/// Controlador de estado do controle remoto universal SixF.
///
/// Integra a interface gráfica com os serviços de back-end por meio
/// do padrão Driver / Adapter ([TvDriver]):
/// - [TvDriver]: Interface agnóstica para comandos padronizados, ciclo de vida e estado.
/// - [LgWebOsDriver]: Driver concreto para TVs LG webOS (SSAP / Pointer Socket).
/// - [WakeOnLanService]: Ligar TV via broadcast UDP Magic Packet.
/// - [SsdpDiscoveryService]: Descoberta automática de dispositivos na rede local.
/// - [StorageService]: Persistência de parâmetros, marca e chaves de pareamento.
/// - [HapticService]: Gerenciamento de resposta tátil por vibração nos botões.
class RemoteController extends ChangeNotifier {
  // Serviços de Back-End
  final StorageService storageService = StorageService();
  final WebOsService _webOsService = WebOsService();
  late TvDriver _driver;

  // Estado de tema e preferências
  ThemeMode _themeMode = ThemeMode.dark;
  bool _isHapticEnabled = true;

  // Estado de conexão e energia - Inicializado estritamente como DESCONECTADO
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isPoweredOn = false;
  bool _isMuted = false;
  bool _isWaitingPairing = false;
  bool _isScanningTvs = false;
  bool _shouldMaintainConnection = false;

  // Valores e identificação da TV
  int _volumeLevel = 18;
  int _currentChannel = 5;
  String _ipAddress = '192.168.1.150';
  String _macAddress = 'A4:77:33:B2:9C:10';
  String? _connectedTvName;
  String _lastActionMessage = 'Aguardando conexão com o dispositivo';
  List<DiscoveredTv> _discoveredTvs = [];

  /// Expõe o [WebOsService] para compatibilidade com código existente e testes unitários.
  WebOsService get webOsService => _webOsService;

  /// Driver ativo no momento.
  TvDriver get driver => _driver;

  /// Marca/ecossistema do dispositivo atualmente selecionado.
  TvBrand get currentBrand => _driver.brand;

  /// Se o dispositivo ativo suporta Magic Pointer / Trackpad livre.
  bool get supportsTrackpad => _driver.supportsTrackpad;

  /// Se o dispositivo ativo exige pareamento com código PIN de 4 a 6 dígitos na tela.
  bool get supportsPairingPin => _driver.supportsPairingPin;

  RemoteController({TvDriver? initialDriver}) {
    _driver = initialDriver ?? LgWebOsDriver(webOsService: _webOsService);
    _bindDriverCallbacks();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      await storageService.init();
      _ipAddress = storageService.getIpAddress(defaultValue: _ipAddress);
      _macAddress = storageService.getMacAddress(defaultValue: _macAddress);
      _connectedTvName = storageService.getTvName();

      final savedBrand = storageService.getBrand();
      if (savedBrand != _driver.brand) {
        selectBrand(savedBrand, notify: false);
      }

      final savedTheme = storageService.getThemeMode();
      if (savedTheme == 'light') {
        _themeMode = ThemeMode.light;
      } else {
        _themeMode = ThemeMode.dark;
      }

      final savedHaptic = storageService.getHapticFeedbackEnabled();
      _isHapticEnabled = savedHaptic;
      HapticService.isEnabled = savedHaptic;

      notifyListeners();
    } catch (e) {
      debugPrint('[RemoteController] Erro ao inicializar serviços: $e');
    }
  }

  /// Callback disparado quando um dispositivo (Android TV) exige digitação de PIN
  Function(bool prompt)? onPinPromptRequested;

  /// Vincula os callbacks de ciclo de vida do [_driver] ao estado do [RemoteController].
  void _bindDriverCallbacks() {
    _driver.onStateChanged = (state) {
      _isConnecting = state == DeviceConnectionState.connecting;
      _isConnected = state == DeviceConnectionState.connected;
      _isWaitingPairing = state == DeviceConnectionState.pairingPrompt;

      if (_isConnected) {
        _isPoweredOn = true;
        _logAction('${_driver.brandDisplayName} Conectada e Autenticada', {
          'ip': _ipAddress,
          'nome': _connectedTvName,
        });
      } else if (_isWaitingPairing) {
        _logAction('Confirmação pendente na tela do dispositivo ou código PIN');
      }
      notifyListeners();
    };

    _driver.onPinPromptRequested = (prompt) {
      _isWaitingPairing = true;
      onPinPromptRequested?.call(prompt);
      notifyListeners();
    };

    _driver.onAuthTokenReceived = (key) {
      storageService.setClientKey(key);
      _logAction('Chave de autenticação salva com sucesso');
    };

    _driver.onError = (err) {
      _logAction('Erro de conexão', {'msg': err});
    };

    _driver.onDeviceNameResolved = (name, model) {
      _connectedTvName = name;
      storageService.setTvName(name);
      _logAction('Nome da TV identificado', {
        'nome': name,
        'modelo': model,
      });

      final idx = _discoveredTvs.indexWhere((t) => t.ip == _ipAddress);
      final item = DiscoveredTv(
        ip: _ipAddress,
        name: name,
        modelName: model,
        brand: _driver.brand,
      );
      if (idx >= 0) {
        _discoveredTvs[idx] = item;
      } else {
        _discoveredTvs.add(item);
      }
      notifyListeners();
    };

    _driver.onVolumeStatusChanged = (volume, isMuted) {
      _volumeLevel = volume;
      _isMuted = isMuted;
      _logAction('Volume da TV sincronizado', {
        'volume': volume,
        'mudo': isMuted,
      });
      notifyListeners();
    };
  }

  /// Alterna a marca ativa do dispositivo e inicializa o driver correspondente.
  void selectBrand(TvBrand brand, {bool notify = true}) {
    if (_driver.brand == brand) return;
    _driver.disconnect();

    if (brand == TvBrand.lgWebOs) {
      _driver = LgWebOsDriver(webOsService: _webOsService);
    } else {
      _driver = DriverFactory.create(brand);
    }
    _bindDriverCallbacks();
    storageService.setBrand(brand);
    _logAction('Marca selecionada', {'marca': brand.displayName});
    if (notify) notifyListeners();
  }

  // Getters
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isPoweredOn => _isPoweredOn;
  bool get isMuted => _isMuted;
  bool get isWaitingPairing => _isWaitingPairing;
  bool get isScanningTvs => _isScanningTvs;
  int get volumeLevel => _volumeLevel;
  int get currentChannel => _currentChannel;
  String get ipAddress => _ipAddress;
  String get macAddress => _macAddress;
  String? get connectedTvName => _connectedTvName;
  String get lastActionMessage => _lastActionMessage;
  List<DiscoveredTv> get discoveredTvs => _discoveredTvs;

  // --- Gerenciamento de Tema ---

  void toggleTheme() {
    _themeMode = (_themeMode == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
    storageService.setThemeMode(_themeMode.name);
    _logAction('Tema alternado', {'modo': _themeMode.name});
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    storageService.setThemeMode(_themeMode.name);
    _logAction('Tema definido', {'modo': _themeMode.name});
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

  // --- Gerenciamento de Conexão e Rede ---

  Future<void> connect({
    String? ip,
    String? mac,
    String? tvName,
    TvBrand? brand,
  }) async {
    if (_isConnecting) return;

    if (brand != null && brand != _driver.brand) {
      selectBrand(brand, notify: false);
    }
    if (ip != null && ip.trim().isNotEmpty) {
      _ipAddress = ip.trim();
      await storageService.setIpAddress(_ipAddress);
    }
    if (mac != null && mac.trim().isNotEmpty) {
      _macAddress = mac.trim();
      await storageService.setMacAddress(_macAddress);
    }
    if (tvName != null && tvName.trim().isNotEmpty) {
      _connectedTvName = tvName.trim();
      await storageService.setTvName(_connectedTvName);
    }

    _isConnecting = true;
    _isConnected = false;
    _isWaitingPairing = false;
    _logAction('Conectando à TV LG', {
      'ip': _ipAddress,
      'nome': _connectedTvName,
    });
    notifyListeners();

    try {
      final savedKey = storageService.getClientKey();
      final success = await _driver.connect(
        ipAddress: _ipAddress,
        authToken: savedKey,
        timeout: const Duration(seconds: 4),
      );

      _isConnecting = false;
      if (_driver.connectionState == DeviceConnectionState.pairingPrompt) {
        _isConnected = false;
        _isWaitingPairing = true;
        _logAction('Aguardando confirmação na tela da TV', {
          'ip': _ipAddress,
          'nome': _connectedTvName,
        });
      } else if (success) {
        _isConnected = true;
        _isWaitingPairing = false;
        _isPoweredOn = true;
        _shouldMaintainConnection = true;
        _logAction('Conexão estabelecida com sucesso', {
          'ip': _ipAddress,
          'nome': _connectedTvName,
        });
      } else {
        _isConnected = false;
        _isWaitingPairing = false;
        _logAction('Falha ao conectar ao dispositivo', {'ip': _ipAddress});
      }
    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      _isWaitingPairing = false;
      _logAction('Erro de conexão', {'ip': _ipAddress, 'erro': '$e'});
    }
    notifyListeners();
  }

  void disconnect() {
    _shouldMaintainConnection = false;
    _driver.disconnect();
    _isConnected = false;
    _isConnecting = false;
    _isWaitingPairing = false;
    _logAction('Desconectado da TV LG');
    notifyListeners();
  }

  /// Reconecta de forma transparente quando o usuário retorna ao aplicativo
  Future<void> autoReconnectIfNeeded() async {
    if (!_shouldMaintainConnection) return;
    if (_isConnected || _isConnecting) return;
    if (_ipAddress.isEmpty) return;

    await connect(
      ip: _ipAddress,
      mac: _macAddress,
      tvName: _connectedTvName,
    );
  }

  // --- Descoberta Automática de TVs na Rede (SSDP e Probes) ---

  Future<List<DiscoveredTv>> scanForTvs() async {
    if (_isScanningTvs) return _discoveredTvs;
    _isScanningTvs = true;
    _logAction('Buscando TVs LG na rede local (SSDP)...');
    notifyListeners();

    try {
      _discoveredTvs = await SsdpDiscoveryService.discoverTvs(
        timeout: const Duration(seconds: 4),
        knownIp: _ipAddress,
      );

      // Se a TV atual tiver nome resolvido ou estiver salva no histórico, garante que esteja presente
      if (_ipAddress.isNotEmpty && _connectedTvName != null) {
        if (!_discoveredTvs.any((t) => t.ip == _ipAddress)) {
          _discoveredTvs.add(DiscoveredTv(
            ip: _ipAddress,
            name: _connectedTvName!,
            brand: _driver.brand,
          ));
        }
      }

      _logAction('Busca concluída', {'encontradas': _discoveredTvs.length});
    } catch (e) {
      _logAction('Erro na busca SSDP', {'erro': '$e'});
    } finally {
      _isScanningTvs = false;
      notifyListeners();
    }

    return _discoveredTvs;
  }

  void selectDiscoveredTv(DiscoveredTv tv) {
    if (tv.brand != _driver.brand) {
      selectBrand(tv.brand, notify: false);
    }
    _ipAddress = tv.ip;
    _connectedTvName = tv.name;
    storageService.setIpAddress(_ipAddress);
    storageService.setTvName(_connectedTvName);
    _logAction('TV selecionada', {'nome': tv.name, 'ip': tv.ip});
    notifyListeners();
  }

  Future<void> connectToTv(DiscoveredTv tv) async {
    selectDiscoveredTv(tv);
    await connect(ip: tv.ip, tvName: tv.name, brand: tv.brand);
  }

  // --- Controle de Energia ---

  void powerToggle() {
    HapticService.heavyPress();
    _isPoweredOn = !_isPoweredOn;
    if (_isPoweredOn) {
      _logAction('Enviando Wake-on-LAN para ligar a TV', {'mac': _macAddress});
      WakeOnLanService.wake(_macAddress);
    } else {
      _driver.sendKey(RemoteKey.power);
      _isConnected = false;
    }
    _logAction('Power Toggle', {'isPoweredOn': _isPoweredOn});
    notifyListeners();
  }

  // --- Volume, Canal e Mudo ---

  void volumeUp() {
    if (_volumeLevel < 100) {
      _volumeLevel++;
      if (_isMuted) _isMuted = false;
    }
    _driver.sendKey(RemoteKey.volumeUp);
    _logAction('Volume Up', {'level': _volumeLevel, 'muted': _isMuted});
    notifyListeners();
  }

  void volumeDown() {
    if (_volumeLevel > 0) {
      _volumeLevel--;
      if (_isMuted) _isMuted = false;
    }
    _driver.sendKey(RemoteKey.volumeDown);
    _logAction('Volume Down', {'level': _volumeLevel, 'muted': _isMuted});
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    _driver.setMute(_isMuted);
    _logAction('Mute Toggle', {'isMuted': _isMuted});
    notifyListeners();
  }

  void muteToggle() => toggleMute();

  void channelUp() {
    _currentChannel++;
    _driver.sendKey(RemoteKey.channelUp);
    _logAction('Channel Up', {'channel': _currentChannel});
    notifyListeners();
  }

  void channelDown() {
    if (_currentChannel > 1) {
      _currentChannel--;
    }
    _driver.sendKey(RemoteKey.channelDown);
    _logAction('Channel Down', {'channel': _currentChannel});
    notifyListeners();
  }

  // --- Navegação D-Pad ---

  void dpadUp() {
    _driver.sendKey(RemoteKey.dpadUp);
    _logAction('D-Pad UP');
  }

  void dpadDown() {
    _driver.sendKey(RemoteKey.dpadDown);
    _logAction('D-Pad DOWN');
  }

  void dpadLeft() {
    _driver.sendKey(RemoteKey.dpadLeft);
    _logAction('D-Pad LEFT');
  }

  void dpadRight() {
    _driver.sendKey(RemoteKey.dpadRight);
    _logAction('D-Pad RIGHT');
  }

  void dpadOk() {
    _driver.sendKey(RemoteKey.dpadOk);
    _logAction('D-Pad OK / Enter');
  }

  // --- Navegação de Sistema ---

  void pressHome() {
    _driver.sendKey(RemoteKey.home);
    _logAction('Nav Home');
  }

  void navHome() => pressHome();

  void pressMenu() {
    _driver.sendKey(RemoteKey.menu);
    _logAction('Nav Settings (Menu)');
  }

  void navSettings() => pressMenu();

  void pressBack() {
    _driver.sendKey(RemoteKey.back);
    _logAction('Nav Back');
  }

  void navBack() => pressBack();

  void pressExit() {
    _driver.sendKey(RemoteKey.exit);
    _logAction('Nav Exit');
  }

  void navInput() {
    _driver.sendKey(RemoteKey.input);
    _logAction('Nav Input / Source');
  }

  void switchHdmi1() {
    if (_driver is LgWebOsDriver) {
      (_driver as LgWebOsDriver).webOsService.switchToInput('HDMI_1');
    }
    _logAction('Entrada: HDMI 1');
  }

  void switchTvDigital() {
    if (_driver is LgWebOsDriver) {
      (_driver as LgWebOsDriver).webOsService.launchLiveTv();
    }
    _logAction('Entrada: TV Digital');
  }

  // --- Controles Multimídia ---

  void mediaPlay() {
    _driver.sendKey(RemoteKey.play);
    _logAction('Media Play');
  }

  void mediaPause() {
    _driver.sendKey(RemoteKey.pause);
    _logAction('Media Pause');
  }

  void mediaStop() {
    _driver.sendKey(RemoteKey.stop);
    _logAction('Media Stop');
  }

  void mediaRewind() {
    _driver.sendKey(RemoteKey.rewind);
    _logAction('Media Rewind');
  }

  void mediaFastForward() {
    _driver.sendKey(RemoteKey.fastForward);
    _logAction('Media Fast Forward');
  }

  // --- Botões de Cores WebOS ---

  void pressColorRed() {
    _driver.sendKey(RemoteKey.colorRed);
    _logAction('Color RED');
  }

  void colorRed() => pressColorRed();

  void pressColorGreen() {
    _driver.sendKey(RemoteKey.colorGreen);
    _logAction('Color GREEN');
  }

  void colorGreen() => pressColorGreen();

  void pressColorYellow() {
    _driver.sendKey(RemoteKey.colorYellow);
    _logAction('Color YELLOW');
  }

  void colorYellow() => pressColorYellow();

  void pressColorBlue() {
    _driver.sendKey(RemoteKey.colorBlue);
    _logAction('Color BLUE');
  }

  void colorBlue() => pressColorBlue();

  // --- Teclado Numérico ---

  void sendDigit(int digit) {
    _driver.sendDigit(digit);
    _logAction('Keypad Digit', {'digit': digit});
  }

  void inputDigit(int digit) => sendDigit(digit);

  void sendDash() {
    _driver.sendKey(RemoteKey.dash);
    _logAction('Keypad Dash (-)');
  }

  void sendBackspace() {
    _driver.sendKey(RemoteKey.back);
    _logAction('Keypad Backspace');
  }

  // --- Magic Remote: Trackpad e Ponteiro ---

  void sendTrackpadDelta(double dx, double dy) {
    _driver.sendTrackpadDelta(dx, dy);
    _logAction('Trackpad Move', {'dx': dx, 'dy': dy});
  }

  void onTrackpadPan(double dx, double dy) => sendTrackpadDelta(dx, dy);

  void sendTrackpadClick() {
    _driver.sendTrackpadClick();
    _logAction('Trackpad Click / Confirmação');
  }

  void onTrackpadTap() => sendTrackpadClick();

  // --- Entrada de Texto Remota ---

  void sendText(String text) {
    _driver.sendText(text);
    _logAction('Texto enviado', {'text': text});
  }

  // --- Pareamento com PIN (Android TV) ---

  Future<void> sendPairingPin(String pin) async {
    await _driver.sendPairingPin(pin);
    _logAction('PIN enviado', {'pin': pin});
  }
}
