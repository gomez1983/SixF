# Relatório de Auditoria de Segurança — SixF Smart Remote

Data: 06/11/2026 | Escopo: `C:\Projetos\SixF`, commit `c3f9179` (branch `main`) | Framework: Flutter, Dart SDK ^3.13.3

Procedimento: skill `.agents/skills/flutter-security-audit` (roteiro de 7 passos, checklist e filtro de falsos positivos). Esta auditoria cobre **o que mudou desde 04/11/2026**: player embutido (`media_kit`), miniaturas por fonte, ADB com redescoberta mDNS e `MulticastLock`, login Google/OneDrive no Android e no Windows, repetição e avanço de fila no Chromecast, e código nativo novo em `MainActivity.kt`. As pendências da [auditoria de 04/11](2026-11-04-auditoria.md) foram reavaliadas contra o código atual.

Nenhum arquivo de produção, dependência, preferência, credencial ou pareamento foi alterado por esta auditoria. Nenhum comando foi enviado a TV ou Chromecast. Uso pessoal, sem preparação de publicação.

---

## 1. Sumário Executivo

- **Postura Geral:** não há vulnerabilidade crítica nem alta. Os controles de rede mais sensíveis estão corretos (login OAuth restrito ao loopback com `state` e PKCE, validação de IP local antes de ADB e Cast, componentes ADB validados por expressão regular, token de mídia de 256 bits). Os riscos que restam são de **armazenamento local de segredos** e de **higiene de superfície**. Dois dos seis achados já estavam registrados em 04/11 e continuam abertos.
- **Total de Achados:**
  - 🔴 **CRITICAL:** 0
  - 🟠 **HIGH:** 0
  - 🟡 **MEDIUM:** 1
  - 🟢 **LOW:** 5
  - 🔵 **INFO:** 4

Esta classificação não certifica ausência de outras vulnerabilidades.

---

## 2. Tabela de Vulnerabilidades

| ID | Severidade | Componente / Arquivo | Descrição Resumida | Origem |
|---|---|---|---|---|
| SEC-07 | MEDIUM | `lib/services/storage_service.dart`, `library_sources.dart`, `google_tv_apps_adb.dart` | Tokens de nuvem e chaves privadas (Google TV e ADB) em `SharedPreferences`, em texto simples | Aberto desde 04/11; escopo ampliado |
| SEC-08 | LOW | `android/app/src/main/AndroidManifest.xml` | `allowBackup` não definido: o backup automático inclui as preferências com os segredos | Novo |
| SEC-09 | LOW | `lib/services/library_sources.dart:700` | Token Bearer gravado em disco no descritor `.cloud.json` | RES-03 de 04/11, ainda aberto |
| SEC-10 | LOW | `lib/services/thumbnail_service.dart` | Token Bearer enviado a qualquer URL `https` guardada na biblioteca | Novo (introduzido em 06/11) |
| SEC-11 | LOW | `lib/services/google_cast_media.dart:144` | `onBadCertificate: (_) => true`, sem repetir a checagem de IP local no próprio callback | Novo |
| SEC-12 | LOW | `AndroidManifest.xml` | Permissões `READ_MEDIA_*` e `READ_EXTERNAL_STORAGE` declaradas e nunca usadas | Novo |
| INF-01 | INFO | `AndroidManifest.xml` | `usesCleartextTraffic="true"` | Esperado (TV local) |
| INF-02 | INFO | `lib/services/media_server_service.dart` | Servidor local escuta em todas as interfaces, com CORS `*` | Esperado (Cast) |
| INF-03 | INFO | build | Segredo do cliente Google "desktop" embutido no executável | Esperado |
| INF-04 | INFO | `pubspec.lock` | `media_kit_libs_*` empacota libmpv/FFmpeg nativos, fora da cobertura do OSV | Novo |

---

## 3. Detalhamento dos Achados

### [SEC-07] — Segredos persistidos em texto simples
- **Severidade:** `MEDIUM` (mantida de 04/11)
- **Componente:** `lib/services/storage_service.dart` (client keys de TV, identidade do Google TV), `lib/services/library_sources.dart:181–199` (access e refresh tokens do Google e da Microsoft), `lib/services/google_tv_apps_adb.dart:38` (chave privada ADB por aparelho).
- **Contexto & Descrição:** todos esses valores vão para `SharedPreferences`. No Windows o arquivo fica em `%APPDATA%` e é legível por qualquer processo do mesmo usuário. No Android fica na sandbox do app. Desde 04/11 o escopo cresceu: a chave privada ADB (`sixf_adb_identity_<ip>`) autoriza controle total do Chromecast por depuração, e o refresh token do OneDrive/Google dá leitura contínua dos arquivos da nuvem.
- **Evidência no Código:**
  ```dart
  // lib/services/google_tv_apps_adb.dart:38
  await prefs.setString(key, encoded!);   // chave privada ADB serializada
  // lib/services/library_sources.dart (_persistTokens)
  await prefs.setString(_refreshPrefKey(source), refreshToken);
  ```
- **Impacto:** quem lê o armazenamento local do app, ou um backup dele (ver SEC-08), obtém acesso sem nova autorização. A exploração exige acesso ao arquivo; não há exfiltração pela rede.
- **Recomendação & Mitigação:** priorizar os **refresh tokens** e as **chaves privadas** em armazenamento do SO (Keystore no Android, Credential Manager/DPAPI no Windows), com migração que preserve pareamentos existentes. Adicionar `flutter_secure_storage` é uma nova dependência e deve passar por esta auditoria. Preferências comuns (tema, IP, favoritos) podem continuar como estão.

### [SEC-08] — Backup automático do Android inclui os segredos
- **Severidade:** `LOW`
- **Componente:** `android/app/src/main/AndroidManifest.xml`
- **Contexto & Descrição:** o `<application>` não define `android:allowBackup`, `dataExtractionRules` nem `fullBackupContent`. O padrão é permitir backup, e o arquivo de `SharedPreferences` do SEC-07 entra nele e é restaurado em outro aparelho.
- **Impacto:** amplia a exposição do SEC-07 para fora da sandbox. A barreira é o acesso à conta Google do usuário; o risco prático é baixo para uso pessoal.
- **Recomendação & Mitigação:** desligar o backup do app, já que pareamentos devem ser refeitos por aparelho (o BPM-009 mostra que identidades iguais em dois aparelhos colidem).

### [SEC-09] — Token Bearer gravado no descritor `.cloud.json`
- **Severidade:** `LOW` (era RES-03 em 04/11, ainda aberto)
- **Componente:** `lib/services/library_sources.dart:693–701`
- **Contexto & Descrição:** ao resolver um vídeo da nuvem, o app grava um descritor com `'headers': {'Authorization': 'Bearer …'}` na pasta temporária da sessão. O comentário em `media_server_service.dart:653` afirma que o token "nunca é gravado no descritor em disco", o que não é verdade. O servidor já obtém um token novo a cada requisição (`freshTokenForSourceName`, linhas 655–659), então a cópia em disco é redundante para o proxy.
- **Evidência no Código:**
  ```dart
  'headers': {'Authorization': 'Bearer $authToken'},   // library_sources.dart:700
  ```
- **Impacto:** o access token (cerca de 50 minutos) fica em disco até a limpeza da sessão, que hoje não acontece em Stop nem em dispose (RES-03).
- **Recomendação & Mitigação:** remover o campo `headers` do descritor e deixar o proxy e o probe pegarem o token em tempo de uso. Os pontos que leem `headers` do descritor estão em `media_server_service.dart:40–41` e `media_cast_controller.dart:857–858`.

### [SEC-10] — Token Bearer enviado a qualquer URL de miniatura
- **Severidade:** `LOW` (introduzido pela rodada de 06/11)
- **Componente:** `lib/services/thumbnail_service.dart` (`_download`)
- **Contexto & Descrição:** a miniatura de Drive e OneDrive vem de `LibraryEntry.thumbnailUrl`, que é gravada em `SharedPreferences` junto da fila e das playlists. `_download` aceita qualquer URL `https` e tenta primeiro **com** o cabeçalho `Authorization`.
- **Impacto:** quem alterar esse campo no armazenamento local faz o app enviar o token a um servidor escolhido por ele. Exige acesso de escrita local, o mesmo pré-requisito do SEC-07.
- **Recomendação & Mitigação:** enviar o token apenas para hosts do Google (`*.googleapis.com`, `*.googleusercontent.com`); as miniaturas do OneDrive são pré-assinadas e dispensam o cabeçalho.

### [SEC-11] — `onBadCertificate` aceita qualquer certificado no Cast
- **Severidade:** `LOW`
- **Componente:** `lib/services/google_cast_media.dart:144`
- **Contexto & Descrição:** o Chromecast usa certificado autoassinado, então ignorar a CA é obrigatório (`refs/false-positives.md`, item 2). O host é validado como rede local na linha 137, antes de conectar, e por isso **não** há exposição à internet. A diferença está no padrão: `google_tv_driver.dart:272` repete a checagem dentro do callback, e este não.
- **Recomendação & Mitigação:** usar `NetworkSecurityUtils.isLocalNetworkHost(host)` também aqui, por defesa em profundidade e para manter um único padrão.

### [SEC-12] — Permissões de mídia declaradas e nunca usadas
- **Severidade:** `LOW`
- **Componente:** `android/app/src/main/AndroidManifest.xml:8–11`
- **Contexto & Descrição:** o app escolhe pastas pelo seletor do sistema (`ACTION_OPEN_DOCUMENT_TREE`, em `MainActivity.kt`), que não exige `READ_MEDIA_IMAGES/VIDEO/AUDIO` nem `READ_EXTERNAL_STORAGE`. Não há `permission_handler` no `pubspec.yaml`, então nenhuma dessas permissões é pedida em tempo de execução.
- **Impacto:** nenhum acesso real, mas a lista fica maior que o necessário e a Play Store exige justificativa para `READ_MEDIA_IMAGES/VIDEO`.
- **Recomendação & Mitigação:** remover as quatro linhas e testar a escolha de pasta e a miniatura de arquivos do seletor.

### Achados informativos

- **INF-01 — `usesCleartextTraffic="true"`:** necessário para o WebSocket da Samsung (8001) e para o SSDP. Classificado como INFO conforme `refs/false-positives.md`. O tráfego para nuvem usa `https` (Drive, Graph, OAuth).
- **INF-02 — Servidor de mídia em `0.0.0.0` com CORS `*`:** a porta é efêmera e a URL contém um token aleatório de 256 bits (`Random.secure`, 32 bytes), então não é adivinhável. O CORS aberto é exigido pelo receptor do Chromecast para legendas. Ressalva comum de LAN: a URL trafega em HTTP puro até a TV.
- **INF-03 — Segredo do cliente Google "desktop" no executável:** o Google trata o segredo de aplicativos instalados como não confidencial. O arquivo `.local-secrets/drive-build.json` e o JSON do cliente estão no `.gitignore` e **não** estão no histórico do Git.
- **INF-04 — Bibliotecas nativas do `media_kit`:** `media_kit_libs_windows_video` 1.0.11 e `media_kit_libs_android_video` 1.3.8 trazem libmpv e FFmpeg compilados. O OSV não cobre binários nativos. Atualizar esses pacotes é a forma de receber correções dessas bibliotecas.

---

## 4. Verificações sem achado

| Item do roteiro | Resultado |
|---|---|
| Vulnerabilidades conhecidas (OSV, `POST /v1/querybatch`) | **142 pacotes Pub hospedados** com versão exata do `pubspec.lock`: **0 correspondências**. Não cobre dependências nativas Gradle/Windows, Dart SDK nem falhas ainda não catalogadas |
| Pacotes desatualizados (`dart pub outdated`) | `asn1lib`, `crypto`, `file_picker`, `shared_preferences` com patch/minor novo; `tray_manager`, `window_manager`, `cupertino_icons` com major novo. **Sem advisory**: tratado como INFO de manutenção, nenhum upgrade feito |
| Segredos no Git | `git ls-files` sem `.pem/.key/.jks/.keystore/.p12/.env/google-services.json`; só `android/key.properties.example` (modelo com `PREENCHER_LOCALMENTE`). Histórico (`git log --diff-filter=A`) sem segredos. Varredura por padrões (`AIza…`, `GOCSPX-…`, `*.apps.googleusercontent.com`, chaves PEM) em `lib`, `test`, `android`, `windows` e `docs`: 0 ocorrências |
| Login OAuth (Windows e Android) | Servidor só em `127.0.0.1`, porta efêmera; verificação de `state`; PKCE `S256`; timeout de 3 minutos; escopos mínimos (`drive.readonly`; `Files.Read offline_access`) |
| ADB | `_validate` exige IP de rede local e porta válida; `launch` valida o componente com regex (sem injeção de shell); a porta descoberta por mDNS só é aceita quando o endereço anunciado é o do aparelho selecionado; o `MulticastLock` é liberado no `finally` e em `onDestroy` |
| Código nativo novo (`MainActivity.kt`) | O canal `sixf/library` é interno ao app; `thumbnail` grava JPEG em caminho recebido do Dart, dentro do cache privado; `MainActivity` exportada é a de lançamento, necessária |
| Wake-on-LAN | `parseMacAddress` exige exatamente 12 dígitos hexadecimais; MAC inválido retorna `null` e nada é enviado |
| SSDP/UDP | Janela de varredura de 4 s; sockets fechados no cancelamento; sondas com limite de 1 s. O fechamento no fim normal da varredura não foi rastreado linha a linha nesta rodada |
| Payloads de socket | `jsonDecode` com `try` nos drivers LG (`webos_service`), Samsung e Cast; `lg_webos_driver.dart` não decodifica JSON diretamente |
| Windows (`msix`) | Capacidades mínimas: `internetClient` e `privateNetworkClientServer` |

---

## 5. Patches Sugeridos (apenas propostas; nenhum foi aplicado)

Não há CRITICAL ou HIGH. As propostas abaixo são curtas e de baixo risco, para os achados SEC-08 a SEC-12.

**SEC-08 — desligar o backup automático**
```diff
--- a/android/app/src/main/AndroidManifest.xml
+++ b/android/app/src/main/AndroidManifest.xml
     <application
         android:label="SixF Remote"
         android:name="${applicationName}"
+        android:allowBackup="false"
         android:usesCleartextTraffic="true"
```

**SEC-09 — não gravar o token no descritor**
```diff
--- a/lib/services/library_sources.dart
+++ b/lib/services/library_sources.dart
           'size': resolvedSize ?? 0,
-          'headers': {'Authorization': 'Bearer $authToken'},
         }),
```
Antes de aplicar, trocar a leitura de `headers` em `media_server_service.dart:40–41` e `media_cast_controller.dart:857–858` por `LibrarySources.freshTokenForSourceName(...)`.

**SEC-10 — token apenas para hosts do Google**
```diff
--- a/lib/services/thumbnail_service.dart
+++ b/lib/services/thumbnail_service.dart
+  static bool _sendsToken(Uri uri) =>
+      uri.host.endsWith('.googleapis.com') ||
+      uri.host.endsWith('.googleusercontent.com');
@@
-    final attempts = <Map<String, String>>[
-      if (token != null) {'Authorization': 'Bearer $token'},
+    final attempts = <Map<String, String>>[
+      if (token != null && _sendsToken(uri)) {'Authorization': 'Bearer $token'},
       if (!authOnly) const {},
     ];
```

**SEC-11 — mesmo padrão dos outros sockets**
```diff
--- a/lib/services/google_cast_media.dart
+++ b/lib/services/google_cast_media.dart
-      onBadCertificate: (_) => true,
+      onBadCertificate: (_) => NetworkSecurityUtils.isLocalNetworkHost(host),
```

**SEC-12 — remover permissões não usadas**
```diff
--- a/android/app/src/main/AndroidManifest.xml
+++ b/android/app/src/main/AndroidManifest.xml
-    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
-    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
-    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
-    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
```

**SEC-07 não tem patch curto:** é uma migração (armazenamento seguro com cópia dos valores existentes, sem apagar pareamentos). Merece uma tarefa própria, com testes.

---

## 6. Próximos Passos Recomendados

1. **Agora, de graça:** aplicar SEC-08 e SEC-12 (duas edições no manifesto) e SEC-11 (uma linha). Testar a escolha de pasta no Android depois do SEC-12.
2. **Em seguida:** SEC-09 e SEC-10, que são pequenos e removem os dois pontos em que o token sai do lugar certo.
3. **Quando houver tempo:** SEC-07, a migração para armazenamento seguro, começando pelos refresh tokens e pelas chaves privadas.
4. **Rotina:** reexecutar o OSV a cada atualização do `pubspec.lock` e rever `media_kit_libs_*` junto das atualizações do `media_kit`.
5. **Registro:** a pendência RES-03 (limpar o cache da sessão em Stop e dispose) continua aberta e se encerra junto com o SEC-09.
