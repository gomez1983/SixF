# 📋 Especificação de Correções e Melhorias — SixF Smart Remote

Documento com os requisitos completos e instruções de arquitetura para implementação imediata.

---

## 1. Correção Crítica da Linha do Tempo e Seek no Chromecast (MKV / Remux / Vídeos Locais)

### Sintoma
- Em filmes longos e episódios de séries (especialmente arquivos `.mkv`), a linha do tempo no aplicativo e na TV fica fragmentada/quebrada.
- O player carrega fatias de poucos segundos aos poucos (como se fosse uma transmissão de live stream contínua).
- Ao tentar arrastar a barra de progresso ou avançar/retroceder, o Chromecast perde a sincronia do buffer, o vídeo congela e a imagem para de ser transmitida para a televisão.

### Causa Raiz
1. **Ausência de Duração no Streaming por Pipe:** O processo do `MediaServerService` ao realizar o remux *on-the-fly* via FFmpeg transmite através de um *pipe* de fragmented MP4 (`-movflags frag_keyframe+empty_moov+default_base_moof -f mp4 pipe:1`). Por ser um pipe contínuo, o servidor HTTP não envia o cabeçalho `Content-Length` nem a tabela de índice de quadros (`moov atom`) no início. O Chromecast interpreta a mídia como *Live Stream* (duração desconhecida) e cria fatias de buffer parciais.
2. **Ausência de Duração no Payload de Metadata:** O comando de carregamento do Google Cast (`MediaInformation`) precisa receber a propriedade `duration` explícita em segundos obtida previamente via `ffprobe` (`MediaDetails.duration`).
3. **Seek Quebrado no Stream Pipe:** Quando o usuário dispara um comando de Seek, o Chromecast tenta solicitar um `HTTP Range` que o *pipe* do FFmpeg não suporta navegar por deslocamento de bytes brutos.

### Soluções Obrigatórias
1. **Injeção da Duração no Google Cast:**
   - Em `lib/controllers/media_cast_controller.dart` e `lib/services/google_cast_media.dart`, enviar obrigatoriamente no payload `MediaInformation` a chave `"duration": details.duration.inSeconds` (ou `inMilliseconds / 1000.0`), além do tipo `streamType: "BUFFERED"` (em vez de `LIVE`).
2. **Seek Nativo no Remux via FFmpeg (`-ss`):**
   - Ao receber um comando de seek em mídia que está em remux, o servidor local deve reiniciar o fluxo de remux passando o parâmetro de entrada rápido `-ss <segundos_desejados>` para o FFmpeg.
   - Assim, o novo stream já nasce sincronizado exatamente no minuto/segundo que o usuário pediu, sem quebrar o buffer do Chromecast.

---

## 2. Limpeza de Redundâncias no Card do Player (Aba "Teclas & Mídia")

### Sintoma
- Na aba *Teclas & Mídia*, o card de reprodução ativa (`MediaSessionControls`) apresenta uma série de botões redundantes e duplicados (botões circulares de Play, Pause, Stop, Avanço e Retrocesso e, logo abaixo, outra fileira de botões retangulares repetindo essas mesmas ações).

### Alterações Obrigatórias
1. **Substituição dos botões circulares de busca:**
   - Remover os botões circulares genéricos de avançar e retroceder.
   - Colocar no lugar deles diretamente os botões dedicados de **Recuar 10 segundos (`-10s`)** e **Avançar 10 segundos (`+10s`)**.
2. **Eliminação dos botões retangulares duplicados:**
   - Remover a linha inferior de botões que repetem *Retomar reprodução (Play)*, *Pausar*, *Parar transmissão (Stop)* e *Próximo arquivo*.
   - **Manter apenas:**
     - Botão de **Repetir arquivo (Loop)**;
     - Botão de **Ordem aleatória (Shuffle)**.
3. **Padrão Estético:**
   - Manter esses dois botões dentro da linguagem visual **Liquid Glass** do projeto (bordas translúcidas, cores sutis do tema e feedback de toque).

---

## 3. Remoção do Card de "Último Comando Executado" (Telemetria/Console)

### Sintoma
- Existe um card de feedback visual que fica mostrando mensagens como `"Último comando executado: Volume Up"`, `"Último comando executado: D-Pad OK"`, etc. Esse card ocupa espaço vertical nobre da interface sem utilidade para o usuário final.

### Alterações Obrigatórias
- Remover a chamada do método `_buildConsoleFeedbackCard()` de `lib/ui/views/remote_view.dart` (tanto na visualização mobile/vertical quanto na coluna lateral de desktop).

---

## 4. Rolagem por Clique e Arraste (Drag to Scroll) na Faixa de Miniaturas da Galeria de Fotos

### Sintoma
- Ao abrir uma pasta com fotos na galeria, a imagem maior é exibida no centro com botões de Próxima/Anterior e, na parte inferior, há uma barra horizontal de mini-previews (miniaturas) das demais imagens.
- No Windows Desktop, não é possível clicar e arrastar essa barra com o mouse para navegar por todas as fotos da pasta.

### Alterações Obrigatórias
- No widget da galeria de fotos (`lib/ui/widgets/media_cast_dialog.dart` ou equivalente), habilitar a rolagem interativa com o mouse configurando um `ScrollConfiguration` com suporte a drag de ponteiros de desktop:
```dart
ScrollConfiguration(
  behavior: ScrollConfiguration.of(context).copyWith(
    dragDevices: {
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
    },
  ),
  child: ListView.builder(
    scrollDirection: Axis.horizontal,
    physics: const BouncingScrollPhysics(),
    // ...
  ),
)
```

---

## 5. Dimensão Inicial da Janela no Windows Desktop (Coluna Única Vertical)

### Sintoma
- Ao abrir o aplicativo no Windows, a janela inicial abre com largura ampla (acima do breakpoint de 840px), ativando o layout de duas colunas lado a lado (*Dual-Pane*), onde o controle físico fica à esquerda e uma segunda coluna fica à direita com atalhos e cards.

### Comportamento Esperado
- O aplicativo deve abrir por padrão em uma **largura esguia de coluna única** (estilo controle remoto vertical / smartphone), onde os elementos ficam empilhados verticalmente e com a navegação por abas na parte inferior.
- A janela não deve iniciar no modo largo lado a lado.

### Alterações Obrigatórias
- No arquivo de inicialização de janela do Windows (`lib/main.dart` e/ou `lib/services/desktop_window_service.dart`), definir o tamanho inicial da janela (`windowOptions` do `window_manager`) para dimensões esguias padrão:
  - **Largura Inicial:** `440.0` (ou `450.0`)
  - **Altura Inicial:** `860.0` (ou `880.0`)
  - **Tamanho Mínimo (`minimumSize`):** `Size(360, 640)`

---

## 6. Garantia de Remoção do Magic Trackpad em Dispositivos sem Suporte

### Regra de Arquitetura
- Em dispositivos que não possuem suporte ao ponteiro (como **Google TV / Chromecast** e **Samsung Tizen**), o botão **Magic Trackpad** deve permanecer **totalmente oculto** na barra de abas inferior (`if (supportsTrackpad)`).
- O botão só deve aparecer quando conectado a TVs **LG webOS**.

---

## 7. Sincronização Fina da Legenda com o Vídeo no Chromecast

### Sintoma
- A legenda WebVTT agora é carregada e ativada corretamente no Chromecast, porém está fora de sincronia em relação ao áudio e à fala dos personagens.

### Plano de Solução
- Investigar se o deslocamento temporal advém do timestamp inicial do vídeo (PTS/DTS offset do container MKV ao extrair com `-c:s webvtt`).
- Implementar suporte a ajuste fino de atraso/avanço de sincronia (offset manual de ±0.5s / ±1s) ou garantir extração com alinhamento absoluto aos timecodes do fluxo de áudio/vídeo.

---

## 8. Overflow de Layout no Card da Biblioteca ao Rodar Imagens no Android (`bottom overflowed by 6.5 pixels`)

### Sintoma
- No Android, ao iniciar a reprodução de imagens/fotos, surge uma faixa listrada em amarelo e preto no card da biblioteca de arquivos (`MediaLibrary` / `MediaCastDialog`) acusando:
  `A RenderFlex overflowed by 6.5 pixels on the bottom.`

### Causa Provável
- Uma `Column` com altura fixa ou restrição de espaço onde os elementos internos (título, botões de ação ou miniaturas) excedem ligeiramente o limite disponível na tela do celular devido a paddings ou alturas não flexíveis (`Expanded` / `SingleChildScrollView` / `Flexible`).

### Soluções Obrigatórias
- Envolver a coluna de conteúdo ou o card afetado em um `SingleChildScrollView` ou utilizar `Flexible`/`Expanded` e ajustar os paddings verticais para acomodar diferentes tamanhos de tela e densidades de pixels sem estourar o layout.

---

## 9. Harmonização Estética dos Botões de Mídia ("Teclas & Mídia")

### Sintoma
- Existe uma disparidade/dessincronização visual nos botões de controle de mídia:
  - Os botões de transporte e busca (Recuar 10s, Pause/Play, Stop, Avançar 10s) estão no formato circular;
  - Logo abaixo, os botões de **Repetir arquivo (Loop)** e **Ordem aleatória (Shuffle)** estão isolados dentro de uma barra/retângulo separado, quebrando a harmonia e o alinhamento da interface.

### Soluções Obrigatórias
- Integrar os botões de Repetir e Shuffle no mesmo agrupamento visual e padrão estético circular/Liquid Glass dos demais controles de transporte, eliminando a caixa retangular isolada e mantendo um conjunto limpo, coeso e harmonioso.

---

## 10. Ausência de Áudio em Arquivos MKV (ex: Episódios do Chaves) no Chromecast

### Sintoma
- Ao reproduzir determinados arquivos MKV de séries (como episódios do Chaves), o vídeo é transmitido normalmente, mas o som **não sai na TV/Chromecast**.

### Causa Provável
- Codec de áudio não suportado nativamente pelo decodificador do Chromecast (por exemplo: áudio em **MP2**, **AC3**, **WMA**, **FLAC** ou faixa de áudio em multicanal sem transcode automático).
- Falha na detecção da necessidade de transcode de áudio ou o remux está copiando o fluxo de áudio incompatível (`-c:a copy`) em vez de recodificar para **AAC estéreo** (`-c:a aac -b:a 192k -ac 2`).

### Soluções Obrigatórias
- Verificar os codecs de áudio aceitos pelo Chromecast em `MediaDetails.isChromecastAudioCompatible`.
- Garantir que qualquer faixa de áudio não nativamente suportada seja forçada para transcodificação AAC stereo durante o remux no `MediaRemuxService`.

---

## 11. Repetir Vídeo Não Repete na TV (volta ao início, mas não reinicia a reprodução)

### Sintoma
- Com um vídeo tocando na televisão e o botão **Repetir** (loop) ativado, ao chegar ao fim o vídeo volta ao começo, mas **não repete**: a reprodução não recomeça.

### Soluções Obrigatórias
- Investigar o fluxo de loop em `MediaCastController` (`toggleLoop`, `isLooping`) e nos drivers de mídia (Google Cast e DLNA): ao terminar o item com loop ativo, o controlador precisa recarregar/dar `play` no mesmo arquivo, e não apenas fazer seek para 0.
- Cobrir com teste: item termina com `isLooping == true` → reprodução reinicia e o estado volta a "tocando".

---

## 12. Login do Google Drive Falha no Android ("falta o ID de cliente OAuth no build")

### Sintoma
- No Android, ao tocar em **Google Drive** na biblioteca de mídia, aparece: "O login do Google Drive não foi concluído nessa versão do SixF (falta o ID de cliente OAuth no build)".

### Causa Provável
- O APK atual (`dist/1.0.6/SixF-1.0.6-Android-teste-payno.apk`) foi gerado com `flutter build apk --debug --no-pub`, **sem** `--dart-define-from-file`. Sem os IDs (`GOOGLE_DESKTOP_CLIENT_ID`/`SECRET`, e `GOOGLE_WEB_CLIENT_ID` para o login nativo), o app mostra essa mensagem (ver `docs/BIBLIOTECA.md` e `lib/services/library_sources.dart`).
- O arquivo local com os IDs existe em `.local-secrets/drive-build.json` (ignorado pelo Git).

### Soluções Obrigatórias
- Passar a gerar o APK (e o Windows) sempre com o arquivo de segredos: `flutter build apk --debug --no-pub --dart-define-from-file=.local-secrets/drive-build.json`.
- Atualizar `docs/DISTRIBUTION.md` para incluir essa flag no procedimento padrão de build.
- Confirmar no aparelho o login do Drive e do OneDrive. Não commitar nem copiar o JSON de segredos para `dist/`.

---

## 13. Botões −/+ e ∨/∧ dos Cards de Volume e Canal: Maiores e com Fundo Branco

### Sintoma
- Na aba **Controle**, os botões circulares de menos/mais (Volume) e de para baixo/para cima (Canal) estão pequenos e discretos, em cinza-claro.

### Soluções Obrigatórias
- Aumentar o diâmetro desses botões (hoje 36 px em `lib/ui/widgets/volume_channel_controls.dart`, função `step`), aproximando-os dos círculos de **Ações rápidas** (48 px).
- Usar o mesmo fundo branco com sombra suave dos botões HOME, MENU, INPUT e EXIT (`AppColors.circleOf` / `softShadowOf`), em vez do cinza atual (`surfaceInteractiveOf`), e ícone escuro nos dois temas.
- Manter a repetição ao segurar o botão e rodar `test/layout_overflow_test.dart` para garantir que os cards não estourem com o botão maior.

---

## 14. Nova Ordem das Abas: Controle, Mídia, Teclas, Apps (Trackpad em 3º na LG)

### Sintoma
- Hoje a ordem das abas é Controle, Teclas, (Trackpad), Mídia, Apps.

### Soluções Obrigatórias
- Trocar Teclas e Mídia de lugar. Sem trackpad (Chromecast, Samsung): **Controle, Mídia, Teclas, Apps**.
- Com TV LG (que tem trackpad): o Trackpad continua na **3ª posição**, ou seja, **Controle, Mídia, Trackpad, Teclas, Apps**. *(Interpretação a confirmar com o desenvolvedor antes de implementar.)*
- A ordem vale na barra inferior (celular), no trilho lateral (paisagem/desktop) e no modo Liquid Glass (`glassTabItems` em `lib/ui/glass/glass_remote_shell.dart`). Em `lib/ui/views/remote_view.dart` o ponto central é `_navItems()`; cuidar para que os índices internos das abas (`_selectedTabIndex` e o `IndexedStack`) continuem apontando para o conteúdo certo.
- Ajustar `test/media_library_navigation_test.dart` (compara a posição de Mídia e Apps) e rodar `test/layout_overflow_test.dart`.

---

## 15. Foto em Tela Cheia no Celular Não Acompanha a Televisão ao Avançar

### Sintoma
- Na aba **Mídia**, com uma foto sendo espelhada na televisão, ao abrir o botão de **tela cheia** o celular mostra a foto em tela cheia.
- Ao avançar/voltar de foto **dentro da tela cheia**, a televisão **continua na foto anterior**. Só quando o usuário sai da tela cheia (volta ao card normal com carrossel) é que a TV passa para a foto escolhida.

### Causa Provável
- `ImageFullscreenViewer` (`lib/ui/widgets/image_fullscreen_viewer.dart`) só devolve o último índice ao fechar (`Navigator.pop<int>`). Em `lib/ui/views/media_library.dart` (por volta da linha 1135), o resultado é aplicado depois, com `_focusEntry(chosen, ...)`. Durante a troca de páginas (`onPageChanged`), nada avisa a biblioteca, então a TV não é atualizada.

### Soluções Obrigatórias
- Adicionar ao viewer um callback (por exemplo `onIndexChanged(LibraryEntry entry)`), chamado a cada `onPageChanged`, e ligá-lo em `media_library.dart` ao mesmo caminho que já espelha a foto na TV (`openPhotoAndMirror` / `_focusEntry`), só quando houver transmissão ativa para a TV.
- Evitar rajada de envios ao deslizar rápido: aplicar *debounce* curto (ou enviar apenas a foto em que o usuário parou) e ignorar respostas fora de ordem.
- Manter o comportamento atual ao fechar a tela cheia (o carrossel fica na última foto vista).
- Cobrir com teste: abrir tela cheia com a TV como destino, avançar uma foto e verificar que o driver recebeu a nova imagem sem sair da tela cheia.

---

## 16. Redesenho da Aba Mídia (navegação de arquivos mais visual)

### Sintoma
- A forma de apresentar imagens, arquivos e a hierarquia de pastas estava confusa: o caminho aparecia como texto ("Meu Drive / Mídia") ao lado de uma seta e, ao abrir uma pasta, o visualizador abria sozinho e escondia os arquivos atrás do aviso "arquivos no carrossel acima".

### Soluções Aplicadas (mockup aprovado em `docs/design/mockups/sixf-midia-mockup.html`)
- Caminho no topo em etapas clicáveis (cada etapa volta direto à pasta), nome da pasta em destaque com a contagem por tipo.
- Raiz com as fontes em cards (Google Drive, OneDrive, pastas deste aparelho) e "Abertas recentemente" (persistidas).
- Subpastas em cards e arquivos em grade de miniaturas (ou lista), filtros por tipo com quantidade, busca e ordenação.
- Seleção por círculos e barra azul de ações (Playlist, Fila, Tocar na TV). Tocar abre/toca no destino escolhido; segurar abre as opções.
- A pasta abre na grade (o visualizador só aparece ao tocar num arquivo). Seções na ordem Arquivos, Playlists, Fila.
- Desktop: árvore de fontes e pastas à esquerda mostrando onde o usuário está.

---

### Status em 11/11/2026
- Itens **11, 13, 14, 15 e 16** implementados, com testes automáticos (o item 11 ainda precisa de confirmação numa TV real).
- Item **12**: procedimento de build corrigido em `docs/DISTRIBUTION.md`; o login do Drive no Android precisa ser confirmado no aparelho.

---

## 17. Login do Google Drive/OneDrive Não Conclui no Galaxy S23 Ultra (Android 14)

### Sintoma
- No S23 Ultra, o fluxo no navegador termina com "Autorização concluída com sucesso", mas ao voltar ao SixF as pastas não aparecem e surge "Não foi possível abrir a pasta". No S9+ (Android 10) o mesmo fluxo funciona.

### Causa Provável (a confirmar no aparelho)
- O código de autorização chega ao SixF enquanto o navegador ainda está na frente e o app, em segundo plano, pode ficar sem rede (restrição de rede em segundo plano do Android 14/One UI). A troca do código pelo acesso (`oauth2.googleapis.com`) falha por erro de rede e o login não é salvo, por isso o app abre o navegador de novo.

### Correção Aplicada
- `lib/services/library_sources.dart`: aguarda o app voltar ao primeiro plano antes de trocar o código; repete a troca até 4 vezes em falha de rede; informa o motivo real (ex.: "sem conexão", "invalid_grant") em vez de mensagem genérica.
- `lib/ui/views/media_library.dart`: mensagem de erro sem repetição, com botão separado "Tentar novamente".
- Pendente: confirmar no S23 Ultra. Se persistir, coletar `adb logcat` do app durante o login.

---

## 18. Faixa Amarela e Preta ("Bottom overflowed by 0.833 pixels") no Card do Vídeo em Paisagem

### Sintoma
- No S23 Ultra deitado, na aba Mídia, com um **vídeo tocando no celular**, o card do player mostrava a faixa de estouro. Com foto, ou com vídeo na TV, não aparecia.

### Causa
- O player local usa os controles do `media_kit`, que pedem ~148 px de altura (barra superior 56 + inferior 56 + linha do tempo 36). Em paisagem o card do vídeo mede 145–176 px; nas alturas de 144 a 148 px, faltava uma fração de pixel.

### Correção (`lib/ui/views/media_library.dart`)
- `compactVideoControlSizes`: em cards com menos de 200 px, as barras dos controles encolhem para sempre caber (`test/video_controls_height_test.dart`). Em tela cheia e em alturas folgadas nada muda.
- Em cards com menos de 96 px os controles internos saem; os botões do painel ao lado continuam.
- Teste de estouro com vídeo tocando em 11 tamanhos e 3 escalas de fonte em `test/media_library_actions_test.dart`.
- Pendente: confirmar no S23 Ultra.
