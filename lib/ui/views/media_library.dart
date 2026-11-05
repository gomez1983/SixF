import 'dart:ui' show PointerDeviceKind;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/media_cast_controller.dart';
import '../../controllers/remote_controller.dart';
import '../../services/drivers/tv_driver.dart';
import '../../services/haptic_service.dart';
import '../../services/library_sources.dart';
import '../../services/media_remux_service.dart';
import '../theme/app_colors.dart';
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
  const MediaLibrary({super.key, this.embedded = false});
  final bool embedded;
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
  bool ready = false, loading = false, casting = false;
  bool loadFailed = false;
  String filter = '', folderError = '';
  bool sortByExtension = false;
  bool showThumbnails = true;
  final search = TextEditingController();
  final photoScroll = ScrollController();

  // Estado do visualizador de fotos/vídeos integrado (com espelhamento simultâneo na TV)
  List<LibraryEntry> activePhotos = [];
  int activePhotoIndex = 0;
  LibraryEntry? activeMediaItem;
  File? viewedPhotoFile;
  bool loadingPhotoPreview = false;
  Directory? _photoCache;

  // Estado de destino de reprodução (Google Fotos / Cast padrão: TV vs Este Aparelho)
  PlaybackTarget? _userChosenTarget;
  bool isMultiSelecting = false;
  final Set<String> multiSelectedIds = {};

  PlaybackTarget getPlaybackTarget(RemoteController tv) {
    if (_userChosenTarget != null) return _userChosenTarget!;
    return tv.isConnected ? PlaybackTarget.tv : PlaybackTarget.local;
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
      unawaited(
        old.delete(recursive: true).catchError((_) => old),
      );
    }
  }

  @override
  void dispose() {
    _clearPhotoCache();
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
    setState(() {
      casting = false;
      loadingPhotoPreview = false;
      activePhotos = [];
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
        setState(() => entries = items);
        final mediaItems = items
            .where((e) => !e.folder && (e.isImage || e.isVideo || e.isAudio))
            .toList();
        if (mediaItems.isNotEmpty &&
            activePhotos.isEmpty &&
            activeMediaItem == null) {
          final first = mediaItems.first;
          if (first.isImage) {
            unawaited(
              openPhotoAndMirror(mediaItems, first, syncToQueue: false),
            );
          } else {
            setState(() {
              activeMediaItem = first;
              activePhotos = mediaItems.where((e) => e.isImage).toList();
              activePhotoIndex = 0;
              viewedPhotoFile = null;
              loadingPhotoPreview = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted && generation == version) {
        setState(
          () => folderError = e is TimeoutException
              ? 'Tempo limite atingido ao carregar a pasta na nuvem. Verifique sua conexão ou tente novamente.'
              : (e is FormatException
                    ? e.message
                    : 'Não foi possível abrir a pasta. Verifique o acesso e tente novamente.'),
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
      final folderMedia =
          _visibleFolderEntries().where((e) => !e.folder).toList();
      if (folderMedia.isNotEmpty) return folderMedia;
    }
    return activePhotos;
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

  Widget _buildViewModeToggleButton() {
    return IconButton.filledTonal(
      tooltip: showThumbnails
          ? 'Modo compacto (somente nomes)'
          : 'Modo detalhado (miniaturas e nomes)',
      icon: Icon(
        showThumbnails
            ? Icons.view_headline_rounded
            : Icons.grid_view_rounded,
        size: 19,
        color: showThumbnails ? Theme.of(context).colorScheme.primary : null,
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
    final stayInFolderForPhoto =
        playNow && tab == 2 && newItems.first.isImage;
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
    final exists = queue.any(
      (q) => q.id == item.id && q.source == item.source,
    );
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

    setState(() {
      if (syncToQueue) {
        _ensureEntryInQueue(tappedPhoto);
      }
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
      if (photoScroll.hasClients) {
        final targetOffset = (activePhotoIndex * 48.0) - 100.0;
        photoScroll.animateTo(
          targetOffset.clamp(0.0, photoScroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }

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

  Future<void> navigateActivePhoto(int delta) async {
    if (activeMediaItem != null && !activeMediaItem!.isImage) {
      final carouselItems = _carouselContextItems();
      final curIdx = carouselItems.indexWhere(
        (e) =>
            e.id == activeMediaItem!.id && e.source == activeMediaItem!.source,
      );
      final nextIdx = curIdx + delta;
      if (curIdx < 0 || nextIdx < 0 || nextIdx >= carouselItems.length) return;
      HapticService.selectionClick();
      final nextItem = carouselItems[nextIdx];
      if (nextItem.isImage) {
        await openPhotoAndMirror(
          carouselItems,
          nextItem,
          syncToQueue: tab != 1,
        );
      } else {
        await play(
          tab == 1 ? queue : [nextItem],
          start: tab == 1
              ? queue
                    .indexWhere(
                      (q) =>
                          q.id == nextItem.id && q.source == nextItem.source,
                    )
                    .clamp(0, queue.length - 1)
              : 0,
          sourceTitle: tab == 1 ? queueTitle : nextItem.name,
          syncToQueue: tab != 1,
        );
      }
      return;
    }
    final nextIdx = activePhotoIndex + delta;
    if (nextIdx < 0 || nextIdx >= activePhotos.length) return;
    HapticService.selectionClick();
    setState(() {
      activePhotoIndex = nextIdx;
      activeMediaItem = activePhotos[nextIdx];
    });
    await _loadAndMirrorActivePhoto();
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
    if (items[safeStart].isVideo) {
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
      // Reprodução no dispositivo local configurada no carrossel
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
  Widget _buildSectionSelector(BuildContext context, RemoteController tv) {
    final isDark = tv.isDarkMode;
    final highlightColor = isDark
        ? AppColors.iconHighlight
        : AppColors.lightIconHighlight;

    final tabs = <({int index, IconData icon, String label})>[
      (index: 0, icon: Icons.playlist_play_rounded, label: 'Playlists'),
      (
        index: 1,
        icon: Icons.queue_music_rounded,
        label: queue.isEmpty ? 'Fila' : 'Fila (${queue.length})',
      ),
      (index: 2, icon: Icons.folder_rounded, label: 'Arquivos'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Builder(
                builder: (context) {
                  final item = tabs[i];
                  final isActive = tab == item.index;
                  final textColor = isActive
                      ? (isDark
                            ? AppColors.textPrimary
                            : AppColors.lightTextPrimary)
                      : (isDark
                            ? AppColors.textSecondary
                            : AppColors.lightTextSecondary);
                  final iconColor = isActive
                      ? highlightColor
                      : (isDark
                            ? AppColors.textSecondary
                            : AppColors.lightTextSecondary);
                  final borderColor = isActive
                      ? highlightColor
                      : (isDark
                            ? AppColors.borderSubtle
                            : AppColors.lightBorderSubtle);
                  final bgColor = isActive
                      ? highlightColor.withValues(alpha: isDark ? 0.22 : 0.14)
                      : (isDark
                            ? AppColors.surfaceCard
                            : AppColors.lightSurfaceCard);

                  return InkWell(
                    onTap: () {
                      HapticService.selectionClick();
                      setState(() {
                        tab = item.index;
                        _syncActivePhotosForTab(item.index);
                      });
                    },
                    borderRadius: BorderRadius.circular(13),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: isActive ? null : bgColor,
                        gradient: isActive
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isDark
                                    ? const [
                                        Color(0x3838BDF8),
                                        Color(0x300EA5E9),
                                        Color(0x220E8FF1),
                                      ]
                                    : const [
                                        Color(0xE8FFFFFF),
                                        Color(0x40BAE6FD),
                                        Color(0x300EA5E9),
                                      ],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: borderColor,
                          width: isActive ? 1.3 : 1.0,
                        ),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: highlightColor.withValues(
                                    alpha: isDark ? 0.24 : 0.16,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
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
                                    ? FontWeight.bold
                                    : FontWeight.w600,
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

    if (entry.isImage) {
      if (entry.source == LibrarySource.local) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(entry.id),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: 160,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: highlight.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.image_outlined, color: highlight, size: 20),
            ),
          ),
        );
      }

      final token = LibrarySources.currentTokenForSource(entry.source);
      final netUrl =
          entry.thumbnailUrl ??
          (entry.source == LibrarySource.drive
              ? 'https://www.googleapis.com/drive/v3/files/${entry.id}?alt=media'
              : null);
      if (netUrl != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            netUrl,
            headers: token != null ? {'Authorization': 'Bearer $token'} : null,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: 160,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: highlight.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.image_outlined, color: highlight, size: 20),
            ),
          ),
        );
      }
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: highlight.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.image_outlined, color: highlight, size: 20),
      );
    }

    if (entry.isVideo) {
      if (entry.source == LibrarySource.local) {
        return FutureBuilder<String?>(
          future: MediaRemuxService.extractVideoThumbnail(entry.id),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(snapshot.data!),
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, _, _) =>
                          _buildVideoFallback(size, highlight),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ],
              );
            }
            return _buildVideoFallback(size, highlight);
          },
        );
      }
      final netThumb = entry.thumbnailUrl;
      if (netThumb != null) {
        final token = LibrarySources.currentTokenForSource(entry.source);
        return Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                netThumb,
                headers: token != null
                    ? {'Authorization': 'Bearer $token'}
                    : null,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: 160,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, _, _) => _buildVideoFallback(size, highlight),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ],
        );
      }
      return _buildVideoFallback(size, highlight);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: highlight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        entry.isImage
            ? Icons.image_outlined
            : entry.isAudio
            ? Icons.audiotrack_rounded
            : Icons.movie_creation_outlined,
        color: highlight,
        size: 20,
      ),
    );
  }

  Widget _buildVideoFallback(double size, Color highlight) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: highlight.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.movie_outlined, color: highlight, size: 20),
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

  Widget _buildLargeVideoThumbnail(LibraryEntry entry, {double height = 200}) {
    final highlight = AppColors.iconHighlightOf(context);
    if (entry.source == LibrarySource.local) {
      return FutureBuilder<String?>(
        future: MediaRemuxService.extractVideoThumbnail(entry.id),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.file(
              File(snapshot.data!),
              width: double.infinity,
              height: height,
              fit: BoxFit.contain,
              cacheWidth: 640,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => _buildVideoFallback(120, highlight),
            );
          }
          return _buildVideoFallback(120, highlight);
        },
      );
    }
    final netThumb = entry.thumbnailUrl;
    if (netThumb != null) {
      final token = LibrarySources.currentTokenForSource(entry.source);
      return Image.network(
        netThumb,
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        width: double.infinity,
        height: height,
        fit: BoxFit.contain,
        cacheWidth: 640,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _buildVideoFallback(120, highlight),
      );
    }
    return _buildVideoFallback(120, highlight);
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
        setState(() {
          if (isTv) {
            _userChosenTarget = PlaybackTarget.local;
            message('Destino de reprodução: Este aparelho (local).');
          } else {
            if (!tv.isConnected) {
              message('Conecte uma TV para transmitir.');
            } else {
              _userChosenTarget = PlaybackTarget.tv;
              message(
                'Destino de reprodução: ${tv.connectedTvName ?? tv.ipAddress}.',
              );
            }
          }
        });
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

  /// Abrir mídia local em tela cheia com visualizador dedicado
  Future<void> _openLocalFullScreen(LibraryEntry entry) async {
    HapticService.selectionClick();
    if (entry.source == LibrarySource.local && File(entry.id).existsSync()) {
      try {
        final uri = Uri.file(entry.id);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              entry.name,
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          body: Center(
            child: entry.isImage &&
                    viewedPhotoFile != null &&
                    viewedPhotoFile!.existsSync()
                ? InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5.0,
                    child: Image.file(viewedPhotoFile!),
                  )
                : _buildLargeVideoThumbnail(entry, height: double.infinity),
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
                entry.isImage
                    ? 'Foto'
                    : (entry.isVideo ? 'Vídeo' : 'Áudio'),
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
      if (entry.isImage) {
        await openPhotoAndMirror(_carouselContextItems(), entry);
      } else {
        setState(() => activeMediaItem = entry);
      }
    } else if (action == 'multi_select') {
      setState(() {
        isMultiSelecting = true;
        multiSelectedIds.add(entry.id);
      });
      message(
        'Modo de seleção ativado. Toque nas miniaturas para selecionar.',
      );
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
    RemoteController tv,
  ) {
    if (carouselItems.isEmpty) return const SizedBox.shrink();

    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    final carouselHeight = (54.0 + 20.0 * textScale).clamp(74.0, 96.0);

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
                ? carouselItems
                      .take(i)
                      .where((e) => e.isImage)
                      .length
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
                  if (item.isImage) {
                    final targetIdx = activePhotos.indexWhere(
                      (e) => e.id == item.id && e.source == item.source,
                    );
                    if (targetIdx >= 0 &&
                        (targetIdx != activePhotoIndex ||
                            activeMediaItem?.isImage != true)) {
                      setState(() {
                        activePhotoIndex = targetIdx;
                        activeMediaItem = activePhotos[targetIdx];
                      });
                      _loadAndMirrorActivePhoto();
                    } else if (targetIdx < 0) {
                      openPhotoAndMirror(carouselItems, item);
                    }
                  } else {
                    final pTarget = getPlaybackTarget(tv);
                    if (pTarget == PlaybackTarget.tv && tv.isConnected) {
                      play(
                        tab == 1 ? queue : [item],
                        start: tab == 1
                            ? queue
                                  .indexWhere(
                                    (q) =>
                                        q.id == item.id &&
                                        q.source == item.source,
                                  )
                                  .clamp(0, queue.length - 1)
                            : 0,
                        sourceTitle: tab == 1 ? queueTitle : item.name,
                        syncToQueue: tab != 1,
                      );
                    } else {
                      setState(() {
                        activeMediaItem = item;
                        viewedPhotoFile = null;
                      });
                    }
                  }
                },
                onLongPress: () {
                  HapticService.heavyPress();
                  _showCarouselItemActions(item);
                },
                child: SizedBox(
                  width: 62,
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
                            child: _buildEntryThumbnail(
                              item,
                              size: 42,
                            ),
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
  Widget _buildPreviewBox(
    LibraryEntry current,
    bool canPrev,
    bool canNext, {
    double height = 200,
  }) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(color: Colors.black26),
            if (!current.isImage)
              _buildLargeVideoThumbnail(current, height: height)
            else if (loadingPhotoPreview)
              const CircularProgressIndicator()
            else if (viewedPhotoFile != null &&
                viewedPhotoFile!.existsSync())
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.file(
                  viewedPhotoFile!,
                  key: ValueKey(viewedPhotoFile!.path),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: height,
                ),
              )
            else
              _buildEntryThumbnail(current, size: 120),
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
                  current.isImage
                      ? 'Foto ${safeIdx + 1} de ${activePhotos.length} · ${tab == 1 ? 'Fila' : 'Pasta'}'
                      : 'Vídeo ${curCarouselIdx >= 0 ? curCarouselIdx + 1 : 1} de ${carouselItems.isNotEmpty ? carouselItems.length : 1} · ${tab == 1 ? 'Fila' : 'Pasta'}',
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
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(4),
          tooltip: isTv ? 'Enviar à TV' : 'Exibir neste aparelho',
          icon: Icon(
            isTv ? Icons.cast_rounded : Icons.phone_android_rounded,
            size: 18,
          ),
          onPressed: loadingPhotoPreview
              ? null
              : () {
                  if (isTv) {
                    if (current.isImage) {
                      _loadAndMirrorActivePhoto();
                    } else {
                      play(
                        tab == 1 ? queue : [current],
                        start: tab == 1
                            ? queue
                                  .indexWhere(
                                    (q) =>
                                        q.id == current.id &&
                                        q.source == current.source,
                                  )
                                  .clamp(0, queue.length - 1)
                            : 0,
                        sourceTitle: tab == 1 ? queueTitle : current.name,
                        syncToQueue: tab != 1,
                      );
                    }
                  } else {
                    _openLocalFullScreen(current);
                  }
                },
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(4),
          tooltip: 'Fechar visualizador de fotos',
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: () {
            _clearPhotoCache();
            setState(() {
              activePhotos = [];
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
    final pTarget = getPlaybackTarget(tv);
    final isTv = pTarget == PlaybackTarget.tv;
    final isCurrentVideoStreaming =
        cast != null &&
        isStreamingToTarget &&
        cast.currentFileName == current.name;

    return Container(
      padding: const EdgeInsets.all(12),
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
              if (!current.isImage)
                IconButton(
                  tooltip: 'Abrir em tela cheia',
                  icon: const Icon(Icons.fullscreen_rounded, size: 20),
                  onPressed: () => _openLocalFullScreen(current),
                ),
            ],
          ),
          const SizedBox(height: 8),
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
                ? 'Foto • Visualizador SixF'
                : (current.isVideo
                      ? 'Vídeo • ${isTv ? "Transmissão para TV" : "Reprodução Local"}'
                      : 'Áudio • ${isTv ? "Transmissão para TV" : "Reprodução Local"}'),
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              if (isCurrentVideoStreaming && cast.canSeek)
                IconButton.filledTonal(
                  tooltip: 'Recuar 10 segundos',
                  icon: const Icon(Icons.replay_10_rounded),
                  onPressed: () => cast.seekTo(
                    cast.currentPosition - const Duration(seconds: 10),
                  ),
                ),
              IconButton.filled(
                tooltip: 'Reproduzir',
                isSelected: isCurrentVideoStreaming && cast.isPlaying,
                onPressed: () {
                  if (isTv && !tv.isConnected) {
                    message('Conecte um dispositivo para transmitir.');
                    return;
                  }
                  if (isTv) {
                    if (isCurrentVideoStreaming &&
                        (cast.isPaused || cast.canPlay)) {
                      cast.play();
                    } else {
                      play(
                        tab == 1 ? queue : [current],
                        sourceTitle: current.name,
                      );
                    }
                  } else {
                    _openLocalFullScreen(current);
                  }
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
              ),
              IconButton.filledTonal(
                tooltip: 'Pausar',
                isSelected: isCurrentVideoStreaming && cast.isPaused,
                onPressed: isCurrentVideoStreaming &&
                        (cast.isPlaying || cast.canPause)
                    ? cast.pause
                    : null,
                icon: const Icon(Icons.pause_rounded, size: 22),
              ),
              if (isCurrentVideoStreaming)
                IconButton.filledTonal(
                  tooltip: 'Parar transmissão',
                  onPressed: cast.stop,
                  icon: const Icon(Icons.stop_rounded, size: 22),
                ),
              if (isCurrentVideoStreaming && cast.canSeek)
                IconButton.filledTonal(
                  tooltip: 'Avançar 10 segundos',
                  icon: const Icon(Icons.forward_10_rounded),
                  onPressed: () => cast.seekTo(
                    cast.currentPosition + const Duration(seconds: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Repetir arquivo',
                isSelected: cast != null && cast.isLooping,
                onPressed: cast != null && (cast.canLoop || cast.isLooping)
                    ? cast.toggleLoop
                    : null,
                icon: Icon(
                  Icons.repeat_rounded,
                  color: (cast?.isLooping ?? false) ? highlight : null,
                ),
              ),
              IconButton(
                tooltip: 'Ordem aleatória',
                isSelected: cast != null && cast.isShuffling,
                onPressed: cast != null && cast.canShuffle
                    ? cast.toggleShuffle
                    : null,
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: (cast?.isShuffling ?? false) ? highlight : null,
                ),
              ),
            ],
          ),
          if (cast != null && isStreamingToTarget && cast.hasProgress) ...[
            const SizedBox(height: 6),
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

  /// Painel de controles de vídeo para a orientação vertical (Portrait)
  Widget _buildPortraitVideoControls(
    RemoteController tv,
    MediaCastController? cast,
    bool isStreamingToTarget,
    LibraryEntry current,
    Color highlight,
  ) {
    final pTarget = getPlaybackTarget(tv);
    final isTv = pTarget == PlaybackTarget.tv;
    final isCurrentVideoStreaming =
        cast != null &&
        isStreamingToTarget &&
        cast.currentFileName == current.name;

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
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              IconButton.filledTonal(
                tooltip: 'Reproduzir vídeo',
                isSelected: isCurrentVideoStreaming && cast.isPlaying,
                onPressed: () {
                  if (isTv && !tv.isConnected) {
                    message('Conecte um dispositivo para transmitir.');
                    return;
                  }
                  if (isTv) {
                    if (cast != null &&
                        isCurrentVideoStreaming &&
                        (cast.isPaused || cast.canPlay)) {
                      cast.play();
                    } else {
                      play(
                        tab == 1 ? queue : [current],
                        start: tab == 1
                            ? queue
                                  .indexWhere(
                                    (q) =>
                                        q.id == current.id &&
                                        q.source == current.source,
                                  )
                                  .clamp(0, queue.length - 1)
                            : 0,
                        sourceTitle: tab == 1 ? queueTitle : current.name,
                        syncToQueue: tab != 1,
                      );
                    }
                  } else {
                    _openLocalFullScreen(current);
                  }
                },
                icon: const Icon(Icons.play_arrow_rounded),
              ),
              IconButton.filledTonal(
                tooltip: 'Pausar vídeo',
                isSelected: isCurrentVideoStreaming && cast.isPaused,
                onPressed: cast != null &&
                        isCurrentVideoStreaming &&
                        (cast.isPlaying || cast.canPause)
                    ? cast.pause
                    : null,
                icon: const Icon(Icons.pause_rounded),
              ),
              IconButton.filledTonal(
                tooltip: 'Repetir vídeo',
                isSelected: cast != null && cast.isLooping,
                onPressed: cast != null &&
                        isStreamingToTarget &&
                        (cast.canLoop || cast.isLooping)
                    ? cast.toggleLoop
                    : null,
                icon: const Icon(Icons.repeat_rounded),
              ),
              IconButton.filledTonal(
                tooltip: 'Abrir em tela cheia',
                icon: const Icon(Icons.fullscreen_rounded),
                onPressed: () => _openLocalFullScreen(current),
              ),
            ],
          ),
          if (cast != null && isStreamingToTarget && cast.hasProgress)
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

  /// Painel integrado de visualização de fotos e vídeos no app com carrossel adaptativo (Retrato e Paisagem).
  Widget _buildPhotoViewerCard(
    RemoteController tv,
    MediaCastController? cast,
    bool isStreamingToTarget,
  ) {
    if (activePhotos.isEmpty && activeMediaItem == null) {
      return const SizedBox.shrink();
    }
    final safeIdx = activePhotos.isNotEmpty
        ? activePhotoIndex.clamp(0, activePhotos.length - 1)
        : 0;
    final carouselItems = _carouselContextItems();
    LibraryEntry current = activeMediaItem ?? activePhotos[safeIdx];
    if (!current.isImage &&
        cast != null &&
        isStreamingToTarget &&
        cast.currentFileName != null) {
      final matched = carouselItems
          .where((e) => e.name == cast.currentFileName)
          .firstOrNull;
      if (matched != null) {
        current = matched;
      }
    }
    final highlight = AppColors.iconHighlightOf(context);
    final curCarouselIdx = carouselItems.indexWhere(
      (e) => e.id == current.id && e.source == current.source,
    );
    final canPrev = current.isImage
        ? (safeIdx > 0 && !loadingPhotoPreview)
        : (curCarouselIdx > 0 && !loadingPhotoPreview);
    final canNext = current.isImage
        ? (safeIdx + 1 < activePhotos.length && !loadingPhotoPreview)
        : (curCarouselIdx >= 0 &&
              curCarouselIdx + 1 < carouselItems.length &&
              !loadingPhotoPreview);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft && canPrev) {
            navigateActivePhoto(-1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && canNext) {
            navigateActivePhoto(1);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape =
              MediaQuery.of(context).orientation == Orientation.landscape ||
              (constraints.maxWidth >= 600 &&
                  constraints.maxWidth >
                      (MediaQuery.of(context).size.height * 0.7));

          if (isLandscape) {
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Coluna 1 (Esquerda): Carrossel Completo
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
                              height: 220,
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
                      // Coluna 2 (Direita): Controles de Mídia
                      Expanded(
                        flex: 5,
                        child: _buildLandscapeMediaControlsPanel(
                          tv,
                          cast,
                          isStreamingToTarget,
                          current,
                          highlight,
                        ),
                      ),
                    ],
                  ),
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
                  height: 200,
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
                _buildThumbnailsCarousel(
                  carouselItems,
                  current,
                  highlight,
                  tv,
                ),
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

    final content = SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverList.list(
            children: [
              // Cabeçalho da Biblioteca com indicação clara do aparelho de destino e botão de limpeza rápida
              Padding(
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
                        onPressed: () =>
                            abortAndClearQueue(clearQueueItems: true),
                        icon: const Icon(
                          Icons.cleaning_services_rounded,
                          size: 16,
                          color: AppColors.powerRed,
                        ),
                      ),
                  ],
                ),
              ),

              if (!tv.isConnected)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.amber,
                          size: 16,
                        ),
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
                ),

              // Seletor de 3 seções no padrão Liquid Glass idêntico ao seletor de dispositivos
              _buildSectionSelector(context, tv),

              // Visualizador de fotos e vídeos integrado com carrossel
              if (activePhotos.isNotEmpty || activeMediaItem != null)
                _buildPhotoViewerCard(tv, cast, isStreamingToTarget),

              // Pastilha / Banner de controle da sessão remota ativa (quando reproduzindo áudio ou sem carrossel aberto)
              if (isStreamingToTarget &&
                  activePhotos.isEmpty &&
                  activeMediaItem == null)
                _buildActivePlaybackCard(cast, tv),

              if (casting)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
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
                        onPressed: () =>
                            abortAndClearQueue(clearQueueItems: false),
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: const Text('Cancelar'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          // Keep a usable library viewport below the naturally sized cards.
          // Short screens and large text scroll the cards instead of squeezing
          // a fixed-height photo preview into the outer Column.
          SliverLayoutBuilder(
            builder: (context, constraints) => SliverToBoxAdapter(
              child: SizedBox(
                height:
                    (constraints.viewportMainAxisExtent -
                            constraints.precedingScrollExtent)
                        .clamp(240.0, double.infinity),
                child: loadFailed
                    ? const Center(
                        child: Text('A biblioteca salva não pôde ser lida.'),
                      )
                    : !ready
                    ? const Center(child: CircularProgressIndicator())
                    : tab == 0
                    ? playlistView()
                    : tab == 1
                    ? queueView(cast, isStreamingToTarget)
                    : filesView(),
              ),
            ),
          ),
        ],
      ),
    );

    return widget.embedded
        ? content
        : Scaffold(
            appBar: AppBar(title: const Text('Biblioteca de mídia')),
            body: content,
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
  Widget filesView() {
    if (trail.isEmpty) {
      return ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Adicionar pasta deste aparelho'),
            onTap: addRoot,
          ),
          for (final root in [
            ...roots,
            const LibraryEntry(
              LibrarySource.drive,
              'root',
              'Google Drive',
              folder: true,
            ),
            const LibraryEntry(
              LibrarySource.oneDrive,
              'root',
              'OneDrive',
              folder: true,
            ),
          ])
            ListTile(
              leading: Icon(
                root.source == LibrarySource.local ||
                        root.source == LibrarySource.androidTree
                    ? Icons.folder
                    : Icons.cloud_outlined,
              ),
              title: Text(root.name),
              subtitle:
                  (root.source == LibrarySource.drive && driveLogged) ||
                      (root.source == LibrarySource.oneDrive && oneDriveLogged)
                  ? const Text(
                      'Sessão salva · Login automático ativado',
                      style: TextStyle(fontSize: 11),
                    )
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((root.source == LibrarySource.drive && driveLogged) ||
                      (root.source == LibrarySource.oneDrive && oneDriveLogged))
                    IconButton(
                      tooltip: 'Sair da conta ${root.name}',
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      onPressed: () async {
                        await sources.signOut(root.source);
                        await _refreshCloudAuthState();
                        message('Sessão de ${root.name} desconectada.');
                      },
                    ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => enter(root),
            ),
          if (roots.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: AppColors.powerRed,
                  side: BorderSide(
                    color: AppColors.powerRed.withValues(alpha: 0.5),
                  ),
                ),
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
    return Column(
      children: [
        ListTile(
          leading: BackButton(
            onPressed: () {
              trail.removeLast();
              browse();
            },
          ),
          title: Text(
            trail.map((e) => e.name).join(' / '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: 'Recarregar pasta',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () {
              if (trail.isNotEmpty) {
                LibrarySources.invalidateFolderCache(
                  "${trail.last.source.name}:${trail.last.id}",
                );
              }
              browse();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar nesta pasta',
                  ),
                  onChanged: (v) => setState(() => filter = v.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              _buildViewModeToggleButton(),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: sortByExtension
                    ? 'Ordenado por Tipo / Extensão'
                    : 'Ordenar por Nome (A-Z)',
                icon: Icon(
                  sortByExtension
                      ? Icons.category_rounded
                      : Icons.sort_by_alpha_rounded,
                  color: sortByExtension
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: () {
                  HapticService.selectionClick();
                  setState(() => sortByExtension = !sortByExtension);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: Builder(
            builder: (_) {
              if (loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (folderError.isNotEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: browse,
                        child: Text(
                          '$folderError\nTentar novamente',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() => trail.clear());
                          save();
                        },
                        icon: const Icon(Icons.home_outlined, size: 16),
                        label: const Text('Voltar às fontes'),
                      ),
                    ],
                  ),
                );
              }
              final visible = _visibleFolderEntries();
              if (visible.isEmpty) {
                return const Center(
                  child: Text('Nenhuma pasta ou mídia encontrada.'),
                );
              }
              final isCarouselActive =
                  activePhotos.isNotEmpty || activeMediaItem != null;
              final subfolders = visible.where((e) => e.folder).toList();

              // Quando o carrossel estiver ativo e não houver filtro digitado,
              // os arquivos de mídia ficam centralizados no carrossel superior para liberar espaço.
              if (isCarouselActive && filter.isEmpty) {
                if (subfolders.isNotEmpty) {
                  return ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Subpastas (${subfolders.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ),
                      for (final e in subfolders)
                        ListTile(
                          dense: !showThumbnails,
                          visualDensity: showThumbnails
                              ? null
                              : VisualDensity.compact,
                          leading: showThumbnails
                              ? _buildEntryThumbnail(e, size: 38)
                              : Icon(
                                  Icons.folder_outlined,
                                  size: 20,
                                  color: AppColors.iconHighlightOf(context),
                                ),
                          title: Text(e.name),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => enter(e),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '${visible.where((e) => !e.folder).length} arquivos no carrossel acima · Segure na miniatura para opções',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMutedOf(context),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.swipe_rounded,
                          size: 28,
                          color: AppColors.textMutedOf(context),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${visible.where((e) => !e.folder).length} arquivos disponíveis no carrossel acima',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimaryOf(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Toque nas miniaturas para navegar ou segure para opções rápidas e seleção múltipla.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                itemCount: visible.length,
                itemBuilder: (_, i) {
                  final e = visible[i];
                  if (e.folder) {
                    return ListTile(
                      dense: !showThumbnails,
                      visualDensity: showThumbnails
                          ? null
                          : VisualDensity.compact,
                      leading: showThumbnails
                          ? _buildEntryThumbnail(e, size: 38)
                          : Icon(
                              Icons.folder_outlined,
                              size: 20,
                              color: AppColors.iconHighlightOf(context),
                            ),
                      title: Text(e.name),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => enter(e),
                    );
                  }
                  final index = selected.indexWhere(
                    (s) => s.id == e.id && s.source == e.source,
                  );

                  final ext = p.extension(e.name).toUpperCase();
                  final cleanExt = ext.startsWith('.') ? ext.substring(1) : ext;

                  if (e.isImage) {
                    return ListTile(
                      dense: !showThumbnails,
                      visualDensity: showThumbnails
                          ? null
                          : VisualDensity.compact,
                      leading: showThumbnails
                          ? _buildEntryThumbnail(e, size: 42)
                          : null,
                      title: Text(e.name),
                      subtitle: showThumbnails
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.amberAccent.withValues(
                                        alpha: 0.7,
                                      ),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    'FOTO • $cleanExt',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                      color: AppColors.textPrimaryOf(context),
                                    ),
                                  ),
                                ),
                                Text(
                                  e.size != null
                                      ? '${_formatBytes(e.size!)} · Toque para abrir'
                                      : 'Toque para abrir e espelhar na TV',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            )
                          : null,
                      onTap: () => showFileActions(e, photoContext: visible),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Visualizar e espelhar na TV',
                            icon: const Icon(Icons.cast_rounded),
                            onPressed: () => openPhotoAndMirror(visible, e),
                          ),
                          Checkbox(
                            value: index >= 0,
                            onChanged: (_) => setState(() {
                              if (index < 0) {
                                selected.add(e);
                              } else {
                                selected.removeAt(index);
                              }
                            }),
                          ),
                        ],
                      ),
                    );
                  }

                  final isVid = e.isVideo;
                  return ListTile(
                    dense: !showThumbnails,
                    visualDensity: showThumbnails
                        ? null
                        : VisualDensity.compact,
                    leading: showThumbnails
                        ? _buildEntryThumbnail(e, size: 42)
                        : null,
                    onTap: () => showFileActions(e, photoContext: visible),
                    title: Text(e.name),
                    subtitle: showThumbnails
                        ? Wrap(
                            spacing: 6,
                            runSpacing: 2,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: isVid
                                      ? const Color(0xFF0E8FF1).withValues(
                                          alpha: 0.25,
                                        )
                                      : Colors.teal.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isVid
                                        ? const Color(0xFF38BDF8).withValues(
                                            alpha: 0.7,
                                          )
                                        : Colors.tealAccent.withValues(
                                            alpha: 0.7,
                                          ),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  isVid
                                      ? 'VÍDEO • $cleanExt'
                                      : 'ÁUDIO • $cleanExt',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                              ),
                              if (e.size != null)
                                Text(
                                  _formatBytes(e.size!),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                ),
                            ],
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Reproduzir no aparelho ativo',
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () =>
                              play([e], start: 0, sourceTitle: e.name),
                        ),
                        Checkbox(
                          value: index >= 0,
                          onChanged: (_) => setState(() {
                            if (index < 0) {
                              selected.add(e);
                            } else {
                              selected.removeAt(index);
                            }
                          }),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (selected.isNotEmpty) selectionBar(),
      ],
    );
  }

  /// Barra de ações claras para os itens selecionados:
  /// 1. Tocar na TV / Adicionar à Fila Temporária
  /// 2. Criar / Salvar em Playlist Persistida
  Widget selectionBar() {
    final count = selected.length;
    final tv = context.read<RemoteController>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppColors.glassCardDecoration(context, borderRadius: 18),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.iconHighlightOf(context)
                      .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count ${count == 1 ? 'arquivo selecionado' : 'arquivos selecionados'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.iconHighlightOf(context),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Desmarcar todos',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => selected.clear()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: !tv.isConnected
                    ? () => addSelectionToQueue(playNow: false)
                    : () => addSelectionToQueue(playNow: true),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Tocar na TV'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => addSelectionToQueue(playNow: false),
                icon: const Icon(Icons.queue_music_rounded, size: 18),
                label: const Text('Adicionar à fila'),
              ),
              OutlinedButton.icon(
                onPressed: addSelection,
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: const Text('Criar playlist'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
