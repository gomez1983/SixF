# SixF — Auditoria de estabilidade, recursos e segurança

Data: 04/11/2026, America/Sao_Paulo. Escopo: working tree de `C:\Projetos\SixF`, incluindo alterações ainda não commitadas de mídia, legenda e seek. Uso pessoal, sem preparação para publicação. Nenhuma modificação de produção, dependência, preferência real, credencial ou pareamento foi aplicada nesta auditoria. Nenhum comando foi enviado à TV.

Procedimento: skill `D:\Google Drive\Meu Drive\Pessoal\My Second Brain\.agents\skills\auditoria-codigo\SKILL.md`, avaliação técnica de 12/10 e BPM-006 já consultado na investigação de mídia. Navegação pelo Graphify antes de ler código. A avaliação histórica é uma referência de regressão, não uma lista de bugs atuais.

## Resultado executivo

**Quatro problemas reproduzidos**, duas oportunidades de desempenho identificadas e uma exposição local de credenciais identificada por leitura. A prioridade prática é corrigir a gestão de processos FFmpeg e as leituras HTTP concorrentes; não há evidência que justifique reescrever o aplicativo.

| ID | Prioridade de engenharia | Tipo | Evidência |
|---|---|---|---|
| RES-01 | P1 | Subprocesso continua após timeout de miniatura | Reproduzido com FFmpeg real |
| MID-02 | P1 | Segundo GET da mesma mídia mata o primeiro stream | Reproduzido em HTTP loopback |
| RES-03 | P2 | Cache da sessão permanece após Stop e dispose | Reproduzido com arquivo sintético |
| MID-04 | P2 | Seleção de áudio alternativo volta ao padrão | Reproduzido com transporte simulado |
| PERF-05 | P2 | Seek recodifica e consome mais CPU/RAM/banda | Medido em subprocesso Full HD |
| PERF-06 | P2 | Miniaturas sem deduplicação em andamento e caches sem limite | Leitura estática; acúmulo em uso prolongado não medido |
| SEC-07 | P2 | Tokens persistidos sem proteção específica do SO | Leitura estática; acesso local necessário |

Prioridade P1 indica impacto operacional, não severidade HIGH de vulnerabilidade. No recorte de segurança: 0 CRITICAL/HIGH confirmadas, 2 MEDIUM (retenção de descritores com token em RES-03 e persistência em SEC-07), 1 INFO (inventário de versões). Esta classificação não certifica ausência de outras vulnerabilidades.

## 1. Evidências e recomendações

### RES-01 — Timeout não encerra o FFmpeg

Local: `lib/services/media_remux_service.dart:131`, especialmente `Process.run(...).timeout(...)` nas linhas 146–159. O mesmo padrão aparece na conversão GIF/imagem e no ffprobe.

A extração de miniatura retorna null após quatro segundos, mas não possui referência ao processo para encerrá-lo. A documentação do [Future.timeout](https://api.dart.dev/dart-async/Future/timeout.html) distingue timeout da espera e conclusão do Future original; o timeout não cancela o subprocesso.

**Reprodução:** um servidor local de teste aceita a conexão e não envia a mídia. Após o retorno de `extractVideoThumbnail`, a inspeção por psutil encontrou **1 ffmpeg.exe ainda ativo**, identificado exclusivamente pelo marcador exclusivo na URL sintética. O teste encerrou esse processo no cleanup. Isso prova retenção após timeout, não que todo arquivo local normal deixe um processo vivo indefinidamente.

**Impacto:** I/O travado ou mídia lenta pode deixar trabalho ativo depois de a UI desistir. A abertura de várias miniaturas pode multiplicar o custo, pois não há deduplicação das extrações em andamento. `Process.run` também acumula stdout/stderr até o término.

**Proposta:** gerenciador comum com `Process.start`, consumo dos pipes, prazo, cancelamento e `finally` que encerra o filho. Registrar o processo na operação que o iniciou. Aplicar a miniaturas, probe e conversões; preservar a distinção de extração de legendas, que já tem `finally { process?.kill(); }`, mas ainda não recebe cancelamento imediato de Stop.

### MID-02 — Leitura concorrente interrompe a reprodução anterior

Local: `lib/services/media_server_service.dart:369–370` e 743–745.

Cada GET cria um FFmpeg e executa `_activeRemuxProcess?.kill()` antes de assumir o campo. A validação de caminho/fábrica protege contra **URLs antigas**, mas não distingue dois leitores válidos da **mesma URL atual**.

**Reprodução:** primeiro GET em loopback, seguido de outro GET com a mesma URL enquanto o primeiro ainda transmite. Foram criados 2 processos; o primeiro terminou com código **-1** antes de completar os 30 s da fonte sintética. O teste lida explicitamente com encerramento dos streams e remove seus recursos.

**Impacto:** um probe/retry/leitor concorrente pode derrubar o stream ativo. É uma falha comprovada do servidor, mas ainda não foi demonstrado que o Chromecast real faça essa sequência no filme relatado.

**Proposta:** definir a posse por geração de mídia e por resposta HTTP. Um leitor não deve matar outro leitor da mesma geração. Manter registro de processos e cancelá-los na troca/Stop; incluir limite de concorrência ou spool compartilhado com política explícita. Evitar simplesmente retirar o kill, o que permitiria processos ilimitados. Testes de aceitação: dois GET simultâneos; descarte de leitor; troca rápida de URL; Stop durante criação do processo.

### RES-03 — Cache sobrevive ao encerramento

Local: `lib/controllers/media_cast_controller.dart:198–212`, `stop` em 1300 e `dispose` em 1370. Descritor de nuvem: `lib/services/library_sources.dart:675`.

O cache é removido por `_replaceCache` ao substituir a sessão, mas Stop e dispose não chamam esse mecanismo. O teste passou um diretório temporário a `castResolvedPlaylist`, executou Stop e dispose, e confirmou que o diretório continuou existindo; a referência `activeCacheDirectory` também permaneceu após Stop.

**Impacto:** retenção em disco e de referências da lista; isso não é, por si só, um vazamento comprovado do heap Dart. Em nuvem, `.cloud.json` contém cabeçalho Authorization com access token, aumentando o tempo de retenção desse dado no disco. Uma nova sessão pode limpar o cache anterior; a retenção não cresce necessariamente a cada Stop isoladamente. Exclusão automática futura pelo SO não substitui uma política de limpeza.

**Proposta:** limpar cache pertencente à sessão após fechar streams; limpar também no dispose, invalidando resoluções pendentes. Separar cache do visualizador e do cast, pois a biblioteca pode continuar exibindo uma foto depois de parar a TV. Testar arquivo ainda aberto no Windows e novas resoluções que terminam depois do cancelamento. Em descritores, guardar referência ao provedor/ID em vez de uma cópia do token quando possível.

### MID-04 — A troca de áudio é descartada

Local: `lib/controllers/media_cast_controller.dart:376`, reset na linha 669 e seleção padrão na região 751–759.

`selectAudioTrack` define a faixa e chama `castFile`, que a limpa e escolhe novamente o default no probe.

**Reprodução:** arquivo sintético e transporte simulado com faixas 1/default e 2/alternativa. Solicitada faixa 2; após aguardar a recarga, `selectedAudioTrack.id` era **1**. Isso confirma a falha de estado; não envolve escuta de áudio na TV.

**Proposta:** transportar o ID solicitado como parâmetro explícito da recarga, validá-lo no novo probe e mapeá-lo no FFmpeg. Preservar posição e pausa; falha deve manter a seleção anterior ou informar a recusa. Não persistir automaticamente a faixa 2 para um arquivo diferente que reutilize o mesmo índice.

### PERF-05 — Recodificação no seek tem custo relevante

Local: `lib/services/media_remux_service.dart:714–741`. Qualquer startPosition positivo usa libx264, mesmo quando o vídeo original é compatível. Isso mantém seek exato; substituir por copy sem tratar keyframes reintroduziria erros de posição e legenda.

Medição reproduzível com psutil, amostragem a cada 20 ms, FFmpeg com os mesmos argumentos do serviço, fonte sintética H264+AAC 1920×1080, 30 fps e 12 s:

| Operação | Mídia processada | Tempo de parede | CPU acumulada amostrada | Pico RSS amostrado | Saída |
|---|---:|---:|---:|---:|---:|
| Copiar vídeo + AAC | 12 s | 0,949 s | 0,922 s | 25,7 MiB | 8,32 MiB |
| Seek em 3,25 s + libx264/AAC | 8,75 s | 0,809 s | 4,641 s | 183,8 MiB | 14,93 MiB |

CPU acumulada soma vários núcleos e pode exceder o tempo de parede. O pico é amostrado, não um máximo exato. A saída no seek representa aproximadamente 14,3 Mbit/s nesta fixture, maior que a cópia. A fonte não é o filme pessoal do usuário; a duração processada difere entre as linhas e impede comparar apenas o tempo total como benchmark equivalente.

**Conclusão limitada:** o processo de recodificação foi mais caro em CPU/RAM e produziu maior taxa de dados nesta amostra. Ambos terminaram com exit code 0. Isso **não comprova vazamento**, travamento na TV ou consumo excessivo do app inteiro. O teste não mede heap Flutter, GPU, Android ou uso prolongado; uma fonte 4K também não foi medida.

**Proposta:** medir primeiro o filme real no hardware utilizado e o total app + filhos. Considerar perfil de bitrate/resolução configurável ou seek em keyframe com posição real propagada a UI/legenda. Não remover a precisão do seek silenciosamente. A correção recente de fragmentos de 1 s permanece útil, mas não elimina o custo de recodificação.

### PERF-06 — Trabalho repetido e ausência de limites de cache

Local: `lib/ui/views/media_library.dart:983–985`, `lib/services/media_remux_service.dart:101–102,131`, `lib/services/library_sources.dart:101,430,591`.

O build cria um Future de miniatura. O cache só registra o resultado pronto, sem compartilhar o Future em andamento; reconstruções antes do término podem iniciar trabalho duplicado. As tabelas estáticas de miniaturas/conversões e o cache de pastas não têm limite de entradas. Expiração de pasta é verificada na leitura, mas não remove globalmente entradas expiradas não revisitadas. Arquivos temporários de miniatura/conversão não têm política central de expurgo.

**Evidência:** leitura estática; não foi medido crescimento de RAM do app durante centenas de navegações. Os mapas de miniaturas armazenam caminhos, não bitmaps; não atribuir a eles o tamanho das imagens decodificadas.

**Proposta:** memoização de Futures em andamento, fila de trabalho limitada, LRU/TTL com limite de bytes/entradas e limpeza em disco. Invalidar por tamanho/mtime do arquivo, não só pelo caminho. O visualizador principal de foto também decodifica sem cacheWidth, ao contrário das miniaturas; vale medir fotos grandes antes de impor resolução menor e prejudicar o zoom.

### SEC-07 — Persistência local de tokens

Local: `lib/services/storage_service.dart:101–124` e `lib/services/library_sources.dart:181–199`.

Client keys de TV e access/refresh tokens de nuvem são gravados em SharedPreferences sem um cofre específico do SO neste fluxo. Acesso ao armazenamento local do usuário/app é pré-condição; a sandbox do Android continua sendo uma barreira. Não há evidência de exfiltração pela rede ou segredo real commitado nesta investigação.

**Proposta:** priorizar refresh tokens em armazenamento protegido do SO e migração sem apagar pareamentos válidos. O uso pessoal reduz exposição operacional, mas não torna um refresh token público. Nenhuma dependência de secure storage foi adicionada automaticamente.

## 2. Propostas de patch para revisão

Revise cada patch antes de aplicar. Nenhuma alteração foi realizada automaticamente no código de produção. Os fragmentos abaixo são propostas localizadas; a correção completa inclui os testes de aceitação descritos e os demais pontos com o mesmo padrão.

Para RES-01, substituir a execução da miniatura por processo sob posse explícita:

```diff
--- a/lib/services/media_remux_service.dart
+++ b/lib/services/media_remux_service.dart
@@
-      final res = await Process.run('ffmpeg', [
+      final process = await Process.start('ffmpeg', [
         '-ss',
         '00:00:03',
         '-i',
         videoPath,
         '-vframes',
         '1',
         '-vf',
         'scale=160:-1',
         '-q:v',
         '5',
         '-y',
         target.path,
-      ]).timeout(const Duration(seconds: 4));
-
-      if (res.exitCode == 0 && await target.exists()) {
-        return _thumbnailCache[videoPath] = target.path;
+      ]);
+      try {
+        unawaited(process.stdout.drain<void>());
+        unawaited(process.stderr.drain<void>());
+        final exitCode = await process.exitCode.timeout(const Duration(seconds: 4));
+        if (exitCode == 0 && await target.exists()) {
+          return _thumbnailCache[videoPath] = target.path;
+        }
+      } finally {
+        process.kill();
       }
```

O helper definitivo também deve aguardar a conclusão/encerramento, tratar erro dos pipes, associar cancelamento e remover arquivos parciais; só esse fragmento não resolve deduplicação de Futures. Para MID-02, a posse e o limite de leitores precisam ser implementados juntos; um patch que apenas remove `_activeRemuxProcess?.kill()` criaria outro risco e não é recomendado.

## 3. Dependências e segredos

- OSV `POST /v1/querybatch`: **125 pacotes Pub hospedados, com versões exatas de pubspec.lock; 0 correspondências**. Resultado: `support/2026-11-04-dependencies.json`. Consulta não cobre dependências nativas Gradle/Windows, FFmpeg instalado, Dart SDK nem vulnerabilidades ainda não catalogadas.
- `flutter pub outdated --json`: inventário salvo em `build/audit_outdated.json`, 40 entradas com versões mais novas e nenhuma advisory reportada pelo comando. Versão mais nova não foi tratada como vulnerabilidade. Nenhum upgrade foi executado.
- `git ls-files` para PEM/KEY/JKS/keystore/P12/.env/credentials/secrets: apareceu apenas arquivo de **código-fonte** `lib/services/drivers/google_tv/credentials.dart`, não uma chave de usuário. Seu conteúdo implementa geração/serialização, sem chave privada literal encontrada.
- Busca em lib/android/windows/pubspec por padrões de private key, Google API key, GitHub token e AWS access key: nenhuma correspondência. Não é um scanner universal nem uma inspeção de todo histórico Git. Não foram lidos arquivos pessoais de credenciais.
- Manifest Android: activity launcher exportada é necessária para abertura do app; tráfego claro é compatibilidade com TV local. Não classificados como falha por si só. Permissões de microfone e mídia correspondem a recursos presentes.
- Restrição TLS a IPs locais e cancelamento em NetworkOperation foram identificados. Aceitar certificado autoassinado de TV privada não foi equiparado a aceitar qualquer certificado da Internet.

Referência do inventário de advisories: [Dart — Security advisories](https://dart.dev/tools/pub/security-advisories). Resultado OSV é uma fotografia da consulta, não garantia de segurança.

## 4. Conferência da avaliação histórica

- `RemoteController.dispose` já cancela descoberta, encerra sessões e descarta voz (linhas 70–85): a ausência de dispose descrita em outubro não é um achado atual.
- Fábrica padrão é DriverFactory e os callbacks são vinculados por sessão. O antigo compartilhamento LG não foi reapresentado como bug atual.
- `selectDiscoveredTv` aguarda `saveOrUpdateDevice`; `connectToTv` aguarda seleção e conexão (região 1066–1074).
- Storage lê por ID/IP e não faz o antigo fallback indiscriminado por marca (região 90–98).
- Servidor atual exige rota/token; rota arbitrária não dá acesso a qualquer arquivo. RES-03 não significa que a URL da mídia continua válida depois do Stop: a mídia é revogada, embora o diretório permaneça.
- Ciclo de vida Cast contém geração, _loading e limpeza; não foi atribuído ao app o antigo problema de mistura genérica de callbacks sem evidência.

## 5. Validação e limites

- Quatro reproduções isoladas passaram **confirmando comportamentos defeituosos atuais**. Não são testes de correção aprovada.
- Fontes e comandos em `support/2026-11-04-probe_test.dart`, `support/2026-11-04-profile.py` e `support/2026-11-04-dependencies.py`; saída de medições em JSON. Exigem FFmpeg/ffprobe, Flutter e Python com psutil.
- Execução: `flutter test --no-pub docs/security/audits/support/2026-11-04-probe_test.dart`; `python docs/security/audits/support/2026-11-04-profile.py`; `python docs/security/audits/support/2026-11-04-dependencies.py`.
- Os testes de reprodução devem mudar ou deixar de esperar o defeito quando as correções forem aplicadas. Não integram automaticamente `flutter test` do diretório test/.
- A rodada anterior desta conversa passou 249 testes e análise estática; isso é referência anterior, não foi repetido integralmente nesta auditoria sem mudanças de produção.
- Nenhum teste com Chromecast físico, filme do usuário, app Android rodando ou profiling do heap da versão Windows foi realizado. Não há base para afirmar vazamento de RAM do app ou correção definitiva do travamento relatado.
- Graphify atualizado por AST ao encerrar a auditoria; a atualização não constitui indexação semântica integral deste relatório Markdown.

## Ordem recomendada

1. Posse/cancelamento de subprocessos + deduplicação e limite de miniaturas.
2. Leituras HTTP concorrentes e regressão de Stop/troca rápida de mídia.
3. Seleção de áudio, preservação de posição/pausa e limpeza segura de caches.
4. Medição do filme real e proteção dos tokens de nuvem, conforme o uso desses recursos.

Nenhum commit, push, publicação ou alteração no vault foi realizado.


---

## 6. Validação pós-correção (04/11/2026)

As correções para **RES-01**, **MID-02**, **RES-03** e **MID-04** foram implementadas e validadas sem remover o histórico original da auditoria.

### 6.1 Estado por item do relatório

| ID | Estado pós-validação | Arquivos e evidências |
|---|---|---|
| **RES-01** | **Corrigido** | `lib/services/media_remux_service.dart` (`_runProcess`, `extractVideoThumbnail`, `convertImageOrAnimationForCast`, `probeMediaDetails`, `extractVttSubtitle`) e `lib/services/media_server_service.dart` (`_mediaOperation` em `prepareSubtitle`). Subprocessos são iniciados com `Process.start`, registrados em `NetworkOperation.onCancel`, têm `stdout`/`stderr` drenados, são encerrados no `finally` (`process.kill()` + espera curta de `exitCode`) e removem arquivos temporários parciais em caso de falha/timeout. `extractVideoThumbnail` deduplica chamadas concorrentes via `_inFlightThumbnails`. Validado com `psutil` em `docs/security/audits/support/2026-11-04-probe_test.dart` (`0` processos `ffmpeg.exe` remanescentes após timeout e após cancelamento). |
| **MID-02** | **Corrigido** | `lib/services/media_server_service.dart` (`_activeRemuxProcesses`, `maxConcurrentRemuxStreams = 4`, `_killActiveRemuxProcesses`, `res.bufferOutput = false`). Leitores HTTP concorrentes na mesma geração (`_mediaPath`) coexistem sem matar o processo do primeiro leitor; a 5ª conexão simultânea recebe `503 Service Unavailable` sem criar novo subprocesso; `restartRemuxAt`, `serveFile` e `stop` encerram todos os processos ativos da geração. Validado em `docs/security/audits/support/2026-11-04-probe_test.dart`. |
| **RES-03** | **Corrigido (parcial quanto ao formato de token no descritor `.cloud.json`)** | `lib/controllers/media_cast_controller.dart` (`_replaceCache`, `_navigate`, `castResolvedPlaylist`, `castFile`, `stop`, `dispose`) e `lib/ui/views/media_library.dart` (`_clearPhotoCache`, `_loadAndMirrorActivePhoto`). `stop()`, troca de arquivo avulso, falha de carga, resolução tardia após cancelamento e `dispose()` removem o diretório de cache da sessão de cast e zeram `activeCacheDirectory`. O cache do visualizador local de fotos (`_photoCache`) foi separado do diretório de sessão do cast (`castDir`), mantendo a foto aberta íntegra após `stop()` na TV. Os descritores `.cloud.json` passam a ser removidos imediatamente no `stop()`/`dispose()`, mas ainda contêm o cabeçalho resolvido durante a sessão ativa (não refatorado para referência indireta ao provedor nesta etapa). |
| **MID-04** | **Corrigido** | `lib/controllers/media_cast_controller.dart` (`selectAudioTrack`, `castFile`, `_castFile`). O ID da faixa de áudio (`preferredAudioTrackId`), a faixa de legenda (`preferredSubtitleTrackId`), o `_subtitleOffset`, a posição (`initialPosition`) e o estado de pausa (`initialAutoplay`) são preservados na recarga do mesmo arquivo; faixas de áudio não padrão acionam remux (`needAudioRemux = true`); faixas inexistentes fazem rollback para a seleção e posição anteriores; um novo arquivo volta à faixa padrão. Validado em `docs/security/audits/support/2026-11-04-probe_test.dart`. |
| **PERF-05** | **Pendente (recomendação preservada para avaliação própria)** | Nenhuma alteração automática no pipeline de recodificação do seek (`libx264`), preservando o seek exato e a sincronia de legendas/keyframes validada em `test/media_remux_seek_test.dart` e `test/media_subtitle_sync_test.dart`. As medições de CPU (`0,922 s` em cópia vs `4,641 s` em seek) e pico RSS (`25,7 MiB` vs `183,8 MiB`) em `support/2026-11-04-profile.json` referem-se exclusivamente ao subprocesso `ffmpeg` isolado (fixture sintética 1080p30 de 12 s), não ao heap/CPU do processo Dart/Flutter do aplicativo. |
| **PERF-06** | **Parcialmente corrigido** | A deduplicação de `Future`s em andamento de `extractVideoThumbnail` (`_inFlightThumbnails`) foi implementada em `lib/services/media_remux_service.dart`. Limites globais LRU/TTL para os mapas estáticos de caminhos e expurgo periódico de miniaturas em `Directory.systemTemp` permanecem como recomendação futura. |
| **SEC-07** | **Pendente (recomendação de arquitetura)** | Persistência de credenciais/tokens em `SharedPreferences` mantida sem adição automática de dependência nativa (`flutter_secure_storage`), conforme escopo definido. |

### 6.2 Execução de testes, análise estática, Graphify e build

- `flutter test --no-pub docs/security/audits/support/2026-11-04-probe_test.dart`: **5/5 testes aprovados** (verificando o comportamento corrigido de `RES-03`, `RES-01`, `MID-04`, `MID-02` e `MID-02b` com `stop()`/troca de mídia enquanto `remuxProcessFactory` ainda aguarda a criação do processo).
- `flutter test --no-pub`: **250/250 testes aprovados** na suíte completa do repositório (incluindo `media_subtitle_sync_test.dart`, `media_subtitle_offset_controller_test.dart`, `media_remux_seek_test.dart`, `media_gallery_cast_test.dart`, `media_library_actions_test.dart` e `security_lifecycle_test.dart`).
- `flutter analyze --no-pub`: **No issues found!**.
- `graphify update .`: grafo AST atualizado em `graphify-out/` (`2428 nodes, 3292 edges, 116 communities`).
- `flutter build windows --release`: compilado com sucesso (`C:\Projetos\SixF\build\windows\x64\runner\Release\sixf_remote.exe`).
- `flutter build apk --debug`: compilado com sucesso (`C:\Projetos\SixF\build\app\outputs\flutter-apk\app-debug.apk`), preservando `applicationId` (`com.andregomez.sixf_remote`), versão e assinatura de teste anteriores.
- Validação física no Chromecast real (filme grande, avanços/recuos repetidos, legenda ativa, troca de áudio, Stop e troca de arquivo) permanece pendente de execução manual pelo usuário.
