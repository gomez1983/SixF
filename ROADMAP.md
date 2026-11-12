# SixF — implementação e escopo futuro

Implementado não equivale a homologado em todos os modelos de TV. Consulte `docs/DISTRIBUTION.md` para a matriz manual e os resultados locais registrados.

## Implementado no código

- [x] Windows e Android; drivers LG webOS, Samsung Tizen e Google TV (Remote Service v2).
- [x] Sessões independentes, aparelhos salvos e alternância de controle ativo.
- [x] Credenciais por marca/IP, cancelamento e limpeza de operações.
- [x] Arquivos locais via SSAP/DLNA, URL exclusiva, HEAD/Range e revogação ao encerrar.
- [x] Estado de mídia e controles conforme informações da TV; envio separado de reprodução confirmada.
- [x] Diagnóstico por aparelho, repetição de D-Pad/volume/canais, favoritos persistidos por TV.
- [x] Janela compacta Windows com restauração da geometria e sobreposição anteriores.
- [x] Chromecast com Google TV: inventário e abertura de apps via ADB (opcional, autorizado pelo usuário), voz pelo microfone.
- [x] Aba Mídia: Google Drive, OneDrive e pastas locais; login persistente; streaming sob demanda (proxy HTTP Range); fila temporária e playlists com reordenação; visualizador de fotos e vídeos; controles da sessão remota (play/pausa, anterior/próximo, ±10 s, repetir, aleatório, legenda e faixa de áudio).
- [x] Aba Controle com faixas de slots configuráveis (por aparelho) e card único de Volume/Canal + D-pad.
- [x] **Visual ZIXO (12/11/2026):** paleta fechada (grafite `#414140`, branco, verde `#38BC37`, vermelho `#F44336`), vidro fosco, destaque invertido no tema escuro e fonte única Open Sans (pesos 300–800, sem itálico). Referências em `docs/design/referencias/`, mockup em `docs/design/mockups/sixf-zixo-mockup.html`.
- [x] Mídia (12/11/2026): Legenda e Áudio só com ícone na linha de transporte; Repetir/Aleatório ligados em círculo no destaque; tela cheia do player respeita a orientação do aparelho.

## Próxima fase — identidade do app

- [ ] **Novo ícone do aplicativo** (Android adaptativo, Windows `.ico`, Microsoft Store), alinhado ao visual ZIXO.
- [ ] **Avaliar novo nome** para substituir "SixF". Ao trocar, revisar todos os pontos, não só o texto da interface:
  - nome exibido (`pubspec.yaml` `msix_config`, título da janela Windows, `android:label`, instalador `.iss`);
  - identificador do pacote Android `com.andregomez.controle_lg` (trocar o ID cria um app novo na loja e perde dados locais dos usuários);
  - canal nativo `controle_lg/volume_keys` (`lib/services/volume_key_service.dart` e `windows/runner/flutter_window.cpp`) e o `execution_alias: controle_lg`;
  - logotipo `assets/icons/SixF_Logo_01.png` e o `PaynoLogo` do cabeçalho.

## Dependências externas da distribuição

- [ ] Homologar em TVs LG e Samsung físicas e Android/Windows reais.
- [ ] Configurar chave Android (`android/key.properties`) e certificado/identidade de distribuição Windows. Até lá o APK de teste é Debug (ver `AGENTS.md`, item 7).
- [ ] Assinar, revisar instaladores e publicar nas lojas mediante autorização (`docs/Guia_Publicacao_Lojas.md`).

## Dívida técnica

- [ ] Remover a interface experimental Liquid Glass (`lib/ui/glass/`, `lib/main_glass_preview.dart`, `multimedia_controls.dart` e os ramos `kGlassUi` nos widgets), substituída pelo visual ZIXO.
- [ ] Renomear `payno.dart`/`paynoCardDecoration` para nomes neutros (hoje desenham o visual ZIXO).
- [ ] Teste `MediaDetails identifica compatibilidade de codecs com decodificador Chromecast` falha: espera `webp` incompatível e recebe compatível. Anterior ao visual ZIXO.
- [ ] Refresh token do Google Drive/OneDrive em `shared_preferences` sem proteção do sistema operacional; migrar para armazenamento protegido exige nova dependência e aprovação.
- [ ] Primeiro uso sem cadastro legado predefinido.
- [ ] Identidade estável de aparelho e armazenamento de credenciais protegido pelo sistema operacional.
- [ ] Seleção de interface de rede por rota, revisão de descoberta e validação uniforme dos destinos.
- [ ] Separar responsabilidades restantes do `RemoteController` e medir custo de notificações.

## Ideias fora do escopo atual

- [ ] Comandos explícitos de energia/mudo na bandeja e validação de volume absoluto por driver.
- [ ] Atalhos globais adicionais, widgets e Quick Settings Android.
- [ ] Captura/espelhamento de tela e eventual transcodificação: recursos distintos, não implementados.
- [ ] Monetização, Apple TV, Roku e automações: propostas sem implementação (`docs/MARKET_STRATEGY.md`).
