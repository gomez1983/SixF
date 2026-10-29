# SixF — validação e distribuição

## Pareamento persistente e ícones — 29/10/2026

Correção de colisão entre identidades do controle Google TV: novos certificados têm subject distinto por chave pública. Reconexões preservam certificados aceitos; EOF isolado não inicia novo PIN. Certificados legados só são adaptados quando um novo pareamento é necessário, preservando a chave privada. Menus do aparelho oferecem Refazer pareamento para recuperação explícita.

Catálogo local com 13 ícones de aplicativos reconhecidos, disponível offline no Windows e Android. Imagens fornecidas pela TV continuam prioritárias; em caso de falha, usa-se o catálogo e depois o ícone alternativo. Aplicativos ADB desconhecidos não recebem marca por aproximação do nome. Origem e licença em assets/app_icons/ATTRIBUTION.md. Nenhum aplicativo é inventado pelo catálogo: o inventário continua vindo do Chromecast via ADB.

Controle remoto e inventário ADB têm autorizações separadas por instalação. O usuário confirmou que a lista completa apareceu no Android após configurar o ADB. Favoritos permanecem locais. Ambiente informado: Windows, Galaxy S23 Ultra e um Galaxy S9 (possivelmente S9+); a confirmação geral de funcionamento não especificou uma matriz completa de reinicializações e alternância entre os três clientes.

Validação: 217 testes aprovados, análise estática dos arquivos alterados limpa e Graphify atualizado. Windows Release e APK Android debug recompilados; 13 PNGs conferidos em ambos os pacotes. Executável: build/windows/x64/runner/Release/sixf_remote.exe. APK: build/app/outputs/flutter-apk/app-debug.apk. Mantida versão 1.0.6+8 e assinatura de teste existente para atualização por cima da instalação atual, sem desinstalar. Usuário confirmou que funcionou e autorizou commit/envio ao GitHub. Auditoria flutter-security-audit recomendada e não executada nesta rodada.

## Voz, galeria e mídia — 27/10/2026

Windows Release atualizado no caminho do atalho e APK Android debug gerado; pacotes verificados em dist/1.0.4. Microfone físico e reprodução real continuam pendentes de teste no aparelho.

Versão 1.0.4+6: captura antecipada do microfone, conversão do formato PCM efetivo do hardware para 8 kHz mono e drenagem antes de VOICE_END ao soltar; galeria com seleção múltipla, anterior/próxima e gestos; telemetria Cast, seek, saltos, repetição após FINISHED e shuffle de arquivos; D-pad centralizado no Chromecast com posição de Voltar persistida; controles compartilhados na aba Teclas & Mídia.

205 testes aprovados e flutter analyze sem apontamentos. Novos testes cobrem PCM Windows estéreo/Android mono, buffers fragmentados, fala curta, fim da captura, timeout, voz pelo servidor TLS local, seek recusado, cancelamento, repetição e duplicidade de eventos, galeria por gestos em 320 px, destino da sessão e preferência de Voltar. Graphify atualizado. Nenhuma validação física de microfone ou Chromecast foi inferida desses testes.

A solicitação de listar todos os apps do Chromecast permanece sem implementação por limite do protocolo atual, respeitando a recusa de auxiliar e ADB. Repetição e timeline têm escopo nos arquivos transmitidos pelo SixF; shuffle requer múltiplos arquivos.


## Correções Chromecast — 27/10/2026

Versão 1.0.3+5: Netflix usa netflix://; aba identifica atalhos em vez de inventário; áudio PCM pelo Android TV Remote Service v2 via pacote record; mídia local usa receptor Google Cast na porta 8009 com confirmação MEDIA_STATUS; volume/mudo podem usar uma sessão LG/Samsung enquanto o Chromecast está ativo, com escolha persistida por aparelho. Nenhum aplicativo auxiliar ou ADB foi adicionado ao Chromecast.

Windows Release e APK Android debug compilados. Executável atualizado em build/windows/x64/runner/Release/sixf_remote.exe e APK disponível em dist/1.0.3/SixF-1.0.3-Android-teste.apk.

189 testes aprovados; análise estática e metadados limpos. Testes de Cast usam servidor TLS local para abertura do receptor, LOAD, MIME e controles da sessão; teste de volume verifica destino e persistência. Homologação física de microfone, codecs, rede e CEC continua necessária. A lista completa de aplicativos instalados não é atendida pelo protocolo escolhido; restrição aceita pelo usuário.


## Google TV — 27/10/2026

Versão `1.0.2+4`: driver Android TV Remote Service v2, descoberta mDNS/probe local, pareamento hexadecimal, identidade persistente por aparelho, comandos de navegação/configurações/mídia, digitação e atalhos YouTube/Netflix. LG e Samsung preservados.

Validação: 187 testes aprovados, análise estática limpa e metadados consistentes. Testes novos usam servidor TLS local com certificado de cliente, comprovando pareamento, reconexão sem novo código, ping/pong, teclado e texto; interface validada em 320 px com fonte ampliada. Graphify atualizado.

Pacotes em `dist/1.0.2/`: `SixF-1.0.2-Windows-x64.zip` (extrair tudo e executar `sixf_remote.exe`) e `SixF-1.0.2-Android-teste.apk` (assinatura debug, somente teste). Ambos compilados e verificados como arquivos ZIP íntegros. Não são pacotes assinados para publicação nas lojas.

Homologação no Chromecast com Google TV físico ainda pendente: código inicial, reinício do SixF, queda de rede/standby, teclado, volume/energia conforme CEC/saída de áudio e alternância com a LG. O protocolo de rede não emite infravermelho. Não foi implementado envio de mídia via Google Cast nem streaming de microfone.


## Correções para teste — 13/10/2026

Versão `1.0.1+3`: descoberta com cartões reorganizados e diálogo rolável em telas estreitas; pressionamento contínuo passa pelo feedback tátil, respeitando a preferência de vibração; vídeos/áudios LG priorizam SetAVTransportURI + Play por DLNA, mantendo fotos no canal nativo e alternativa nativa quando DLNA recusa. MP4 deixa de anunciar um perfil AVC SD/AAC não verificado.

Validação: 176 testes aprovados, análise estática limpa e metadados de versão consistentes. Windows release e Android debug compilados. A primeira compilação Windows encontrou o executável antigo aberto; após encerrar a instância do SixF, a compilação foi concluída.

Arquivos em `dist/1.0.1/`: `SixF-1.0.1-Windows-x64.zip` (extrair inteiro e executar `sixf_remote.exe`) e `SixF-1.0.1-Android-teste.apk` (APK debug para teste local). Nenhuma assinatura de produção ou publicação foi feita. A auditoria `flutter-security-audit` recomendada pelo AGENTS.md antes da distribuição permanece pendente.

Relato físico: LG 49LF5900-SA abre o visualizador, fotos funcionam e vídeos MP4 de computador não iniciam. A causa exata na TV ainda requer reteste; os testes automatizados usam respostas simuladas e servidor HTTP local. A correção não converte codecs. Referência técnica para metadados DLNA sem perfil de codec presumido: [Connect SDK — DLNAService](https://github.com/ConnectSDK/Connect-SDK-Android-Core/blob/master/src/com/connectsdk/service/DLNAService.java).

## Versões e identidade

`pubspec.yaml` é a referência: `1.0.1+3`. Android usa `1.0.1`/código `3`; Windows e MSIX usam `1.0.1.3`. Atualize `msix_version` com o mesmo build e execute `dart run tool/check_release.dart`. O Inno Setup lê a versão do executável Release, evitando número independente no script.

Foram preservados applicationId Android, identity_name/alias MSIX e AppId Inno para evitar quebrar a continuidade de instalações. O nome público e o logo MSIX agora são SixF. Certificado e publisher precisam corresponder à identidade de distribuição real; esta tarefa não cria nem registra identidades nas lojas.

## Validação local

```powershell
flutter pub get
dart run tool/check_release.dart
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release --no-pub
flutter build apk --debug --no-pub
```

A CI repete análise/testes e builds Windows release/Android debug com Flutter 3.47.3. Workflow criado localmente não significa execução remota nem publicação. APK debug serve para desenvolvimento, nunca para distribuição em produção.

## Android release

1. Use uma chave de distribuição sob sua guarda (ou a chave de upload já vinculada à loja).
2. Copie `android/key.properties.example` para `android/key.properties` e preencha localmente. `storeFile` é absoluto ou relativo a `android/`.
3. Não versione chave, arquivo preenchido ou senhas. Estão ignorados pelo Git.
4. Execute `flutter build appbundle --release` e valide a assinatura antes do envio.

Sem os campos e o arquivo da chave, tarefas release falham com mensagem de configuração. Nunca se usa a chave debug como alternativa. Referência: [documentação oficial Flutter](https://docs.flutter.dev/deployment/android).

## Windows

O diretório `build/windows/x64/runner/Release/` precisa ser distribuído completo, incluindo DLLs, assets e dados. O executável sozinho não é pacote portátil.

Após compilar Release, use Inno Setup instalado para compilar `installers/sixf_installer.iss`. A versão é extraída com [GetVersionNumbersString](https://jrsoftware.org/ishelp/topic_getversionnumbersstring.htm). O instalador gerado localmente não é automaticamente assinado.

MSIX exige certificado/publisher compatíveis com a identidade escolhida. O projeto mantém `install_certificate: false`: não instala certificados no computador automaticamente. Antes de gerar para distribuição, configure certificado e verifique restrições da loja, inclusive a quarta parte da versão. Não envie senhas pela linha de comando nem as salve no repositório.

## Homologação manual pendente

| Cenário | LG webOS | Samsung Tizen |
| --- | --- | --- |
| Pareamento, recusa, reconexão após standby | Pendente | Pendente |
| Duas TVs conectadas e troca durante comando | Pendente | Pendente |
| D-Pad/volume/canal mantidos; soltar e sair do app | Pendente | Pendente |
| Favoritos por aparelho e após reiniciar | Pendente | Pendente |
| Foto, vídeo e áudio; codecs reais | Pendente | Pendente |
| Play recusado, falta de telemetria, seek e loop | Pendente | Pendente |
| Stop/troca durante transmissão | Pendente | Pendente |

Windows: verificar entrada/saída do compacto, escala de tela, múltiplos monitores, maximização, sobreposição e bandeja. Android: testar em aparelho físico, segundo plano, gestos e permissões.

## Segurança e limites

O AGENTS.md recomenda a auditoria `flutter-security-audit` antes de release. Os testes de regressão não substituem auditoria nem homologação. SharedPreferences, identidade marca/IP, cadastro legado e revisão mais ampla de destinos de rede continuam como evoluções documentadas no ROADMAP.

A preparação de código não inclui assinatura com credenciais particulares, publicação, commit ou push.

## Resultado local — 12/10/2026

- 166 testes aprovados; análise estática e diff sem apontamentos.
- Windows release compilado; versão numérica do executável conferida em 1.0.0.2.
- Android debug compilado. Release sem key.properties falhou com a mensagem prevista: proteção de assinatura confirmada.
- Verificador de metadados aprovado. Nenhuma dependência foi atualizada/removida; lockfile preservado.
- Instaladores Inno/MSIX não gerados; Inno não localizado no PATH/diretórios padrão consultados e assinatura de distribuição não configurada nesta tarefa.
- CI adicionada, sem execução remota. Sem commit/push/publicação.
- Testes de janela usam API simulada; TVs físicas, Android físico e integração de janela/monitores ainda exigem homologação.

## Correções Chromecast — 28/10/2026 — 1.0.5+7

Windows: certificado salvo recusado pelo Chromecast real (TLS CERTIFICATE_UNKNOWN). O driver agora trata alertas TLS assíncronos e encerramento precoce sem mensagens de controle, retornando ao PIN sem regenerar identidade. Informar o novo código quando solicitado.

Corrigidos varints protobuf negativos de 10 bytes, roteamento da confirmação de voz durante release, cancelamento de voz vinculado à conexão original, atividade de saída no watchdog e reconexão limitada após quedas (2/5/10 segundos; cancelável pelo usuário). Cast ignora callbacks de sockets substituídos e falha imediatamente ao consultar uma sessão encerrada.

Validação: 209 testes aprovados, incluindo TLS local com certificado recusado, PIN, fala curta com identificador negativo, recuperação/cancelamento/limite de tentativas, atividade contínua e 30 recargas Cast. Análise estática limpa. Testes simulados não comprovam reconhecimento de voz nem estabilidade prolongada no aparelho físico. O teste real confirmou somente a recusa do certificado Windows; não foi solicitado novo PIN durante esse diagnóstico.

Pacotes compilados e com integridade ZIP/APK verificada em dist/1.0.5: Windows x64 Release completo e APK Android debug para teste. O executável usado pelo atalho permanece em build/windows/x64/runner/Release/sixf_remote.exe. Inventário completo de apps segue pendente pelas restrições de não instalar auxiliar e não habilitar ADB.


## Aplicativos, voz e interface — 28/10/2026 — 1.0.6+8

ADB agora autorizado pelo usuário: pareamento integrado sem auxiliar na TV, inventário real de atividades LAUNCHER/LEANBACK_LAUNCHER e abertura por componente. Validado pelo cliente SixF com 23 apps e lançamento do VLC. A identidade Windows pareada foi salva na configuração local; cada instalação Android deve realizar seu próprio pareamento em Aplicativos > Configurar aplicativos via ADB. Portas de pareamento e conexão são distintas; tentativa limitada e redescoberta apenas do IP selecionado.

Voz corrigida: o campo 31 cliente→TV recebe bytes PCM crus, não uma mensagem interna com session_id e samples. A análise do serviço instalado confirmou que o envelope anterior corrompia o áudio. Após corrigir, a TV reconheceu palavra por palavra e concluiu “Qual é a previsão do tempo para amanhã” usando a mesma fonte sintética 8 kHz. Captura real de microfone no Windows/Android ainda exige reteste; handshake e bytes enviados sozinhos não comprovam reconhecimento.

Play/Pause/Stop mantêm o último comando solicitado selecionado por aparelho. Voltar fica próximo à margem, com tamanho e alinhamento horizontal de Home, e continua configurável para esquerda/direita. 211 testes aprovados, análise estática limpa, metadados consistentes e geometria verificada em 320/393/1280 px. Graphify: 2.017 nós e 2.716 arestas.

Windows Release e APK Android debug gerados e verificados em dist/1.0.6. O executável do atalho foi atualizado no caminho habitual. Os pacotes não contêm identidades ADB de diagnóstico nem a cópia analisada do serviço da TV. Sem publicação, commit ou push.
