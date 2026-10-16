# SixF — validação e distribuição

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
