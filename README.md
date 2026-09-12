# LG Smart TV Remote (Windows)

Um aplicativo desktop moderno e intuitivo desenvolvido em Flutter para controlar Smart TVs LG (webOS) diretamente pelo computador Windows.

---

## 🚀 Funcionalidades

- **Descoberta Automática na Rede (SSDP)**: Localiza TVs LG conectadas na mesma rede Wi-Fi/Ethernet sem necessidade de digitar IP manualmente.
- **Conexão via WebSocket (webOS SSAP)**: Pareamento seguro com handshake oficial da LG e salvamento de chave para reconexão automática.
- **Wake-on-LAN (WoL)**: Liga a TV desligada enviando Magic Packets pela rede local.
- **Controles Completos**:
  - **Navegação**: Teclado direcional (D-Pad), botão OK/Enter, Voltar, Home e Menu.
  - **Volume e Canais**: Aumentar/diminuir volume, mudo, troca de canais e teclado numérico.
  - **Multimídia**: Play, Pause, Stop, Avançar e Retroceder.
  - **Cores & Atalhos Rápidos**: Botões coloridos (Vermelho, Verde, Amarelo e Azul) usados em apps e canais.
  - **Trackpad / Mouse Virtual**: Controle de cursor tipo Magic Remote na tela da TV.
- **Integração com Windows**:
  - **Bandeja do Sistema (System Tray)**: Minimiza para a bandeja do relógio em segundo plano sem poluir a barra de tarefas.
  - **Atalhos de Teclado**: Controle rápido de volume e mídia pelo teclado do PC.
- **Temas**: Suporte a Modo Escuro (Dark) e Claro (Light).

---

## 🛠️ Tecnologias Utilizadas

- **[Flutter](https://flutter.dev/) & [Dart](https://dart.dev/)**: Framework principal para interface e lógica reativa multiplataforma.
- **webOS SSAP (WebSocket)**: Protocolo de comunicação oficial das Smart TVs LG.
- **SSDP / UDP Broadcast**: Protocolos de rede para descoberta de dispositivos e Wake-on-LAN.
- **Pacotes Principais**:
  - `provider`: Gerenciamento de estado reativo da aplicação.
  - `window_manager`: Personalização e controle da janela no Windows.
  - `tray_manager`: Suporte ao ícone e menu na bandeja do sistema (tray).
  - `shared_preferences`: Armazenamento local das configurações, IP e chaves de pareamento.
  - `msix`: Empacotamento para distribuição no Windows.

---

## 📋 Como Usar

1. Certifique-se de que a **Smart TV LG** e o seu **computador** estão conectados na **mesma rede local** (Wi-Fi ou cabo de rede).
2. Na TV, certifique-se de que a opção **"LG Connect Apps"** (ou "Ligar TV via Wi-Fi") esteja ativada nas configurações de rede da TV.
3. Abra o aplicativo:
   - Clique no ícone de **Rede/Dispositivos** no topo para escanear e selecionar sua TV.
   - Na primeira conexão, aparecerá um pedido de confirmação na tela da TV: selecione **Permitir** usando o controle original.
4. Pronto! O controle estará conectado e pronto para uso.
