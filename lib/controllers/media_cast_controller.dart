import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/dlna_renderer.dart';
import '../services/dlna_service.dart';
import '../services/drivers/tv_driver.dart';
import '../services/haptic_service.dart';
import '../services/media_server_service.dart';

enum MediaCastStatus {
  idle,
  picking,
  preparingServer,
  connectingTv,
  playing,
  paused,
  stopped,
  error,
}

/// Controlador de transmissão de mídia e fotos/vídeos locais para a Smart TV (DLNA / UPnP).
class MediaCastController extends ChangeNotifier {
  final MediaServerService _serverService = MediaServerService();

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

  MediaCastStatus get status => _status;
  bool get isStreaming => _status == MediaCastStatus.playing || _status == MediaCastStatus.paused;
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
    _setErrorMessage(null);
    _status = MediaCastStatus.picking;
    _activeDriver = activeDriver;
    notifyListeners();

    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: fileType,
      );

      if (pickedFiles.isEmpty || pickedFiles.first.path == null) {
        _status = isStreaming ? _status : MediaCastStatus.idle;
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
  /// tenta prioritariamente a reprodução via API nativa do fabricante (SSAP / WebSocket).
  /// Caso contrário ou em caso de recusa da TV, recorre ao protocolo aberto DLNA / UPnP AVTransport.
  Future<bool> castFile(
    File file, {
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

      _currentFileName = fileName ?? file.uri.pathSegments.last;
      _currentFilePath = file.path;
      _currentFileSize = await file.length();
      _currentTvName = tvName ?? '${brand.displayName} ($targetTvIp)';

      // 1. Inicia ou reutiliza o servidor HTTP local
      _status = MediaCastStatus.preparingServer;
      notifyListeners();

      await _serverService.start();
      _serverService.serveFile(file, customName: _currentFileName);
      _currentMimeType = _serverService.currentMimeType;

      final mediaUrl = await _serverService.getMediaUrlForTv(targetTvIp);
      if (mediaUrl == null) {
        throw Exception('Não foi possível identificar o IP local do celular/PC na mesma rede da TV.');
      }

      // 2. Canal de Envio:
      // Se houver driver nativo conectado (LG webOS SSAP / Samsung WebSocket), utiliza prioritariamente
      // a API nativa da TV (ssap://media.viewer/open e system.launcher).
      // Isso elimina 100% de erros de recusa de porta de rede (como Erro 1225 do DLNA/UPnP).
      _status = MediaCastStatus.connectingTv;
      notifyListeners();

      if (activeDriver != null && activeDriver.isConnected) {
        debugPrint('[MediaCast] Transmitindo mídia via canal nativo do fabricante (${activeDriver.runtimeType})...');
        try {
          final nativeSuccess = await activeDriver.openMediaUrl(
            mediaUrl,
            title: _currentFileName ?? 'Mídia SixF',
            mimeType: _currentMimeType,
          );
          if (nativeSuccess) {
            debugPrint('[MediaCast] Mídia iniciada com sucesso via canal nativo do driver!');
            _status = MediaCastStatus.playing;
            HapticService.heavyPress();
            notifyListeners();

            if (!isPhoto) {
              Future.delayed(const Duration(milliseconds: 600), () {
                try {
                  activeDriver.sendKey(RemoteKey.play);
                } catch (_) {}
              });
              _startPositionPolling();
            }
            return true;
          }
        } catch (nativeErr) {
          debugPrint('[MediaCast] Canal nativo falhou ($nativeErr), recorrendo ao fallback DLNA...');
        }
      }

      // 3. Canal Universal / DLNA AVTransport (Fallback para reprodutores genéricos ou quando driver desconectado)
      debugPrint('[MediaCast] Acionando canal DLNA AVTransport para $targetTvIp (${_currentMimeType})...');
      final renderer = await DlnaService.resolveRenderer(
        targetTvIp,
        locationUrl: locationUrl,
        brand: brand,
        tvName: tvName,
      );

      if (renderer == null) {
        // Se o DLNA não respondeu, tenta uma última vez via canal nativo caso disponível
        if (activeDriver != null && activeDriver.isConnected) {
          final fallbackSuccess = await activeDriver.openMediaUrl(
            mediaUrl,
            title: _currentFileName ?? 'Mídia SixF',
            mimeType: _currentMimeType,
          );
          if (fallbackSuccess) {
            _status = MediaCastStatus.playing;
            notifyListeners();
            return true;
          }
        }
        throw Exception('A Smart TV não respondeu aos comandos de mídia DLNA/UPnP.');
      }

      _activeRenderer = renderer;
      _currentControlUrl = renderer.controlUrl;

      // 4. Envia SetAVTransportURI
      final setResult = await DlnaService.setAVTransportURI(
        renderer.controlUrl,
        mediaUrl,
        title: _currentFileName ?? 'Mídia SixF',
        mimeType: _currentMimeType ?? 'video/mp4',
        fileSize: _currentFileSize,
      );

      if (!setResult.success) {
        // Se falhou por recusa de porta de rede (errno 1225) e há driver conectado, tenta acioná-lo imediatamente
        if (activeDriver != null && activeDriver.isConnected) {
          debugPrint('[MediaCast] DLNA recusou conexão (1225). Tentando recuperar via canal nativo...');
          final recoverySuccess = await activeDriver.openMediaUrl(
            mediaUrl,
            title: _currentFileName ?? 'Mídia SixF',
            mimeType: _currentMimeType,
          );
          if (recoverySuccess) {
            _status = MediaCastStatus.playing;
            HapticService.heavyPress();
            notifyListeners();
            if (!isPhoto) {
              Future.delayed(const Duration(milliseconds: 600), () {
                try {
                  activeDriver.sendKey(RemoteKey.play);
                } catch (_) {}
              });
              _startPositionPolling();
            }
            return true;
          }
        }
        throw Exception(setResult.userFriendlyMessage);
      }

      // Para fotos estáticas, SetAVTransportURI já renderiza a imagem na TV.
      // Dispara comando Play apenas para vídeos e áudios para não causar erro 701 na TV.
      if (!isPhoto) {
        final playResult = await DlnaService.play(renderer.controlUrl);
        if (!playResult.success) {
          debugPrint('[MediaCast] Aviso ao acionar Play via DLNA: ${playResult.userFriendlyMessage}');
        }
        // Se houver driver LG webOS conectado e o SmartShare abrir em pausa, envia tecla Play física
        if (activeDriver != null && activeDriver.isConnected) {
          Future.delayed(const Duration(milliseconds: 600), () {
            try {
              activeDriver.sendKey(RemoteKey.play);
            } catch (_) {}
          });
        }
        // Inicia o monitoramento de progresso e loop
        _startPositionPolling();
      }

      _status = MediaCastStatus.playing;
      HapticService.heavyPress();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[MediaCast] Erro ao transmitir mídia: $e');
      _status = MediaCastStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Pausa a reprodução na TV.
  Future<void> pause() async {
    HapticService.selectionClick();
    if (_currentControlUrl != null) {
      final result = await DlnaService.pause(_currentControlUrl!);
      if (result.success) {
        _status = MediaCastStatus.paused;
        notifyListeners();
        return;
      }
    }
    if (_activeDriver != null && _activeDriver!.isConnected) {
      _activeDriver!.sendKey(RemoteKey.pause);
      _status = MediaCastStatus.paused;
      notifyListeners();
    }
  }

  /// Retoma a reprodução na TV.
  Future<void> play() async {
    HapticService.selectionClick();
    if (_currentControlUrl != null) {
      final result = await DlnaService.play(_currentControlUrl!);
      if (result.success) {
        _status = MediaCastStatus.playing;
        notifyListeners();
        return;
      }
    }
    if (_activeDriver != null && _activeDriver!.isConnected) {
      _activeDriver!.sendKey(RemoteKey.play);
      _status = MediaCastStatus.playing;
      notifyListeners();
    }
  }

  /// Alterna a repetição contínua (Loop) do vídeo/áudio.
  void toggleLoop() {
    HapticService.selectionClick();
    _isLooping = !_isLooping;
    notifyListeners();
  }

  /// Realiza busca rápida de posição (Seek) no vídeo.
  Future<void> seekTo(Duration target) async {
    if (_currentControlUrl == null || isPhoto) return;
    _isSeeking = true;
    _currentPosition = target;
    notifyListeners();

    final hours = target.inHours.toString().padLeft(2, '0');
    final minutes = (target.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (target.inSeconds % 60).toString().padLeft(2, '0');
    final targetTimeStr = '$hours:$minutes:$seconds';

    debugPrint('[MediaCast] Executando Seek para: $targetTimeStr');
    await DlnaService.seek(_currentControlUrl!, targetTimeStr);
    _isSeeking = false;
  }

  /// Polling periódico da posição de reprodução e detecção de loop.
  void _startPositionPolling() {
    _positionPollTimer?.cancel();
    _positionPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_currentControlUrl == null || _status != MediaCastStatus.playing || isPhoto) {
        return;
      }

      if (_isSeeking) return;

      try {
        final posInfo = await DlnaService.getPositionInfo(_currentControlUrl!);
        if (posInfo != null) {
          if (posInfo.duration > Duration.zero) {
            _totalDuration = posInfo.duration;
          }
          _currentPosition = posInfo.position;
          notifyListeners();

          // Detecção de fim de vídeo para loop automático
          if (_isLooping && _totalDuration > Duration.zero) {
            final remaining = _totalDuration - _currentPosition;
            if (remaining <= const Duration(seconds: 1)) {
              debugPrint('[MediaCast] Loop ativado: reiniciando vídeo do início...');
              await seekTo(Duration.zero);
              await play();
            }
          }
        } else {
          // Fallback se GetPositionInfo não for retornado: verifica estado de transporte
          if (_isLooping) {
            final state = await DlnaService.getTransportInfo(_currentControlUrl!);
            if (state == 'STOPPED') {
              debugPrint('[MediaCast] Vídeo finalizado (STOPPED) e loop ativo: reiniciando...');
              await seekTo(Duration.zero);
              await play();
            }
          }
        }
      } catch (_) {}
    });
  }

  /// Encerra a transmissão e libera a TV e o servidor local.
  Future<void> stop() async {
    HapticService.buttonPress();
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;

    if (_activeDriver != null && _activeDriver!.isConnected) {
      try {
        _activeDriver!.sendKey(RemoteKey.stop);
        _activeDriver!.sendKey(RemoteKey.back);
      } catch (_) {}
    }
    if (_currentControlUrl != null) {
      try {
        await DlnaService.stop(_currentControlUrl!);
      } catch (e) {
        debugPrint('[MediaCast] Aviso ao interromper na TV: $e');
      }
    }
    await _serverService.stop();
    _status = MediaCastStatus.idle;
    _currentFileName = null;
    _currentFilePath = null;
    _currentFileSize = null;
    _currentMimeType = null;
    _activeDriver = null;
    _activeRenderer = null;
    _currentControlUrl = null;
    notifyListeners();
  }

  void _setErrorMessage(String? msg) {
    _errorMessage = msg;
  }

  @override
  void dispose() {
    _positionPollTimer?.cancel();
    _serverService.stop();
    super.dispose();
  }
}
