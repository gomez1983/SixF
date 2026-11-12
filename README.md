# SixF Remote — Windows e Android

Controle de TVs LG webOS, Samsung Tizen e Chromecast com Google TV pela rede local, desenvolvido com Flutter/Provider. O driver Google TV usa Android TV Remote Service v2; Chromecast clássico (somente Cast) não é suportado como controle. Não há projeto iOS neste repositório.

## Recursos

- **Aparelhos:** dispositivos salvos, conexão por aparelho e alternância entre sessões; descoberta SSDP, pareamento na TV e diagnóstico de conexão (toque no status do cabeçalho).
- **Controle:** faixas de atalhos configuráveis (segure um botão para trocar), Volume e Canal em pílulas, Mudo, Voz e D-pad com Voltar, TV Digital e HDMI 1 onde o aparelho tem essas entradas. D-pad, volume e canais repetem ao segurar.
- **Mídia:** Google Drive, OneDrive e pastas locais; fila temporária e playlists; visualizador de fotos e vídeos; controles da sessão na TV (play/pausa, anterior/próximo, ±10 s, repetir, aleatório, legenda e faixa de áudio). Transmissão de arquivos, sem espelhamento de tela.
- **Teclas:** teclado numérico e botões coloridos. **Trackpad:** somente LG.
- **Apps:** lista da TV (LG), catálogo (Samsung) e, no Chromecast, apps instalados via ADB opcional; busca e favoritos por aparelho.
- **Windows:** bandeja, atalhos de teclado com a janela em foco e modo compacto sempre visível.
- **Visual:** padrão ZIXO (grafite, vidro fosco, Open Sans), tema claro e escuro, feedback háptico.

## Primeiro uso

1. Ligue a TV e mantenha TV e computador/celular na mesma rede local.
2. Abra a busca de TVs, selecione o aparelho e aceite o pedido exibido na TV. Se solicitado, informe o PIN.
3. Confira o IP nas configurações se a descoberta não encontrar o aparelho. No Windows, permita o SixF em redes privadas no firewall.
4. Para ligar por Wake-on-LAN, configure o MAC real e habilite a função correspondente na TV. Disponibilidade depende do modelo/rede.

## Chromecast com Google TV

Na busca, selecione o Chromecast e informe no SixF o código hexadecimal de 6 caracteres exibido na TV. Se a rede bloquear a descoberta, informe o IP e selecione Google TV nas configurações. As credenciais são salvas por aparelho e reutilizadas ao reconectar.

Controle (setas/OK, voltar, Home, reprodução, digitação, voz) usa o Remote Service v2 (portas 6466/6467). Fotos e vídeos usam Google Cast com o receptor de mídia padrão. A lista de apps instalados exige ativar a Depuração por Wi-Fi no Chromecast; o painel passo a passo fica na aba Apps e o controle funciona sem ela. Em Configurações, "Controlar volume de" direciona volume/mudo para uma TV salva enquanto o Chromecast está selecionado.

## Mídia e limites

"Mídia enviada" significa aceitação do comando, não reprodução comprovada. Progresso, avanço e repetição só aparecem conforme as informações da TV; modelos que não informam ações suportadas podem ter controles indisponíveis. Codecs e compatibilidade precisam de validação nos modelos físicos.

As chaves de pareamento ficam em SharedPreferences, separadas por marca/IP. A URL de cada transmissão tem token aleatório e é revogada ao parar ou trocar o arquivo; use rede local confiável.

## Desenvolvimento e validação

Ambiente validado: Flutter 3.47.3 / Dart 3.13.3. Os builds usam o arquivo de segredos local (ignorado pelo Git), sem o qual o login do Google Drive/OneDrive não funciona:

    flutter pub get
    dart run tool/check_release.dart
    flutter analyze --no-pub
    flutter test --no-pub
    flutter build windows --release --dart-define-from-file=.local-secrets/drive-build.json
    flutter build apk --release --dart-define-from-file=.local-secrets/drive-build.json

Regras para agentes de IA (builds, commits, post-mortems): `AGENTS.md`. Versão canônica: `pubspec.yaml`. Distribuição e assinatura: `docs/DISTRIBUTION.md`. Biblioteca de mídia e OAuth: `docs/BIBLIOTECA.md`. Estado e próximos passos: `ROADMAP.md`. Visual: `docs/design/`.
