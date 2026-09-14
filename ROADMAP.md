# 🗺️ Roadmap de Atualizações - SixF Smart Remote (Antigo controle_LG)

Este documento centraliza o planejamento estratégico e a evolução do aplicativo, marcando a transição de um controle exclusivo para webOS (LG) em direção ao **SixF** (abreviação de *Six Finger* — múltiplos controles e dispositivos na ponta dos dedos), um controle universal inteligente para Windows e Android (LG, Chromecast / Google TV, Samsung Tizen, Sony e TCL).

---

## 📌 Status Atual: v0.9.0 (Estágio Beta / Base LG webOS Estável)
- [x] [Suporte Multiplataforma (Windows com bandeja do sistema e Android)](#)
- [x] [Layout mobile otimizado em 3 abas (Essenciais, Teclado/Mídia e Magic Trackpad)](#)
- [x] [Suporte a Ícone Adaptativo / Material You / Themed Icons no Android](#)
- [x] [Descoberta de TVs via SSDP e pareamento seguro via WebSocket (webOS SSAP)](#)
- [x] [Wake-on-LAN (WoL) para ligar a TV via rede local](#)
- [x] [Reconexão inteligente e ping keep-alive em segundo plano](#)
- [x] [Temas Claro (Light) e Escuro (Dark)](#)

---

## 🚀 Fases Planejadas

### 🌟 Fase 1: Rebranding SixF & Expansão de Marcas (v0.9.5 Beta) — *PRIORIDADE IMEDIATA*
- [x] [Rebranding & Nova Identidade Visual (SixF)](#):
  - Oficialização do nome **SixF** (*Six Finger* — todos os seus controles na ponta dos dedos).
  - Criação de novo logotipo/ícone moderno estilizado com a marca **SixF** (neutro e tecnológico) compatível com Windows e Android (Adaptive Icons / Material You / Themed Icons).
  - Atualização dos metadados de projeto (`pubspec.yaml`, manifests Android/Windows, títulos de janela e strings de UI).
- [x] [Refatoração da Camada de Abstração (Driver / Adapter Pattern)](#):
  - Criação de uma interface base agnóstica (`TvDriver`) para comandos padronizados (`sendKey`, `volumeUp`, `openApp`, `mouseMove`).
  - Isolamento do driver atual da LG em um módulo específico (`LgWebOsDriver`).
  - Criação de `DriverFactory`, `AndroidTvDriver` e `SamsungTizenDriver` desacoplando o `RemoteController`.
- [ ] **Expansão de Marcas e Protocolos (Um dispositivo conectado por vez)**:
  - **Chromecast & Google TV / Android TV (Sony, TCL, Philips, Xiaomi)**:
    - Suporte a Chromecast com Google TV (4K / HD) via *Android TV Remote Service v2* (pareamento com código PIN na tela, D-Pad, atalhos e volume).
    - Suporte a Chromecast Clássico (Cast v2) para controle de mídia e volume.
  - **Samsung Smart TV (Tizen OS)**:
    - Protocolo WebSocket Tizen (portas 8001/8002 com chave/token e handshake na tela).
- [ ] **Seletor de Marca & Detecção Automática no Escaneamento**:
  - Descoberta unificada na rede local (SSDP para LG, mDNS para Chromecast/Google TV e Samsung) permitindo selecionar e parear com qualquer marca suportada.

---

### 🌐 Fase 2: Experiência Móvel & Conexões Simultâneas (v0.9.8 Beta)
- [ ] **Conexão Simultânea & Alternância Rápida (Multi-Device)**:
  - Manter 2 ou mais dispositivos conectados ativamente em segundo plano (ex: **TV LG** + **Chromecast 4K** na mesma sala).
  - Aba/Pills de alternância rápida no topo da tela para trocar o controle ativo com 1 clique.
- [ ] **Múltiplos Dispositivos Salvos**:
  - Salvar lista de dispositivos com apelidos (ex: *Sala*, *Quarto*) para reconexão rápida.
- [ ] **Feedback Háptico (Vibração)**: Resposta tátil sutil ao tocar nos botões no Android.
- [ ] **Gaveta / Atalhos de Aplicativos**: Listar apps instalados no dispositivo conectado para abertura direta.
- [ ] **Entrada de Texto Remota**: Digitação via teclado do celular/PC enviada diretamente para o dispositivo ativo.

---

### ⚡ Fase 3: Recursos Avançados & Integrações (v0.9.9 Release Candidate)
- [ ] **Android Quick Settings & Widgets**:
  - Bloco de Ação Rápida (Quick Settings Tile) na barra de notificações para Ligar/Desligar e Mute.
  - Widget para a tela inicial do Android.
- [ ] **Atalhos Globais no Windows**:
  - Teclas de atalho para atuar no segundo plano / bandeja do sistema.
- [ ] **Conexão por IP Manual**: Inclusão manual para redes corporativas, sub-redes separadas ou VLANs.

---

### 📦 Fase 4: Lançamento Oficial nas Lojas (v1.0.0 Oficial / GA)
- [ ] **Microsoft Store (Windows)**:
  - Empacotamento `.msix` assinado com o novo nome/marca universal.
- [ ] **Google Play Store (Android)**:
  - Pacote `.aab` de produção.
  - Enxoval gráfico da loja (ícone 512x512, banner 1024x500 e capturas de tela demonstrando controle multi-marcas).
  - Período de teste fechado (14 dias com 20 testadores) e publicação oficial.

---

> *Nota: Este roadmap é iterativo e pode ser adaptado com base nas necessidades e feedbacks de uso.*
