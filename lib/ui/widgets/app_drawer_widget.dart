import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../../services/drivers/tv_app_info.dart';
import '../theme/app_colors.dart';
import 'device_discovery_dialog.dart';
import 'remote_button.dart';

/// Gaveta / Grid de Aplicativos instalados na Smart TV conectada.
///
/// Pode ser exibido tanto como uma aba da tela principal, um componente
/// embutido no layout Desktop, ou via Modal BottomSheet.
class AppDrawerWidget extends StatefulWidget {
  final bool isEmbeddedInDesktop;

  const AppDrawerWidget({
    super.key,
    this.isEmbeddedInDesktop = false,
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

    final filteredApps = apps.where((app) {
      if (_searchQuery.isEmpty) return true;
      return app.name.toLowerCase().contains(_searchQuery) ||
          app.id.toLowerCase().contains(_searchQuery);
    }).toList();

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isEmbeddedInDesktop ? 12 : 16,
        vertical: widget.isEmbeddedInDesktop ? 10 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Barra Superior: Título, Filtro de Busca e Botão Atualizar
          _buildHeaderBar(context, controller, isConnected, isLoading, apps.length),

          SizedBox(height: widget.isEmbeddedInDesktop ? 8 : 12),

          // 2. Campo de Pesquisa Instantânea
          if (isConnected && apps.isNotEmpty) ...[
            _buildSearchField(context),
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
    );
  }

  Widget _buildHeaderBar(
    BuildContext context,
    RemoteController controller,
    bool isConnected,
    bool isLoading,
    int totalApps,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.iconHighlightOf(context).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.apps_rounded,
            size: 20,
            color: AppColors.iconHighlightOf(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aplicativos & Atalhos',
                style: TextStyle(
                  color: AppColors.textPrimaryOf(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isConnected
                    ? '${controller.driver.brandDisplayName} • $totalApps aplicativo${totalApps == 1 ? '' : 's'}'
                    : 'Desconectado da Smart TV',
                style: TextStyle(
                  color: AppColors.textMutedOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
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
            backgroundColor: AppColors.surfaceInteractiveOf(context),
            borderColor: AppColors.borderSubtleOf(context),
            foregroundColor: AppColors.iconHighlightOf(context),
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
        borderRadius: BorderRadius.circular(isDesktop ? 10 : 12),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.cast_connected_rounded, size: 14),
                label: const Text('Conectar TV', style: TextStyle(fontSize: 11)),
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
                  backgroundColor: AppColors.iconHighlightOf(context),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        childAspectRatio: isDesktop ? 0.94 : 0.85,
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
    final brandColor = app.brandColor ?? AppColors.surfaceInteractiveOf(context);
    final hasRemoteIcon = app.iconUrl != null &&
        (app.iconUrl!.startsWith('http://') || app.iconUrl!.startsWith('https://'));

    final iconBoxSize = isDesktop ? 36.0 : 44.0;
    final iconInnerSize = isDesktop ? 18.0 : 22.0;

    return Material(
      color: AppColors.surfaceCardOf(context),
      borderRadius: BorderRadius.circular(isDesktop ? 12 : 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(isDesktop ? 12 : 16),
        onTap: () => controller.openApp(app.id, appName: app.name),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 4,
            vertical: isDesktop ? 4 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isDesktop ? 12 : 16),
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
                  color: hasRemoteIcon ? Colors.transparent : brandColor.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(isDesktop ? 10 : 12),
                  border: Border.all(
                    color: hasRemoteIcon
                        ? Colors.transparent
                        : (app.brandColor ?? AppColors.borderSubtleOf(context)).withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: hasRemoteIcon
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(isDesktop ? 8 : 10),
                        child: Image.network(
                          app.iconUrl!,
                          width: iconBoxSize - 4,
                          height: iconBoxSize - 4,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Icon(
                            app.fallbackIcon,
                            size: iconInnerSize,
                            color: app.brandColor ?? AppColors.iconHighlightOf(context),
                          ),
                        ),
                      )
                    : Icon(
                        app.fallbackIcon,
                        size: iconInnerSize,
                        color: app.brandColor ?? AppColors.iconHighlightOf(context),
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
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
