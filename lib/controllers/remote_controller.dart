import 'package:flutter/material.dart';
import '../services/ssdp_discovery_service.dart';
import '../services/storage_service.dart';
import '../services/wake_on_lan_service.dart';
import '../services/webos_service.dart';

/// Controlador de estado do controle remoto para Smart TV LG.
///
/// Integra a interface gráfica com os serviços de back-end:
/// - [WebOsService]: Comunicação WebSocket SSAP, Pointer Socket (Magic Remote), handshake e SSL.
/// - [WakeOnLanService]: Ligar TV via broadcast UDP Magic Packet.
/// - [SsdpDiscoveryService]: Descoberta automática de TVs na rede local com extração do friendlyName.
/// - [StorageService]: Persistência de parâmetros e chaves de pareamento.
class RemoteController extends ChangeNotifier {
  // Serviços de Back-End
  final StorageService storageService = StorageService();
  final WebOsService webOsService = WebOsService();

  // Estado de tema
  ThemeMode _themeMode = ThemeMode.dark;

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
  String _lastActionMessage = 'Aguardando conexão com a TV LG';
  List<DiscoveredTv> _discoveredTvs = [];

  RemoteController() {
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      await storageService.init();
      _ipAddress = storageService.getIpAddress(defaultValue: _ipAddress);
      _macAddress = storageService.getMacAddress(defaultValue: _macAddress);
      _connectedTvName = storageService.getTvName();

      final savedTheme = storageService.getThemeMode();
      if (savedTheme == 'light') {
        _themeMode = ThemeMode.light;
      } else {
        _themeMode = ThemeMode.dark;
      }
      notifyListeners();

      // Configuração dos callbacks do WebOsService
      webOsService.onStateChanged = (state) {
        _isConnecting = state == WebOsConnectionState.connecting;
        _isConnected = state == WebOsConnectionState.connected;
        _isWaitingPairing = state == WebOsConnectionState.pairingPrompt;

        if (_isConnected) {
          _isPoweredOn = true;
          _logAction('TV LG Conectada e Autenticada', {
            'ip': _ipAddress,
            'nome': ?_connectedTvName,
          });
        } else if (_isWaitingPairing) {
          _logAction('Confirmação pendente na tela da TV LG');
        }
        notifyListeners();
      };

      webOsService.onClientKeyReceived = (key) {
        storageService.setClientKey(key);
        _logAction('Chave client-key salva com sucesso');
      };

      webOsService.onError = (err) {
        _logAction('Erro de conexão', {'msg': err});
      };

      // Resolução automática do nome amigável da TV (ex: "André TV")
      webOsService.onDeviceNameResolved = (name, model) {
        _connectedTvName = name;
        storageService.setTvName(name);
        _logAction('Nome da TV identificado', {
          'nome': name,
          'modelo': ?model,
        });

        // Adiciona ou atualiza na lista de descobertos
        final idx = _discoveredTvs.indexWhere((t) => t.ip == _ipAddress);
        final item = DiscoveredTv(ip: _ipAddress, name: name, modelName: model);
        if (idx >= 0) {
          _discoveredTvs[idx] = item;
        } else {
          _discoveredTvs.add(item);
        }
        notifyListeners();
      };

      // Sincronização em tempo real do volume real da TV LG
      webOsService.onVolumeStatusChanged = (volume, isMuted) {
        _volumeLevel = volume;
        _isMuted = isMuted;
        _logAction('Volume da TV sincronizado', {
          'volume': volume,
          'mudo': isMuted,
        });
        notifyListeners();
      };
    } catch (e) {
      debugPrint('[RemoteController] Erro ao inicializar serviços: $e');
    }
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

  void _logAction(String action, [Map<String, dynamic>? params]) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final paramsStr = (params != null && params.isNotEmpty) ? ' -> $params' : '';
    _lastActionMessage = '[$timestamp] $action$paramsStr';
    debugPrint('[LG_REMOTE] $timestamp | Ação: $action$paramsStr');
    notifyListeners();
  }

  // --- Gerenciamento de Conexão e Rede ---

  Future<void> connect({String? ip, String? mac, String? tvName}) async {
    if (_isConnecting) return;
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
      'nome': ?_connectedTvName,
    });
    notifyListeners();

    try {
      final savedKey = storageService.getClientKey();
      final success = await webOsService.connect(
        ipAddress: _ipAddress,
        savedClientKey: savedKey,
        timeout: const Duration(seconds: 4),
      );

      _isConnecting = false;
      _isConnected = success;
      if (success) {
        _isPoweredOn = true;
        _shouldMaintainConnection = true;
        _logAction('Conexão estabelecida com sucesso', {
          'ip': _ipAddress,
          'nome': ?_connectedTvName,
        });
      } else {
        _logAction('Falha ao conectar à TV', {'ip': _ipAddress});
      }
    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      _logAction('Erro de conexão', {'ip': _ipAddress, 'erro': '$e'});
    }
    notifyListeners();
  }

  void disconnect() {
    _shouldMaintainConnection = false;
    webOsService.disconnect();
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
    _ipAddress = tv.ip;
    _connectedTvName = tv.name;
    storageService.setIpAddress(_ipAddress);
    storageService.setTvName(_connectedTvName);
    _logAction('TV selecionada', {'nome': tv.name, 'ip': tv.ip});
    notifyListeners();
  }

  Future<void> connectToTv(DiscoveredTv tv) async {
    selectDiscoveredTv(tv);
    await connect(ip: tv.ip, tvName: tv.name);
  }

  // --- Controle de Energia ---

  void powerToggle() {
    _isPoweredOn = !_isPoweredOn;
    if (_isPoweredOn) {
      _logAction('Enviando Wake-on-LAN para ligar a TV', {'mac': _macAddress});
      WakeOnLanService.wake(_macAddress);
    } else {
      webOsService.turnOff();
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
    webOsService.volumeUp();
    _logAction('Volume Up', {'level': _volumeLevel, 'muted': _isMuted});
    notifyListeners();
  }

  void volumeDown() {
    if (_volumeLevel > 0) {
      _volumeLevel--;
      if (_isMuted) _isMuted = false;
    }
    webOsService.volumeDown();
    _logAction('Volume Down', {'level': _volumeLevel, 'muted': _isMuted});
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    webOsService.setMute(_isMuted);
    _logAction('Mute Toggle', {'isMuted': _isMuted});
    notifyListeners();
  }

  void muteToggle() => toggleMute();

  void channelUp() {
    _currentChannel++;
    webOsService.channelUp();
    _logAction('Channel Up', {'channel': _currentChannel});
    notifyListeners();
  }

  void channelDown() {
    if (_currentChannel > 1) {
      _currentChannel--;
    }
    webOsService.channelDown();
    _logAction('Channel Down', {'channel': _currentChannel});
    notifyListeners();
  }

  // --- Navegação D-Pad ---

  void dpadUp() {
    webOsService.dpadUp();
    _logAction('D-Pad UP');
  }

  void dpadDown() {
    webOsService.dpadDown();
    _logAction('D-Pad DOWN');
  }

  void dpadLeft() {
    webOsService.dpadLeft();
    _logAction('D-Pad LEFT');
  }

  void dpadRight() {
    webOsService.dpadRight();
    _logAction('D-Pad RIGHT');
  }

  void dpadOk() {
    webOsService.pressOk();
    _logAction('D-Pad OK / Enter');
  }

  // --- Navegação de Sistema ---

  void pressHome() {
    webOsService.pressHome();
    _logAction('Nav Home');
  }

  void navHome() => pressHome();

  void pressMenu() {
    webOsService.pressMenu();
    _logAction('Nav Settings (Menu)');
  }

  void navSettings() => pressMenu();

  void pressBack() {
    webOsService.pressBack();
    _logAction('Nav Back');
  }

  void navBack() => pressBack();

  void pressExit() {
    webOsService.pressExit();
    _logAction('Nav Exit');
  }

  void navInput() {
    webOsService.sendButton('INPUT');
    _logAction('Nav Input / Source');
  }

  void switchHdmi1() {
    webOsService.switchToInput('HDMI_1');
    _logAction('Entrada: HDMI 1');
  }

  void switchTvDigital() {
    webOsService.launchLiveTv();
    _logAction('Entrada: TV Digital');
  }

  // --- Controles Multimídia ---

  void mediaPlay() {
    webOsService.mediaPlay();
    _logAction('Media Play');
  }

  void mediaPause() {
    webOsService.mediaPause();
    _logAction('Media Pause');
  }

  void mediaStop() {
    webOsService.mediaStop();
    _logAction('Media Stop');
  }

  void mediaRewind() {
    webOsService.mediaRewind();
    _logAction('Media Rewind');
  }

  void mediaFastForward() {
    webOsService.mediaFastForward();
    _logAction('Media Fast Forward');
  }

  // --- Botões de Cores WebOS ---

  void pressColorRed() {
    webOsService.pressColorRed();
    _logAction('Color RED');
  }

  void colorRed() => pressColorRed();

  void pressColorGreen() {
    webOsService.pressColorGreen();
    _logAction('Color GREEN');
  }

  void colorGreen() => pressColorGreen();

  void pressColorYellow() {
    webOsService.pressColorYellow();
    _logAction('Color YELLOW');
  }

  void colorYellow() => pressColorYellow();

  void pressColorBlue() {
    webOsService.pressColorBlue();
    _logAction('Color BLUE');
  }

  void colorBlue() => pressColorBlue();

  // --- Teclado Numérico ---

  void sendDigit(int digit) {
    webOsService.pressDigit(digit);
    _logAction('Keypad Digit', {'digit': digit});
  }

  void inputDigit(int digit) => sendDigit(digit);

  void sendDash() {
    webOsService.pressDash();
    _logAction('Keypad Dash (-)');
  }

  void sendBackspace() {
    webOsService.pressBack();
    _logAction('Keypad Backspace');
  }

  // --- Magic Remote: Trackpad e Ponteiro ---

  void sendTrackpadDelta(double dx, double dy) {
    webOsService.sendTrackpadDelta(dx, dy);
    _logAction('Trackpad Move', {'dx': dx, 'dy': dy});
  }

  void onTrackpadPan(double dx, double dy) => sendTrackpadDelta(dx, dy);

  void sendTrackpadClick() {
    webOsService.sendTrackpadClick();
    _logAction('Trackpad Click / Confirmação');
  }

  void onTrackpadTap() => sendTrackpadClick();
}
