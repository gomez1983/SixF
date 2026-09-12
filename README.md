# LG Smart TV Remote (Windows & Android)

Um aplicativo moderno, fluido e intuitivo desenvolvido em Flutter para controlar Smart TVs LG (webOS) diretamente pelo computador Windows ou celular Android.

---

## 🚀 Funcionalidades

- **Multiplataforma (Windows e Android)**:
  - **Windows**: Modo janela personalizável, suporte a minimizar para a bandeja do sistema (System Tray) e atalhos de teclado.
  - **Android**: Layout móvel em 3 abas otimizado para celulares de tela grande (ex: Samsung Galaxy S23 Ultra), aproveitando toda a largura da tela sem rolagem vertical excessiva:
    - **Aba 1 (Essenciais)**: D-Pad navegacional com atalhos HDMI 1 e TV Digital, Volume, Troca de Canais, Mute, Home, Menu lateral rápido, Voltar e Exit.
    - **Aba 2 (Teclado & Mídia)**: Teclado numérico completo para canais diretos, botões coloridos de contexto (Vermelho, Verde, Amarelo, Azul) e controles multimídia (Play/Pause, Stop, Avançar, Retroceder).
    - **Aba 3 (Magic Trackpad)**: Superfície de toque expansiva que utiliza quase 100% da tela para emular o mouse / ponteiro do Magic Remote na TV.
  - **Ícones Adaptativos & Themed Icons**: Ícone vetorial com camada `<monochrome>` compatível com a Paleta de Cores do Android 13+ (Material You) e personalização dinâmica do Samsung Good Lock (Theme Park).
  - **Reconexão Inteligente em Segundo Plano**: Ping keep-alive periódico e reconexão silenciosa ao retornar da bandeja de apps abertos.
- **Descoberta Automática na Rede (SSDP)**: Localiza TVs LG conectadas na mesma rede Wi-Fi/Ethernet sem necessidade de digitar IP manualmente.
- **Conexão via WebSocket (webOS SSAP)**: Pareamento seguro com handshake oficial da LG e salvamento de chave para reconexão automática.
- **Wake-on-LAN (WoL)**: Liga a TV desligada enviando Magic Packets pela rede local.
- **Temas**: Suporte a Modo Escuro (Dark) e Claro (Light).

---

## 🛠️ Tecnologias Utilizadas

- **[Flutter](https://flutter.dev/) & [Dart](https://dart.dev/)**: Framework principal para interface e lógica reativa multiplataforma.
- **webOS SSAP (WebSocket)**: Protocolo de comunicação oficial das Smart TVs LG.
- **SSDP / UDP Broadcast**: Protocolos de rede para descoberta de dispositivos e Wake-on-LAN.
- **Pacotes Principais**:
  - `provider`: Gerenciamento de estado reativo da aplicação.
  - `window_manager`: Personalização e controle da janela no Windows.
  - `tray_manager`: Suporte ao ícone e menu na bandeja do sistema (tray) no Windows.
  - `shared_preferences`: Armazenamento local das configurações, IP e chaves de pareamento.
  - `msix`: Empacotamento para distribuição no Windows.

---

## 📋 Como Usar

1. Certifique-se de que a **Smart TV LG** e o seu dispositivo (**PC Windows** ou **Celular Android**) estão conectados na **mesma rede local** (Wi-Fi ou cabo de rede).
2. Na TV, certifique-se de que a opção **"LG Connect Apps"** (ou "Ligar TV via Wi-Fi") esteja ativada nas configurações de rede da TV.
3. Abra o aplicativo:
   - Clique no ícone de **Rede/Dispositivos** no topo para escanear e selecionar sua TV.
   - Na primeira conexão, aparecerá um pedido de confirmação na tela da TV: selecione **Permitir** usando o controle original.
4. Pronto! O controle estará conectado e pronto para uso.
