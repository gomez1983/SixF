import 'google_tv_adb_dialog.dart';
import '../../services/drivers/tv_driver.dart';
import '../../services/google_tv_apps_adb.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/remote_controller.dart';
import '../glass/glass_flags.dart';
import '../glass/liquid_glass.dart' show GlassTokens, glassFlatDecoration;
import '../theme/app_colors.dart';
import 'device_discovery_dialog.dart';
import 'payno.dart';
import 'remote_button.dart';

/// Gaveta / Grid de Aplicativos instalados na Smart TV conectada.
///
/// Pode ser exibido tanto como uma aba da tela principal, um componente
/// embutido no layout Desktop, ou via Modal BottomSheet.
class AppDrawerWidget extends StatefulWidget {
  final bool isEmbeddedInDesktop;

  /// Já está dentro de um card (aba Apps do desktop): o cabeçalho não ganha
  /// card próprio.
  final bool isInCard;

  const AppDrawerWidget({
    super.key,
    this.isEmbeddedInDesktop = false,
    this.isInCard = false,
  });

  /// Exibe a gaveta de aplicativos como um Modal BottomSheet moderno.
  static Future<void> showAsBottomSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceCardOf(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.borderSubtleOf(ctx)),
          ),
          child: const AppDrawerWidget(),
        ),
      ),
    );
  }

  @override
  State<AppDrawerWidget> createState() => _AppDrawerWidgetState();
}

class _AppDrawerWidgetState extends State<AppDrawerWidget> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final isConnected = controller.isConnected;
    final isLoading = controller.isLoadingApps;
    final apps = controller.installedApps;

    final filteredApps =
        apps.where((app) {
          if (_favoritesOnly && !controller.isFavoriteApp(app.id)) return false;
          if (_searchQuery.isEmpty) return true;
          return app.name.toLowerCase().contains(_searchQuery) ||
              app.id.toLowerCase().contains(_searchQuery);
        }).toList()..sort((a, b) {
          final favoriteOrder =
              (controller.isFavoriteApp(b.id) ? 1 : 0) -
              (controller.isFavoriteApp(a.id) ? 1 : 0);
          return favoriteOrder != 0
              ? favoriteOrder
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

    // Padrão Payno: título, contagem em destaque, busca e filtros num card.
    final showSearch = isConnected && apps.isNotEmpty;
    final top = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeaderBar(
          context,
          controller,
          isConnected,
          isLoading,
          apps.length,
        ),
        if (showSearch && !kGlassUi) ...[
          const SizedBox(height: 12),
          _buildSearchField(context),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PaynoChip(
                'Todos',
                selected: !_favoritesOnly,
                onTap: () => setState(() => _favoritesOnly = false),
              ),
              PaynoChip(
                'Favoritos',
                icon: Icons.star_outline_rounded,
                selected: _favoritesOnly,
                onTap: () => setState(() => _favoritesOnly = true),
              ),
            ],
          ),
        ],
      ],
    );

    // Em alturas pequenas (paisagem, janela baixa) cabeçalho e painel ADB
    // têm teto e rolam por dentro: a grade nunca é empurrada para fora.
    return LayoutBuilder(
      builder: (context, box) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.isEmbeddedInDesktop ? 12 : 16,
          vertical: widget.isEmbeddedInDesktop ? 10 : 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Cabeçalho: título, contagem, busca e filtros
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: _cap(box.maxHeight, 0.5)),
              child: SingleChildScrollView(
                child: kGlassUi || widget.isEmbeddedInDesktop || widget.isInCard
                    ? top
                    : PaynoCard(child: top),
              ),
            ),

            SizedBox(height: widget.isEmbeddedInDesktop ? 8 : 12),

            // Chromecast sem a lista ADB ativa: passo a passo + campos de porta e
            // código dentro da própria gaveta (sem diálogo, sem outra tela).
            if (isConnected &&
                !isLoading &&
                controller.currentBrand == TvBrand.googleTv &&
                !apps.any((a) => a.id.startsWith('adb:')))
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _cap(box.maxHeight, 0.4)),
                child: SingleChildScrollView(
                  child: FutureBuilder<bool>(
                    key: ValueKey('adb-panel-${controller.ipAddress}'),
                    future: GoogleTvAppsAdb.configured(controller.ipAddress),
                    builder: (context, snapshot) => GoogleTvAdbPanel(
                      host: controller.ipAddress,
                      wasConfigured:
                          snapshot.data == true || controller.appsError != null,
                      onConnected: () async {
                        final host = controller.ipAddress;
                        if (mounted && controller.ipAddress == host) {
                          await controller.fetchInstalledApps(
                            forceRefresh: true,
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
            if (isConnected &&
                !isLoading &&
                controller.currentBrand == TvBrand.googleTv &&
                !apps.any((a) => a.id.startsWith('adb:')))
              SizedBox(height: widget.isEmbeddedInDesktop ? 8 : 12),
            // 2. Campo de Pesquisa Instantânea (modo Liquid Glass)
            if (showSearch && kGlassUi) ...[
              _buildSearchField(context),
              Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('Favoritos'),
                  selected: _favoritesOnly,
                  onSelected: (value) => setState(() => _favoritesOnly = value),
                  // Modo Liquid Glass: chip translúcido em vez do fundo opaco.
                  backgroundColor: kGlassUi
                      ? AppColors.surfaceInteractiveOf(context)
                      : null,
                  selectedColor: kGlassUi
                      ? GlassTokens.of(context).tintBlue
                      : null,
                  surfaceTintColor: kGlassUi ? Colors.transparent : null,
                  elevation: kGlassUi ? 0 : null,
                  side: kGlassUi
                      ? BorderSide(
                          color: GlassTokens.of(context).rimLight
                              .withValues(alpha: 0.5),
                        )
                      : null,
                  shape: kGlassUi ? const StadiumBorder() : null,
                  labelStyle: kGlassUi
                      ? TextStyle(color: GlassTokens.of(context).label)
                      : null,
                ),
              ),
              SizedBox(height: widget.isEmbeddedInDesktop ? 8 : 12),
            ],

            // 3. Área de Conteúdo: Grid de Apps ou Estados Vazios
            Expanded(
              child: _buildContent(
                context,
                controller,
                isConnected,
                isLoading,
                filteredApps,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fração da altura útil (descontados espaçamentos e margens).
  static double _cap(double height, double fraction) =>
      ((height - 44).clamp(0.0, double.infinity)) * fraction;

  Widget _buildHeaderBar(
    BuildContext context,
    RemoteController controller,
    bool isConnected,
    bool isLoading,
    int totalApps,
  ) {
    final isGoogleTv = controller.currentBrand == TvBrand.googleTv;
    final hasAdb = controller.installedApps.any((a) => a.id.startsWith('adb:'));
    final title = isGoogleTv
        ? (hasAdb ? 'Aplicativos do Chromecast' : 'Atalhos do Chromecast')
        : 'Aplicativos & Atalhos';
    final showCount = isConnected && (!isGoogleTv || hasAdb);
    final unit = isGoogleTv
        ? 'aplicativos · ADB'
        : '${totalApps == 1 ? 'aplicativo' : 'aplicativos'} · ${controller.driver.brandDisplayName}';
    final note = isConnected
        ? 'Configure ADB para listar os apps instalados'
        : 'Desconectado da Smart TV';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.grid_view_rounded,
                    size: 16,
                    color: AppColors.textMutedOf(context),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimaryOf(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (showCount)
                PaynoBigValue(
                  '$totalApps',
                  unit: unit,
                  size: widget.isEmbeddedInDesktop ? 28 : 34,
                )
              else
                Text(
                  note,
                  style: TextStyle(
                    color: AppColors.textMutedOf(context),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        if (isConnected)
          RemoteButton(
            width: 36,
            height: 36,
            isCircular: true,
            foregroundColor: AppColors.textPrimaryOf(context),
            icon: Icons.refresh_rounded,
            iconSize: 18,
            tooltip: 'Recarregar aplicativos da TV',
            onPressed: isLoading
                ? null
                : () => controller.fetchInstalledApps(forceRefresh: true),
          ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final isDesktop = widget.isEmbeddedInDesktop;

    return Container(
      height: isDesktop ? 36 : 42,
      decoration: BoxDecoration(
        color: AppColors.surfaceInteractiveOf(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(
          color: AppColors.textPrimaryOf(context),
          fontSize: isDesktop ? 12 : 13,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar aplicativo na TV...',
          hintStyle: TextStyle(
            color: AppColors.textMutedOf(context),
            fontSize: isDesktop ? 12 : 13,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: isDesktop ? 16 : 18,
            color: AppColors.textMutedOf(context),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded, size: isDesktop ? 14 : 16),
                  color: AppColors.textMutedOf(context),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.symmetric(vertical: isDesktop ? 6 : 10),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    RemoteController controller,
    bool isConnected,
    bool isLoading,
    List<TvAppInfo> filteredApps,
  ) {
    if (!isConnected) {
      if (widget.isEmbeddedInDesktop) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tv_off_rounded,
                size: 24,
                color: AppColors.textMutedOf(context),
              ),
              const SizedBox(height: 6),
              Text(
                'Smart TV Desconectada',
                style: TextStyle(
                  color: AppColors.textPrimaryOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.borderSubtleOf(context)),
                  foregroundColor: AppColors.iconHighlightOf(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.cast_connected_rounded, size: 14),
                label: const Text(
                  'Conectar TV',
                  style: TextStyle(fontSize: 11),
                ),
                onPressed: () => DeviceDiscoveryDialog.show(context),
              ),
            ],
          ),
        );
      }

      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceInteractiveOf(context),
                  border: Border.all(color: AppColors.borderSubtleOf(context)),
                ),
                child: Icon(
                  Icons.tv_off_rounded,
                  size: 26,
                  color: AppColors.textMutedOf(context),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Smart TV Desconectada',
                style: TextStyle(
                  color: AppColors.textPrimaryOf(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Conecte-se à TV para visualizar os aplicativos instalados e abri-los diretamente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMutedOf(context),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentFillOf(context),
                  foregroundColor: AppColors.onAccentOf(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.cast_connected_rounded, size: 16),
                label: const Text(
                  'Conectar TV',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () => DeviceDiscoveryDialog.show(context),
              ),
            ],
          ),
        ),
      );
    }

    if (isLoading && filteredApps.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.iconHighlightOf(context),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Carregando aplicativos da TV...',
                style: TextStyle(
                  color: AppColors.textSecondaryOf(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (filteredApps.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 36,
                color: AppColors.textMutedOf(context),
              ),
              const SizedBox(height: 10),
              Text(
                'Nenhum aplicativo encontrado',
                style: TextStyle(
                  color: AppColors.textPrimaryOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_searchQuery.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Filtro: "$_searchQuery"',
                  style: TextStyle(
                    color: AppColors.textMutedOf(context),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Grid de Aplicativos
    final isDesktop = widget.isEmbeddedInDesktop;

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(bottom: isDesktop ? 8 : 16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: isDesktop ? 86 : 96,
        mainAxisSpacing: isDesktop ? 8 : 10,
        crossAxisSpacing: isDesktop ? 8 : 10,
        childAspectRatio: isDesktop ? 0.75 : 0.72,
      ),
      itemCount: filteredApps.length,
      itemBuilder: (context, index) {
        final app = filteredApps[index];
        return _buildAppTile(context, controller, app);
      },
    );
  }

  Widget _buildAppTile(
    BuildContext context,
    RemoteController controller,
    TvAppInfo app,
  ) {
    final isDesktop = widget.isEmbeddedInDesktop;
    final brandColor =
        app.brandColor ?? AppColors.surfaceInteractiveOf(context);
    final hasRemoteIcon =
        app.iconAsset != null ||
        (app.iconUrl != null &&
            (app.iconUrl!.startsWith('http://') ||
                app.iconUrl!.startsWith('https://')));

    final iconBoxSize = isDesktop ? 36.0 : 44.0;
    final iconInnerSize = isDesktop ? 18.0 : 22.0;

    return Stack(
      children: [
        Positioned.fill(
          child: Material(
            color: kGlassUi
                ? Colors.transparent
                : AppColors.surfaceInteractiveOf(context),
            borderRadius: BorderRadius.circular(isDesktop ? 12 : 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(isDesktop ? 12 : 16),
              onTap: () => controller.openApp(app.id, appName: app.name),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: isDesktop ? 4 : 8,
                ),
                decoration: kGlassUi
                    ? glassFlatDecoration(context, radius: isDesktop ? 12 : 16)
                    : BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          isDesktop ? 12 : 16,
                        ),
                        border: Border.all(
                          color: AppColors.borderSubtleOf(context),
                          width: 1,
                        ),
                      ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Ícone do App
                    Container(
                      width: iconBoxSize,
                      height: iconBoxSize,
                      decoration: BoxDecoration(
                        color: hasRemoteIcon
                            ? Colors.transparent
                            : brandColor.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(
                          isDesktop ? 10 : 12,
                        ),
                        border: Border.all(
                          color: hasRemoteIcon
                              ? Colors.transparent
                              : (app.brandColor ??
                                        AppColors.borderSubtleOf(context))
                                    .withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: hasRemoteIcon
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(
                                isDesktop ? 8 : 10,
                              ),
                              child: _buildAppImage(
                                context,
                                app,
                                iconBoxSize - 4,
                                iconInnerSize,
                              ),
                            )
                          : Icon(
                              app.fallbackIcon,
                              size: iconInnerSize,
                              color:
                                  app.brandColor ??
                                  AppColors.iconHighlightOf(context),
                            ),
                    ),

                    SizedBox(height: isDesktop ? 4 : 6),

                    // Nome do App
                    Text(
                      app.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimaryOf(context),
                        fontSize: isDesktop ? 10 : 11,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            iconSize: 18,
            tooltip: controller.isFavoriteApp(app.id)
                ? 'Remover ${app.name} dos favoritos'
                : 'Favoritar ${app.name}',
            icon: Icon(
              controller.isFavoriteApp(app.id)
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: AppColors.iconHighlightOf(context),
            ),
            onPressed: () => controller.toggleFavoriteApp(app.id),
          ),
        ),
      ],
    );
  }

  Widget _buildAppImage(
    BuildContext context,
    TvAppInfo app,
    double size,
    double fallbackSize,
  ) {
    Widget fallback() => Icon(
      app.fallbackIcon,
      size: fallbackSize,
      color: app.brandColor ?? AppColors.iconHighlightOf(context),
    );
    Widget bundled() => app.iconAsset == null
        ? fallback()
        : Image.asset(
            app.iconAsset!,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => fallback(),
          );
    final url = app.iconUrl;
    if (url == null ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      return bundled();
    }
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => bundled(),
    );
  }
}
