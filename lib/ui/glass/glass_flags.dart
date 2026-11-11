/// Interface Liquid Glass (iOS 26) em modo experimental: desligada por padrão.
///
/// Ligue na compilação, sem mexer em nenhuma configuração salva:
///
///   flutter run -d windows --dart-define=SIXF_GLASS_UI=true
///
/// Quando ligada, valem o layout de retrato (celular e janela estreita) e as
/// superfícies de conteúdo das abas (botões, cartões, grades de apps). O layout
/// largo do desktop e a paisagem mantêm a moldura atual, mas os botões e
/// cartões que eles reutilizam também ficam em vidro.
///
/// Não é `const` para a vitrine de design (`main_glass_preview.dart`) poder
/// ligar o modo em tempo de execução; no app normal só muda na inicialização.
bool kGlassUi = const bool.fromEnvironment('SIXF_GLASS_UI');
