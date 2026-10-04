---
tags:
  - ia
  - post-mortem
  - projeto
  - dlna
  - webos
  - upnp
  - network
cssclass: ai-note
projeto: "SixF Smart Remote"
status: resolvido
data: 2026-10-03
severidade: media
componente: "Media Cast / DLNA / SSAP WebSocket"
---

# Post-Mortem: BPM-003 — Recusa de Conexão (Errno 1225) por Portas Efêmeras SSDP e Arquitetura Dual Channel na Transmissão de Mídia

- **Projeto Relacionado:** SixF Smart Remote
- **Data do Incidente:** 2026-10-03
- **Severidade:** Média
- **Status:** Resolvido

---

## 1. Sintoma e Comportamento Observado
Ao tentar transmitir fotos ou vídeos locais do aplicativo para a Smart TV LG (IP `192.168.15.2`), o aplicativo disparava o seletor de mídia e o servidor HTTP local iniciava normalmente, mas a TV rejeitava imediatamente a conexão de controle com os seguintes erros na interface:

- **Transmissão de Imagem:**
```text
Falha de rede com a Smart TV (Socket: O computador remoto recusou a conexão de rede (OS Error: O computador remoto recusou a conexão de rede, errno = 1225), address = 192.168.15.2, port = 54590)
```

- **Transmissão de Vídeo:**
```text
Falha de rede com a Smart TV (Socket: O computador remoto recusou a conexão de rede (OS Error: O computador remoto recusou a conexão de rede, errno = 1225), address = 192.168.15.2, port = 49295)
```

---

## 2. Hipótese Incorreta da IA (Anti-Padrão)
- **Anti-Padrão 1 (Confiança Cega no SSDP `LOCATION`):** A IA assumiu inicialmente que qualquer URL contida no cabeçalho `LOCATION` da resposta SSDP (ex: `http://192.168.15.2:54590/dial/dd.xml` ou `49295/second-screen`) pertencia ao renderizador DLNA/UPnP e estava apta a receber comandos SOAP HTTP POST de `SetAVTransportURI`.
- **Anti-Padrão 2 (Ignorar o Canal Nativo já Autenticado):** Tentar forçar o protocolo UPnP aberto mesmo quando a TV LG já possuía uma sessão WebSocket SSAP (portas 3000/3001) ativa e autenticada com permissão de lançador de mídia (`media.viewer`).

---

## 3. Causa Raiz Real (Root Cause)
1. **Portas Efêmeras de Serviços Secundários:** O broadcast SSDP captura respostas de diversos serviços UPnP/DIAL anunciados pela Smart TV. Alguns desses serviços rodam em portas TCP dinâmicas e efêmeras (`54590`, `49295`). O kernel do webOS não roda servidores SOAP de controle de mídia nessas portas secundárias, fechando ativamente qualquer tentativa de conexão TCP (`WSAECONNREFUSED` / `errno = 1225`).
2. **Portas Reais de Mídia na LG webOS:** O endpoint permanente de AVTransport DLNA da LG roda exclusivamente na porta **19531** (`http://ip:19531/udap/api/data?target=avtransport.xml`) ou na porta **8080** (`http://ip:8080/avt`).
3. **Comportamento em Imagens Estáticas:** Ao enviar fotos, o comando de velocidade `Play(Speed=1)` causava erro SOAP `701 (Transition not available)` porque fotos no webOS são renderizadas estaticamente logo no `SetAVTransportURI`.

---

## 4. Solução Definitiva: Arquitetura Dual Channel

Implementou-se uma estratégia de dois níveis de transmissão com fallback automático e probe de validação de portas:

1. **Canal 1 — Driver Nativo SSAP (Prioritário):**
   - Se a Smart TV LG já estiver conectada ao SixF via `LgWebOsDriver`, o aplicativo envia o comando nativo `ssap://media.viewer/open` (com fallback para `ssap://system.launcher/open`).
   - A TV abre o visualizador de fotos/vídeos oficial em tela cheia instantaneamente sem depender de portas UPnP ou negociações SOAP.

2. **Canal 2 — DLNA AVTransport com Auto-Probe e Fallback de Portas (Universal):**
   - Se a TV não estiver conectada via driver ou for Samsung Tizen, o `DlnaService.resolveRenderer` realiza um teste de probe antes de aceitar qualquer endpoint.
   - Caso a porta anunciada no SSDP seja efêmera ou recuse conexão TCP (`errno = 1225`), ela é sumariamente descartada e o serviço redireciona para as portas oficiais:
     - **LG webOS:** `19531` e `8080`
     - **Samsung Tizen:** `9197` e `7676`
   - O comando `Play` só é disparado para vídeos e áudios, preservando a renderização imediata de fotos.

3. **Unificação dos Controles de Mídia:**
   - Os métodos `pause()`, `play()` e `stop()` no `MediaCastController` foram adaptados para despachar teclas nativas (`RemoteKey.pause`, `RemoteKey.play`, `RemoteKey.stop`, `RemoteKey.back`) quando operando via driver conectado, mantendo paridade com o DLNA.

```dart
// lib/controllers/media_cast_controller.dart
if (activeDriver != null && activeDriver.isConnected) {
  final nativeSuccess = await activeDriver.openMediaUrl(
    mediaUrl,
    title: _currentFileName ?? 'Mídia SixF',
    mimeType: _currentMimeType,
  );
  if (nativeSuccess) {
    _status = MediaCastStatus.playing;
    notifyListeners();
    return true;
  }
}

// Fallback DLNA com probe de portas reais
final renderer = await DlnaService.resolveRenderer(
  targetTvIp,
  locationUrl: locationUrl,
  brand: brand,
);
```

---

## 5. Limitação Observada em Vídeos no webOS Legado (2.1 / LF5900) e Próximos Passos
- **Comportamento Observado:**
  - **Fotos:** Funcionam de maneira instantânea e confiável via canal SSAP (`media.viewer/open`).
  - **Vídeos:** Em webOS 2.1.0-3163 (LG 49LF5900-SA), o sistema abre a interface de reprodução (SmartShare / Media Viewer), mas a decodificação/buffer do arquivo de vídeo local não inicia ou falha silenciosamente sem disparar o playback.
- **Hipóteses Levantadas para Resolução Futura:**
  1. **Codec / Transcoding:** A TV LG webOS 2.0/2.1 pode exigir perfis de container específicos (ex: baseline H.264 profile sem áudio AAC de múltiplos canais) ou rejeitar Content-Type/protocolInfo que modelos mais recentes (webOS 3.0+) aceitam com folga.
  2. **Certificado ou Cabeçalhos HTTP do Servidor:** Algumas versões antigas do NetCast / webOS 2.0 rejeitam servidores HTTP sem cabeçalhos UPnP específicos (`transferMode.dlna.org: Streaming` e `contentFeatures.dlna.org`).
  3. **Permissão do App Nativo:** O endpoint `media.viewer/open` no webOS 2 pode exigir registro prévio de chave com permissão explícita de `media.controls` concedida pela TV durante o primeiro pareamento.
- **Decisão:** Pausar a depuração de reprodução de vídeo para este modelo legado e focar nas próximas frentes do Roadmap. A transmissão de fotos e o controle remoto permanecem 100% funcionais e estáveis.

---

## 6. Regra Preventiva
- *Regra 1:* **Nunca enviar requisições de controle DLNA/SOAP para portas efêmeras (>40000) capturadas no SSDP sem probe prévio; no ecossistema LG webOS, prefira sempre o canal nativo SSAP (`media.viewer/open`) ou as portas permanentes `19531` / `8080`.**
- *Regra 2:* **Em streaming DLNA para Smart TVs, fotos não devem receber o comando `Play(Speed=1)` após o `SetAVTransportURI`, sob risco de erro UPnP 701.**
- *Regra 3:* **Para Smart TVs LG de geração legada (webOS 2.x), a transmissão de vídeo requer validação rigorosa de cabeçalhos de streaming DLNA (`transferMode`) e compatibilidade de codecs de vídeo antes de forçar o playback.**
