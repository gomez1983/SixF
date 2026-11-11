# 🛡️ Relatório de Auditoria de Código e Segurança — SixF Smart Remote

**Data da Auditoria:** 2026-11-08
**Escopo Auditado:** `C:\Projetos\SixF` (raiz), commit `b185bfc` (branch `main`)
**Procedimento:** skill `.agents/skills/auditoria-codigo` (8 passos), primeira execução no projeto
**Arquivo Persistido:** `docs/security/audits/2026-11-08-auditoria.md`

Auditoria somente leitura. Nenhum arquivo de código, dependência, preferência, credencial ou pareamento foi alterado. Nenhum comando foi enviado a TV ou Chromecast. Os patches da seção 3 são **propostas** e não foram aplicados.

---

### 🔍 Stack e Arquitetura Detectada
- **Ambiente/Linguagem:** Dart / Flutter (Android e Windows)
- **Componentes de Dados/Rede:** WebSockets SSAP (LG) e Tizen (Samsung), Android TV Remote v2 + Google Cast (Chromecast), ADB por Wi-Fi, SSDP/mDNS, Wake-on-LAN, servidor HTTP local de mídia (DLNA/Cast), OAuth Google Drive / OneDrive
- **Mecanismos de Defesa Identificados:** `NetworkSecurityUtils.isLocalNetworkHost` nos callbacks de certificado (DLNA, Cast, ADB, WebSocket genérico, Google TV); token aleatório de 256 bits no caminho do servidor de mídia; OAuth em loopback com `state` + PKCE S256; allowlist de hosts para o Bearer das miniaturas; `allowBackup="false"`; logs sem segredos.

---

## 📊 1. Resumo Executivo de Severidade

| Severidade | Quantidade | Postura Geral |
| :--- | :---: | :--- |
| 🔴 **CRITICAL** | 0 | — |
| 🟠 **HIGH** | 0 | — |
| 🟡 **MEDIUM** | 1 | SEC-07, já conhecido e ainda aberto |
| 🟢 **LOW** | 2 | SEC-13 e SEC-14, novos |
| 🔵 **INFO** | 5 | Notas de contexto |

**Postura geral:** boa. Das seis pendências da auditoria de 06/11, **cinco foram corrigidas** no commit `b185bfc`. Resta só o SEC-07. Os dois achados novos são de baixo impacto e exigem pré-condição local.

### Evolução desde 06/11

| ID (06/11) | Situação hoje | Evidência |
| :--- | :--- | :--- |
| SEC-07 — segredos em `SharedPreferences` | 🟡 **Aberto** | ver abaixo |
| SEC-08 — `allowBackup` não definido | ✅ Corrigido | `AndroidManifest.xml:12` `allowBackup="false"` |
| SEC-09 — Bearer gravado no `.cloud.json` | ✅ Corrigido | `library_sources.dart:703-714` grava só URL/ID/nome/tamanho |
| SEC-10 — Bearer para qualquer URL de miniatura | ✅ Corrigido | `thumbnail_service.dart:141-156` (allowlist de hosts Google) |
| SEC-11 — `onBadCertificate: (_) => true` no Cast | ✅ Corrigido | `google_cast_media.dart:144` checa IP local |
| SEC-12 — permissões de mídia sem uso | ✅ Corrigido | manifest só tem rede, Wi-Fi, multicast, vibração e microfone |

---

## 🔎 2. Detalhamento dos Achados

### Armazenamento local

#### [SEC-07] Tokens de nuvem e chaves privadas em `SharedPreferences` (texto simples)
- **Severidade:** `MEDIUM` (mantida)
- **Localização:** `lib/services/library_sources.dart:193-210`, `lib/services/google_tv_apps_adb.dart:28-46`, `lib/services/storage_service.dart:101-124`
- **Evidência no Código:**
```dart
await prefs.setString(_refreshPrefKey(source), refreshToken);          // library_sources.dart:207
await prefs.setString('sixf_adb_identity_$host', encoded!);            // google_tv_apps_adb.dart:30-38
result = await _prefs!.setString(idTarget, key);                       // storage_service.dart:112
```
- **Impacto Real:** no Windows, o arquivo fica em `%APPDATA%`, legível por qualquer processo do mesmo usuário. Ele guarda o refresh token do Drive/OneDrive (leitura contínua dos arquivos), a chave privada ADB (controle total do Chromecast por depuração) e as chaves de pareamento das TVs. No Android, o risco é menor: o arquivo fica na sandbox do app e o backup está desligado.
- **Recomendação Técnica:** migrar só esses valores para `flutter_secure_storage`, que usa DPAPI no Windows e Keystore no Android. **Atenção:** a migração mexe no pareamento de todas as TVs e no ADB. Ela precisa de leitura do valor antigo, regravação no cofre e remoção do antigo, além de teste com cada aparelho real. Também exige consultar o BPM-001 e o BPM-009. Não é uma correção para fazer às pressas.

### Rede e protocolos

#### [SEC-13] Descritor `.cloud.json` é aceito ao lado de qualquer arquivo, e a URL dele recebe o Bearer
- **Severidade:** `LOW` (novo; mesma classe do SEC-10, que foi corrigido só nas miniaturas)
- **Localização:** `lib/services/media_server_service.dart:177-185` e `:652-662`, `lib/controllers/media_cast_controller.dart:845-868`
- **Evidência no Código:**
```dart
final cloudMeta = File('${file.path}.cloud.json');        // qualquer arquivo, inclusive local
...
final upstreamReq = await proxyClient.getUrl(Uri.parse(remoteUrl));   // remoteUrl vem do JSON
upstreamReq.headers.set('Authorization', 'Bearer $freshToken');      // source também vem do JSON
```
- **Impacto Real:** o app só cria esse descritor na pasta de cache, sempre com URLs `https://www.googleapis.com` ou `https://graph.microsoft.com`. Mas a leitura não confere isso. Basta existir um `video.mp4.cloud.json` ao lado de um `video.mp4` **local** que o usuário transmita, por exemplo numa pasta baixada ou compartilhada. Com `{"url":"https://atacante/x","source":"drive"}`, o access token do Drive é enviado ao atacante. O token vale cerca de 1 hora e dá leitura de todo o Drive. O refresh token não vaza.
- **Recomendação Técnica:** só aceitar o descritor se a URL for `https` e o host for um dos dois provedores. É o mesmo padrão do `_sendsToken` das miniaturas. Isso não muda o comportamento normal do app, porque as URLs legítimas sempre usam esses hosts. Patch na seção 3.

#### [SEC-14] URL `LOCATION` do SSDP é buscada sem conferir o host
- **Severidade:** `LOW` (novo)
- **Localização:** `lib/services/ssdp_discovery_service.dart:214-220` e `:415-426`
- **Evidência no Código:**
```dart
final uri = Uri.parse(locationUrl);                 // vem da resposta UDP
final request = await client.getUrl(uri).timeout(timeout);
```
- **Impacto Real:** qualquer aparelho da rede local pode responder ao M-SEARCH com uma `LOCATION` apontando para outro endereço, interno ou externo, e o app faz um GET nesse endereço. Não há envio de credenciais e o timeout é de 2 s. O efeito prático é só uma requisição forçada e um nome de TV falso na lista. O DLNA (`dlna_service.dart:209`) já faz essa checagem; o SSDP não.
- **Recomendação Técnica:** aceitar `LOCATION` só quando o host é igual ao IP de quem respondeu e é IP local. Patch na seção 3. Aplicado depois de um teste de descoberta com as TVs reais.

---

## 🛠️ 3. Propostas de Correção (Patches Sugeridos)

> ⚠️ **Revise cada patch antes de aplicar. Nenhuma alteração foi realizada automaticamente no repositório.**

**SEC-13** — validação compartilhada da URL do descritor:

```diff
--- a/lib/services/library_sources.dart
+++ b/lib/services/library_sources.dart
@@ static Future<String?> freshTokenForSourceName(...)
+  /// Só URLs de provedor recebem Bearer. O `.cloud.json` é lido do disco e
+  /// pode estar ao lado de um arquivo local que o app não criou.
+  static bool isTrustedCloudUrl(Object? url) {
+    final uri = url is String ? Uri.tryParse(url) : null;
+    return uri != null &&
+        uri.scheme == 'https' &&
+        (uri.host == 'www.googleapis.com' || uri.host == 'graph.microsoft.com');
+  }
```

```diff
--- a/lib/services/media_server_service.dart
+++ b/lib/services/media_server_service.dart
@@ -180,4 +180,5 @@
         final decoded = jsonDecode(cloudMeta.readAsStringSync());
-        if (decoded is Map<String, dynamic>) {
+        if (decoded is Map<String, dynamic> &&
+            LibrarySources.isTrustedCloudUrl(decoded['url'])) {
           _cloudDescriptor = decoded;
```

```diff
--- a/lib/controllers/media_cast_controller.dart
+++ b/lib/controllers/media_cast_controller.dart
@@ -849,3 +849,4 @@
           final decoded = jsonDecode(cloudMeta.readAsStringSync());
-          if (decoded is Map<String, dynamic>) cloudDesc = decoded;
+          if (decoded is Map<String, dynamic> &&
+              LibrarySources.isTrustedCloudUrl(decoded['url'])) cloudDesc = decoded;
```

**SEC-14** — `LOCATION` só no próprio aparelho que respondeu:

```diff
--- a/lib/services/ssdp_discovery_service.dart
+++ b/lib/services/ssdp_discovery_service.dart
@@ -423,4 +423,8 @@
     try {
       final uri = Uri.parse(locationUrl);
+      if (uri.host != ip || !NetworkSecurityUtils.isLocalNetworkHost(uri.host)) {
+        throw const FormatException('LOCATION fora do aparelho que respondeu.');
+      }
       final request = await client.getUrl(uri).timeout(timeout);
```
*(Nesse caso, o `catch` em `:223` já mantém a TV na lista pelo IP de quem respondeu, então a descoberta continua funcionando.)*

---

## 📦 4. Análise de Dependências e CVEs
- **Consulta OSV (`api.osv.dev/v1/querybatch`, ecossistema Pub):** 142 pacotes *hosted* do `pubspec.lock`, versões exatas. **Nenhuma vulnerabilidade conhecida.**
- Não há dependências por `git` ou `path`.
- **[INF-04, mantido]** `media_kit_libs_*` empacota libmpv/FFmpeg nativos, que o OSV do Pub não cobre. Para conferir, verifique periodicamente os avisos do FFmpeg/mpv nas versões empacotadas.

---

## 🔑 5. Varredura de Segredos e Arquivos Rastreados
- **`git ls-files`:** nenhum certificado, chave, keystore ou JSON de credencial rastreado. `lib/services/drivers/google_tv/credentials.dart` é código (classe `GoogleTvCredentials`), não um segredo. `android/key.properties.example` é só um modelo.
- **Histórico Git (`git log --all --name-only`):** nenhum arquivo sensível jamais foi commitado.
- **Arquivos locais ignorados (ok):** `.local-secrets/` (JSON do cliente OAuth Google e config de build), `drive_secrets.json`, `cert.pem`, `key.pem` e `android/key.properties`, todos cobertos pelo `.gitignore`.
- **Código-fonte:** nenhuma chave de API, segredo de cliente, chave privada ou senha hardcoded. O segredo do cliente "desktop" entra por `--dart-define`.
- **Logs:** os `debugPrint` mencionam token e client-key só como "presente/recebido", sem o valor.

---

## 🔵 Notas INFO

- **INF-01** `usesCleartextTraffic="true"`: necessário para Samsung na porta 8001, DLNA e o servidor de mídia local. Esperado.
- **INF-02** Servidor de mídia em `InternetAddress.anyIPv4` com CORS `*`: o caminho exige o token de 256 bits (`Random.secure`), a comparação de rota é exata e só aceita GET/HEAD/OPTIONS. Esperado para o Cast/DLNA funcionar.
- **INF-03** Segredo do cliente Google "desktop" embutido no executável: o Google trata esse segredo como não confidencial em apps instalados, e o fluxo usa PKCE. Esperado.
- **INF-05** `cert.pem` e `key.pem` na raiz do projeto: ignorados pelo Git e sem uso no código (só citados em `docs/GUIA_SKILL_AUDITORIA_SEGURANCA.md`). Se não forem mais necessários, mova para fora da pasta do projeto para reduzir o risco de vazamento acidental, por exemplo num zip do projeto.
- **INF-06** Drivers LG e Samsung não recusam IP público, ao contrário do `GoogleTvDriver:236`. Em `samsung_tizen_driver.dart:319`, o certificado é aceito só para o IP escolhido (`host == ip`), o que já limita o risco. Seria só uma questão de consistência.

---

## 🧹 6. Falsos Positivos Descartados
- `badCertificateCallback` em DLNA, SSDP/Samsung, WebSocket e Cast: todos restritos a IP privado ou ao IP escolhido. É o padrão de firmware das TVs (LG 3001, Samsung 8002, Chromecast 6466/6467).
- Servidor OAuth local (`library_sources.dart:345`): escuta só em loopback, valida `state` e usa PKCE S256.
- Wake-on-LAN: o MAC é validado (6 bytes) antes de montar o pacote mágico (`wake_on_lan_service.dart:30-33`), e o socket é fechado.
- Sockets SSDP: fechados no `finally` (`ssdp_discovery_service.dart:236-240`).
- `RECORD_AUDIO`: usada pelo comando de voz (`speech_to_text`, `record`).
- `exported="true"` na `MainActivity`: obrigatório para a activity de LAUNCHER.
- Escopo do Drive: `drive.readonly` (mínimo necessário).

---

## 🎯 7. Conclusão e Prioridades de Remediação
1. **SEC-13 (LOW, correção simples e segura):** o patch não muda o fluxo normal e fecha o único vazamento de token remanescente. É a melhor relação benefício/risco.
2. **SEC-14 (LOW):** aplicar depois de um teste de descoberta com as TVs reais.
3. **SEC-07 (MEDIUM, médio prazo):** migração para `flutter_secure_storage` planejada com cuidado, porque envolve todos os pareamentos e o ADB. Testar aparelho por aparelho.
4. INF-05: decisão sua sobre os arquivos `.pem` locais.

Esta classificação não certifica a ausência de outras vulnerabilidades.
