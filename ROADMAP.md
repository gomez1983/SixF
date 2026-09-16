# 🗺️ Roadmap de Atualizações - SixF Smart Remote (Antigo controle_LG)

Este documento centraliza o planejamento estratégico e a evolução do aplicativo, marcando a transição de um controle exclusivo para webOS (LG) em direção ao SixF (abreviação de Six Finger — múltiplos controles e dispositivos na ponta dos dedos), um controle universal inteligente para Windows e Android focado nas plataformas líderes (LG webOS e Samsung Tizen).

---

### 🎨 Legenda de Status:
- [x] [Título em Azul](#): Alterações já concluídas e comitadas no Git.
> - [x] Título em Verde: Alterações implementadas no código local, mas ainda não comitadas.
- [ ] **Título em Laranja**: Alterações planejadas (ainda não processadas).

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

### 🌟 Fase 1: Rebranding SixF & Expansão de Marcas (v0.9.5 Beta) — PRIORIDADE IMEDIATA
- [x] [Rebranding & Nova Identidade Visual (SixF)](#):
  - Oficialização do nome SixF (Six Finger — todos os seus controles na ponta dos dedos).
  - Criação de novo logotipo/ícone moderno estilizado com a marca SixF (neutro e tecnológico) compatível com Windows e Android (Adaptive Icons / Material You / Themed Icons).
  - Atualização dos metadados de projeto (pubspec.yaml, manifests Android/Windows, títulos de janela e strings de UI).
- [x] [Refatoração da Camada de Abstração (Driver / Adapter Pattern)](#):
  - Criação de uma interface base agnóstica (TvDriver) para comandos padronizados (sendKey, volumeUp, openApp, mouseMove).
  - Isolamento do driver atual da LG em um módulo específico (LgWebOsDriver).
  - Criação de DriverFactory, AndroidTvDriver e SamsungTizenDriver desacoplando o RemoteController.
- [x] [Expansão de Marcas e Protocolos (Samsung Tizen e LG webOS Estável)](#):
  - ~~Chromecast e Google TV / Android TV (Sony, TCL, Philips, Xiaomi)~~ [DESCONTINUADO / ABANDONADO]:
    - *Desvio de rota:* As especificações recentes do protocolo Google Cast / Android TV Remote v2 apresentaram instabilidades frequentes de handshake TLS e expiração forçada de sessão pelo ecossistema Google. A funcionalidade foi abandonada para manter a confiabilidade e robustez do app.
  - Samsung Smart TV (Tizen OS):
    - Protocolo WebSocket Tizen (portas 8001/8002 com chave/token e handshake na tela).
- [x] [Seletor de Marca & Detecção Automática no Escaneamento](#):
  - Descoberta unificada na rede local (SSDP para LG e Samsung, e varredura de portas 8001/3000) permitindo selecionar e parear com as marcas suportadas.
  - Seletor rápido de marcas (LG webOS e Samsung Tizen) na barra lateral e crachás de identificação visual no popup de busca.

---

### 🌐 Fase 2: Experiência Móvel & Conexões Simultâneas (v0.9.8 Beta)
- [x] [Feedback Háptico (Vibração)](#):
  - Resposta tátil com impacto físico suave ao tocar nos botões no Android.
  - Pulso firme de impacto médio dedicado para alternar energia (Power) e cliques discretos no trackpad e abas.
  - Chave de ativação/desativação no menu de configurações com persistência local.
- [x] [Gaveta / Atalhos de Aplicativos](#):
  - Listar apps instalados no dispositivo conectado para abertura direta com busca instantânea e grade interativa.
  - Suporte dinâmico em tempo real via SSAP na LG webOS (`listLaunchPoints`) e catálogo curado dos principais streamings na Samsung Tizen.
  - 4ª aba dedicada no layout mobile ("Apps"), card integrado no painel Desktop dual-pane e feedback háptico ao abrir.
- [ ] **Conexão Simultânea & Alternância Rápida (Multi-Device)**:
  - Manter 2 ou mais dispositivos conectados ativamente em segundo plano (ex: TV LG + Chromecast 4K na mesma sala).
  - Aba/Pills de alternância rápida no topo da tela para trocar o controle ativo com 1 clique.
- [ ] **Múltiplos Dispositivos Salvos**:
  - Salvar lista de dispositivos com apelidos (ex: Sala, Quarto) para reconexão rápida.
- [ ] **Entrada de Texto Remota**:
  - Digitação via teclado do celular/PC enviada diretamente para o dispositivo ativo.

---

### ⚡ Fase 3: Recursos Avançados & Integrações (v0.9.9 Release Candidate)
- [ ] **Android Quick Settings & Widgets**:
  - Bloco de Ação Rápida (Quick Settings Tile) na barra de notificações para Ligar/Desligar e Mute.
  - Widget para a tela inicial do Android.
- [ ] **Atalhos Globais no Windows**:
  - Teclas de atalho para atuar no segundo plano / bandeja do sistema.
- [ ] **Conexão por IP Manual**:
  - Inclusão manual para redes corporativas, sub-redes separadas ou VLANs.

---

### 💡 Ideias Futuras / Backlog (Pós v1.0)
- [ ] **Suporte a Apple TV**:
  - Integração via protocolo companion / pyatv.
- [ ] **Suporte a Roku OS**:
  - Protocolo ECP (External Control Protocol) via HTTP.
- [ ] **Integração com Automações**:
  - Suporte a Home Assistant e integração MQTT.
- [ ] **Controle por Voz**:
  - Reconhecimento de voz integrado ao app mobile.
