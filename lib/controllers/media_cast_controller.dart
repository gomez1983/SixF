import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/dlna_renderer.dart';
import '../services/dlna_transport.dart';
import '../services/drivers/tv_driver.dart';
import '../services/haptic_service.dart';
import '../services/media_server_service.dart';
import '../services/network_operation.dart';

enum MediaCastStatus {
  idle,
  picking,
  preparingServer,
  connectingTv,
  sent,
  playing,
  paused,
  stopped,
  error,
}

enum MediaCastTransport { none, native, dlna }

/// Controlador de transmissão de mídia e fotos/vídeos locais para a Smart TV (DLNA / UPnP).
class MediaCastController extends ChangeNotifier {
  final MediaServerService _serverService;
  final DlnaTransport _dlna;
  NetworkOperation? _operation;
  bool _disposed = false;
  int _selectionGeneration = 0;
  bool _polling = false;

  MediaCastController({MediaServerService? serverService, DlnaTransport? dlna})
      : _serverService = serverService ?? MediaServerService(),
        _dlna = dlna ?? DlnaTransport();

  bool _current(NetworkOperation operation) => !_disposed && !operation.isCancelled && identical(_operation, operation);

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _cancelTimers() {
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
    _polling = false;
  }

  MediaCastStatus _status = MediaCastStatus.idle;
  String? _currentFileName;
  String? _currentFilePath;
  String? _currentMimeType;
  int? _currentFileSize;
  String? _currentTvName;
  String? _currentControlUrl;
  String? _errorMessage;
  DlnaRenderer? _activeRenderer;
  TvDriver? _activeDriver;

  // Controle de Progresso / Timeline e Loop
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isLooping = false;
  Timer? _positionPollTimer;
  bool _isSeeking = false;
  bool _commandPending = false;
  bool _hasPosition = false;
  bool _loopRestarting = false;
  Set<String> _actions = {};
  MediaCastTransport _transport = MediaCastTransport.none;
  String? _lastCommand;

  MediaCastTransport get transport => _transport;
  bool get hasProgress => isStreaming && !isPhoto && _transport == MediaCastTransport.dlna && _hasPosition;
  bool get canSeek => hasProgress && _totalDuration > Duration.zero && _actions.contains('Seek') && !_isSeeking && !_commandPending && !_polling;
  bool get canLoop => canSeek && _actions.contains('Play');
  bool get canPlay => _canCommand('Play');
  bool get canPause => _canCommand('Pause');
  bool _canCommand(String action) => isStreaming && !isPhoto && !_commandPending && !_isSeeking && !_polling &&
      (_transport == MediaCastTransport.native
          ? _activeDriver?.isConnected == true
          : _actions.contains(action));

  String get playbackLabel {
    if (isPhoto) return 'Imagem enviada à TV';
    if (_status == MediaCastStatus.playing) return 'Reproduzindo na TV';
    if (_status == MediaCastStatus.paused) return 'Pausado na TV';
    if (_status == MediaCastStatus.stopped) return 'Reprodução parada na TV';
    return _lastCommand ?? 'Mídia enviada à TV';
  }


  MediaCastStatus get status => _status;
  bool get isStreaming => const {MediaCastStatus.sent, MediaCastStatus.playing, MediaCastStatus.paused, MediaCastStatus.stopped}.contains(_status);
  bool get isPlaying => _status == MediaCastStatus.playing;
  bool get isPaused => _status == MediaCastStatus.paused;
  bool get isVideo => _currentMimeType?.startsWith('video/') ?? false;
  bool get isPhoto => _currentMimeType?.startsWith('image/') ?? false;
  bool get isAudio => _currentMimeType?.startsWith('audio/') ?? false;

  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  bool get isLooping => _isLooping;
  bool get isSeeking => _isSeeking;

  String? get currentFileName => _currentFileName;
  String? get currentFilePath => _currentFilePath;
  String? get currentMimeType => _currentMimeType;
  int? get currentFileSize => _currentFileSize;
  String? get currentTvName => _currentTvName;
  String? get errorMessage => _errorMessage;
  DlnaRenderer? get activeRenderer => _activeRenderer;
  TvDriver? get activeDriver => _activeDriver;

  /// Abre a galeria/seletor de arquivos do dispositivo e transmite para a Smart TV selecionada.
  Future<bool> pickAndCastMedia({
    required String targetTvIp,
    required TvBrand brand,
    String? tvName,
    String? locationUrl,
    FileType fileType = FileType.media,
    TvDriver? activeDriver,
  }) async {
    if (_disposed) return false;
    final selection = ++_selectionGeneration;
    final previousStatus = _status;
    _setErrorMessage(null);
    _status = MediaCastStatus.picking;
    notifyListeners();

    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: fileType,
      );

      if (_disposed || selection != _selectionGeneration) return false;
      if (pickedFiles.isEmpty || pickedFiles.first.path == null) {
        _status = previousStatus;
        notifyListeners();
        return false;
      }

      HapticService.selectionClick();
      final pickedFile = pickedFiles.first;
      final path = pickedFile.path!;
      final file = File(path);
      if (!await file.exists()) {
        throw Exception('O arquivo selecionado não foi encontrado no armazenamento.');
      }

      if (_disposed || selection != _selectionGeneration) return false;
      return await castFile(
        file,
        fileName: pickedFile.name,
        targetTvIp: targetTvIp,
        brand: brand,
        tvName: tvName,
        locationUrl: locationUrl,
        activeDriver: activeDriver,
      );
    } catch (e) {
      if (_disposed || selection != _selectionGeneration) return false;
      debugPrint('[MediaCast] Erro ao selecionar mídia: $e');
      _status = MediaCastStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Transmite um arquivo local específico diretamente para a Smart TV selecionada.
  ///
  /// Se um [activeDriver] conectado for fornecido (ex: LG webOS ou Samsung Tizen já pareada),
  /// fotos priorizam a API nativa do fabricante (SSAP / WebSocket).
  /// Vídeos e áudios LG priorizam DLNA / UPnP AVTransport com Play explícito;
  /// a API nativa é alternativa quando esse transporte recusa o envio.
  Future<bool> castFile(
    File file, {
    String? fileName,
    required String targetTvIp,
    required TvBrand brand,
    String? tvName,
    String? locationUrl,
    TvDriver? activeDriver,
  }) async {
    if (_disposed) return false;
    _selectionGeneration++;
    _operation?.cancel();
    _cancelTimers();
    final operation = NetworkOperation();
    _operation = operation;
    final closing = _serverService.stop();
    _currentControlUrl = null;
    _activeRenderer = null;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _isSeeking = false;
    _commandPending = false;
    _hasPosition = false;
    _loopRestarting = false;
    _isLooping = false;
    _actions = {};
    _transport = MediaCastTransport.none;
    _lastCommand = null;
    try {
      await closing;
      if (!_current(operation)) return false;
      return await operation.run(() => _castFile(file, operation: operation,
        fileName: fileName, targetTvIp: targetTvIp, brand: brand,
        tvName: tvName, locationUrl: locationUrl, activeDriver: activeDriver));
    } on OperationCancelled {
      return false;
    }
  }

  Future<bool> _castFile(
    File file, {
    required NetworkOperation operation,
    String? fileName,
    required String targetTvIp,
    required TvBrand brand,
    String? tvName,
    String? locationUrl,
    TvDriver? activeDriver,
  }) async {
    _setErrorMessage(null);
    _activeDriver = activeDriver;

    try {
      if (!await file.exists()) {
        throw Exception('O arquivo selecionado não foi encontrado no armazenamento.');
      }

      operation.check();
      _currentFileName = fileName ?? file.uri.pathSegments.last;
      _currentFilePath = file.path;
      _currentFileSize = await file.length();
      operation.check();
      _currentTvName = tvName ?? '${brand.displayName} ($targetTvIp)';

      // 1. Inicia ou reutiliza o servidor HTTP local
      _status = MediaCastStatus.preparingServer;
      notifyListeners();

      operation.check();
      await _serverService.start();
      operation.check();
      _serverService.serveFile(file, customName: _currentFileName);
      _currentMimeType = _serverService.currentMimeType;

      final mediaUrl = await _serverService.getMediaUrlForTv(targetTvIp);
      operation.check();
      if (mediaUrl == null) {
        throw Exception('Não foi possível identificar o IP local do celular/PC na mesma rede da TV.');
      }

      _status = MediaCastStatus.connectingTv;
      notifyListeners();

      // O visualizador nativo LG pode aceitar a abertura sem iniciar o vídeo.
      // AVTransport carrega a URI e envia Play explicitamente no mesmo endpoint.
      final preferDlna = brand == TvBrand.lgWebOs && (isVideo || isAudio);
      if (!preferDlna && await _tryNative(mediaUrl, operation)) return true;
      final renderer = await _dlna.resolveRenderer(targetTvIp,
        locationUrl: locationUrl, brand: brand, tvName: tvName);
      operation.check();
      if (renderer == null) {
        if (await _tryNative(mediaUrl, operation)) return true;
        throw Exception('A Smart TV não respondeu aos comandos de mídia DLNA/UPnP.');
      }
      final setResult = await _dlna.setUri(renderer.controlUrl, mediaUrl,
        title: _currentFileName ?? 'Mídia SixF',
        mimeType: _currentMimeType ?? 'video/mp4', fileSize: _currentFileSize);
      operation.check();
      if (!setResult.success) {
        if (await _tryNative(mediaUrl, operation)) return true;
        throw Exception(setResult.userFriendlyMessage);
      }

      // Mantém todos os comandos no endpoint que aceitou a URI, inclusive no fallback.
      _currentControlUrl = setResult.controlUrl ?? renderer.controlUrl;
      _activeRenderer = DlnaRenderer(ip: renderer.ip, name: renderer.name,
        controlUrl: _currentControlUrl!, locationUrl: renderer.locationUrl, brand: renderer.brand);
      _transport = MediaCastTransport.dlna;
      if (!isPhoto) {
        final playResult = await _dlna.play(_currentControlUrl!);
        operation.check();
        if (!playResult.success) {
          if (await _tryNative(mediaUrl, operation)) return true;
          throw Exception(playResult.userFriendlyMessage);
        }
      }
      _status = MediaCastStatus.sent;
      HapticService.heavyPress();
      notifyListeners();
      if (!isPhoto) {
        await _refreshPlayback(operation);
        operation.check();
        _startPositionPolling();
      }
      return true;
    } catch (e) {
      if (!_current(operation)) return false;
      _cancelTimers();
      await _serverService.stop();
      if (!_current(operation)) return false;
      debugPrint('[MediaCast] Erro ao transmitir mídia: ${e.runtimeType}');
      _status = MediaCastStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> _tryNative(String mediaUrl, NetworkOperation operation) async {
    final driver = _activeDriver;
    if (driver == null || !driver.isConnected) return false;
    bool accepted;
    try {
      accepted = await driver.openMediaUrl(mediaUrl,
        title: _currentFileName ?? 'Mídia SixF', mimeType: _currentMimeType);
    } catch (_) {
      operation.check();
      return false;
    }
    operation.check();
    if (!accepted) return false;
    _transport = MediaCastTransport.native;
    _currentControlUrl = null;
    _activeRenderer = null;
    _status = MediaCastStatus.sent;
    HapticService.heavyPress();
    notifyListeners();
    return true;
  }

  Future<void> pause() => _sendPlaybackCommand(false);
  Future<void> play() => _sendPlaybackCommand(true);

  Future<void> _sendPlaybackCommand(bool play) async {
    final operation = _operation;
    if (operation == null || !_current(operation) || !(play ? canPlay : canPause)) return;
    _commandPending = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (_transport == MediaCastTransport.native) {
        _activeDriver!.sendKey(play ? RemoteKey.play : RemoteKey.pause);
      } else {
        final result = await operation.run(() => play
            ? _dlna.play(_currentControlUrl!) : _dlna.pause(_currentControlUrl!));
        operation.check();
        if (!result.success) throw Exception(result.userFriendlyMessage);
      }
      _status = MediaCastStatus.sent;
      _lastCommand = play ? 'Comando de reprodução enviado' : 'Comando de pausa enviado';
      if (_transport == MediaCastTransport.dlna) await _refreshPlayback(operation);
    } catch (e) {
      if (_current(operation)) _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (_current(operation)) {
        _commandPending = false;
        notifyListeners();
      }
    }
  }

  void toggleLoop() {
    if (!_isLooping && !canLoop) return;
    HapticService.selectionClick();
    _isLooping = !_isLooping;
    notifyListeners();
  }

  Future<bool> seekTo(Duration target) async {
    final operation = _operation;
    if (operation == null || !_current(operation) || !canSeek) return false;
    target = Duration(milliseconds: target.inMilliseconds.clamp(0, _totalDuration.inMilliseconds));
    final targetTime = '${target.inHours.toString().padLeft(2, '0')}:'
        '${(target.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(target.inSeconds % 60).toString().padLeft(2, '0')}';
    _isSeeking = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await operation.run(() => _dlna.seek(_currentControlUrl!, targetTime));
      operation.check();
      if (!result.success) throw Exception(result.userFriendlyMessage);
      // A posição exibida continua sendo a informada pela TV.
      await _refreshPlayback(operation);
      return _current(operation);
    } catch (e) {
      if (_current(operation)) _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      if (_current(operation)) {
        _isSeeking = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshPlayback(NetworkOperation operation) async {
    if (!_current(operation) || _currentControlUrl == null || isPhoto || _polling) return;
    final url = _currentControlUrl!;
    _polling = true;
    try {
      final state = await operation.run(() => _dlna.state(url));
      operation.check();
      _status = switch (state) {
        'PLAYING' => MediaCastStatus.playing,
        'PAUSED_PLAYBACK' => MediaCastStatus.paused,
        'STOPPED' || 'NO_MEDIA_PRESENT' => MediaCastStatus.stopped,
        _ => MediaCastStatus.sent,
      };
      final actions = await operation.run(() => _dlna.actions(url));
      operation.check();
      _actions = actions ?? {};
      final position = await operation.run(() => _dlna.position(url));
      operation.check();
      _hasPosition = position != null && position.duration > Duration.zero;
      if (position != null) {
        _totalDuration = position.duration;
        _currentPosition = position.position;
      }
    } catch (_) {
      if (_current(operation)) {
        _status = MediaCastStatus.sent;
        _actions = {};
        _hasPosition = false;
      }
    } finally {
      if (_current(operation)) {
        _polling = false;
        notifyListeners();
      }
    }
  }

  void _startPositionPolling() {
    final operation = _operation;
    if (operation == null || !_current(operation)) return;
    _positionPollTimer?.cancel();
    _positionPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_current(operation) || _polling || _isSeeking || _commandPending || _loopRestarting) return;
      final wasPlaying = isPlaying;
      await _refreshPlayback(operation);
      if (!_current(operation)) return;
      // Repete apenas após uma transição real para STOPPED, sem cortar o fim do vídeo.
      if (_isLooping && wasPlaying && _status == MediaCastStatus.stopped && canLoop) {
        _loopRestarting = true;
        try {
          if (await seekTo(Duration.zero) && _current(operation)) await play();
        } finally {
          if (_current(operation)) _loopRestarting = false;
        }
      }
    });
  }

  /// Encerra a transmissão e libera a TV e o servidor local.
  Future<void> stop() async {
    if (_disposed) return;
    _selectionGeneration++;
    _operation?.cancel();
    _cancelTimers();
    final driver = _transport == MediaCastTransport.native ? _activeDriver : null;
    final controlUrl = _currentControlUrl;
    final operation = NetworkOperation();
    _operation = operation;
    // Revoga o acesso ao arquivo antes de aguardar qualquer resposta da TV.
    final closing = _serverService.stop();
    _status = MediaCastStatus.idle;
    _transport = MediaCastTransport.none;
    _isLooping = false;
    _actions = {};
    _hasPosition = false;
    _commandPending = false;
    _loopRestarting = false;
    _lastCommand = null;
    _errorMessage = null;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _isSeeking = false;
    _currentFileName = null;
    _currentFilePath = null;
    _currentFileSize = null;
    _currentMimeType = null;
    _activeDriver = null;
    _activeRenderer = null;
    _currentControlUrl = null;
    notifyListeners();
    if (driver != null && driver.isConnected) {
      try {
        driver.sendKey(RemoteKey.stop);
        driver.sendKey(RemoteKey.back);
      } catch (_) {}
    }
    await closing;
    if (controlUrl != null && _current(operation)) {
      try { await operation.run(() => _dlna.stop(controlUrl)); } catch (_) {}
    }
  }

  void _setErrorMessage(String? msg) {
    _errorMessage = msg;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _selectionGeneration++;
    _operation?.cancel();
    _cancelTimers();
    _serverService.stop();
    super.dispose();
  }
}
