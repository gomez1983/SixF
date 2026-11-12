import 'dart:ui' show PointerDeviceKind;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/media_cast_controller.dart';
import '../../controllers/remote_controller.dart';
import '../../services/drivers/tv_driver.dart';
import '../../services/haptic_service.dart';
import '../../services/library_sources.dart';
import '../../services/thumbnail_service.dart';
import '../theme/app_colors.dart';
import '../widgets/image_fullscreen_viewer.dart';
import '../widgets/media_session_controls.dart';

enum PlaybackTarget { tv, local }

class _Collection {
  _Collection(this.name, this.items, {this.favorite = false});
  String name;
  final List<LibraryEntry> items;
  bool favorite;
  Map<String, dynamic> toJson() => {
    'name': name,
    'favorite': favorite,
    'items': items.map((e) => e.toJson()).toList(),
  };
  factory _Collection.read(Map<String, dynamic> v) => _Collection(v['name'], [
    for (final item in v['items'] ?? []) LibraryEntry.fromJson(item),
  ], favorite: v['favorite'] == true);
}

class MediaLibrary extends StatefulWidget {
  const MediaLibrary({
    super.key,
    this.embedded = false,
    this.wideHeader,
    this.onWideViewerChanged,
  });
  final bool embedded;

  /// Cabeçalho do app (nome, botões, aparelhos) para o topo da coluna direita
  /// quando o visualizador ocupa toda a altura (tela deitada / janela larga).
  /// Quem hospeda a biblioteca esconde o próprio cabeçalho nesse momento.
  final Widget? wideHeader;

  /// Avisa quando o visualizador de altura inteira entra ou sai de cena.
  final ValueChanged<bool>? onWideViewerChanged;
  @override
  State<MediaLibrary> createState() => _MediaLibraryState();
}

class _MediaLibraryState extends State<MediaLibrary> {
  final sources = LibrarySources();
  final lists = <_Collection>[],
      queue = <LibraryEntry>[],
      roots = <LibraryEntry>[],
      trail = <LibraryEntry>[];
  final selected = <LibraryEntry>[];
  final Set<String> failedEntryIds = {};
  List<LibraryEntry> entries = [];
  _Collection? opened;
  String? queueTitle;
  bool queueExpanded = true;
  int tab = 0, generation = 0, _playGeneration = 0;
  bool _reportedWideViewer = false;
  bool ready = false, loading = false, casting = false;
  bool loadFailed = false;
  String filter = '', folderError = '';
  bool sortByExtension = false;
  bool showThumbnails = true;

  /// Filtro por tipo na pasta aberta: all, folder, video, image, audio.
  String _typeFilter = 'all';

  /// Pastas abertas recentemente (caminhos completos), mais recente primeiro.
  final List<List<LibraryEntry>> recent = [];

  /// Subpastas já vistas de cada pasta (para a árvore do desktop).
  final Map<String, List<LibraryEntry>> _folderKids = {};
  final search = TextEditingController();
  final photoScroll = ScrollController();

  // Estado do visualizador de fotos/vídeos integrado (com espelhamento simultâneo na TV)
  List<LibraryEntry> activePhotos = [];
  int activePhotoIndex = 0;
  LibraryEntry? activeMediaItem;
  File? viewedPhotoFile;
  bool loadingPhotoPreview = false;
  Directory? _photoCache;

  /// Contexto completo do visualizador (fotos, vídeos e áudios na ordem do carrossel).
  List<LibraryEntry> viewerContext = [];

  /// Último arquivo informado pela sessão na TV: o card só acompanha a TV quando
  /// ela troca de arquivo (avanço da playlist), nunca sobrepondo a escolha do usuário.
  String? _lastCastFile;

  // Player embutido no card (destino "Este aparelho"): vídeos e áudios tocam aqui,
  // sem abrir o player externo do sistema.
  Player? _localPlayer;
  VideoController? _localVideo;
  String? _localKey;
  bool _localLoading = false;
  String? _localError;
  int _localGen = 0;

  static String _keyOf(LibraryEntry e) => '${e.source.name}:${e.id}';
  static bool _same(LibraryEntry a, LibraryEntry b) =>
      a.id == b.id && a.source == b.source;

  // Estado de destino de reprodução (Google Fotos / Cast padrão: TV vs Este Aparelho)
  PlaybackTarget? _userChosenTarget;
  bool isMultiSelecting = false;
  final Set<String> multiSelectedIds = {};

  /// Regra combinada com o usuário:
  /// 1. Ao abrir o app, o padrão é sempre "Local" (só visualizar no SixF).
  /// 2. Ao apertar para enviar à TV, o modo vira "Na TV" e toda mídia aberta
  ///    depois vai para a TV.
  /// 3. Só volta a "Local" quando o usuário trocar.
  /// 4. A escolha não é salva: cada abertura do app começa em "Local".
  PlaybackTarget getPlaybackTarget(RemoteController tv) {
    if (_userChosenTarget == PlaybackTarget.tv && tv.isConnected) {
      return PlaybackTarget.tv;
    }
    return PlaybackTarget.local;
  }

  /// Liga o modo "Na TV" e envia o item atual imediatamente.
  Future<void> _sendToTv(LibraryEntry? current) async {
    final tv = context.read<RemoteController>();
    if (!tv.isConnected) {
      message('Conecte uma TV para transmitir.');
      return;
    }
    _stopLocalPlayback();
    setState(() => _userChosenTarget = PlaybackTarget.tv);
    message('Destino de reprodução: ${tv.connectedTvName ?? tv.ipAddress}.');
    if (current == null) return;
    if (current.isImage) {
      await _loadAndMirrorActivePhoto();
    } else {
      await _startEntryPlayback(current);
    }
  }

  /// Volta ao modo "Local": a TV deixa de receber novas mídias.
  void _backToLocal() {
    setState(() => _userChosenTarget = PlaybackTarget.local);
    message('Destino de reprodução: Este aparelho (local).');
  }

  // Estado de sessão salva das nuvens
  bool driveLogged = false;
  bool oneDriveLogged = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  void _clearPhotoCache() {
    final old = _photoCache;
    _photoCache = null;
    if (old != null) {
      unawaited(old.delete(recursive: true).catchError((_) => old));
    }
  }

  @override
  void dispose() {
    _clearPhotoCache();
    _localGen++;
    unawaited(_localCompletedSub?.cancel());
    unawaited(_localPlayer?.dispose());
    search.dispose();
    photoScroll.dispose();
    super.dispose();
  }

  void message(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _refreshCloudAuthState() async {
    final d = await sources.hasSavedSession(LibrarySource.drive);
    final o = await sources.hasSavedSession(LibrarySource.oneDrive);
    if (mounted) {
      setState(() {
        driveLogged = d;
        oneDriveLogged = o;
      });
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonDecode(prefs.getString('mediaLibrary.v1') ?? '{}');
      lists.addAll([for (final v in data['lists'] ?? []) _Collection.read(v)]);
      roots.addAll([
        for (final v in data['roots'] ?? []) LibraryEntry.fromJson(v),
      ]);
      queue.addAll([
        for (final v in data['queue'] ?? []) LibraryEntry.fromJson(v),
      ]);
      if (data['queueTitle'] is String) {
        queueTitle = data['queueTitle'] as String;
      }
      for (final r in data['recent'] ?? []) {
        final path = [for (final v in r) LibraryEntry.fromJson(v)];
        if (path.isNotEmpty) recent.add(path);
      }
      if (data['showThumbnails'] is bool) {
        showThumbnails = data['showThumbnails'] as bool;
      }
      final savedTrail = [
        for (final v in data['trail'] ?? []) LibraryEntry.fromJson(v),
      ];
      await _refreshCloudAuthState();
      if (savedTrail.isNotEmpty) {
        final last = savedTrail.last;
        final canRestore =
            (last.source == LibrarySource.local &&
                Directory(last.id).existsSync()) ||
            (last.source == LibrarySource.drive && driveLogged) ||
            (last.source == LibrarySource.oneDrive && oneDriveLogged);
        if (canRestore) {
          trail.addAll(savedTrail);
        }
      }
      if (mounted) {
        setState(() => ready = true);
        if (trail.isNotEmpty) {
          unawaited(browse());
        }
      }
    } catch (_) {
      if (mounted) setState(() => loadFailed = true);
    }
  }

  Future<void> save() async {
    final value = jsonEncode({
      'lists': lists.map((e) => e.toJson()).toList(),
      'roots': roots.map((e) => e.toJson()).toList(),
      'queue': queue.map((e) => e.toJson()).toList(),
      'trail': trail.map((e) => e.toJson()).toList(),
      'recent': [for (final r in recent) r.map((e) => e.toJson()).toList()],
      'showThumbnails': showThumbnails,
      if (queueTitle != null) 'queueTitle': queueTitle,
    });
    try {
      if (!await (await SharedPreferences.getInstance()).setString(
        'mediaLibrary.v1',
        value,
      )) {
        throw StateError('save');
      }
    } catch (_) {
      message('Falha ao salvar a biblioteca.');
    }
  }

  LibraryEntry _cloneEntry(LibraryEntry e) => LibraryEntry(
    e.source,
    e.id,
    e.name,
    folder: e.folder,
    mimeType: e.mimeType,
    size: e.size,
    thumbnailUrl: e.thumbnailUrl,
  );

  /// Limpeza total da fila e cancelamento imediato de qualquer operação ou leitura travada.
  Future<void> abortAndClearQueue({bool clearQueueItems = true}) async {
    _playGeneration++;
    sources.abortActiveOperations();
    MediaCastController? cast;
    try {
      cast = context.read<MediaCastController?>();
    } catch (_) {
      cast = null;
    }
    _stopLocalPlayback();
    setState(() {
      casting = false;
      loadingPhotoPreview = false;
      activePhotos = [];
      viewerContext = [];
      activeMediaItem = null;
      viewedPhotoFile = null;
      failedEntryIds.clear();
      if (clearQueueItems) {
        queue.clear();
        queueTitle = null;
      }
    });
    _clearPhotoCache();
    if (clearQueueItems) {
      await save();
    }
    if (cast != null) {
      await cast.stop();
    }
    message(
      clearQueueItems
          ? 'Fila limpa e tentativas de reprodução encerradas.'
          : 'Tentativa de reprodução cancelada.',
    );
  }

  /// Sincroniza imediatamente a ordem da Fila com o MediaCastController ativo,
  /// permitindo que o usuário altere a sequência de reprodução na mesma hora.
  void _syncLiveCastQueue() {
    if (!mounted) return;
    MediaCastController? cast;
    try {
      cast = context.read<MediaCastController?>();
    } catch (_) {
      cast = null;
    }
    if (cast == null || !cast.isStreaming || queue.isEmpty) return;
    final dir = cast.activeCacheDirectory;
    if (dir == null) return;
    final currentName = cast.currentFileName;
    var newIndex = currentName != null
        ? queue.indexWhere((e) => e.name == currentName)
        : cast.currentPlaylistIndex;
    if (newIndex < 0) newIndex = 0;
    cast.updateLivePlaylist(
      [for (final item in queue) () => sources.resolve(item, dir)],
      names: [for (final item in queue) item.name],
      currentIndex: newIndex,
    );
  }

  Future<void> browse() async {
    final version = ++generation;
    search.clear();
    setState(() {
      filter = '';
      entries = [];
      loading = trail.isNotEmpty;
      folderError = '';
    });
    unawaited(save());
    if (trail.isEmpty) return;
    try {
      final target = trail.last;
      if (target.source == LibrarySource.drive ||
          target.source == LibrarySource.oneDrive) {
        await sources.token(target.source);
        if (!mounted || generation != version) return;
      }
      final items = await sources
          .list(target)
          .timeout(const Duration(seconds: 15));
      await _refreshCloudAuthState();
      if (mounted && generation == version) {
        setState(() {
          entries = items;
          _folderKids[_keyOf(target)] = items.where((e) => e.folder).toList();
          _rememberRecent();
        });
        unawaited(save());
        // A pasta abre na grade (mockup aprovado): o visualizador só
        // aparece quando o usuário toca numa foto ou num vídeo.
      }
    } catch (e) {
      if (mounted && generation == version) {
        setState(
          () => folderError = e is TimeoutException
              ? 'Tempo limite atingido ao carregar a pasta na nuvem. Verifique sua conexão.'
              : (e is FormatException
                    ? e.message
                    : (e is SocketException
                          ? 'Sem conexão com a internet para abrir a pasta.'
                          : 'Não foi possível abrir a pasta. Verifique o acesso à conta e à internet.')),
        );
      }
    } finally {
      if (mounted && version == generation) setState(() => loading = false);
    }
  }

  void enter(LibraryEntry dir) {
    trail.add(dir);
    browse();
  }

  Future<void> addRoot() async {
    try {
      final android = Platform.isAndroid;
      final id = android
          ? await LibrarySources.tree.invokeMethod<String>('pick')
          : await FilePicker.getDirectoryPath();
      if (id == null || !mounted) return;
      final root = LibraryEntry(
        android ? LibrarySource.androidTree : LibrarySource.local,
        id,
        android
            ? Uri.parse(id).pathSegments.last.split(':').last
            : p.basename(id),
        folder: true,
      );
      if (!roots.any((r) => r.id == id)) {
        roots.add(root);
        await save();
      }
      if (mounted) enter(root);
    } catch (_) {
      message('Não foi possível acessar a pasta escolhida.');
    }
  }

  Future<String?> nameDialog({
    String title = 'Nova playlist',
    String label = 'Nome da playlist',
    String initial = '',
  }) async {
    var value = initial;
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => value = v,
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (value.trim().isNotEmpty) Navigator.pop(ctx, value.trim());
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> renamePlaylist(_Collection list) async {
    final oldName = list.name;
    final newName = await nameDialog(
      title: 'Renomear playlist',
      label: 'Novo nome da playlist',
      initial: oldName,
    );
    if (newName == null || newName == oldName || !mounted) return;
    setState(() {
      list.name = newName;
      if (queueTitle == oldName) {
        queueTitle = newName;
      }
    });
    await save();
    message('Playlist renomeada para "$newName".');
  }

  Future<void> deletePlaylist(_Collection list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir playlist'),
        content: Text('Deseja realmente excluir a playlist "${list.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      lists.remove(list);
      if (opened == list) {
        opened = null;
      }
      if (queueTitle == list.name) {
        queueTitle = null;
      }
    });
    await save();
    message('Playlist "${list.name}" excluída.');
  }

  Future<void> addSelection() async {
    if (selected.isEmpty) return;
    final target = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Criar nova playlist'),
              onTap: () => Navigator.pop(ctx, -1),
            ),
            for (var i = 0; i < lists.length; i++)
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text(lists[i].name),
                subtitle: Text('${lists[i].items.length} itens'),
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    _Collection list;
    if (target < 0) {
      final name = await nameDialog();
      if (name == null || !mounted) return;
      list = _Collection(name, []);
      lists.add(list);
    } else {
      list = lists[target];
    }
    final addedItems = selected.map(_cloneEntry).toList();
    setState(() {
      list.items.addAll(addedItems);
      queue
        ..clear()
        ..addAll(list.items.map(_cloneEntry));
      queueTitle = list.name;
      queueExpanded = true;
      selected.clear();
      opened = list;
      tab = 0;
    });
    await save();
    _syncLiveCastQueue();
    message('Adicionado à playlist "${list.name}" e carregado na Fila.');
  }

  List<LibraryEntry> _visibleFolderEntries() {
    final visible = entries
        .where((e) => e.name.toLowerCase().contains(filter))
        .toList();
    if (sortByExtension) {
      visible.sort((a, b) {
        if (a.folder != b.folder) return a.folder ? -1 : 1;
        final typeA = a.isVideo ? 0 : (a.isImage ? 1 : 2);
        final typeB = b.isVideo ? 0 : (b.isImage ? 1 : 2);
        if (typeA != typeB) return typeA.compareTo(typeB);
        final extA = p.extension(a.name).toLowerCase();
        final extB = p.extension(b.name).toLowerCase();
        if (extA != extB) return extA.compareTo(extB);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    return visible;
  }

  List<LibraryEntry> _carouselContextItems() {
    if (tab == 1) {
      final queueMedia = queue.where((e) => !e.folder).toList();
      if (queueMedia.isNotEmpty) return queueMedia;
    } else if (tab == 2) {
      final folderMedia = _visibleFolderEntries()
          .where((e) => !e.folder)
          .toList();
      if (folderMedia.isNotEmpty) return folderMedia;
    }
    return viewerContext.isNotEmpty ? viewerContext : activePhotos;
  }

  void _syncActivePhotosForTab(int targetTab, {LibraryEntry? preferredPhoto}) {
    if (activePhotos.isEmpty &&
        activeMediaItem == null &&
        preferredPhoto == null) {
      return;
    }
    final current =
        preferredPhoto ??
        activeMediaItem ??
        ((activePhotoIndex >= 0 && activePhotoIndex < activePhotos.length)
            ? activePhotos[activePhotoIndex]
            : null);
    if (current == null) return;

    List<LibraryEntry> sourceList;
    if (targetTab == 1 && queue.isNotEmpty) {
      sourceList = queue.where((e) => e.isImage).toList();
    } else if (targetTab == 2 && entries.isNotEmpty) {
      sourceList = _visibleFolderEntries().where((e) => e.isImage).toList();
    } else {
      sourceList = activePhotos.where((e) => e.isImage).toList();
    }

    if (sourceList.isEmpty) {
      sourceList = [current];
    } else if (current.isImage &&
        !sourceList.any(
          (e) => e.id == current.id && e.source == current.source,
        )) {
      sourceList = [...sourceList, current];
    }

    final idx = sourceList.indexWhere(
      (e) => e.id == current.id && e.source == current.source,
    );
    activePhotos = sourceList;
    activePhotoIndex = idx >= 0 ? idx : 0;
  }

  /// Botão de alternância: ativo em azul-marinho com ícone branco, inativo
  /// em cinza-claro com ícone escuro.
  ButtonStyle _toggleStyle(bool active) => IconButton.styleFrom(
    backgroundColor: active
        ? AppColors.accentFillOf(context)
        : AppColors.surfaceInteractiveOf(context),
    foregroundColor: active ? Colors.white : AppColors.textPrimaryOf(context),
  );

  Widget _buildViewModeToggleButton() {
    return IconButton.filledTonal(
      tooltip: showThumbnails
          ? 'Modo compacto (somente nomes)'
          : 'Modo detalhado (miniaturas e nomes)',
      style: _toggleStyle(showThumbnails),
      icon: Icon(
        showThumbnails ? Icons.view_headline_rounded : Icons.grid_view_rounded,
        size: 19,
      ),
      onPressed: () {
        HapticService.selectionClick();
        setState(() => showThumbnails = !showThumbnails);
        save();
      },
    );
  }

  void addSelectionToQueue({bool playNow = false}) {
    if (selected.isEmpty) return;
    final newItems = selected.map(_cloneEntry).toList();
    final previousCount = queue.length;
    final stayInFolderForPhoto = playNow && tab == 2 && newItems.first.isImage;
    setState(() {
      if (queue.isEmpty) {
        queueTitle = 'Arquivos selecionados';
      }
      queue.addAll(newItems);
      queueExpanded = true;
      selected.clear();
      if (!stayInFolderForPhoto) {
        tab = 1;
      }
    });
    save();
    _syncLiveCastQueue();
    message(
      '${newItems.length} ${newItems.length == 1 ? 'item adicionado' : 'itens adicionados'} à fila de execução.',
    );
    if (playNow) {
      if (stayInFolderForPhoto) {
        openPhotoAndMirror(
          _visibleFolderEntries(),
          newItems.first,
          syncToQueue: false,
        );
      } else {
        play(
          queue,
          start: previousCount,
          sourceTitle: queueTitle,
          syncToQueue: false,
        );
      }
    }
  }

  Future<void> saveQueueAsPlaylist() async {
    if (queue.isEmpty) return;
    final name = await nameDialog(
      title: 'Salvar fila como playlist',
      initial: queueTitle != null && queueTitle != 'Arquivos selecionados'
          ? queueTitle!
          : '',
    );
    if (name == null || !mounted) return;
    final list = _Collection(name, queue.map(_cloneEntry).toList());
    setState(() {
      lists.add(list);
      queueTitle = name;
      opened = list;
      tab = 0;
    });
    await save();
    message('Playlist "$name" salva com sucesso.');
  }

  void _ensureEntryInQueue(LibraryEntry item, {String? sourceTitle}) {
    final exists = queue.any((q) => q.id == item.id && q.source == item.source);
    if (!exists) {
      queue.add(_cloneEntry(item));
    }
    if (sourceTitle != null && queue.length == 1) {
      queueTitle = sourceTitle;
    } else {
      queueTitle ??= sourceTitle ?? item.name;
    }
    queueExpanded = true;
  }

  Future<void> showFileActions(
    LibraryEntry entry, {
    List<LibraryEntry>? photoContext,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('Adicionar à fila'),
              onTap: () => Navigator.pop(ctx, 'queue'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Adicionar à playlist'),
              onTap: () => Navigator.pop(ctx, 'playlist'),
            ),
            ListTile(
              leading: const Icon(Icons.cast_rounded),
              title: const Text('Reproduzir agora na televisão'),
              onTap: () => Navigator.pop(ctx, 'play'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'queue') {
      setState(() {
        _ensureEntryInQueue(entry);
      });
      await save();
      _syncLiveCastQueue();
      message('1 item adicionado à fila de execução.');
    } else if (action == 'playlist') {
      final previous = List<LibraryEntry>.of(selected);
      selected
        ..clear()
        ..add(entry);
      await addSelection();
      if (mounted) {
        setState(() {
          selected
            ..clear()
            ..addAll(previous);
        });
      }
    } else if (action == 'play') {
      // Escolha explícita de enviar à TV: liga o modo "Na TV".
      final tv = context.read<RemoteController>();
      if (!tv.isConnected) {
        message('Conecte um dispositivo para transmitir.');
        return;
      }
      _stopLocalPlayback();
      setState(() => _userChosenTarget = PlaybackTarget.tv);
      if (entry.isImage) {
        final effectiveContext =
            photoContext ??
            (tab == 2 && entries.isNotEmpty
                ? _visibleFolderEntries()
                : (tab == 1 && queue.isNotEmpty ? queue : [entry]));
        await openPhotoAndMirror(effectiveContext, entry);
      } else {
        await play([entry], sourceTitle: entry.name);
      }
    }
  }

  /// Abre uma foto no visualizador interno do aplicativo e espelha em tempo real na TV conectada.
  Future<void> openPhotoAndMirror(
    List<LibraryEntry> contextList,
    LibraryEntry tappedPhoto, {
    bool syncToQueue = true,
  }) async {
    final effectiveSource =
        (tab == 2 && entries.isNotEmpty && contextList.length <= 1)
        ? _visibleFolderEntries()
        : (tab == 1 && queue.isNotEmpty && contextList.length <= 1)
        ? queue
        : contextList;
    final photos = effectiveSource.where((e) => e.isImage).toList();
    if (photos.isEmpty) {
      photos.add(tappedPhoto);
    } else if (!photos.any(
      (e) => e.id == tappedPhoto.id && e.source == tappedPhoto.source,
    )) {
      photos.add(tappedPhoto);
    }
    var idx = photos.indexWhere(
      (e) => e.id == tappedPhoto.id && e.source == tappedPhoto.source,
    );
    if (idx < 0) idx = 0;
    final media = effectiveSource
        .where((e) => !e.folder && e.isSupportedMedia)
        .toList();

    _pauseLocalPlayback();
    setState(() {
      if (syncToQueue) {
        _ensureEntryInQueue(tappedPhoto);
      }
      viewerContext = media.any((e) => _same(e, tappedPhoto))
          ? media
          : [...media, tappedPhoto];
      activePhotos = photos;
      activePhotoIndex = idx;
      activeMediaItem = tappedPhoto;
      loadingPhotoPreview = true;
    });
    if (syncToQueue) {
      await save();
    }

    await _loadAndMirrorActivePhoto();
  }

  Future<void> _loadAndMirrorActivePhoto() async {
    if (activePhotos.isEmpty ||
        activePhotoIndex < 0 ||
        activePhotoIndex >= activePhotos.length) {
      return;
    }
    final currentPhoto = activePhotos[activePhotoIndex];
    final currentGen = ++_playGeneration;
    sources.abortActiveOperations();

    setState(() {
      _ensureEntryInQueue(currentPhoto);
      activeMediaItem = currentPhoto;
      loadingPhotoPreview = true;
      casting = false;
    });
    unawaited(save());

    try {
      final cached = _photoCache;
      final Directory dir = cached != null && await cached.exists()
          ? cached
          : (_photoCache = await LibrarySources.sessionCache());
      final resolved = await sources.resolve(currentPhoto, dir);
      if (!mounted || currentGen != _playGeneration) return;
      setState(() {
        viewedPhotoFile = resolved;
        loadingPhotoPreview = false;
      });
      _scrollCarouselTo(currentPhoto);

      final tv = context.read<RemoteController>();
      final pTarget = getPlaybackTarget(tv);
      if (pTarget == PlaybackTarget.tv) {
        if (tv.isConnected) {
          final cast = context.read<MediaCastController>();
          final driver = tv.driver,
              ip = tv.ipAddress,
              brand = tv.currentBrand,
              name = tv.connectedTvName;
          final location = tv.discoveredTvs
              .where((e) => e.ip == ip)
              .firstOrNull
              ?.location;
          final castDir = await LibrarySources.sessionCache();
          File castFirst = resolved;
          if (resolved.parent.path == dir.path) {
            final targetPath =
                '${castDir.path}/${resolved.uri.pathSegments.last}';
            castFirst = await resolved.copy(targetPath);
            final cloudMeta = File('${resolved.path}.cloud.json');
            if (await cloudMeta.exists()) {
              await cloudMeta.copy('$targetPath.cloud.json');
            }
          }
          final ok = await cast.castResolvedPlaylist(
            castFirst,
            [() => sources.resolve(currentPhoto, castDir)],
            targetTvIp: ip,
            brand: brand,
            tvName: name,
            locationUrl: location,
            activeDriver: driver,
            startIndex: 0,
            names: [currentPhoto.name],
            cacheDirectory: castDir,
          );
          if (mounted && currentGen == _playGeneration) {
            message(
              ok
                  ? 'Transmitindo para ${name ?? ip}.'
                  : cast.errorMessage ?? 'O dispositivo recusou a imagem.',
            );
          }
        } else {
          message('Conecte um dispositivo para transmitir.');
        }
      }
    } catch (e) {
      if (mounted && currentGen == _playGeneration) {
        setState(() => loadingPhotoPreview = false);
        message(
          e is FormatException
              ? e.message
              : 'Não foi possível carregar a imagem.',
        );
      }
    }
  }

  MediaCastController? _castOrNull() {
    try {
      return context.read<MediaCastController?>();
    } catch (_) {
      return null;
    }
  }

  /// Item exibido no card agora (foto, vídeo ou áudio).
  LibraryEntry? _currentViewerEntry() {
    if (activeMediaItem != null) return activeMediaItem;
    if (activePhotos.isEmpty) return null;
    return activePhotos[activePhotoIndex.clamp(0, activePhotos.length - 1)];
  }

  /// Centraliza a miniatura do item focado na faixa do carrossel.
  void _scrollCarouselTo(LibraryEntry entry) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !photoScroll.hasClients) return;
      final idx = _carouselContextItems().indexWhere((e) => _same(e, entry));
      if (idx < 0) return;
      final position = photoScroll.position;
      final target =
          idx * _carouselStep -
          (position.viewportDimension - _carouselTileWidth) / 2;
      photoScroll.animateTo(
        target.clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  static const double _carouselTileWidth = 64;
  static const double _carouselStep = _carouselTileWidth + 8;

  /// Navegação única do visualizador: anterior/próximo seguem a ordem do
  /// carrossel, misturando fotos, vídeos e áudios.
  Future<void> navigateActivePhoto(int delta) async {
    final current = _currentViewerEntry();
    if (current == null) return;
    final items = _carouselContextItems();
    final idx = items.indexWhere((e) => _same(e, current));
    final next = idx + delta;
    if (idx < 0 || next < 0 || next >= items.length) return;
    await _focusEntry(items[next], items);
  }

  /// Torna [item] a mídia focada do card — mesmo comportamento para foto,
  /// vídeo e áudio. Foto: abre e espelha na TV. Vídeo/áudio: transmite para a
  /// TV (destino "Na TV") ou toca no player do próprio card ("Local").
  Future<void> _focusEntry(
    LibraryEntry item,
    List<LibraryEntry> contextItems,
  ) async {
    HapticService.selectionClick();
    if (item.isImage) {
      final targetIdx = activePhotos.indexWhere((e) => _same(e, item));
      if (targetIdx >= 0) {
        _pauseLocalPlayback();
        setState(() {
          activePhotoIndex = targetIdx;
          activeMediaItem = activePhotos[targetIdx];
        });
        await _loadAndMirrorActivePhoto();
      } else {
        await openPhotoAndMirror(contextItems, item, syncToQueue: tab != 1);
      }
      return;
    }
    final cast = _castOrNull();
    setState(() {
      activeMediaItem = item;
      if (!viewerContext.any((e) => _same(e, item))) {
        viewerContext = contextItems.any((e) => _same(e, item))
            ? contextItems
            : [...viewerContext, item];
      }
      viewedPhotoFile = null;
      loadingPhotoPreview = false;
      _lastCastFile = cast?.currentFileName;
    });
    _scrollCarouselTo(item);
    await _startEntryPlayback(item);
  }

  /// Inicia a reprodução do item no destino atual.
  Future<void> _startEntryPlayback(LibraryEntry item) async {
    final tv = context.read<RemoteController>();
    if (getPlaybackTarget(tv) == PlaybackTarget.tv) {
      if (!tv.isConnected) {
        message('Conecte um dispositivo para transmitir.');
        return;
      }
      _stopLocalPlayback();
      await play(
        tab == 1 ? queue : [item],
        start: tab == 1
            ? queue.indexWhere((q) => _same(q, item)).clamp(0, queue.length - 1)
            : 0,
        sourceTitle: tab == 1 ? queueTitle : item.name,
        syncToQueue: tab != 1,
      );
    } else {
      await _playLocally(item);
    }
  }

  /// Fonte de mídia para o player embutido, sem baixar o arquivo inteiro.
  Future<Media> _localMediaFor(LibraryEntry e) async {
    switch (e.source) {
      case LibrarySource.local:
      case LibrarySource.androidTree:
        return Media(e.id);
      case LibrarySource.drive:
      case LibrarySource.oneDrive:
        final token = await sources.token(e.source);
        final url = e.source == LibrarySource.drive
            ? Uri.https('www.googleapis.com', '/drive/v3/files/${e.id}', {
                'alt': 'media',
              })
            : Uri.https(
                'graph.microsoft.com',
                '/v1.0/me/drive/items/${e.id}/content',
              );
        return Media(
          url.toString(),
          httpHeaders: {'Authorization': 'Bearer $token'},
        );
    }
  }

  /// Toca vídeo/áudio dentro do card (player embutido, nunca o player externo).
  Future<void> _playLocally(LibraryEntry e) async {
    final gen = ++_localGen;
    final key = _keyOf(e);
    try {
      final player = _localPlayer ??= Player();
      _localVideo ??= VideoController(player);
      _localCompletedSub ??= player.stream.completed.listen((done) {
        if (done) _onLocalCompleted();
      });
      await player.setPlaylistMode(
        _localRepeat ? PlaylistMode.single : PlaylistMode.none,
      );
      setState(() {
        activeMediaItem = e;
        _localKey = key;
        _localLoading = true;
        _localError = null;
      });
      final media = await _localMediaFor(e);
      if (!mounted || gen != _localGen) return;
      await player.open(media, play: true);
      if (mounted && gen == _localGen) setState(() => _localLoading = false);
    } catch (err) {
      if (!mounted || gen != _localGen) return;
      setState(() {
        _localLoading = false;
        _localError = err is FormatException
            ? err.message
            : 'Não foi possível reproduzir este arquivo neste aparelho.';
      });
    }
  }

  void _pauseLocalPlayback() {
    final player = _localPlayer;
    if (player != null && player.state.playing) unawaited(player.pause());
  }

  void _stopLocalPlayback() {
    _localGen++;
    final player = _localPlayer;
    if (player != null) unawaited(player.stop());
    _localKey = null;
    _localLoading = false;
    _localError = null;
  }

  bool _isPlayingHere(LibraryEntry e) =>
      _localKey == _keyOf(e) && _localVideo != null;

  /// Tela cheia das fotos (visualizador próprio do SixF, com zoom e deslize).
  Future<void> _openImageFullScreen(LibraryEntry entry) async {
    final images = _carouselContextItems().where((e) => e.isImage).toList();
    if (!images.any((e) => _same(e, entry))) images.add(entry);
    final start = images.indexWhere((e) => _same(e, entry));
    HapticService.selectionClick();
    final cache = _photoCache != null && await _photoCache!.exists()
        ? _photoCache!
        : (_photoCache = await LibrarySources.sessionCache());
    if (!mounted) return;
    // A TV acompanha a tela cheia: cada foto em que o usuário para (após
    // uma pausa curta, para não enviar rajadas ao deslizar) é espelhada na
    // TV. Sem destino TV, só a foto final é aplicada ao fechar.
    final contextItems = _carouselContextItems();
    var mirrored = entry;
    Timer? debounce;
    final last = await ImageFullscreenViewer.show(
      context,
      items: images,
      initialIndex: start,
      resolve: (e) => sources.resolve(e, cache),
      onIndexChanged: (i) {
        debounce?.cancel();
        if (i < 0 || i >= images.length) return;
        debounce = Timer(const Duration(milliseconds: 350), () {
          if (!mounted) return;
          final tv = context.read<RemoteController>();
          if (getPlaybackTarget(tv) != PlaybackTarget.tv || !tv.isConnected) {
            return;
          }
          final chosen = images[i];
          if (_same(chosen, mirrored)) return;
          mirrored = chosen;
          unawaited(_focusEntry(chosen, contextItems));
        });
      },
    );
    debounce?.cancel();
    if (!mounted || last == null || last < 0 || last >= images.length) return;
    final chosen = images[last];
    if (!_same(chosen, mirrored)) {
      await _focusEntry(chosen, contextItems);
    }
  }

  Future<void> play(
    List<LibraryEntry> original, {
    int start = 0,
    String? sourceTitle,
    bool syncToQueue = true,
  }) async {
    if (original.isEmpty) return;
    final items = original.map(_cloneEntry).toList();
    final safeStart = start.clamp(0, items.length - 1);

    // Se o item clicado for uma foto, abre o visualizador rápido com espelhamento em tempo real
    if (items[safeStart].isImage) {
      if (syncToQueue) {
        setState(() {
          if (items.length == 1) {
            _ensureEntryInQueue(items.first, sourceTitle: sourceTitle);
          } else {
            queue
              ..clear()
              ..addAll(items);
            if (sourceTitle != null) {
              queueTitle = sourceTitle;
            }
            queueExpanded = true;
          }
        });
        await save();
      }
      final contextItems = (tab == 2 && entries.isNotEmpty)
          ? _visibleFolderEntries()
          : (tab == 1 && queue.isNotEmpty)
          ? queue
          : items;
      await openPhotoAndMirror(
        contextItems,
        items[safeStart],
        syncToQueue: false,
      );
      return;
    }

    _clearPhotoCache();
    if (items[safeStart].isVideo || items[safeStart].isAudio) {
      final contextMedia = (tab == 2 && entries.isNotEmpty)
          ? _visibleFolderEntries()
                .where((e) => !e.folder && (e.isImage || e.isVideo))
                .toList()
          : (tab == 1 && queue.isNotEmpty)
          ? queue.where((e) => !e.folder && (e.isImage || e.isVideo)).toList()
          : items.where((e) => !e.folder && (e.isImage || e.isVideo)).toList();
      final imageItems = contextMedia.where((e) => e.isImage).toList();
      setState(() {
        activeMediaItem = items[safeStart];
        if (!viewerContext.any((e) => _same(e, items[safeStart]))) {
          viewerContext = contextMedia.isNotEmpty
              ? contextMedia
              : [items[safeStart]];
        }
        activePhotos = imageItems.isNotEmpty
            ? imageItems
            : (contextMedia.isNotEmpty ? contextMedia : [items[safeStart]]);
        activePhotoIndex = 0;
        viewedPhotoFile = null;
        loadingPhotoPreview = false;
      });
    } else {
      setState(() {
        activeMediaItem = null;
        activePhotos = [];
        viewerContext = [];
        viewedPhotoFile = null;
      });
    }
    // Cancela qualquer preparação anterior para não travar a fila
    final currentPlayGen = ++_playGeneration;
    sources.abortActiveOperations();

    if (syncToQueue) {
      setState(() {
        if (items.length == 1) {
          _ensureEntryInQueue(items.first, sourceTitle: sourceTitle);
        } else {
          queue
            ..clear()
            ..addAll(items);
          if (sourceTitle != null) {
            queueTitle = sourceTitle;
          } else if (queueTitle == null && items.length == 1) {
            queueTitle = items.first.name;
          }
          queueExpanded = true;
        }
      });
      await save();
    }

    if (!mounted) return;
    final tv = context.read<RemoteController>();
    final pTarget = getPlaybackTarget(tv);
    if (pTarget == PlaybackTarget.local) {
      // Destino "Este aparelho": toca no player embutido do card.
      if (items[safeStart].isVideo || items[safeStart].isAudio) {
        await _playLocally(items[safeStart]);
      }
      return;
    }
    if (!tv.isConnected) {
      message('Conecte um dispositivo para transmitir.');
      return;
    }
    final cast = context.read<MediaCastController>();
    final driver = tv.driver,
        ip = tv.ipAddress,
        brand = tv.currentBrand,
        name = tv.connectedTvName;
    final location = tv.discoveredTvs
        .where((e) => e.ip == ip)
        .firstOrNull
        ?.location;
    setState(() => casting = true);
    Directory? cache;
    try {
      final dir = await LibrarySources.sessionCache();
      cache = dir;
      final activeQueue = items;
      var effectiveStart = safeStart.clamp(0, activeQueue.length - 1);
      File? first;

      // Se um episódio falhar (ex: movido ou sem acesso), informa qual falhou e tenta o próximo da fila
      while (effectiveStart < activeQueue.length) {
        final candidate = activeQueue[effectiveStart];
        try {
          first = await sources.resolve(candidate, dir);
          failedEntryIds.remove(candidate.id);
          break;
        } catch (e) {
          if (!mounted || currentPlayGen != _playGeneration) return;
          setState(() => failedEntryIds.add(candidate.id));
          if (effectiveStart + 1 < activeQueue.length) {
            message(
              'Episódio "${candidate.name}" indisponível. Avançando para o próximo...',
            );
            effectiveStart++;
          } else {
            rethrow;
          }
        }
      }

      if (first == null ||
          !mounted ||
          currentPlayGen != _playGeneration ||
          !tv.isConnected ||
          !identical(driver, tv.driver) ||
          ip != tv.ipAddress) {
        return;
      }

      final ok = await cast.castResolvedPlaylist(
        first,
        [for (final item in activeQueue) () => sources.resolve(item, dir)],
        targetTvIp: ip,
        brand: brand,
        tvName: name,
        locationUrl: location,
        activeDriver: driver,
        startIndex: effectiveStart,
        names: [for (final item in activeQueue) item.name],
        cacheDirectory: dir,
      );
      if (currentPlayGen != _playGeneration) return;
      cache = null;
      message(
        ok
            ? 'Transmitindo para ${name ?? ip}.'
            : cast.errorMessage ?? 'O dispositivo recusou a mídia.',
      );
    } catch (e) {
      if (currentPlayGen == _playGeneration) {
        message(
          e is FormatException
              ? e.message
              : 'Não foi possível preparar o episódio.',
        );
      }
    } finally {
      if (cache != null && await cache.exists()) {
        try {
          await cache.delete(recursive: true);
        } catch (_) {}
      }
      if (mounted && currentPlayGen == _playGeneration) {
        setState(() => casting = false);
      }
    }
  }

  /// Botões das 3 abas (Playlists | Fila | Arquivos) seguindo à risca o padrão gráfico
  /// das pílulas de dispositivos (borda roxa `highlightColor`, gradiente Liquid Glass e fonte padronizada).
  Widget _buildSectionSelector(
    BuildContext context,
    RemoteController tv, {
    double horizontalPadding = 16,
  }) {
    final isDark = tv.isDarkMode;
    final highlightColor = isDark
        ? AppColors.iconHighlight
        : AppColors.lightIconHighlight;

    final tabs = <({int index, IconData icon, String label})>[
      (index: 2, icon: Icons.folder_rounded, label: 'Arquivos'),
      (index: 0, icon: Icons.playlist_play_rounded, label: 'Playlists'),
      (
        index: 1,
        icon: Icons.queue_music_rounded,
        label: queue.isEmpty ? 'Fila' : 'Fila (${queue.length})',
      ),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 6),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Builder(
                builder: (context) {
                  final item = tabs[i];
                  final isActive = tab == item.index;
                  // Padrão Payno: a seção ativa em azul-marinho sólido.
                  final textColor = isActive
                      ? Colors.white
                      : (isDark
                            ? AppColors.textSecondary
                            : AppColors.lightTextSecondary);
                  final iconColor = textColor;
                  final borderColor = isActive
                      ? Colors.transparent
                      : (isDark
                            ? AppColors.borderSubtle
                            : AppColors.lightBorderSubtle);
                  final bgColor = isActive
                      ? (isDark
                            ? AppColors.accentFill
                            : AppColors.lightAccentFill)
                      : AppColors.cardOf(context);

                  return InkWell(
                    onTap: () {
                      HapticService.selectionClick();
                      setState(() {
                        tab = item.index;
                        _syncActivePhotosForTab(item.index);
                      });
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: borderColor),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: highlightColor.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.icon, size: 16, color: iconColor),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: textColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Miniatura visual (Thumbnail) para fotos locais ou do Google Drive / OneDrive,
  /// e ícones estilizados para vídeos e áudios.
  Widget _buildEntryThumbnail(LibraryEntry entry, {double size = 40}) {
    final highlight = AppColors.iconHighlightOf(context);
    if (entry.folder) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: highlight.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.folder_rounded, color: highlight, size: 22),
      );
    }

    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: highlight.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        entry.isImage
            ? Icons.image_outlined
            : entry.isVideo
            ? Icons.movie_outlined
            : Icons.audiotrack_rounded,
        color: highlight,
        size: (size * 0.45).clamp(16.0, 40.0),
      ),
    );
    if (!ThumbnailService.supports(entry)) return placeholder;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = (size * dpr).round().clamp(64, 480);
    return FutureBuilder<File?>(
      key: ValueKey('thumb-${_keyOf(entry)}'),
      future: ThumbnailService.thumbnailFor(entry),
      initialData: ThumbnailService.peek(entry),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return placeholder;
        final image = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: decodeWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => placeholder,
          ),
        );
        if (!entry.isVideo) return image;
        return Stack(
          alignment: Alignment.center,
          children: [
            image,
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: (size * 0.32).clamp(12.0, 30.0),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Capa grande de vídeo/áudio no card (miniatura em `contain` sobre fundo escuro).
  Widget _buildLargeVideoThumbnail(LibraryEntry entry, {double height = 200}) {
    final highlight = AppColors.iconHighlightOf(context);
    final fallback = Icon(
      entry.isAudio ? Icons.audiotrack_rounded : Icons.movie_outlined,
      color: highlight,
      size: 56,
    );
    if (!ThumbnailService.supports(entry)) return Center(child: fallback);
    return FutureBuilder<File?>(
      key: ValueKey('cover-${_keyOf(entry)}'),
      future: ThumbnailService.thumbnailFor(entry),
      initialData: ThumbnailService.peek(entry),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return Center(child: fallback);
        return Image.file(
          file,
          width: double.infinity,
          height: height,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => Center(child: fallback),
        );
      },
    );
  }

  /// Seletor de Destino no padrão de mercado (Google Fotos / Cast): Este Aparelho vs TV Conectada.
  Widget _buildPlaybackTargetSelector(RemoteController tv) {
    final target = getPlaybackTarget(tv);
    final isTv = target == PlaybackTarget.tv;
    final highlight = AppColors.iconHighlightOf(context);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        HapticService.selectionClick();
        if (isTv) {
          _backToLocal();
        } else {
          _sendToTv(_currentViewerEntry());
        }
      },
      child: Tooltip(
        message: isTv
            ? 'Destino: ${tv.connectedTvName ?? "TV conectada"} (Toque para alternar para Local)'
            : 'Destino: Este aparelho (Toque para alternar para TV)',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isTv
                ? highlight.withValues(alpha: 0.18)
                : AppColors.surfaceInteractiveOf(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isTv ? highlight : AppColors.borderSubtleOf(context),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isTv ? Icons.tv_rounded : Icons.phone_android_rounded,
                size: 13,
                color: isTv ? highlight : AppColors.textSecondaryOf(context),
              ),
              const SizedBox(width: 4),
              Text(
                isTv ? 'Na TV' : 'Local',
                textScaler: const TextScaler.linear(1.0),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isTv ? highlight : AppColors.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Menu de ação rápida acionado ao segurar (Long Press) numa thumbnail do carrossel
  Future<void> _showCarouselItemActions(LibraryEntry entry) async {
    final tv = context.read<RemoteController>();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceCardOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: _buildEntryThumbnail(entry, size: 36),
              title: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                entry.isImage ? 'Foto' : (entry.isVideo ? 'Vídeo' : 'Áudio'),
                style: const TextStyle(fontSize: 11),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.cast_rounded),
              title: const Text('Reproduzir agora na televisão'),
              subtitle: tv.isConnected && tv.connectedTvName != null
                  ? Text(tv.connectedTvName!)
                  : null,
              onTap: () => Navigator.pop(ctx, 'cast_now'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android_rounded),
              title: const Text('Reproduzir neste aparelho'),
              onTap: () => Navigator.pop(ctx, 'play_local'),
            ),
            ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('Selecionar vários arquivos'),
              onTap: () => Navigator.pop(ctx, 'multi_select'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Adicionar à playlist'),
              onTap: () => Navigator.pop(ctx, 'add_playlist'),
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('Adicionar à fila'),
              onTap: () => Navigator.pop(ctx, 'add_queue'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'cast_now') {
      setState(() => _userChosenTarget = PlaybackTarget.tv);
      if (entry.isImage) {
        await openPhotoAndMirror(_carouselContextItems(), entry);
      } else {
        await play(tab == 1 ? queue : [entry], sourceTitle: entry.name);
      }
    } else if (action == 'play_local') {
      setState(() => _userChosenTarget = PlaybackTarget.local);
      await _focusEntry(entry, _carouselContextItems());
    } else if (action == 'multi_select') {
      setState(() {
        isMultiSelecting = true;
        multiSelectedIds.add(entry.id);
      });
      message('Modo de seleção ativado. Toque nas miniaturas para selecionar.');
    } else if (action == 'add_queue') {
      setState(() {
        _ensureEntryInQueue(entry);
      });
      await save();
      _syncLiveCastQueue();
      message('1 item adicionado à fila de execução.');
    } else if (action == 'add_playlist') {
      final previous = List<LibraryEntry>.of(selected);
      selected
        ..clear()
        ..add(entry);
      await addSelection();
      if (mounted) {
        setState(() {
          selected
            ..clear()
            ..addAll(previous);
        });
      }
    }
  }

  /// Salva itens da seleção múltipla do carrossel em uma playlist
  Future<void> _saveMultiSelectionToPlaylist() async {
    if (multiSelectedIds.isEmpty) return;
    final carouselItems = _carouselContextItems();
    final selectedEntries = carouselItems
        .where((e) => multiSelectedIds.contains(e.id))
        .map(_cloneEntry)
        .toList();
    if (selectedEntries.isEmpty) return;

    final name = await nameDialog(title: 'Criar playlist com selecionados');
    if (name == null || !mounted) return;
    final newList = _Collection(name, selectedEntries);
    setState(() {
      lists.add(newList);
      isMultiSelecting = false;
      multiSelectedIds.clear();
    });
    await save();
    message('Playlist "$name" criada com ${selectedEntries.length} itens.');
  }

  /// Manda todos os itens selecionados no carrossel para o fim da fila de
  /// reprodução, na ordem do carrossel, e encerra a seleção.
  Future<void> _addMultiSelectionToQueue() async {
    if (multiSelectedIds.isEmpty) return;
    final chosen = _carouselContextItems()
        .where((e) => multiSelectedIds.contains(e.id))
        .toList();
    var added = 0;
    setState(() {
      for (final item in chosen) {
        final exists = queue.any((q) => _same(q, item));
        if (!exists) {
          queue.add(_cloneEntry(item));
          added++;
        }
      }
      if (queueTitle == null && queue.isNotEmpty) {
        queueTitle = 'Arquivos selecionados';
      }
      queueExpanded = true;
      isMultiSelecting = false;
      multiSelectedIds.clear();
    });
    await save();
    _syncLiveCastQueue();
    final skipped = chosen.length - added;
    message(
      '$added ${added == 1 ? 'item adicionado' : 'itens adicionados'} à fila'
      '${skipped > 0 ? ' ($skipped já estava${skipped == 1 ? '' : 'm'} na fila)' : ''}.',
    );
  }

  /// Barra de controle superior exibida durante a seleção múltipla
  Widget _buildMultiSelectionBar(Color highlight) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: highlight.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.checklist_rounded, size: 18, color: highlight),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${multiSelectedIds.length} ${multiSelectedIds.length == 1 ? 'item selecionado' : 'itens selecionados'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: highlight,
              ),
            ),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('multi-select-queue'),
            onPressed: multiSelectedIds.isNotEmpty
                ? _addMultiSelectionToQueue
                : null,
            icon: const Icon(Icons.queue_music_rounded, size: 16),
            label: const Text('Fila', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 6),
          FilledButton.tonalIcon(
            onPressed: multiSelectedIds.isNotEmpty
                ? _saveMultiSelectionToPlaylist
                : null,
            icon: const Icon(Icons.playlist_add_rounded, size: 16),
            label: const Text('Playlist', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Cancelar seleção',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() {
              isMultiSelecting = false;
              multiSelectedIds.clear();
            }),
          ),
        ],
      ),
    );
  }

  /// Faixa horizontal rolável de miniaturas do carrossel
  Widget _buildThumbnailsCarousel(
    List<LibraryEntry> carouselItems,
    LibraryEntry current,
    Color highlight,
    RemoteController tv, {
    bool showNames = true,
  }) {
    if (carouselItems.isEmpty) return const SizedBox.shrink();

    final textScale = MediaQuery.textScalerOf(context)
        .scale(1.0)
        .clamp(1.0, 2.0);
    // Sem os nomes (coluna direita do visualizador de altura inteira) o
    // carrossel fica só com as miniaturas e poupa altura para a lista.
    final carouselHeight = showNames
        ? (64.0 + 18.0 * textScale).clamp(82.0, 104.0)
        : 58.0;

    return SizedBox(
      height: carouselHeight,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        child: ListView.separated(
          controller: photoScroll,
          physics: const BouncingScrollPhysics(),
          scrollDirection: Axis.horizontal,
          itemCount: carouselItems.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final item = carouselItems[i];
            final isCurrent =
                item.id == current.id && item.source == current.source;
            final isItemMultiSelected = multiSelectedIds.contains(item.id);
            final photoOrd = item.isImage
                ? carouselItems.take(i).where((e) => e.isImage).length
                : -1;
            return Tooltip(
              message: item.name,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  if (isMultiSelecting) {
                    setState(() {
                      if (multiSelectedIds.contains(item.id)) {
                        multiSelectedIds.remove(item.id);
                        if (multiSelectedIds.isEmpty) {
                          isMultiSelecting = false;
                        }
                      } else {
                        multiSelectedIds.add(item.id);
                      }
                    });
                    return;
                  }
                  // Mesmo comportamento para foto, vídeo e áudio: o item
                  // tocado vira a mídia focada do card.
                  if (isCurrent &&
                      (item.isImage
                          ? viewedPhotoFile != null || loadingPhotoPreview
                          : _isPlayingHere(item))) {
                    return;
                  }
                  _focusEntry(item, carouselItems);
                },
                onLongPress: () {
                  HapticService.heavyPress();
                  _showCarouselItemActions(item);
                },
                child: SizedBox(
                  width: _carouselTileWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          Container(
                            key: item.isImage
                                ? ValueKey('photo-thumbnail-$photoOrd')
                                : ValueKey('media-thumbnail-$i'),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isCurrent
                                    ? highlight
                                    : (isItemMultiSelected
                                          ? highlight
                                          : Colors.transparent),
                                width: 2,
                              ),
                            ),
                            child: _buildEntryThumbnail(item, size: 52),
                          ),
                          if (isMultiSelecting)
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                width: 15,
                                height: 15,
                                decoration: BoxDecoration(
                                  color: isItemMultiSelected
                                      ? highlight
                                      : Colors.black54,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1,
                                  ),
                                ),
                                child: isItemMultiSelected
                                    ? const Icon(
                                        Icons.check,
                                        size: 10,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                      if (showNames) ...[
                        const SizedBox(height: 2),
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrent
                                  ? highlight
                                  : AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Caixa de visualização grande do carrossel (foto com zoom ou miniatura expandida do vídeo)
  /// Os controles padrão do media_kit pedem ~148 px de altura (barra superior
  /// de 56 + inferior de 56 + linha do tempo de 36). Em celular deitado o
  /// card do vídeo é mais baixo que isso e estourava por frações de pixel
  /// (faixa amarela e preta). Em alturas menores, as barras encolhem para
  /// caber; em tela cheia e em alturas folgadas nada muda.
  Widget _withCompactVideoControls(double height, Widget video) {
    // Controles de toque (Android): a linha do tempo padrão do media_kit fica
    // colada na borda inferior e tem só 2,4 px. Aqui ela sobe ([lift]) e
    // engrossa; a barra de botões sobe junto para continuar acima dela.
    final lift = touchSeekBarLift(height);
    final sizes = compactVideoControlSizes(height - lift);
    final touch = MaterialVideoControlsThemeData(
      buttonBarHeight: sizes?.bar ?? 56,
      seekBarContainerHeight: sizes?.seek ?? 36,
      seekBarHeight: 4.5,
      seekBarThumbSize: 15,
      seekBarMargin: EdgeInsets.only(left: 14, right: 14, bottom: lift),
      bottomButtonBarMargin: EdgeInsets.only(left: 16, right: 8, bottom: lift),
    );
    // Tela cheia: sobe mais, para sair de cima da barra de gestos do sistema.
    const touchFullscreen = MaterialVideoControlsThemeData(
      seekBarHeight: 4.5,
      seekBarThumbSize: 15,
      seekBarMargin: EdgeInsets.only(left: 16, right: 16, bottom: 42),
      bottomButtonBarMargin: EdgeInsets.only(left: 16, right: 8, bottom: 42),
    );
    final desktop = sizes == null
        ? const MaterialDesktopVideoControlsThemeData()
        : MaterialDesktopVideoControlsThemeData(
            buttonBarHeight: sizes.bar,
            seekBarContainerHeight: sizes.seek,
          );
    return MaterialVideoControlsTheme(
      normal: touch,
      fullscreen: touchFullscreen,
      child: MaterialDesktopVideoControlsTheme(
        normal: desktop,
        fullscreen: const MaterialDesktopVideoControlsThemeData(),
        child: video,
      ),
    );
  }

  Widget _buildPreviewBox(
    LibraryEntry current,
    bool canPrev,
    bool canNext, {
    double height = 200,
  }) {
    final tv = context.read<RemoteController>();
    final isTv = getPlaybackTarget(tv) == PlaybackTarget.tv;
    final playingHere = !current.isImage && !isTv && _isPlayingHere(current);
    final hasImage =
        current.isImage &&
        !loadingPhotoPreview &&
        viewedPhotoFile != null &&
        viewedPhotoFile!.existsSync();

    Widget content;
    if (playingHere) {
      // Player embutido: controles de mercado (play/pausa, barra, volume,
      // tela cheia) fornecidos pelo media_kit em Windows e Android.
      content = Stack(
        fit: StackFit.expand,
        children: [
          _withCompactVideoControls(
            height,
            Video(
              key: ValueKey('inline-video-${_keyOf(current)}'),
              controller: _localVideo!,
              // Em cards muito baixos (<96 px) nem as barras compactas cabem:
              // o vídeo fica sem sobreposição e usa os botões do painel ao lado.
              controls: height < 96 ? NoVideoControls : AdaptiveVideoControls,
              fill: Colors.black,
            ),
          ),
          if (current.isAudio)
            IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.audiotrack_rounded,
                  size: 64,
                  color: AppColors.iconHighlightOf(context),
                ),
              ),
            ),
          if (_localLoading)
            const IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      );
    } else if (!current.isImage) {
      final isStreamingThis = _castOrNull()?.currentFileName == current.name;
      content = Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          _buildLargeVideoThumbnail(current, height: height),
          // Botão de reproduzir (e aviso de erro) encolhem juntos se o card
          // for baixo (celular deitado, fonte grande), em vez de estourar.
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      key: const ValueKey('viewer-play-here'),
                      tooltip: isTv
                          ? 'Reproduzir na TV'
                          : 'Reproduzir neste aparelho',
                      iconSize: 40,
                      color: Colors.white,
                      icon: Icon(
                        isTv && isStreamingThis
                            ? Icons.cast_connected_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      onPressed: () => _startEntryPlayback(current),
                    ),
                  ),
                  if (_localError != null && _localKey == _keyOf(current))
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          _localError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    } else if (loadingPhotoPreview) {
      content = const Center(child: CircularProgressIndicator());
    } else if (hasImage) {
      content = GestureDetector(
        onDoubleTap: () => _openImageFullScreen(current),
        child: Image.file(
          viewedPhotoFile!,
          key: ValueKey(viewedPhotoFile!.path),
          fit: BoxFit.contain,
          width: double.infinity,
          height: height,
          gaplessPlayback: true,
        ),
      );
    } else {
      content = Center(child: _buildEntryThumbnail(current, size: 120));
    }

    // Deslizar para os lados troca de mídia (exceto sobre o player, cujos
    // gestos pertencem aos controles do vídeo).
    if (!playingHere) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -250 && canNext) navigateActivePhoto(1);
          if (v > 250 && canPrev) navigateActivePhoto(-1);
        },
        child: content,
      );
    }

    final items = _carouselContextItems();
    final pos = items.indexWhere((e) => _same(e, current));

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: Container(color: Colors.black26)),
            Positioned.fill(child: content),
            Positioned(
              left: 8,
              child: IconButton.filledTonal(
                tooltip: 'Imagem anterior',
                onPressed: canPrev ? () => navigateActivePhoto(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ),
            Positioned(
              right: 8,
              child: IconButton.filledTonal(
                tooltip: 'Próxima imagem',
                onPressed: canNext ? () => navigateActivePhoto(1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ),
            if (pos >= 0 && items.length > 1)
              Positioned(
                top: 8,
                left: 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${pos + 1} de ${items.length}',
                      textScaler: const TextScaler.linear(1.0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            if (current.isImage)
              Positioned(
                top: 6,
                right: 6,
                child: IconButton.filledTonal(
                  key: const ValueKey('viewer-fullscreen'),
                  tooltip: 'Tela cheia (F)',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openImageFullScreen(current),
                  icon: const Icon(Icons.fullscreen_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Cabeçalho superior do card do carrossel com destino e ações
  Widget _buildViewerHeader(
    RemoteController tv,
    LibraryEntry current,
    int safeIdx,
    int curCarouselIdx,
    List<LibraryEntry> carouselItems,
    Color highlight, {
    required bool isLandscape,
  }) {
    final pTarget = getPlaybackTarget(tv);
    final isTv = pTarget == PlaybackTarget.tv;

    return Row(
      children: [
        Icon(
          current.isImage
              ? Icons.photo_library_rounded
              : current.isAudio
              ? Icons.audiotrack_rounded
              : Icons.movie_creation_outlined,
          color: highlight,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => showFileActions(current),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${current.isImage
                      ? 'Foto'
                      : current.isVideo
                      ? 'Vídeo'
                      : 'Áudio'} ${curCarouselIdx >= 0 ? curCarouselIdx + 1 : 1} de ${carouselItems.isNotEmpty ? carouselItems.length : 1} · ${tab == 1 ? 'Fila' : 'Pasta'} · ${isTv ? 'Na TV' : 'Neste aparelho'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        _buildPlaybackTargetSelector(tv),
        const SizedBox(width: 4),
        if (tv.isConnected)
          IconButton(
            key: const ValueKey('viewer-send-to-tv'),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            tooltip: isTv
                ? 'Reenviar à TV'
                : 'Enviar à TV (${tv.connectedTvName ?? tv.ipAddress})',
            icon: Icon(
              isTv ? Icons.cast_connected_rounded : Icons.cast_rounded,
              size: 18,
              color: isTv ? highlight : null,
            ),
            onPressed: loadingPhotoPreview ? null : () => _sendToTv(current),
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(4),
          tooltip: 'Fechar visualizador de fotos',
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: () {
            _clearPhotoCache();
            _stopLocalPlayback();
            setState(() {
              activePhotos = [];
              viewerContext = [];
              activeMediaItem = null;
              viewedPhotoFile = null;
              isMultiSelecting = false;
              multiSelectedIds.clear();
            });
          },
        ),
      ],
    );
  }

  /// Painel de controles na orientação horizontal (Landscape)
  Widget _buildLandscapeMediaControlsPanel(
    RemoteController tv,
    MediaCastController? cast,
    bool isStreamingToTarget,
    LibraryEntry current,
    Color highlight,
  ) {
    final isTv = getPlaybackTarget(tv) == PlaybackTarget.tv;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevatedOf(context).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildPlaybackTargetSelector(tv),
              const Spacer(),
              if (current.isImage)
                IconButton(
                  tooltip: 'Tela cheia (F)',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.fullscreen_rounded, size: 20),
                  onPressed: () => _openImageFullScreen(current),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            current.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimaryOf(context),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            current.isImage
                ? 'Foto • ${isTv ? "Espelhada na TV" : "Visualizador SixF"}'
                : '${current.isVideo ? 'Vídeo' : 'Áudio'} • ${isTv ? "Transmissão para TV" : "Reprodução neste aparelho"}',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          if (!current.isImage) ...[
            const SizedBox(height: 8),
            _buildTransportRow(
              tv,
              cast,
              isStreamingToTarget,
              current,
              highlight,
            ),
            _buildLocalTrackButtons(current),
            if (isTv && cast != null && isStreamingToTarget)
              MediaSessionControls(
                controller: cast,
                enabled: true,
                showTimeline: true,
                showTransportControls: false,
                showPlaybackModes: false,
              ),
          ],
        ],
      ),
    );
  }

  /// Controles de vídeo/áudio sob a prévia na orientação vertical (Portrait).
  Widget _buildPortraitVideoControls(
    RemoteController tv,
    MediaCastController? cast,
    bool isStreamingToTarget,
    LibraryEntry current,
    Color highlight,
  ) {
    final isTv = getPlaybackTarget(tv) == PlaybackTarget.tv;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevatedOf(context).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTransportRow(tv, cast, isStreamingToTarget, current, highlight),
          _buildLocalTrackButtons(current),
          if (isTv && cast != null && isStreamingToTarget)
            MediaSessionControls(
              controller: cast,
              enabled: true,
              showTimeline: true,
              showTransportControls: false,
              showPlaybackModes: false,
            ),
        ],
      ),
    );
  }

  /// Linha única de controles: [−10s] Reproduzir · Pausar [+10s] [Parar] ·
  /// Repetir · Aleatório. Mesmos botões para a TV e para o player local; os
  /// de busca e parar só aparecem durante uma transmissão que os aceita.
  /// Em larguras estreitas a linha encolhe (FittedBox) em vez de quebrar.
  Widget _buildTransportRow(
    RemoteController tv,
    MediaCastController? cast,
    bool isStreamingToTarget,
    LibraryEntry current,
    Color highlight,
  ) {
    final isTv = getPlaybackTarget(tv) == PlaybackTarget.tv;
    final streamingThis =
        isTv &&
        cast != null &&
        isStreamingToTarget &&
        cast.currentFileName == current.name;
    final hereLoaded = !isTv && _isPlayingHere(current);

    final repeatOn = isTv ? (cast?.isLooping ?? false) : _localRepeat;
    final shuffleOn = isTv ? (cast?.isShuffling ?? false) : _localShuffle;

    VoidCallback? onPlay;
    if (isTv) {
      onPlay = () {
        if (!tv.isConnected) {
          message('Conecte um dispositivo para transmitir.');
          return;
        }
        if (streamingThis && (cast.isPaused || cast.canPlay)) {
          cast.play();
        } else {
          _startEntryPlayback(current);
        }
      };
    } else {
      onPlay = () => hereLoaded
          ? unawaited(_localPlayer?.play())
          : _startEntryPlayback(current);
    }

    final VoidCallback? onPause = isTv
        ? (streamingThis && (cast.isPlaying || cast.canPause)
              ? cast.pause
              : null)
        : (hereLoaded ? () => unawaited(_localPlayer?.pause()) : null);

    final VoidCallback? onRepeat = isTv
        ? (cast != null &&
                  isStreamingToTarget &&
                  (cast.canLoop || cast.isLooping)
              ? cast.toggleLoop
              : null)
        : _toggleLocalRepeat;

    final VoidCallback? onShuffle = isTv
        ? (cast != null && cast.canShuffle ? cast.toggleShuffle : null)
        : _toggleLocalShuffle;

    Widget mode(String tip, IconData icon, bool on, VoidCallback? onTap) =>
        IconButton(
          tooltip: tip,
          isSelected: on,
          onPressed: onTap,
          icon: Icon(icon, color: on ? highlight : null),
        );

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (streamingThis && cast.canSeek)
            IconButton(
              tooltip: 'Recuar 10 segundos',
              icon: const Icon(Icons.replay_10_rounded),
              onPressed: () => cast.seekTo(
                cast.currentPosition - const Duration(seconds: 10),
              ),
            ),
          IconButton.filled(
            tooltip: 'Reproduzir vídeo',
            isSelected: streamingThis
                ? cast.isPlaying
                : hereLoaded && (_localPlayer?.state.playing ?? false),
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Pausar vídeo',
            onPressed: onPause,
            icon: const Icon(Icons.pause_rounded),
          ),
          if (streamingThis && cast.canSeek)
            IconButton(
              tooltip: 'Avançar 10 segundos',
              icon: const Icon(Icons.forward_10_rounded),
              onPressed: () => cast.seekTo(
                cast.currentPosition + const Duration(seconds: 10),
              ),
            ),
          if (streamingThis)
            IconButton(
              tooltip: 'Parar transmissão',
              icon: const Icon(Icons.stop_rounded),
              onPressed: cast.stop,
            ),
          const SizedBox(width: 6),
          mode('Repetir vídeo', Icons.repeat_rounded, repeatOn, onRepeat),
          mode('Ordem aleatória', Icons.shuffle_rounded, shuffleOn, onShuffle),
        ],
      ),
    );
  }

  // --- Player local: legendas e faixas de áudio --------------------------

  static String _localTrackLabel(String id, String? title, String? language) {
    final t = title?.trim() ?? '';
    final l = language?.trim() ?? '';
    if (t.isNotEmpty && l.isNotEmpty && t.toLowerCase() != l.toLowerCase()) {
      return '$t ($l)';
    }
    if (t.isNotEmpty) return t;
    if (l.isNotEmpty) return l;
    return 'Faixa $id';
  }

  static bool _isRealTrack(String id) => id != 'auto' && id != 'no';

  /// Botões "Legenda" e "Áudio" do vídeo que toca neste aparelho. Mesmo
  /// padrão da transmissão para a TV: abre a lista, seleciona e confirma.
  /// Só aparecem para vídeo carregado no player embutido.
  Widget _buildLocalTrackButtons(LibraryEntry current) {
    final player = _localPlayer;
    if (player == null || !current.isVideo || !_isPlayingHere(current)) {
      return const SizedBox.shrink();
    }
    // Reconstrói quando o arquivo termina de abrir (faixas disponíveis) e
    // quando a faixa ativa muda.
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      builder: (context, _) => StreamBuilder<Track>(
        stream: player.stream.track,
        builder: (context, _) {
          final subs = player.state.tracks.subtitle
              .where((t) => _isRealTrack(t.id))
              .toList();
          final audios = player.state.tracks.audio
              .where((t) => _isRealTrack(t.id))
              .toList();
          final curSub = player.state.track.subtitle;
          final curAudio = player.state.track.audio;
          final selSub = subs.where((t) => t.id == curSub.id).firstOrNull;
          final selAudio = audios.where((t) => t.id == curAudio.id).firstOrNull;
          return Padding(
            key: const ValueKey('local-track-buttons'),
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                MediaTrackButton(
                  icon: Icons.subtitles_outlined,
                  activeIcon: Icons.subtitles_rounded,
                  label: 'Legenda',
                  selectedTitle: selSub == null
                      ? null
                      : _localTrackLabel(
                          selSub.id,
                          selSub.title,
                          selSub.language,
                        ),
                  tooltip: 'Legendas embutidas',
                  onPressed: () => showTrackPickerDialog<SubtitleTrack>(
                    context,
                    title: 'Legendas',
                    tracks: subs,
                    selected: selSub,
                    labelOf: (t) => _localTrackLabel(t.id, t.title, t.language),
                    detailOf: (t) => t.codec != null ? 'Codec: ${t.codec}' : null,
                    onConfirm: (t) =>
                        player.setSubtitleTrack(t ?? SubtitleTrack.no()),
                  ),
                ),
                MediaTrackButton(
                  icon: Icons.audiotrack_outlined,
                  activeIcon: Icons.audiotrack_rounded,
                  label: 'Áudio',
                  selectedTitle: selAudio == null
                      ? null
                      : _localTrackLabel(
                          selAudio.id,
                          selAudio.title,
                          selAudio.language,
                        ),
                  tooltip: 'Faixa de áudio',
                  onPressed: () => showTrackPickerDialog<AudioTrack>(
                    context,
                    title: 'Faixas de Áudio',
                    tracks: audios,
                    selected: selAudio,
                    labelOf: (t) => _localTrackLabel(t.id, t.title, t.language),
                    detailOf: (t) => t.codec != null ? 'Codec: ${t.codec}' : null,
                    onConfirm: (t) =>
                        player.setAudioTrack(t ?? AudioTrack.auto()),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Player local: repetir, aleatório e avanço automático ---------------

  bool _localRepeat = false;
  bool _localShuffle = false;
  StreamSubscription<bool>? _localCompletedSub;
  final _random = Random();

  void _toggleLocalRepeat() {
    HapticService.selectionClick();
    setState(() {
      _localRepeat = !_localRepeat;
      if (_localRepeat) _localShuffle = false;
    });
    // Repetição nativa do player: recomeça sem intervalo, sem recarregar.
    unawaited(
      _localPlayer?.setPlaylistMode(
        _localRepeat ? PlaylistMode.single : PlaylistMode.none,
      ),
    );
  }

  void _toggleLocalShuffle() {
    HapticService.selectionClick();
    setState(() {
      _localShuffle = !_localShuffle;
      if (_localShuffle) _localRepeat = false;
    });
    unawaited(_localPlayer?.setPlaylistMode(PlaylistMode.none));
  }

  /// Fim de um vídeo/áudio no player local: segue a mesma regra da TV.
  /// Repetir → o player já recomeça sozinho. Aleatório (3+ itens) → sorteia
  /// outro sem repetir o atual. Senão → próximo da fila/carrossel; no último,
  /// para.
  void _onLocalCompleted() {
    if (!mounted || _localRepeat) return;
    final current = _currentViewerEntry();
    if (current == null || current.isImage) return;
    final contextItems = _carouselContextItems();
    final playable = contextItems
        .where((e) => !e.folder && (e.isVideo || e.isAudio))
        .toList();
    final idx = playable.indexWhere((e) => _same(e, current));
    LibraryEntry? next;
    if (_localShuffle && playable.length >= 2) {
      final others = [
        for (final e in playable)
          if (!_same(e, current)) e,
      ];
      next = others[_random.nextInt(others.length)];
    } else if (idx >= 0 && idx + 1 < playable.length) {
      next = playable[idx + 1];
    }
    if (next != null) unawaited(_focusEntry(next, contextItems));
  }

  /// Painel integrado de visualização de fotos e vídeos no app com carrossel adaptativo (Retrato e Paisagem).
  Widget _buildPhotoViewerCard(
    RemoteController tv,
    MediaCastController? cast,
    bool isStreamingToTarget, {
    List<Widget>? wideTop,
    Widget? wideBody,
  }) {
    if (activePhotos.isEmpty && activeMediaItem == null) {
      return const SizedBox.shrink();
    }
    final wide = wideBody != null;
    final safeIdx = activePhotos.isNotEmpty
        ? activePhotoIndex.clamp(0, activePhotos.length - 1)
        : 0;
    final carouselItems = _carouselContextItems();
    // O card só acompanha a TV quando ela muda de arquivo por conta própria
    // (avanço da playlist). A escolha do usuário nunca é sobreposta.
    if (cast != null && isStreamingToTarget) {
      final castFile = cast.currentFileName;
      if (castFile != null && castFile != _lastCastFile) {
        _lastCastFile = castFile;
        final matched = carouselItems
            .where((e) => e.name == castFile && !e.isImage)
            .firstOrNull;
        if (matched != null && !(activeMediaItem?.isImage ?? false)) {
          activeMediaItem = matched;
        }
      }
    }
    final LibraryEntry current = activeMediaItem ?? activePhotos[safeIdx];
    final highlight = AppColors.iconHighlightOf(context);
    final curCarouselIdx = carouselItems.indexWhere((e) => _same(e, current));
    final canPrev = curCarouselIdx > 0 && !loadingPhotoPreview;
    final canNext =
        curCarouselIdx >= 0 &&
        curCarouselIdx + 1 < carouselItems.length &&
        !loadingPhotoPreview;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && canPrev) {
            navigateActivePhoto(-1);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && canNext) {
            navigateActivePhoto(1);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyF && current.isImage) {
            _openImageFullScreen(current);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.space &&
              !current.isImage &&
              _isPlayingHere(current)) {
            unawaited(_localPlayer?.playOrPause());
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = MediaQuery.sizeOf(context).height;
          final isLandscape =
              MediaQuery.of(context).orientation == Orientation.landscape ||
              (constraints.maxWidth >= 600 &&
                  constraints.maxWidth > (screenHeight * 0.7));
          // Área de visualização em 16:9, limitada pela altura da tela para
          // nunca empurrar o carrossel para fora em telas baixas.
          final previewColumnWidth = isLandscape
              ? (constraints.maxWidth - 32 - 24 - 14) * 6 / 11
              : constraints.maxWidth - 32 - 24;
          final previewHeight = (previewColumnWidth * 9 / 16).clamp(
            170.0,
            (screenHeight * (isLandscape ? 0.62 : 0.42)).clamp(170.0, 520.0),
          );

          if (wide) {
            // Tela deitada / janela larga: o visualizador é um card próprio
            // que ocupa toda a altura. Todo o resto (cabeçalho do app, dados
            // da mídia, carrossel, abas e lista) fica condensado à direita.
            final viewerCard = Container(
              key: const ValueKey('wide-viewer-card'),
              margin: const EdgeInsets.fromLTRB(16, 4, 6, 12),
              padding: const EdgeInsets.all(8),
              decoration: AppColors.glassCardDecoration(
                context,
                borderRadius: 16,
              ),
              child: LayoutBuilder(
                builder: (context, box) => _buildPreviewBox(
                  current,
                  canPrev,
                  canNext,
                  height: box.maxHeight,
                ),
              ),
            );
            final isTv = getPlaybackTarget(tv) == PlaybackTarget.tv;
            final top = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...?wideTop?.take(1),
                if (isMultiSelecting) _buildMultiSelectionBar(highlight),
                _buildViewerHeader(
                  tv,
                  current,
                  safeIdx,
                  curCarouselIdx,
                  carouselItems,
                  highlight,
                  isLandscape: true,
                ),
                if (!current.isImage) ...[
                  const SizedBox(height: 6),
                  _buildTransportRow(
                    tv,
                    cast,
                    isStreamingToTarget,
                    current,
                    highlight,
                  ),
                  _buildLocalTrackButtons(current),
                  if (isTv && cast != null && isStreamingToTarget)
                    MediaSessionControls(
                      controller: cast,
                      enabled: true,
                      showTimeline: true,
                      showTransportControls: false,
                      showPlaybackModes: false,
                    ),
                ],
                const SizedBox(height: 6),
                _buildThumbnailsCarousel(
                  carouselItems,
                  current,
                  highlight,
                  tv,
                  showNames: false,
                ),
                ...?wideTop?.skip(1),
              ],
            );
            final sideCard = Container(
              key: const ValueKey('wide-side-card'),
              margin: const EdgeInsets.fromLTRB(6, 4, 16, 12),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              clipBehavior: Clip.antiAlias,
              decoration: AppColors.glassCardDecoration(
                context,
                borderRadius: 16,
              ),
              child: LayoutBuilder(
                builder: (context, box) {
                  // Coluna alta: tudo fixo e só a lista rola. Coluna baixa
                  // (celular deitado): o topo recolhe junto com a rolagem da
                  // lista, que passa a usar a altura inteira e nunca fica
                  // cortada.
                  if (box.maxHeight >= 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        top,
                        Expanded(child: wideBody),
                      ],
                    );
                  }
                  return NestedScrollView(
                    headerSliverBuilder: (context, _) => [
                      SliverToBoxAdapter(child: top),
                    ],
                    body: wideBody,
                  );
                },
              ),
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 6, child: viewerCard),
                Expanded(flex: 5, child: sideCard),
              ],
            );
          }

          if (isLandscape) {
            final controls = _buildLandscapeMediaControlsPanel(
              tv,
              cast,
              isStreamingToTarget,
              current,
              highlight,
            );
            final row = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Coluna 1 (Esquerda): visualizador + carrossel
                Expanded(
                  flex: 6,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildViewerHeader(
                        tv,
                        current,
                        safeIdx,
                        curCarouselIdx,
                        carouselItems,
                        highlight,
                        isLandscape: true,
                      ),
                      const SizedBox(height: 8),
                      _buildPreviewBox(
                        current,
                        canPrev,
                        canNext,
                        height: previewHeight,
                      ),
                      const SizedBox(height: 8),
                      _buildThumbnailsCarousel(
                        carouselItems,
                        current,
                        highlight,
                        tv,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Coluna 2 (Direita): player
                Expanded(flex: 5, child: controls),
              ],
            );
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: AppColors.glassCardDecoration(
                context,
                borderRadius: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMultiSelecting) _buildMultiSelectionBar(highlight),
                  row,
                ],
              ),
            );
          }

          // Orientação Vertical / Retrato (Portrait)
          return Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: AppColors.glassCardDecoration(
              context,
              borderRadius: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMultiSelecting) _buildMultiSelectionBar(highlight),
                _buildViewerHeader(
                  tv,
                  current,
                  safeIdx,
                  curCarouselIdx,
                  carouselItems,
                  highlight,
                  isLandscape: false,
                ),
                const SizedBox(height: 8),
                _buildPreviewBox(
                  current,
                  canPrev,
                  canNext,
                  height: previewHeight,
                ),
                if (!current.isImage) ...[
                  const SizedBox(height: 8),
                  _buildPortraitVideoControls(
                    tv,
                    cast,
                    isStreamingToTarget,
                    current,
                    highlight,
                  ),
                ],
                const SizedBox(height: 8),
                _buildThumbnailsCarousel(carouselItems, current, highlight, tv),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tv = context.watch<RemoteController>();
    MediaCastController? cast;
    try {
      cast = context.watch<MediaCastController?>();
    } catch (_) {
      cast = null;
    }
    final isStreamingToTarget =
        cast != null &&
        cast.isStreaming &&
        cast.isTarget(tv.ipAddress, tv.currentBrand);

    final viewerActive = activePhotos.isNotEmpty || activeMediaItem != null;
    final screen = MediaQuery.sizeOf(context);
    final wideViewer =
        viewerActive &&
        (MediaQuery.orientationOf(context) == Orientation.landscape ||
            (screen.width >= 600 && screen.width > screen.height * 0.7));
    if (wideViewer != _reportedWideViewer) {
      _reportedWideViewer = wideViewer;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onWideViewerChanged?.call(wideViewer);
      });
    }

    // Cabeçalho da Biblioteca com indicação clara do aparelho de destino e botão de limpeza rápida
    final Widget libraryHeader = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevatedOf(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.video_library_rounded,
              color: AppColors.iconHighlightOf(context),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Biblioteca de mídia · ${tv.connectedTvName ?? tv.currentBrand.displayName}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tv.isConnected
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tv.isConnected
                            ? 'Destino ativo: ${tv.connectedTvName ?? tv.ipAddress}'
                            : 'Nenhum aparelho conectado',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondaryOf(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (casting || isStreamingToTarget || queue.isNotEmpty)
            IconButton(
              tooltip: 'Limpar fila',
              onPressed: () => abortAndClearQueue(clearQueueItems: true),
              icon: const Icon(
                Icons.cleaning_services_rounded,
                size: 16,
                color: AppColors.powerRed,
              ),
            ),
        ],
      ),
    );
    final Widget? connectBanner = tv.isConnected
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Conecte um aparelho para reproduzir.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
    final Widget? castingRow = !casting
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Expanded(
                  child: ExcludeSemantics(
                    child: LinearProgressIndicator(
                      semanticsLabel: 'Preparando episódio',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => abortAndClearQueue(clearQueueItems: false),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancelar'),
                ),
              ],
            ),
          );
    final Widget tabContent = loadFailed
        ? const Center(child: Text('A biblioteca salva não pôde ser lida.'))
        : !ready
        ? const Center(child: CircularProgressIndicator())
        : tab == 0
        ? playlistView()
        : tab == 1
        ? queueView(cast, isStreamingToTarget)
        : filesView();

    final Widget content;
    if (wideViewer) {
      // Widescreen: o visualizador é um card próprio de altura inteira à
      // esquerda; à direita, numa coluna condensada, o cabeçalho do app, os
      // dados da mídia, o carrossel e as abas (Arquivos, Playlists, Fila).
      final showClearQueue = casting || isStreamingToTarget || queue.isNotEmpty;
      content = SafeArea(
        child: _buildPhotoViewerCard(
          tv,
          cast,
          isStreamingToTarget,
          wideTop: [
            // O primeiro item vai acima dos dados da mídia; os demais, abaixo
            // do carrossel.
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?widget.wideHeader,
                ?connectBanner,
                const SizedBox(height: 4),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _buildSectionSelector(
                    context,
                    tv,
                    horizontalPadding: 0,
                  ),
                ),
                if (showClearQueue)
                  IconButton(
                    tooltip: 'Limpar fila',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => abortAndClearQueue(clearQueueItems: true),
                    icon: const Icon(
                      Icons.cleaning_services_rounded,
                      size: 16,
                      color: AppColors.powerRed,
                    ),
                  ),
              ],
            ),
            ?castingRow,
          ],
          wideBody: tabContent,
        ),
      );
    } else {
      content = SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverList.list(
              children: [
                // Tela baixa (celular deitado): o título da biblioteca sai
                // para sobrar altura para as pastas.
                if (screen.height >= 520 || viewerActive) libraryHeader,
                ?connectBanner,
                // Seletor de 3 seções no padrão Liquid Glass idêntico ao seletor de dispositivos
                _buildSectionSelector(context, tv),
                // Visualizador de fotos e vídeos integrado com carrossel
                if (viewerActive)
                  _buildPhotoViewerCard(tv, cast, isStreamingToTarget),
                // Pastilha / Banner de controle da sessão remota ativa (quando reproduzindo áudio ou sem carrossel aberto)
                if (isStreamingToTarget && !viewerActive)
                  _buildActivePlaybackCard(cast, tv),
                ?castingRow,
              ],
            ),
            // Keep a usable library viewport below the naturally sized cards.
            // Short screens and large text scroll the cards instead of squeezing
            // a fixed-height photo preview into the outer Column.
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final remaining =
                    constraints.viewportMainAxisExtent -
                    constraints.precedingScrollExtent;
                // Havendo um mínimo usável, a lista ocupa exatamente o que
                // sobra da tela e rola sozinha. Forçar 240 px aqui empurrava a
                // parte de baixo da lista para fora da área visível: em
                // paisagem só a primeira linha de pastas aparecia e as demais
                // ficavam inalcançáveis.
                return SliverToBoxAdapter(
                  child: SizedBox(
                    height: remaining >= 150 ? remaining : 240,
                    child: tabContent,
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    // Desktop / tela larga na aba Arquivos: árvore de fontes e pastas à
    // esquerda, mostrando onde você está.
    final withTree = LayoutBuilder(
      builder: (context, box) {
        if (tab != 2 || box.maxWidth < 980 || !ready) return content;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFolderTree(),
            Expanded(child: content),
          ],
        );
      },
    );

    return widget.embedded
        ? withTree
        : Scaffold(
            appBar: AppBar(title: const Text('Biblioteca de mídia')),
            body: withTree,
          );
  }

  /// Pastilha integrada com controles da sessão de mídia ativa na TV (Play, Pause, Stop, -10s, +10s)
  Widget _buildActivePlaybackCard(
    MediaCastController cast,
    RemoteController tv,
  ) {
    final highlight = AppColors.iconHighlightOf(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppColors.glassCardDecoration(context, borderRadius: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.cast_connected_rounded, color: highlight, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cast.currentFileName ?? 'Transmitindo mídia',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: highlight.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  cast.isPlaying
                      ? 'Reproduzindo'
                      : cast.isPaused
                      ? 'Pausado'
                      : cast.status == MediaCastStatus.stopped
                      ? 'Parado'
                      : 'Carregando...',
                  style: TextStyle(
                    fontSize: 10,
                    color: highlight,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MediaSessionControls(
            controller: cast,
            enabled: true,
            showTimeline: true,
          ),
        ],
      ),
    );
  }

  /// Visão da Lista de Execução ("Fila") com agrupamento retrátil, reordenação e limpeza total
  Widget queueView(MediaCastController? cast, bool isStreamingToTarget) {
    final tv = context.read<RemoteController>();

    if (queue.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.queue_music_outlined,
                size: 54,
                color: AppColors.textMutedOf(context),
              ),
              const SizedBox(height: 14),
              Text(
                'Fila de execução temporária vazia',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Escolha arquivos na aba "Arquivos" ou toque em uma Playlist para ver e ordenar a sequência de reprodução.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => setState(() => tab = 2),
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Navegar em Arquivos'),
              ),
            ],
          ),
        ),
      );
    }

    final headerLabel = (queueTitle != null && queueTitle!.trim().isNotEmpty)
        ? queueTitle!
        : 'Fila de Execução';

    return Column(
      children: [
        // Cabeçalho retrátil (Accordion) da Playlist / Fila ativa
        Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          decoration: AppColors.glassCardDecoration(context, borderRadius: 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => queueExpanded = !queueExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    queueExpanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColors.iconHighlightOf(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerLabel,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimaryOf(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${queue.length} ${queue.length == 1 ? 'arquivo' : 'arquivos'} em sequência · Arraste para ordenar na hora',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondaryOf(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _buildViewModeToggleButton(),
                  IconButton(
                    tooltip: 'Tocar fila completa',
                    icon: const Icon(Icons.play_circle_fill_rounded, size: 26),
                    color: AppColors.iconHighlightOf(context),
                    onPressed: !tv.isConnected
                        ? null
                        : () => play(
                            queue,
                            start: 0,
                            sourceTitle: queueTitle,
                            syncToQueue: false,
                          ),
                  ),
                  IconButton(
                    tooltip: 'Salvar como playlist',
                    icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                    onPressed: saveQueueAsPlaylist,
                  ),
                  IconButton(
                    tooltip: 'Limpar tudo e parar',
                    icon: const Icon(
                      Icons.delete_sweep_outlined,
                      size: 20,
                      color: AppColors.powerRed,
                    ),
                    onPressed: () => abortAndClearQueue(clearQueueItems: true),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!queueExpanded)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Lista recolhida (${queue.length} arquivos). Toque no cabeçalho acima para expandir e ordenar.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondaryOf(context),
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: queue.length,
              onReorderItem: (a, b) {
                setState(() {
                  final moved = queue.removeAt(a);
                  queue.insert(b, moved);
                  if (queueTitle != null) {
                    final matchingList = lists
                        .where((l) => l.name == queueTitle)
                        .firstOrNull;
                    if (matchingList != null &&
                        matchingList.items.length == queue.length) {
                      matchingList.items
                        ..clear()
                        ..addAll(queue.map(_cloneEntry));
                    }
                  }
                });
                save();
                _syncLiveCastQueue();
              },
              itemBuilder: (ctx, i) {
                final item = queue[i];
                final currentOpenPhoto =
                    activePhotos.isNotEmpty &&
                        activePhotoIndex >= 0 &&
                        activePhotoIndex < activePhotos.length
                    ? activePhotos[activePhotoIndex]
                    : null;
                final isCurrentItem =
                    (isStreamingToTarget &&
                        cast?.currentFileName == item.name) ||
                    (currentOpenPhoto != null &&
                        currentOpenPhoto.id == item.id &&
                        currentOpenPhoto.source == item.source);
                final hasFailed = failedEntryIds.contains(item.id);
                return ListTile(
                  key: ObjectKey(item),
                  dense: !showThumbnails,
                  visualDensity: showThumbnails ? null : VisualDensity.compact,
                  selected: isCurrentItem,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                      if (showThumbnails) _buildEntryThumbnail(item, size: 36),
                    ],
                  ),
                  title: Text(
                    item.name,
                    style: TextStyle(
                      fontWeight: isCurrentItem
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: hasFailed ? AppColors.powerRed : null,
                    ),
                  ),
                  subtitle: showThumbnails
                      ? Text(
                          '${i + 1}º na sequência · ${item.source == LibrarySource.drive
                              ? 'Google Drive (Streaming)'
                              : item.source == LibrarySource.oneDrive
                              ? 'OneDrive (Streaming)'
                              : 'Arquivo local'}${isCurrentItem ? ' · Tocando agora' : ''}${hasFailed ? ' · Arquivo indisponível' : ''}',
                          style: const TextStyle(fontSize: 11),
                        )
                      : null,
                  onTap: () => play(
                    queue,
                    start: i,
                    sourceTitle: queueTitle,
                    syncToQueue: false,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Tocar este item',
                        icon: Icon(
                          isCurrentItem
                              ? Icons.equalizer_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        onPressed: !tv.isConnected
                            ? null
                            : () => play(
                                queue,
                                start: i,
                                sourceTitle: queueTitle,
                                syncToQueue: false,
                              ),
                      ),
                      IconButton(
                        tooltip: 'Remover da fila',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          setState(() => queue.removeAt(i));
                          save();
                          _syncLiveCastQueue();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Visão de Playlists Salvas (com suporte a Favoritar, Renomear, Excluir e Enviar para Fila)
  Widget playlistView() {
    final list = opened;
    if (list == null) {
      final ordered = List.of(lists)
        ..sort(
          (a, b) => a.favorite == b.favorite
              ? a.name.compareTo(b.name)
              : a.favorite
              ? -1
              : 1,
        );
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Playlists Salvas (${lists.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final name = await nameDialog();
                    if (name != null && mounted) {
                      final nova = _Collection(name, []);
                      setState(() {
                        lists.add(nova);
                        opened = nova;
                      });
                      save();
                    }
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nova playlist'),
                ),
              ],
            ),
          ),
          if (ordered.isEmpty)
            ListTile(
              title: const Text('Sua primeira playlist'),
              subtitle: const Text(
                'Escolha episódios em Arquivos e salve na ordem que quiser.',
              ),
              trailing: const Icon(Icons.folder_open),
              onTap: () => setState(() => tab = 2),
            ),
          for (final l in ordered)
            ListTile(
              leading: Icon(
                l.favorite ? Icons.star_rounded : Icons.playlist_play_rounded,
                color: l.favorite ? Colors.amber : null,
              ),
              title: Text(l.name),
              subtitle: Text('${l.items.length} itens'),
              onTap: () => setState(() => opened = l),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (l.items.isNotEmpty)
                    IconButton(
                      tooltip: 'Tocar playlist na Fila',
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      onPressed: () =>
                          play(l.items, start: 0, sourceTitle: l.name),
                    ),
                  IconButton(
                    tooltip: 'Favoritar playlist',
                    icon: Icon(l.favorite ? Icons.star : Icons.star_border),
                    color: l.favorite ? Colors.amber : null,
                    onPressed: () {
                      setState(() => l.favorite = !l.favorite);
                      save();
                    },
                  ),
                  IconButton(
                    tooltip: 'Renomear playlist',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => renamePlaylist(l),
                  ),
                  IconButton(
                    tooltip: 'Excluir playlist',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    onPressed: () => deletePlaylist(l),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return Column(
      children: [
        ListTile(
          leading: BackButton(onPressed: () => setState(() => opened = null)),
          title: Text(list.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${list.items.length} itens · Arraste para ordenar'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Renomear playlist',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => renamePlaylist(list),
              ),
              IconButton(
                tooltip: 'Excluir playlist',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => deletePlaylist(list),
              ),
              IconButton(
                tooltip: 'Carregar na Fila de execução',
                icon: const Icon(Icons.queue_music_rounded),
                onPressed: list.items.isEmpty
                    ? null
                    : () {
                        setState(() {
                          queue
                            ..clear()
                            ..addAll(list.items.map(_cloneEntry));
                          queueTitle = list.name;
                          queueExpanded = true;
                          tab = 1;
                        });
                        save();
                        _syncLiveCastQueue();
                        message(
                          'Playlist "${list.name}" carregada na Fila (${list.items.length} itens).',
                        );
                      },
              ),
              IconButton(
                tooltip: 'Reproduzir playlist',
                onPressed: list.items.isEmpty
                    ? null
                    : () => play(list.items, start: 0, sourceTitle: list.name),
                icon: const Icon(Icons.play_circle),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: list.items.length,
            onReorderItem: (a, b) {
              setState(() {
                final moved = list.items.removeAt(a);
                list.items.insert(b, moved);
                if (queueTitle == list.name) {
                  queue
                    ..clear()
                    ..addAll(list.items.map(_cloneEntry));
                }
              });
              save();
              _syncLiveCastQueue();
            },
            itemBuilder: (ctx, i) => ListTile(
              key: ObjectKey(list.items[i]),
              leading: ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle),
                ),
              ),
              title: Text(list.items[i].name),
              onTap: () => play(list.items, start: i, sourceTitle: list.name),
              trailing: IconButton(
                tooltip: 'Remover episódio',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () {
                  setState(() {
                    list.items.removeAt(i);
                    if (queueTitle == list.name) {
                      queue
                        ..clear()
                        ..addAll(list.items.map(_cloneEntry));
                    }
                  });
                  save();
                  _syncLiveCastQueue();
                },
              ),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() => tab = 2),
          icon: const Icon(Icons.add),
          label: const Text('Escolher mais episódios'),
        ),
      ],
    );
  }

  /// Visão de Navegação em Pastas e Arquivos (Locais e Nuvem) com Miniaturas de Fotos e Login Persistente
  // ---------------------------------------------------------------------
  // Navegação de arquivos (padrão Payno, mockup aprovado em
  // docs/design/mockups/sixf-midia-mockup.html): caminho em etapas
  // clicáveis no topo, fontes como cards, subpastas em cards e arquivos em
  // grade de miniaturas (ou lista), seleção com círculos e barra de ações.
  // ---------------------------------------------------------------------

  static const _driveRoot = LibraryEntry(
    LibrarySource.drive,
    'root',
    'Google Drive',
    folder: true,
  );
  static const _oneDriveRoot = LibraryEntry(
    LibrarySource.oneDrive,
    'root',
    'OneDrive',
    folder: true,
  );

  bool _isSelected(LibraryEntry e) => selected.any((s) => _same(s, e));

  /// Arquivos selecionáveis da pasta aberta, na ordem exibida: respeita a
  /// busca e o filtro de tipo e deixa as subpastas de fora.
  List<LibraryEntry> _selectableFiles() {
    final all = _visibleFolderEntries();
    final visible = _typeFilter == 'all'
        ? all
        : all.where((e) => _typeOf(e) == _typeFilter);
    return visible.where((e) => !e.folder).toList();
  }

  /// Último arquivo marcado: ponto de partida do Shift + clique.
  LibraryEntry? _selectAnchor;

  void _toggleSelected(LibraryEntry e) {
    HapticService.selectionClick();
    // Shift + clique (teclado físico, no Windows): marca todos os arquivos
    // entre o último marcado e este, como no Explorador de Arquivos.
    final anchor = _selectAnchor;
    if (HardwareKeyboard.instance.isShiftPressed && anchor != null) {
      final files = _selectableFiles();
      final from = files.indexWhere((f) => _same(f, anchor));
      final to = files.indexWhere((f) => _same(f, e));
      if (from >= 0 && to >= 0) {
        final lo = from < to ? from : to;
        final hi = from < to ? to : from;
        setState(() {
          for (final f in files.sublist(lo, hi + 1)) {
            if (!_isSelected(f)) selected.add(f);
          }
          _selectAnchor = e;
        });
        return;
      }
    }
    setState(() {
      final i = selected.indexWhere((s) => _same(s, e));
      if (i < 0) {
        selected.add(e);
        _selectAnchor = e;
      } else {
        selected.removeAt(i);
        if (selected.isEmpty) _selectAnchor = null;
      }
    });
  }

  /// Marca todos os arquivos visíveis da pasta; se já estiverem todos
  /// marcados, desmarca-os.
  void _toggleSelectAll() {
    HapticService.selectionClick();
    final files = _selectableFiles();
    if (files.isEmpty) return;
    final allSelected = files.every(_isSelected);
    setState(() {
      if (allSelected) {
        selected.removeWhere((s) => files.any((f) => _same(f, s)));
        if (selected.isEmpty) _selectAnchor = null;
      } else {
        for (final f in files) {
          if (!_isSelected(f)) selected.add(f);
        }
        _selectAnchor = files.last;
      }
    });
  }

  /// Volta direto para a etapa [index] do caminho.
  void _openTrailAt(int index) {
    if (index < 0) {
      trail.clear();
    } else if (index < trail.length - 1) {
      trail.removeRange(index + 1, trail.length);
    } else {
      return;
    }
    _typeFilter = 'all';
    browse();
  }

  void _openPath(List<LibraryEntry> path) {
    trail
      ..clear()
      ..addAll(path.map(_cloneEntry));
    _typeFilter = 'all';
    browse();
  }

  /// Guarda a pasta aberta nas "Abertas recentemente" (máximo de 4).
  void _rememberRecent() {
    if (trail.isEmpty) return;
    final path = [for (final e in trail) _cloneEntry(e)];
    recent.removeWhere((r) => r.isNotEmpty && _same(r.last, path.last));
    recent.insert(0, path);
    if (recent.length > 4) recent.removeRange(4, recent.length);
  }

  bool _isCloudLogged(LibrarySource s) =>
      (s == LibrarySource.drive && driveLogged) ||
      (s == LibrarySource.oneDrive && oneDriveLogged);

  String _ext(LibraryEntry e) {
    final ext = p.extension(e.name).toUpperCase();
    return ext.startsWith('.') ? ext.substring(1) : ext;
  }

  String _typeOf(LibraryEntry e) => e.folder
      ? 'folder'
      : e.isVideo
      ? 'video'
      : e.isImage
      ? 'image'
      : e.isAudio
      ? 'audio'
      : 'other';

  Widget _sourceLogo(LibrarySource source, {double size = 22}) {
    switch (source) {
      case LibrarySource.drive:
        return SizedBox(
          width: size,
          height: size,
          child: const CustomPaint(painter: _DriveLogoPainter()),
        );
      case LibrarySource.oneDrive:
        return Icon(
          Icons.cloud_rounded,
          size: size,
          color: const Color(0xFF0F78D4),
        );
      case LibrarySource.local:
      case LibrarySource.androidTree:
        return Icon(
          Icons.smartphone_rounded,
          size: size,
          color: AppColors.iconHighlightOf(context),
        );
    }
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.textMutedOf(context),
      ),
    ),
  );

  /// Card de linha (fonte, pasta salva, pasta recente).
  Widget _rowCard({
    required Widget leading,
    required String title,
    String? subtitle,
    Widget? subtitleLead,
    Widget? trailing,
    VoidCallback? onTap,
    bool dashed = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: dashed ? Colors.transparent : AppColors.circleOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: dashed
                ? AppColors.textMutedOf(context).withValues(alpha: 0.5)
                : AppColors.borderSubtleOf(context),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceInteractiveOf(context),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: leading,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            ?subtitleLead,
                            Flexible(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMutedOf(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chevron() =>
      Icon(Icons.chevron_right_rounded, color: AppColors.textMutedOf(context));

  Widget _statusDot(Color color) => Container(
    width: 6,
    height: 6,
    margin: const EdgeInsets.only(right: 5),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  /// Raiz: fontes em cards, pastas deste aparelho e abertas recentemente.
  Widget _buildSourcesRoot() {
    Widget cloud(LibraryEntry root) {
      final logged = _isCloudLogged(root.source);
      return _rowCard(
        leading: _sourceLogo(root.source, size: 24),
        title: root.name,
        subtitle: logged
            ? 'Sessão salva · Login automático ativado'
            : 'Toque para entrar na conta',
        subtitleLead: logged ? _statusDot(AppColors.okOf(context)) : null,
        onTap: () => enter(root),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logged)
              IconButton(
                tooltip: 'Sair da conta ${root.name}',
                icon: Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: AppColors.textMutedOf(context),
                ),
                onPressed: () async {
                  await sources.signOut(root.source);
                  await _refreshCloudAuthState();
                  message('Sessão de ${root.name} desconectada.');
                },
              ),
            _chevron(),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _sectionLabel('Fontes'),
        cloud(_driveRoot),
        cloud(_oneDriveRoot),
        _sectionLabel('Neste aparelho'),
        for (final root in roots)
          _rowCard(
            leading: Icon(
              Icons.folder_rounded,
              color: AppColors.iconHighlightOf(context),
            ),
            title: root.name,
            subtitle: 'Pasta salva',
            onTap: () => enter(root),
            trailing: _chevron(),
          ),
        _rowCard(
          dashed: true,
          leading: Icon(
            Icons.create_new_folder_outlined,
            color: AppColors.iconHighlightOf(context),
          ),
          title: 'Adicionar pasta deste aparelho',
          onTap: addRoot,
        ),
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: _sectionLabel('Abertas recentemente')),
              TextButton.icon(
                key: const ValueKey('library-clear-recent'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondaryOf(context),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: () {
                  setState(recent.clear);
                  unawaited(save());
                  message('Lista de abertas recentemente limpa.');
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Limpar'),
              ),
            ],
          ),
          for (final path in recent)
            _rowCard(
              leading: Icon(
                Icons.history_rounded,
                color: AppColors.iconHighlightOf(context),
              ),
              title: path.last.name,
              subtitle: path.map((e) => e.name).join(' › '),
              onTap: () => _openPath(path),
              trailing: _chevron(),
            ),
        ],
        if (roots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.powerRed),
              onPressed: () {
                setState(() => roots.clear());
                save();
                message('Histórico de pastas deste aparelho limpo.');
              },
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              label: const Text('Limpar histórico de pastas salvas'),
            ),
          ),
        if (selected.isNotEmpty) selectionBar(),
      ],
    );
  }

  /// Caminho em etapas clicáveis: "Google Drive › Mídia › Séries".
  Widget _buildCrumbs() {
    // Alinhado à esquerda; se o caminho for longo, rola mostrando o fim
    // (a pasta atual).
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: box.maxWidth),
          child: Row(
            children: [
              for (var i = 0; i < trail.length; i++) ...[
                if (i > 0)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.textMutedOf(context),
                  ),
                Builder(
                  builder: (context) {
                    final current = i == trail.length - 1;
                    return Material(
                      color: current
                          ? AppColors.accentSoftOf(context)
                          : AppColors.surfaceInteractiveOf(context),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: current
                              ? Colors.transparent
                              : AppColors.borderSubtleOf(context),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: current ? null : () => _openTrailAt(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (i == 0) ...[
                                _sourceLogo(trail[0].source, size: 14),
                                const SizedBox(width: 5),
                              ],
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 160,
                                ),
                                child: Text(
                                  trail[i].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: current
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: current
                                        ? AppColors.iconHighlightOf(context)
                                        : AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool active = false,
    double size = 36,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? AppColors.accentFillOf(context)
            : AppColors.circleOf(context),
        shape: CircleBorder(
          side: BorderSide(
            color: active
                ? Colors.transparent
                : AppColors.borderSubtleOf(context),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticService.selectionClick();
            onPressed();
          },
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: size * 0.48,
              color: active ? Colors.white : AppColors.textPrimaryOf(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeChip(String id, String label, IconData? icon, int? count) {
    final on = _typeFilter == id;
    final fg = on ? Colors.white : AppColors.textSecondaryOf(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: on
            ? AppColors.accentFillOf(context)
            : AppColors.surfaceInteractiveOf(context),
        shape: StadiumBorder(
          side: BorderSide(
            color: on ? Colors.transparent : AppColors.borderSubtleOf(context),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _typeFilter = id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: fg),
                  const SizedBox(width: 5),
                ],
                Text(
                  count == null ? label : '$label $count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget filesView() {
    if (trail.isEmpty) return _buildSourcesRoot();

    final counts = <String, int>{};
    for (final e in entries) {
      counts.update(_typeOf(e), (v) => v + 1, ifAbsent: () => 1);
    }
    String plural(int n, String one, String many) =>
        '$n ${n == 1 ? one : many}';
    final summary = [
      if ((counts['folder'] ?? 0) > 0)
        plural(counts['folder']!, 'pasta', 'pastas'),
      if ((counts['video'] ?? 0) > 0)
        plural(counts['video']!, 'vídeo', 'vídeos'),
      if ((counts['image'] ?? 0) > 0) plural(counts['image']!, 'foto', 'fotos'),
      if ((counts['audio'] ?? 0) > 0)
        plural(counts['audio']!, 'áudio', 'áudios'),
    ].join(' · ');

    // Cabeçalho da pasta e conteúdo rolam juntos: em telas baixas (paisagem,
    // fonte ampliada) nada fica espremido nem estoura.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                // 1. Voltar + caminho clicável + recarregar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(
                    children: [
                      _circleButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Voltar',
                        size: 34,
                        onPressed: () => _openTrailAt(trail.length - 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _buildCrumbs()),
                      const SizedBox(width: 8),
                      _circleButton(
                        icon: Icons.refresh_rounded,
                        tooltip: 'Recarregar pasta',
                        size: 34,
                        onPressed: () {
                          LibrarySources.invalidateFolderCache(
                            "${trail.last.source.name}:${trail.last.id}",
                          );
                          browse();
                        },
                      ),
                    ],
                  ),
                ),
                // 2. Nome da pasta em destaque + contagem
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trail.last.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 24,
                          height: 1.1,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -0.5,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      if (summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMutedOf(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // 3. Busca + grade/lista + ordenação
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.circleOf(context),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.borderSubtleOf(context),
                            ),
                          ),
                          // Ícone e texto numa linha centralizada: o campo
                          // "colapsado" não herda a altura mínima de 48 px do
                          // prefixIcon, que empurrava o texto para baixo no
                          // Android.
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: AppColors.textMutedOf(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: search,
                                  textAlignVertical: TextAlignVertical.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.2,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                  decoration: InputDecoration.collapsed(
                                    hintText: 'Buscar nesta pasta',
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      height: 1.2,
                                      color: AppColors.textMutedOf(context),
                                    ),
                                  ),
                                  onChanged: (v) =>
                                      setState(() => filter = v.toLowerCase()),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _circleButton(
                        icon: showThumbnails
                            ? Icons.grid_view_rounded
                            : Icons.view_list_rounded,
                        tooltip: showThumbnails
                            ? 'Modo compacto (somente nomes)'
                            : 'Modo detalhado (miniaturas e nomes)',
                        active: true,
                        onPressed: () {
                          setState(() => showThumbnails = !showThumbnails);
                          save();
                        },
                      ),
                      const SizedBox(width: 6),
                      _circleButton(
                        icon: sortByExtension
                            ? Icons.category_rounded
                            : Icons.sort_by_alpha_rounded,
                        tooltip: sortByExtension
                            ? 'Ordenado por Tipo / Extensão'
                            : 'Ordenar por Nome (A-Z)',
                        active: sortByExtension,
                        onPressed: () =>
                            setState(() => sortByExtension = !sortByExtension),
                      ),
                    ],
                  ),
                ),
                // 4. Filtros por tipo, com a quantidade de cada um
                if (entries.isNotEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 9, 10, 4),
                      children: [
                        _typeChip('all', 'Tudo', null, null),
                        if ((counts['folder'] ?? 0) > 0)
                          _typeChip(
                            'folder',
                            'Pastas',
                            Icons.folder_outlined,
                            counts['folder'],
                          ),
                        if ((counts['video'] ?? 0) > 0)
                          _typeChip(
                            'video',
                            'Vídeos',
                            Icons.movie_outlined,
                            counts['video'],
                          ),
                        if ((counts['image'] ?? 0) > 0)
                          _typeChip(
                            'image',
                            'Fotos',
                            Icons.image_outlined,
                            counts['image'],
                          ),
                        if ((counts['audio'] ?? 0) > 0)
                          _typeChip(
                            'audio',
                            'Áudios',
                            Icons.audiotrack_outlined,
                            counts['audio'],
                          ),
                      ],
                    ),
                  ),
                // 5. Conteúdo: subpastas em cards + arquivos em grade ou lista
                ..._buildFolderContent(box.maxWidth),
              ],
            ),
          ),
        ),
        if (selected.isNotEmpty) selectionBar(),
      ],
    );
  }

  List<Widget> _buildFolderContent(double maxWidth) {
    Widget state(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Center(child: child),
    );
    if (loading) return [state(const CircularProgressIndicator())];
    if (folderError.isNotEmpty) {
      return [
        state(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                folderError,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              TextButton(
                onPressed: browse,
                child: const Text('Tentar novamente'),
              ),
              TextButton.icon(
                onPressed: () => _openTrailAt(-1),
                icon: const Icon(Icons.home_outlined, size: 16),
                label: const Text('Voltar às fontes'),
              ),
            ],
          ),
        ),
      ];
    }
    final all = _visibleFolderEntries();
    final visible = _typeFilter == 'all'
        ? all
        : all.where((e) => _typeOf(e) == _typeFilter).toList();
    if (visible.isEmpty) {
      return [
        state(
          Text(
            'Nenhuma pasta ou mídia encontrada.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMutedOf(context)),
          ),
        ),
      ];
    }
    final folders = visible.where((e) => e.folder).toList();
    final files = visible.where((e) => !e.folder).toList();
    // Contexto do carrossel/visualizador: todos os arquivos visíveis da pasta.
    final photoContext = all.where((e) => !e.folder).toList();

    const gap = 8.0;
    final width = (maxWidth - 32).clamp(120.0, double.infinity);
    final folderCols = (width / 190).floor().clamp(2, 5);
    final folderW = (width - gap * (folderCols - 1)) / folderCols;
    final tileCols = (width / 120).floor().clamp(3, 8);
    final tileW = (width - gap * (tileCols - 1)) / tileCols;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (folders.isNotEmpty)
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final f in folders)
                    SizedBox(width: folderW, child: _folderCard(f)),
                ],
              ),
            if (folders.isNotEmpty && files.isNotEmpty)
              const SizedBox(height: 12),
            if (files.isNotEmpty && showThumbnails)
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final e in files)
                    SizedBox(
                      width: tileW,
                      height: tileW,
                      child: _fileTile(e, photoContext, tileW),
                    ),
                ],
              )
            else
              for (final e in files) _fileRow(e, photoContext),
          ],
        ),
      ),
    ];
  }

  Widget _folderCard(LibraryEntry folder) {
    return Material(
      color: AppColors.circleOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.borderSubtleOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => enter(folder),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accentSoftOf(context),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.folder_rounded,
                  size: 19,
                  color: AppColors.iconHighlightOf(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Círculo de seleção (vazio ou azul com ✓).
  Widget _selectCircle(LibraryEntry e, {bool onImage = false}) {
    final on = _isSelected(e);
    return Tooltip(
      message: on ? 'Desmarcar' : 'Selecionar',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggleSelected(e),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on
                  ? AppColors.accentFillOf(context)
                  : (onImage ? const Color(0x55000000) : Colors.transparent),
              border: Border.all(
                color: on
                    ? Colors.white
                    : (onImage ? Colors.white : AppColors.textMutedOf(context)),
                width: 1.6,
              ),
            ),
            child: on
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }

  Widget _fileTile(LibraryEntry e, List<LibraryEntry> ctx, double size) {
    final on = _isSelected(e);
    return Material(
      color: AppColors.surfaceInteractiveOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: on
            ? BorderSide(color: AppColors.accentFillOf(context), width: 3)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _focusEntry(e, ctx),
        onLongPress: () => showFileActions(e, photoContext: ctx),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildEntryThumbnail(e, size: size),
            // Nome sobre degradê escuro
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(7, 14, 7, 5),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xA6000000)],
                  ),
                ),
                child: Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (!e.isImage)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x9E0A0E16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _ext(e),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 0,
              top: 0,
              child: _selectCircle(e, onImage: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileRow(LibraryEntry e, List<LibraryEntry> ctx) {
    final on = _isSelected(e);
    final details = [
      _ext(e),
      if (e.size != null) _formatBytes(e.size!),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: on
            ? AppColors.accentSoftOf(context)
            : AppColors.circleOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: on ? Colors.transparent : AppColors.borderSubtleOf(context),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _focusEntry(e, ctx),
          onLongPress: () => showFileActions(e, photoContext: ctx),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 4, 6),
            child: Row(
              children: [
                _selectCircle(e),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _buildEntryThumbnail(e, size: 42),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textMutedOf(context),
                          ),
                        ),
                    ],
                  ),
                ),
                if (e.isImage)
                  IconButton(
                    tooltip: 'Visualizar e espelhar na TV',
                    icon: Icon(
                      Icons.cast_rounded,
                      size: 20,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    onPressed: () => openPhotoAndMirror(ctx, e),
                  )
                else
                  IconButton(
                    tooltip: 'Reproduzir no aparelho ativo',
                    icon: Icon(
                      Icons.play_arrow_rounded,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    onPressed: () => play([e], start: 0, sourceTitle: e.name),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Árvore de fontes e pastas (desktop): mostra onde você está e permite
  /// pular para qualquer pasta já visitada do caminho atual.
  Widget _buildFolderTree() {
    final nodes = <Widget>[];
    void node(
      LibraryEntry entry, {
      required int depth,
      required bool current,
      required VoidCallback onTap,
      bool source = false,
      Widget? trailing,
    }) {
      final fg = current
          ? Colors.white
          : (source
                ? AppColors.textPrimaryOf(context)
                : AppColors.textSecondaryOf(context));
      nodes.add(
        Padding(
          padding: EdgeInsets.only(
            left: depth * 14.0,
            bottom: 2,
            top: source ? 6 : 0,
          ),
          child: Material(
            color: current
                ? AppColors.accentFillOf(context)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                child: Row(
                  children: [
                    if (source)
                      _sourceLogo(entry.source, size: 16)
                    else
                      Icon(
                        Icons.folder_outlined,
                        size: 16,
                        color: current
                            ? Colors.white
                            : AppColors.textMutedOf(context),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: current || source
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: fg,
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    void level(int depth) {
      final parent = trail[depth];
      final kids =
          _folderKids[_keyOf(parent)] ??
          (depth + 1 < trail.length
              ? [trail[depth + 1]]
              : const <LibraryEntry>[]);
      for (final kid in kids.take(40)) {
        final onPath = depth + 1 < trail.length && _same(kid, trail[depth + 1]);
        node(
          kid,
          depth: depth + 1,
          current: onPath && depth + 1 == trail.length - 1,
          onTap: () => _openPath([...trail.take(depth + 1), kid]),
        );
        if (onPath && depth + 1 < trail.length - 1) level(depth + 1);
        if (onPath && depth + 1 == trail.length - 1) {
          // Subpastas da pasta atual
          for (final sub
              in (_folderKids[_keyOf(kid)] ?? const <LibraryEntry>[]).take(
                40,
              )) {
            node(
              sub,
              depth: depth + 2,
              current: false,
              onTap: () => _openPath([...trail, sub]),
            );
          }
        }
      }
    }

    for (final root in [_driveRoot, _oneDriveRoot, ...roots]) {
      final open = trail.isNotEmpty && _same(trail[0], root);
      final cloud =
          root.source == LibrarySource.drive ||
          root.source == LibrarySource.oneDrive;
      node(
        root,
        depth: 0,
        source: true,
        current: open && trail.length == 1,
        onTap: () => _openPath([root]),
        trailing: cloud && !_isCloudLogged(root.source)
            ? Text(
                'Entrar',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.iconHighlightOf(context),
                ),
              )
            : null,
      );
      if (open) level(0);
    }

    return Container(
      width: 236,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: AppColors.borderSubtleOf(context)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        children: [
          _sectionLabel('Fontes e pastas'),
          ...nodes,
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: addRoot,
            icon: const Icon(Icons.create_new_folder_outlined, size: 16),
            label: const Text(
              'Adicionar pasta',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Barra de ações dos itens selecionados (azul-marinho, padrão Payno):
  /// tocar na TV, adicionar à fila temporária ou criar playlist.
  Widget selectionBar() {
    final count = selected.length;
    final tv = context.read<RemoteController>();
    Widget action(
      IconData icon,
      String label,
      String tooltip,
      VoidCallback onTap, {
      bool primary = false,
    }) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: primary ? Colors.white : const Color(0x2EFFFFFF),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              // Se a barra ficar estreita, o botão encolhe em vez de estourar.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: primary ? AppColors.lightAccentFill : Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primary
                            ? AppColors.lightAccentFill
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final files = trail.isEmpty ? const <LibraryEntry>[] : _selectableFiles();
    final allSelected = files.isNotEmpty && files.every(_isSelected);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.accentFillOf(context),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentFillOf(context).withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        spacing: 8,
        runSpacing: 6,
        children: [
          Text(
            '$count ${count == 1 ? 'selecionado' : 'selecionados'}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (files.isNotEmpty)
                action(
                  allSelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                  allSelected ? 'Desmarcar todos' : 'Selecionar todos',
                  allSelected
                      ? 'Desmarcar todos os arquivos da pasta'
                      : 'Selecionar todos os arquivos da pasta',
                  _toggleSelectAll,
                ),
              action(
                Icons.playlist_add_rounded,
                'Playlist',
                'Criar playlist',
                addSelection,
              ),
              action(
                Icons.queue_music_rounded,
                'Fila',
                'Adicionar à fila',
                () => addSelectionToQueue(playNow: false),
              ),
              action(
                Icons.cast_rounded,
                'Tocar na TV',
                'Tocar na TV',
                () => addSelectionToQueue(playNow: tv.isConnected),
                primary: true,
              ),
              IconButton(
                tooltip: 'Limpar seleção',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Colors.white,
                ),
                onPressed: () => setState(() {
                  selected.clear();
                  _selectAnchor = null;
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Logotipo do Google Drive (três faixas: verde, amarela e azul).
class _DriveLogoPainter extends CustomPainter {
  const _DriveLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 24, h = size.height / 24;
    Path path(List<double> pts) {
      final path = Path()..moveTo(pts[0] * w, pts[1] * h);
      for (var i = 2; i < pts.length; i += 2) {
        path.lineTo(pts[i] * w, pts[i + 1] * h);
      }
      return path..close();
    }

    canvas.drawPath(
      path([8.2, 3, 15.8, 3, 21.8, 13.4, 14.2, 13.4]),
      Paint()..color = const Color(0xFFF6B400),
    );
    canvas.drawPath(
      path([2.2, 13.4, 6, 20, 18, 20, 14.2, 13.4]),
      Paint()..color = const Color(0xFF2684FC),
    );
    canvas.drawPath(
      path([8.2, 3, 2.2, 13.4, 6, 20, 12, 9.6]),
      Paint()..color = const Color(0xFF00AC47),
    );
  }

  @override
  bool shouldRepaint(_DriveLogoPainter oldDelegate) => false;
}

/// Alturas das barras dos controles do vídeo para um card de [height] px, ou
/// `null` se a altura padrão (56 + 56 + 36) já cabe com folga. Sempre
/// `bar * 2 + seek + 4 <= height` enquanto `height >= 88`.
/// Quanto a linha do tempo dos controles de toque sobe em relação à borda
/// inferior do vídeo, para um card de [height] px. Em cards baixos sobe
/// menos, para as barras continuarem cabendo.
@visibleForTesting
double touchSeekBarLift(double height) =>
    height >= 200 ? 14 : (height >= 120 ? 8 : 0);

@visibleForTesting
({double bar, double seek})? compactVideoControlSizes(double height) {
  if (height >= 200) return null;
  final seek = height >= 150 ? 30.0 : 24.0;
  final bar = ((height - seek - 4) / 2).clamp(24.0, 56.0).toDouble();
  return (bar: bar, seek: seek);
}
