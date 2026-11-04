import '../services/media_remux_service.dart';

import 'dart:convert';

import '../services/google_cast_media.dart';

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

enum MediaCastTransport { none, native, dlna, cast }

/// Controlador de transmissÃ£o de mÃ­dia e fotos/vÃ­deos locais para a Smart TV (DLNA / UPnP).
class MediaCastController extends ChangeNotifier {
  final MediaServerService _serverService;
  final DlnaTransport _dlna;
  GoogleCastMedia? _cast;
  final GoogleCastMedia Function() _castFactory;
  final Future<MediaDetails> Function(String) _probeMedia;
  Duration _sourceDuration = Duration.zero;
  Duration _castOffset = Duration.zero;
  bool _remuxCast = false;
  NetworkOperation? _operation;
  bool _disposed = false;
  int _selectionGeneration = 0;
  bool _polling = false;
  List<Future<File> Function()> _playlist = [];
  bool _sequential = false;
  List<String>? _playlistNames;
  List<int> _order = [];
  int _playlistIndex = 0;
  bool _shuffling = false;
  bool _navigating = false;
  String? _targetIp;
  TvBrand? _targetBrand;
  ({
    String ip,
    TvBrand brand,
    String? name,
    String? location,
    TvDriver? driver,
  })?
  _playlistTarget;
  int? _handledFinish;
  bool get isNavigatingPlaylist => _navigating;
  bool get isShuffling => _shuffling;
  bool get canShuffle => _playlist.length > 1 && !_navigating && !isBusy;
  bool get isBusy => const {
    MediaCastStatus.picking,
    MediaCastStatus.preparingServer,
    MediaCastStatus.connectingTv,
  }.contains(_status);
  int get playlistCount => _playlist.length;
  int get playlistPosition => _playlist.isEmpty ? 0 : _playlistIndex + 1;
  int get currentPlaylistIndex => _playlistIndex;
  Directory? get activeCacheDirectory => _sessionCache;

  /// Atualiza a fila de reproduÃ§Ã£o ativa em tempo real (ex: ao reordenar na Fila),
  /// preservando a sessÃ£o em andamento e o item atual.
  void updateLivePlaylist(
    List<Future<File> Function()> files, {
    required List<String> names,
    required int currentIndex,
  }) {
    if (_disposed || files.isEmpty) return;
    _playlist = List.of(files);
    _playlistNames = List.of(names);
    _sequential = true;
    _playlistIndex = currentIndex.clamp(0, files.length - 1);
    _order = List.generate(files.length, (i) => i);
    if (_shuffling && _order.length > 1) {
      _order.remove(_playlistIndex);
      _order.shuffle();
      _order.insert(0, _playlistIndex);
    }
    notifyListeners();
  }

  bool get canPrevious =>
      !_navigating && !isBusy && _order.indexOf(_playlistIndex) > 0;
  bool get canNext =>
      !_navigating &&
      !isBusy &&
      _order.indexOf(_playlistIndex) + 1 < _order.length;
  bool isTarget(String ip, TvBrand brand) =>
      _targetIp == ip && _targetBrand == brand;
  void toggleShuffle() {
    if (!canShuffle) return;
    _shuffling = !_shuffling;
    _order = List.generate(_playlist.length, (i) => i);
    if (_shuffling) {
      _isLooping = false;
      _order.remove(_playlistIndex);
      _order.shuffle();
      _order.insert(0, _playlistIndex);
    }
    notifyListeners();
  }

  Future<bool> previous() => _navigate(-1);
  Future<bool> next() => _navigate(1);
  Future<bool> _navigate(int step) async {
    if (step < 0 ? !canPrevious : !canNext) return false;
    final target = _playlistTarget;
    if (target == null) return false;
    final selection = _selectionGeneration;
    final playlist = _playlist;
    final index = _order[_order.indexOf(_playlistIndex) + step];
    _navigating = true;
    notifyListeners();
    late final File file;
    try {
      file = await playlist[index]();
      if (!await file.exists()) throw const FileSystemException();
    } catch (_) {
      if (identical(playlist, _playlist)) {
        _errorMessage = 'O arquivo nÃ£o estÃ¡ disponÃ­vel.';
      }
      _navigating = false;
      if (!_disposed) notifyListeners();
      return false;
    }
    if (_disposed ||
        selection != _selectionGeneration ||
        !identical(playlist, _playlist)) {
      _navigating = false;
      if (!_disposed) notifyListeners();
      return false;
    }
    final previousIndex = _playlistIndex;
    _playlistIndex = index;
    try {
      final result = await castFile(
        file,
        fileName: _playlistNames?[index],
        targetTvIp: target.ip,
        brand: target.brand,
        tvName: target.name,
        locationUrl: target.location,
        activeDriver: target.driver,
        preservePlaylist: true,
      );
      if (!result && identical(playlist, _playlist)) {
        _playlistIndex = previousIndex;
      }
      return result;
    } finally {
      _navigating = false;
      notifyListeners();
    }
  }

  Future<bool> castPlaylist(
    List<File> files, {
    required String targetTvIp,
    required TvBrand brand,
    String? tvName,
    String? locationUrl,
    TvDriver? activeDriver,
    int startIndex = 0,
  }) async {
    if (files.isEmpty || startIndex < 0 || startIndex >= files.length) {
      return false;
    }
    return castResolvedPlaylist(
      files[startIndex],
      [for (final f in files) () async => f],
      targetTvIp: targetTvIp,
      brand: brand,
      tvName: tvName,
      locationUrl: locationUrl,
      activeDriver: activeDriver,
      startIndex: startIndex,
    );
  }

  Directory? _sessionCache;
  void _replaceCache(Directory? next) {
    final old = _sessionCache;
    _sessionCache = next;
    if (old != null && old.path != next?.path) {
      unawaited(_removeCache(old));
    }
  }

  Future<void> _removeCache(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Android or Windows can still hold an outstanding read on the temporary file.
    }
  }

  Future<bool> castResolvedPlaylist(
    File first,
    List<Future<File> Function()> files, {
    required String targetTvIp,
    required TvBrand brand,
    String? tvName,
    String? locationUrl,
    TvDriver? activeDriver,
    int startIndex = 0,
    Directory? cacheDirectory,
    List<String>? names,
  }) async {
    if (_disposed || startIndex < 0 || startIndex >= files.length) return false;
    _replaceCache(cacheDirectory);
    _playlist = List.of(files);
    _playlistNames = names;
    _sequential = names != null;
    _order = List.generate(files.length, (i) => i);
    _playlistIndex = startIndex;
    _shuffling = false;
    _playlistTarget = (
      ip: targetTvIp,
      brand: brand,
      name: tvName,
      location: locationUrl,
      driver: activeDriver,
    );
    return castFile(
      first,
      fileName: names?[startIndex],
      targetTvIp: targetTvIp,
      brand: brand,
      tvName: tvName,
      locationUrl: locationUrl,
      activeDriver: activeDriver,
      preservePlaylist: true,
    );
  }

  Future<List<File>> _photoSiblings(File first) async {
    if (!Platform.isWindows) return [first];
    const extensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'};
    try {
      final siblings = await first.parent
          .list(followLinks: false)
          .where(
            (e) =>
                e is File &&
                extensions.any((ext) => e.path.toLowerCase().endsWith(ext)),
          )
          .cast<File>()
          .toList();
      siblings.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );
      return siblings.any((f) => f.path == first.path) ? siblings : [first];
    } catch (_) {
      return [first];
    }
  }

  MediaCastController({
    MediaServerService? serverService,
    DlnaTransport? dlna,
    GoogleCastMedia Function()? castFactory,
    Future<MediaDetails> Function(String)? probeMedia,
  }) : _castFactory = castFactory ?? GoogleCastMedia.new,
       _probeMedia = probeMedia ?? MediaRemuxService.probeMediaDetails,
       _serverService = serverService ?? MediaServerService(),
       _dlna = dlna ?? DlnaTransport();

  bool _current(NetworkOperation operation) =>
      !_disposed && !operation.isCancelled && identical(_operation, operation);

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
  List<MediaTrack> _availableTracks = [];
  MediaTrack? _selectedAudioTrack;
  MediaTrack? _selectedSubtitleTrack;

  List<MediaTrack> get audioTracks =>
      _availableTracks.where((t) => t.type == 'audio').toList();
  List<MediaTrack> get subtitleTracks =>
      _availableTracks.where((t) => t.type == 'subtitle').toList();
  MediaTrack? get selectedAudioTrack => _selectedAudioTrack;
  MediaTrack? get selectedSubtitleTrack => _selectedSubtitleTrack;

  Future<void> selectAudioTrack(MediaTrack? track) async {
    _selectedAudioTrack = track;
    notifyListeners();
    if (isStreaming &&
        _currentFilePath != null &&
        _targetIp != null &&
        _targetBrand != null) {
      final file = File(_currentFilePath!);
      if (await file.exists()) {
        await castFile(
          file,
          fileName: _currentFileName,
          targetTvIp: _targetIp!,
          brand: _targetBrand!,
          tvName: _currentTvName,
          preservePlaylist: true,
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _buildCastTracks(String targetTvIp) async {
    final castTracks = <Map<String, dynamic>>[];
    for (final sub in _availableTracks.where((t) => t.type == 'subtitle')) {
      final subUrl = await _serverService.getSubtitleUrlForTv(
        targetTvIp,
        sub.id,
      );
      if (subUrl != null) {
        castTracks.add({
          'trackId': sub.id + 1,
          'type': 'TEXT',
          'trackContentId': subUrl,
          'trackContentType': 'text/vtt',
          'name': sub.title,
          'language': MediaRemuxService.toBcp47(sub.language),
          'subtype': 'SUBTITLES',
        });
      }
    }
    return castTracks;
  }

  Future<void> selectSubtitleTrack(MediaTrack? track) async {
    final operation = _operation;
    if (_transport != MediaCastTransport.cast ||
        _cast == null ||
        operation == null) {
      _selectedSubtitleTrack = track;
      notifyListeners();
      return;
    }
    final cast = _cast!;
    _errorMessage = null;
    try {
      if (track != null) await _serverService.prepareSubtitle(track.id);
      operation.check();
      final trackIds = track != null ? [track.id + 1] : <int>[];
      try {
        await cast.setActiveTrackIds(trackIds);
      } catch (e) {
        debugPrint(
          '[MediaCast] EDIT_TRACKS_INFO recusado ($e). Aplicando via recarregamento de sessão...',
        );
        operation.check();
        final targetIp = _targetIp;
        final tracks = targetIp != null
            ? await _buildCastTracks(targetIp)
            : <Map<String, dynamic>>[];
        operation.check();
        final resumePosition = _remuxCast
            ? (_currentPosition - _castOffset)
            : _currentPosition;
        await cast.reloadWithActiveTracks(
          activeTrackIds: trackIds,
          tracks: tracks.isNotEmpty ? tracks : null,
          currentTime: resumePosition > Duration.zero ? resumePosition : null,
          autoplay: isPlaying,
        );
      }
      operation.check();
      _selectedSubtitleTrack = track;
    } catch (e) {
      if (_current(operation)) {
        _errorMessage = 'Não foi possível ativar a legenda: $e';
      }
      rethrow;
    } finally {
      if (_current(operation)) notifyListeners();
    }
  }

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
  bool get hasProgress =>
      isStreaming &&
      !isPhoto &&
      (_transport == MediaCastTransport.dlna ||
          _transport == MediaCastTransport.cast) &&
      _hasPosition;
  bool get canSeek =>
      hasProgress &&
      _totalDuration > Duration.zero &&
      _actions.contains('Seek') &&
      !_isSeeking &&
      !_commandPending;
  bool get canLoop => canSeek && _actions.contains('Play');
  bool get canPlay => _canCommand('Play');
  bool get canPause => _canCommand('Pause');
  bool _canCommand(String action) =>
      isStreaming &&
      !isPhoto &&
      !_commandPending &&
      !_isSeeking &&
      (_transport == MediaCastTransport.native
          ? _activeDriver?.isConnected == true
          : _actions.contains(action));

  String get playbackLabel {
    if (isPhoto) return 'Imagem enviada Ã  TV';
    if (_status == MediaCastStatus.playing) return 'Reproduzindo na TV';
    if (_status == MediaCastStatus.paused) return 'Pausado na TV';
    if (_status == MediaCastStatus.stopped) return 'ReproduÃ§Ã£o parada na TV';
    return _lastCommand ?? 'MÃ­dia enviada Ã  TV';
  }

  MediaCastStatus get status => _status;
  bool get isStreaming => const {
    MediaCastStatus.sent,
    MediaCastStatus.playing,
    MediaCastStatus.paused,
    MediaCastStatus.stopped,
  }.contains(_status);
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
      final pickedFiles = await FilePicker.pickFiles(type: fileType);

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
        throw Exception(
          'O arquivo selecionado nÃ£o foi encontrado no armazenamento.',
        );
      }

      if (_disposed || selection != _selectionGeneration) return false;
      var files = pickedFiles
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
      if (fileType == FileType.image && files.length == 1) {
        files = await _photoSiblings(file);
      }
      if (_disposed || selection != _selectionGeneration) return false;
      return await castPlaylist(
        files,
        targetTvIp: targetTvIp,
        brand: brand,
        tvName: tvName,
        locationUrl: locationUrl,
        activeDriver: activeDriver,
        startIndex: files
            .indexWhere((f) => f.path == file.path)
            .clamp(0, files.length - 1),
      );
    } catch (e) {
      if (_disposed || selection != _selectionGeneration) return false;
      _cast?.close();
      debugPrint('[MediaCast] Erro ao selecionar mÃ­dia: $e');
      _status = MediaCastStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Transmite um arquivo local especÃ­fico diretamente para a Smart TV selecionada.
  ///
  /// Se um [activeDriver] conectado for fornecido (ex: LG webOS ou Samsung Tizen jÃ¡ pareada),
  /// fotos priorizam a API nativa do fabricante (SSAP / WebSocket).
  /// VÃ­deos e Ã¡udios LG priorizam DLNA / UPnP AVTransport com Play explÃ­cito;
  /// a API nativa Ã© alternativa quando esse transporte recusa o envio.
  Future<bool> castFile(
    File file, {
    String? fileName,
    required String targetTvIp,
    required TvBrand brand,
    String? tvName,
    String? locationUrl,
    TvDriver? activeDriver,
    bool preservePlaylist = false,
  }) async {
    if (_disposed) return false;
    _targetIp = targetTvIp;
    _targetBrand = brand;
    if (!preservePlaylist) {
      _replaceCache(null);
      _playlistNames = null;
      _playlist = [() async => file];
      _sequential = false;
      _order = [0];
      _playlistIndex = 0;
      _shuffling = false;
      _playlistTarget = (
        ip: targetTvIp,
        brand: brand,
        name: tvName,
        location: locationUrl,
        driver: activeDriver,
      );
    }
    _handledFinish = null;
    _selectionGeneration++;
    _operation?.cancel();
    _cancelTimers();
    _cast?.close();
    _cast = null;
    _navigating = false;
    final operation = NetworkOperation();
    _operation = operation;
    final closing = _serverService.stop();
    _currentControlUrl = null;
    _activeRenderer = null;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _sourceDuration = Duration.zero;
    _castOffset = Duration.zero;
    _remuxCast = false;
    _isSeeking = false;
    _commandPending = false;
    _hasPosition = false;
    _loopRestarting = false;
    _isLooping = false;
    _actions = {};
    _transport = MediaCastTransport.none;
    _lastCommand = null;
    _availableTracks = [];
    _selectedAudioTrack = null;
    _selectedSubtitleTrack = null;
    try {
      await closing;
      if (!_current(operation)) return false;
      return await operation.run(
        () => _castFile(
          file,
          operation: operation,
          fileName: fileName,
          targetTvIp: targetTvIp,
          brand: brand,
          tvName: tvName,
          locationUrl: locationUrl,
          activeDriver: activeDriver,
        ),
      );
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
        throw Exception(
          'O arquivo selecionado nÃ£o foi encontrado no armazenamento.',
        );
      }

      final originalPath = file.path;
      if (brand == TvBrand.googleTv) {
        file = await MediaRemuxService.convertImageOrAnimationForCast(file);
      }
      operation.check();
      _currentFileName = fileName ?? file.uri.pathSegments.last;
      _currentFilePath = file.path;
      _currentFileSize = await file.length();
      operation.check();
      _currentTvName = tvName ?? '${brand.displayName} ($targetTvIp)';

      final cloudMeta = File('${file.path}.cloud.json');
      Map<String, dynamic>? cloudDesc;
      if (cloudMeta.existsSync()) {
        try {
          final decoded = jsonDecode(cloudMeta.readAsStringSync());
          if (decoded is Map<String, dynamic>) cloudDesc = decoded;
        } catch (_) {}
      }
      final probeTarget = cloudDesc != null
          ? cloudDesc['url'] as String?
          : file.path;
      final probeHeaders = cloudDesc != null && cloudDesc['headers'] is Map
          ? Map<String, String>.from(cloudDesc['headers'] as Map)
          : null;

      MediaDetails? mediaDetails;
      if (probeTarget != null) {
        if (cloudDesc == null) {
          try {
            final details = await _probeMedia(probeTarget)
                .timeout(const Duration(seconds: 4));
            mediaDetails = details;
            _availableTracks = details.tracks;
            _selectedAudioTrack =
                details.tracks
                    .where((t) => t.type == 'audio' && t.isDefault)
                    .firstOrNull ??
                details.tracks.where((t) => t.type == 'audio').firstOrNull;
            _selectedSubtitleTrack = details.tracks
                .where((t) => t.type == 'subtitle' && t.isDefault)
                .firstOrNull;
          } catch (_) {}
        } else {
          MediaRemuxService.probeMediaDetails(
                probeTarget,
                headers: probeHeaders,
              )
              .then((details) {
                if (_currentFilePath == file.path &&
                    details.tracks.isNotEmpty) {
                  _availableTracks = details.tracks;
                  _selectedAudioTrack ??=
                      details.tracks
                          .where((t) => t.type == 'audio' && t.isDefault)
                          .firstOrNull ??
                      details.tracks
                          .where((t) => t.type == 'audio')
                          .firstOrNull;
                  _selectedSubtitleTrack ??= details.tracks
                      .where((t) => t.type == 'subtitle' && t.isDefault)
                      .firstOrNull;
                  notifyListeners();
                }
              })
              .catchError((_) {});
        }
      }

      // 1. Inicia ou reutiliza o servidor HTTP local
      _status = MediaCastStatus.preparingServer;
      notifyListeners();

      operation.check();
      await _serverService.start();
      operation.check();

      final isMkv = file.path.toLowerCase().endsWith('.mkv');
      final needAudioRemux =
          mediaDetails != null && !mediaDetails.isChromecastAudioCompatible;
      final needVideoTranscode =
          brand == TvBrand.googleTv &&
          (mediaDetails != null && !mediaDetails.isChromecastVideoCompatible);
      final isVideoFile =
          isMkv ||
          file.path.toLowerCase().endsWith('.mp4') ||
          file.path.toLowerCase().endsWith('.webm') ||
          file.path.toLowerCase().endsWith('.avi') ||
          file.path.toLowerCase().endsWith('.ts') ||
          file.path.toLowerCase().endsWith('.mov');
      final needRemux =
          (brand == TvBrand.googleTv &&
              (needAudioRemux || needVideoTranscode || (isMkv && !isPhoto))) ||
          (needAudioRemux && isVideoFile);

      _sourceDuration = mediaDetails?.duration ?? Duration.zero;
      _castOffset = Duration.zero;
      _remuxCast = needRemux && brand == TvBrand.googleTv;
      _totalDuration = _sourceDuration;

      _serverService.serveFile(
        file,
        customName: _currentFileName,
        mimeType: needRemux
            ? 'video/mp4'
            : file.path != originalPath
            ? (file.path.endsWith('.png') ? 'image/png' : 'video/mp4')
            : null,
        remuxProcessFactory: needRemux
            ? () => MediaRemuxService.startRemuxProcess(
                file.path,
                selectedAudioIndex: _selectedAudioTrack?.id,
                transcodeVideo: needVideoTranscode,
                startPosition: _serverService.remuxStart,
              )
            : null,
      );
      _currentFileSize =
          _serverService.currentContentLength ?? _currentFileSize;
      _currentMimeType = _serverService.currentMimeType;

      final mediaUrl = await _serverService.getMediaUrlForTv(targetTvIp);
      operation.check();
      if (mediaUrl == null) {
        throw Exception(
          'NÃ£o foi possÃ­vel identificar o IP local do celular/PC na mesma rede da TV.',
        );
      }

      _status = MediaCastStatus.connectingTv;
      notifyListeners();

      // O visualizador nativo LG pode aceitar a abertura sem iniciar o vÃ­deo.
      // AVTransport carrega a URI e envia Play explicitamente no mesmo endpoint.
      if (brand == TvBrand.googleTv) {
        final cast = _castFactory();
        _cast = cast;
        cast.onStatus = (state) {
          if (_current(operation)) _applyCastStatus(state, operation);
        };
        operation.onCancel(cast.close);
        final castMime = needRemux
            ? 'video/mp4'
            : ((_currentMimeType != null &&
                      (_currentMimeType!.startsWith('video/') ||
                          _currentMimeType == 'video/x-matroska'))
                  ? 'video/mp4'
                  : (_currentMimeType ?? 'video/mp4'));

        final castTracks = await _buildCastTracks(targetTvIp);

        if (castTracks.isNotEmpty) {
          final ptSub = _availableTracks
              .where((t) =>
                  t.type == 'subtitle' &&
                  (t.language == 'por' ||
                      t.title.toLowerCase().contains('portug')))
              .firstOrNull;
          if (ptSub != null) {
            unawaited(_serverService.prepareSubtitle(ptSub.id).catchError((_) => ''));
          }
        }

        await cast.load(
          targetTvIp,
          mediaUrl,
          _currentFileName ?? 'SixF',
          castMime,
          duration: mediaDetails?.duration,
          tracks: castTracks.isNotEmpty ? castTracks : null,
          activeTrackIds: _selectedSubtitleTrack != null
              ? [_selectedSubtitleTrack!.id + 1]
              : null,
        );
        operation.check();
        _transport = MediaCastTransport.cast;
        _applyCastStatus(cast.status, operation);
        if (!isPhoto) _startPositionPolling();
        notifyListeners();
        return true;
      }
      final preferDlna = brand == TvBrand.lgWebOs && (isVideo || isAudio);
      if (!preferDlna && await _tryNative(mediaUrl, operation)) return true;
      final renderer = await _dlna.resolveRenderer(
        targetTvIp,
        locationUrl: locationUrl,
        brand: brand,
        tvName: tvName,
      );
      operation.check();
      if (renderer == null) {
        if (await _tryNative(mediaUrl, operation)) return true;
        throw Exception(
          'A Smart TV nÃ£o respondeu aos comandos de mÃ­dia DLNA/UPnP.',
        );
      }
      final setResult = await _dlna.setUri(
        renderer.controlUrl,
        mediaUrl,
        title: _currentFileName ?? 'MÃ­dia SixF',
        mimeType: _currentMimeType ?? 'video/mp4',
        fileSize: _currentFileSize,
      );
      operation.check();
      if (!setResult.success) {
        if (await _tryNative(mediaUrl, operation)) return true;
        throw Exception(setResult.userFriendlyMessage);
      }

      // MantÃ©m todos os comandos no endpoint que aceitou a URI, inclusive no fallback.
      _currentControlUrl = setResult.controlUrl ?? renderer.controlUrl;
      _activeRenderer = DlnaRenderer(
        ip: renderer.ip,
        name: renderer.name,
        controlUrl: _currentControlUrl!,
        locationUrl: renderer.locationUrl,
        brand: renderer.brand,
      );
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
      _cast?.close();
      debugPrint('[MediaCast] Erro ao transmitir mÃ­dia: ${e.runtimeType}');
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
      accepted = await driver.openMediaUrl(
        mediaUrl,
        title: _currentFileName ?? 'MÃ­dia SixF',
        mimeType: _currentMimeType,
      );
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
    if (operation == null ||
        !_current(operation) ||
        !(play ? canPlay : canPause)) {
      return;
    }
    _commandPending = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (_transport == MediaCastTransport.cast) {
        if (play && _remuxCast && _cast!.status['idleReason'] == 'FINISHED') {
          await _restartCastRemux(Duration.zero, operation);
        } else {
          await _cast!.command(play ? 'PLAY' : 'PAUSE');
        }
        operation.check();
      } else if (_transport == MediaCastTransport.native) {
        _activeDriver!.sendKey(play ? RemoteKey.play : RemoteKey.pause);
      } else {
        final result = await operation.run(
          () => play
              ? _dlna.play(_currentControlUrl!)
              : _dlna.pause(_currentControlUrl!),
        );
        operation.check();
        if (!result.success) throw Exception(result.userFriendlyMessage);
      }
      if (_transport != MediaCastTransport.cast) _status = MediaCastStatus.sent;
      _lastCommand = play
          ? 'Comando de reproduÃ§Ã£o enviado'
          : 'Comando de pausa enviado';
      if (_transport == MediaCastTransport.dlna) {
        await _refreshPlayback(operation);
      }
    } catch (e) {
      if (_current(operation)) {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      }
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
    if (_isLooping) _shuffling = false;
    notifyListeners();
  }

  Future<bool> seekTo(Duration target) async {
    final operation = _operation;
    if (operation == null || !_current(operation) || !canSeek) return false;
    target = Duration(
      milliseconds: target.inMilliseconds.clamp(
        0,
        _remuxCast
            ? _totalDuration.inMilliseconds - 1
            : _totalDuration.inMilliseconds,
      ),
    );
    final targetTime =
        '${target.inHours.toString().padLeft(2, '0')}:'
        '${(target.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(target.inSeconds % 60).toString().padLeft(2, '0')}';
    _isSeeking = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (_transport == MediaCastTransport.cast) {
        if (_remuxCast) {
          await _restartCastRemux(target, operation, autoplay: !isPaused);
        } else {
          await _cast!.command(
            'SEEK',
            currentTime: target.inMilliseconds / 1000,
          );
        }
        operation.check();
      } else {
        final result = await operation.run(
          () => _dlna.seek(_currentControlUrl!, targetTime),
        );
        operation.check();
        if (!result.success) throw Exception(result.userFriendlyMessage);
        await _refreshPlayback(operation);
      }
      return _current(operation);
    } catch (e) {
      if (_current(operation)) {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      }
      return false;
    } finally {
      if (_current(operation)) {
        _isSeeking = false;
        notifyListeners();
      }
    }
  }

  Future<void> _restartCastRemux(
    Duration target,
    NetworkOperation operation, {
    bool autoplay = true,
  }) async {
    final cast = _cast!;
    _serverService.restartRemuxAt(target);
    final url = await _serverService.getMediaUrlForTv(_targetIp!);
    operation.check();
    if (url == null) throw StateError('Servidor de mÃ­dia indisponÃ­vel.');
    final previousOffset = _castOffset;
    _castOffset = target;
    try {
      await cast.replaceRemux(url, _totalDuration - target, autoplay: autoplay);
      operation.check();
    } catch (_) {
      if (_current(operation)) _castOffset = previousOffset;
      rethrow;
    }
  }

  Future<void> _refreshPlayback(NetworkOperation operation) async {
    if (_transport == MediaCastTransport.cast) {
      if (!_current(operation) || isPhoto || _polling) return;
      _polling = true;
      try {
        await _cast!.refresh();
        operation.check();
      } catch (_) {
        if (_current(operation)) {
          _hasPosition = false;
          _actions = {};
        }
      } finally {
        if (_current(operation)) {
          _polling = false;
          notifyListeners();
        }
      }
      return;
    }
    if (!_current(operation) ||
        _currentControlUrl == null ||
        isPhoto ||
        _polling) {
      return;
    }
    final url = _currentControlUrl!;
    _polling = true;
    try {
      final state = await operation.run(() => _dlna.state(url));
      operation.check();
      final reachedEnd =
          _sequential &&
          canNext &&
          isPlaying &&
          state == 'STOPPED' &&
          _hasPosition &&
          _totalDuration > Duration.zero &&
          _currentPosition >= _totalDuration - const Duration(seconds: 2);
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
      if (reachedEnd) {
        scheduleMicrotask(() {
          if (_current(operation) && canNext) next();
        });
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

  void _applyCastStatus(
    Map<String, dynamic> state,
    NetworkOperation operation,
  ) {
    _status = switch (state['playerState']) {
      'PLAYING' => MediaCastStatus.playing,
      'PAUSED' => MediaCastStatus.paused,
      'IDLE' => MediaCastStatus.stopped,
      _ => MediaCastStatus.sent,
    };
    final info = state['media'] as Map?;
    final duration = info?['duration'];
    final time = state['currentTime'];
    if (_sourceDuration > Duration.zero) {
      _totalDuration = _sourceDuration;
    } else if (duration is num && duration.isFinite && duration >= 0) {
      _totalDuration = Duration(milliseconds: (duration * 1000).round());
    }
    if (time is num && time.isFinite && time >= 0) {
      _currentPosition =
          _castOffset + Duration(milliseconds: (time * 1000).round());
    }
    _hasPosition = _totalDuration > Duration.zero && time is num;
    final commands = (state['supportedMediaCommands'] as num?)?.toInt() ?? 0;
    _actions = {
      if ((commands & 1) != 0) 'Pause',
      if ((commands & 2) != 0 ||
          (_remuxCast && _sourceDuration > Duration.zero))
        'Seek',
      'Play',
    };
    if (state['idleReason'] == 'ERROR') {
      _errorMessage = 'O Chromecast nÃ£o conseguiu reproduzir o arquivo.';
      _actions = {};
    }
    if (!isPhoto && state['idleReason'] == 'FINISHED') {
      final id = state['mediaSessionId'] as int?;
      if (id != null &&
          id != _handledFinish &&
          !_loopRestarting &&
          (_isLooping || _shuffling || (_sequential && canNext))) {
        _handledFinish = id;
        // Run outside the socket callback; no overlapping poll/command mutation.
        scheduleMicrotask(() => _finishCast(operation));
      }
    }
    if (!_polling) notifyListeners();
  }

  Future<void> _finishCast(NetworkOperation operation) async {
    if (!_current(operation) ||
        _loopRestarting ||
        _transport != MediaCastTransport.cast) {
      return;
    }
    _loopRestarting = true;
    try {
      if (_isLooping) {
        if (_remuxCast) {
          await _restartCastRemux(Duration.zero, operation);
        } else {
          await _cast!.reload();
        }
      } else if ((_shuffling || _sequential) && canNext) {
        await next();
      }
    } catch (_) {
      if (_current(operation)) {
        _errorMessage = 'NÃ£o foi possÃ­vel repetir a mÃ­dia.';
      }
    } finally {
      _loopRestarting = false;
      notifyListeners();
    }
  }

  void _startPositionPolling() {
    final operation = _operation;
    if (operation == null || !_current(operation)) return;
    _positionPollTimer?.cancel();
    _positionPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_current(operation) ||
          _polling ||
          _isSeeking ||
          _commandPending ||
          _loopRestarting) {
        return;
      }
      final wasPlaying = isPlaying;
      await _refreshPlayback(operation);
      if (!_current(operation)) return;
      // Repete apenas apÃ³s uma transiÃ§Ã£o real para STOPPED, sem cortar o fim do vÃ­deo.
      if (_transport != MediaCastTransport.cast &&
          _isLooping &&
          wasPlaying &&
          _status == MediaCastStatus.stopped &&
          canLoop) {
        _loopRestarting = true;
        try {
          if (await seekTo(Duration.zero) && _current(operation)) await play();
        } finally {
          if (_current(operation)) _loopRestarting = false;
        }
      }
    });
  }

  /// Encerra a transmissÃ£o e libera a TV e o servidor local.
  Future<void> stop() async {
    if (_disposed) return;
    final previousOperation = _operation;
    if (_transport == MediaCastTransport.cast) {
      try {
        await _cast?.stopReceiver();
      } catch (_) {}
      if (!identical(previousOperation, _operation) || _disposed) return;
    }
    _playlist = [];
    _order = [];
    _playlistTarget = null;
    _shuffling = false;
    _selectionGeneration++;
    _operation?.cancel();
    _cancelTimers();
    _cast?.close();
    _cast = null;
    _navigating = false;
    final driver = _transport == MediaCastTransport.native
        ? _activeDriver
        : null;
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
    _availableTracks = [];
    _selectedAudioTrack = null;
    _selectedSubtitleTrack = null;
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
      try {
        await operation.run(() => _dlna.stop(controlUrl));
      } catch (_) {}
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
    _cast?.close();
    _cast = null;
    _navigating = false;
    _serverService.stop();
    super.dispose();
  }
}
