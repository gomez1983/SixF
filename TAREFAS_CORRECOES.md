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
