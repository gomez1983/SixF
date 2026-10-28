```markdown
# SixF Remote — Windows e Android

Controle de TVs LG webOS, Samsung Tizen e Chromecast com Google TV pela rede local, desenvolvido com Flutter/Provider. O driver Google TV usa Android TV Remote Service v2; Chromecast clássico (somente Cast) não é suportado como controle. Não há projeto iOS neste repositório.

## Recursos implementados

- Dispositivos salvos, conexão por aparelho e alternância entre sessões.
- Descoberta SSDP, pareamento na TV e diagnóstico de conexão: toque no status do cabeçalho.
- D-Pad, volume e canais com repetição ao segurar quando conectado. Setas e teclas de volume numéricas aceitam repetição do teclado; comandos como Power e Mute não repetem.
- Apps: lista LG e catálogo Samsung, pesquisa e favoritos separados por aparelho. Toque na estrela para favoritar; use o filtro Favoritos.
- Windows: bandeja, atalhos com a janela em foco e modo compacto sempre visível. O botão Modo compacto fica no cabeçalho; Sair do modo compacto restaura a janela.
- Mobile: Controle, Teclas & Mídia, Apps e, somente na LG, Magic Trackpad. HDMI 1 e TV Digital aparecem apenas onde implementados.
- Transmissão de arquivos locais (fotos, vídeos e áudio). Isto não captura nem espelha a tela.
- Tema claro/escuro, feedback háptico e voz conforme suporte da plataforma.

## Primeiro uso

1. Ligue a TV e mantenha TV e computador/celular na mesma rede local.
2. Abra a busca de TVs, selecione o aparelho e aceite o pedido exibido na TV. Se solicitado, informe o PIN.
3. Confira o IP nas configurações se a descoberta não encontrar o aparelho. No Windows, permita o SixF em redes privadas no firewall.
4. Para ligar por Wake-on-LAN, configure o MAC real e habilite a função correspondente na TV. Disponibilidade depende do modelo/rede.

## Chromecast com Google TV

Na busca, selecione o Chromecast e informe no SixF o código hexadecimal de 6 caracteres exibido na TV. Se a rede bloquear descoberta, informe o IP e selecione Google TV nas configurações. As credenciais são salvas por aparelho e reutilizadas ao reconectar; não é necessário ADB nem modo desenvolvedor.

Inclui setas/OK, voltar, Home, configurações, reprodução, digitação em campos abertos e atalhos YouTube/Netflix. Esses atalhos não são uma lista de apps instalados. Nas configurações, Controlar volume de permite direcionar volume/mudo à TV salva enquanto o Chromecast fica selecionado. A TV precisa estar conectada; com uma única TV salva ela é selecionada por padrão. Volume/energia enviados ao Chromecast dependem da configuração de áudio e HDMI-CEC; comandos via rede não reproduzem o infravermelho do controle físico. Para controlar a LG diretamente, selecione sua sessão salva. O botão de microfone envia áudio PCM ao Google TV enquanto a escuta estiver aberta. É necessário permitir o microfone no Windows/Android.

Validação automatizada cobre TLS mútuo, pareamento, reconexão e comandos. Homologação no Chromecast físico ainda pendente. Referência do protocolo: https://github.com/tronikos/androidtvremote2 (Remote Service: 6466/6467, distinto de Google Cast 8009).

Fotos e vídeos locais destinados ao Chromecast usam Google Cast e o receptor de mídia padrão. A lista completa de apps instalados permanece indisponível sem integração auxiliar ou depuração, opções recusadas pelo usuário; a interface identifica explicitamente os atalhos.

## Mídia e limites

“Mídia enviada” significa aceitação do comando, não reprodução comprovada. No DLNA, reprodução e pausa são confirmadas pela TV quando ela informa o estado. No canal nativo, Play/Pause são comandos enviados.

Progresso, avanço e repetição só aparecem conforme as informações da TV. Modelos que não informam ações suportadas podem ter controles indisponíveis. Fotos não recebem Play. Codecs e compatibilidade precisam de validação nos modelos físicos.

As chaves de pareamento permanecem em SharedPreferences, separadas por marca/IP. A URL de cada transmissão tem token aleatório e é revogada ao parar ou trocar o arquivo; use rede local confiável. Troca de IP pode exigir novo pareamento. O cadastro legado predefinido ainda pode existir: revise os dados antes de conectar.

## Desenvolvimento e validação

Ambiente validado: Flutter 3.47.3 / Dart 3.13.3.

    flutter pub get
    dart run tool/check_release.dart
    flutter analyze --no-pub
    flutter test --no-pub
    flutter run -d windows

Versão canônica: pubspec.yaml. Distribuição, assinatura e homologação: docs/DISTRIBUTION.md. Estado e escopo futuro: ROADMAP.md. A CI verifica análise, testes e builds Windows/Android; só executa no GitHub após envio das alterações.

## Galeria e controles de mídia — 1.0.4

- Fotos: selecione várias imagens para navegar com anterior/próxima ou deslizando a prévia para os lados. No Windows, ao selecionar uma única foto, o SixF reúne as imagens compatíveis da mesma pasta. No Android, selecione as fotos desejadas juntas no seletor do sistema.
- Vídeos e áudios transmitidos pelo SixF: linha do tempo, seek ao soltar o slider, saltos de 10 segundos, pausa/reprodução e repetição no fim confirmado pelo Chromecast. Informações e capacidades vêm do receptor; apps externos como Netflix podem não fornecer esses dados ao SixF.
- Shuffle usa a lista de arquivos selecionados e permite reprodução em ordem aleatória. Repetir arquivo e shuffle são modos exclusivos; repetir recarrega o arquivo atual ao terminar. Seleção única não oferece shuffle.
- A aba Teclas & Mídia usa a sessão transmitida apenas quando seu destino corresponde ao aparelho selecionado. Sem sessão compatível, mantém as teclas remotas e desabilita os controles que exigem telemetria.
- Google TV: D-pad centralizado; Voltar abaixo dele à esquerda por padrão. Configurações > Voltar à direita do D-pad salva a escolha.
- Voz: pressione e segure para captar; solte para enviar os últimos bytes e encerrar a fala. O SixF converte o PCM do dispositivo para 8 kHz mono, incluindo ajustes de hardware informados pela biblioteca de captura. Microfone físico Windows/Android ainda exige homologação.
- Aplicativos: o protocolo atual não fornece o inventário instalado no Chromecast. Mantidos atalhos identificados, respeitando a recusa de aplicativo auxiliar e ADB.

## Correções de conexão e voz — 1.0.5

- Se o Chromecast recusar o certificado salvo, o SixF volta ao pareamento por PIN com a mesma identidade. A recusa do certificado Windows foi observada em teste de rede com o aparelho real.
- O protocolo agora aceita identificadores negativos de ping/voz (varints protobuf de dez bytes). Antes esses valores podiam interromper a conexão.
- Soltar o microfone antes da resposta do Chromecast mantém a sessão até enviar a fala curta e seu encerramento. Captura vazia gera erro explícito.
- Quedas após uma conexão estabelecida têm até três tentativas de recuperação, com intervalos de 2, 5 e 10 segundos. Desconectar manualmente cancela a recuperação. Comandos enviados também contam como atividade da conexão.
- Respostas de conexões antigas de mídia são ignoradas após troca/cancelamento.
- 209 testes passaram; análise estática limpa. Voz e estabilidade prolongada no Chromecast físico ainda precisam de reteste. Inventário completo de apps permanece indisponível sem auxiliar/ADB.

```
