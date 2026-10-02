# 💼 SixF - Inteligência de Mercado, Precificação & Diferenciais Competitivos

Este documento consolida o estudo estratégico de mercado, modelos de monetização, análise de concorrentes e planejamento de diferenciais para o lançamento do **SixF** nas lojas oficiais (**Google Play Store, Apple App Store e Microsoft Store**).

---

## 🔍 1. Raio-X dos Concorrentes de Mercado

Análise dos principais aplicativos da categoria (*Universal TV Remote Control by BoostVision*, *TVRem*, *Remotie*, *AirBeam*, etc.):

### O Modelo de Cobrança Predatório dos Concorrentes:
- **Assinaturas Semanais/Mensais:**
  - Cobram entre **R$ 14,90 a R$ 24,90 por semana** (ou **US$ 3.99 a US$ 4.99/semana**).
  - Assinatura Anual: entre **R$ 89,90 e R$ 159,90/ano**.
- **Opção Vitalícia (Lifetime) Rara:**
  - Poucos oferecem pagamento único. Quando oferecem, cobram entre **R$ 69,90 e R$ 149,90** (US$ 19.99 a US$ 29.99).
- **A Experiência Gratuita dos Concorrentes:**
  - Extremamente agressiva: vídeos publicitários em tela cheia (interstitials de 30 segundos) a cada 2 a 4 toques no controle, gerando grande insatisfação e avaliações de 1 estrela de usuários frustrados.

---

## 💎 2. Onde o SixF já Supera a Concorrência?

1. **Multiplataforma Real (Windows + Android + iOS)**:
   - Quase 100% dos concorrentes existem **apenas** para celular. O SixF roda nativamente no Windows com bandeja de sistema (*System Tray*), atalhos de teclado físico e layout adaptativo Dual-Pane.
2. **Zero Anúncios Invasivos**:
   - Interface limpa, responsiva e focada em utilidade pura. Sem SDKs pesados de anúncios que drenam bateria e travam a conexão.
3. **Hardware-Grade Feedback Háptico**:
   - Sensação tátil refinada e realista de clique mecânico em cada botão e chave de desligamento.
4. **Resiliência em Segundo Plano**:
   - Keep-alive agressivo de 5s e reconexão automática transparente (`autoReconnectIfNeeded`).

---

## 🚀 3. Funcionalidades de Maior Atratividade Comercial (Prioridades)

### 🥇 Prioridade Máxima: Screen Mirroring & Transmissão de Mídia (Media Cast)
- **Por que é tão valioso?**
  - É a funcionalidade número #1 que os concorrentes usam para converter usuários em pagantes.
  - Permite espelhar a tela do celular/computador ou transmitir fotos e vídeos locais da galeria diretamente para a TV.
  - **Viabilidade Técnica**: Tanto a LG (webOS) quanto a Samsung (Tizen) possuem receptores nativos via DLNA/UPnP e protocolos de mídia WebSocket na rede local, sem necessidade de servidores intermediários na nuvem.

### 🥈 Prioridade Alta: Widgets e Quick Settings (Android / Windows)
- **Controle sem abrir o app**:
  - Widget compacto para a tela inicial do celular com botões essenciais: *Power*, *Volume* e *Mute*.
  - Bloco de Ação Rápida (*Quick Settings Tile*) na cortina de notificações do Android.
  - Mini-janela flutuante ou barra compacta no Windows.

### 🥉 Prioridade Média: Multi-Dispositivo com Troca Instantânea (1-Tap Switching)
- Barra de abas/pills no topo para alternar em 1 segundo entre a TV da Sala (LG webOS) e a TV do Quarto (Samsung Tizen), com ambas conectadas em segundo plano.

---

## 🏷️ 4. Estratégia de Precificação Justa (O Diferencial Matador)

### Modelo: **Freemium com Desbloqueio Único Vitalício (Lifetime IAP)**
- **Download Gratuito**: Funções essenciais liberadas (D-Pad, Teclado, Volume, Mudo, Power). Gera confiança imediata e elimina pedidos de reembolso.
- **Compra Única (In-App Purchase)**: Desbloqueia recursos avançados (Screen Mirroring, Transmissão de Mídia, Comandos de Voz Avançados, Widgets e Sem Limites).

### Tabela de Preços Recomendada:

| Mercado | Preço Vitalício Sugerido | Percepção do Usuário |
| :--- | :--- | :--- |
| 🇧🇷 **Brasil (Google Play / Microsoft / App Store)** | **R$ 14,90 a R$ 19,90** *(pagamento único)* | Enquanto concorrentes cobram R$ 19 **por semana**, o SixF cobra R$ 19 **para sempre**. O valor se torna uma compra de impulso irresistível. |
| 🇺🇸 **Exterior (EUA / Internacional)** | **US$ 3.99 a US$ 4.99** *(pagamento único)* | Preço no padrão "coffee price" para utilitários de alta qualidade, maximizando volume e nota nas lojas. |

---

## 🗺️ 5. Plano de Implementação Técnica

1. **Fase Atual (v0.9.8)**:
   - Polimento final dos comandos de voz e push-to-talk.
2. **Próxima Fase (v1.0.0 - Lançamento Comercial)**:
   - Implementação do módulo **Media Casting & Screen Mirroring** (transmissão de fotos/vídeos locais e espelhamento DLNA/WebSocket).
   - Integração com o SDK de Compras no App (`in_app_purchase`).
   - Widgets para Android e Windows.
