---
name: flutter-security-audit
description: 'Auditoria de segurança para apps Flutter e Dart com foco em Smart Remote e IoT (LG webOS, Samsung Tizen). Analisa dependências no pubspec.lock, segredos expostos, WebSockets locais, SSDP/UDP broadcast, permissões no AndroidManifest e SharedPreferences. Use ao pedir "auditar segurança", "auditoria de segurança", "revisão de segurança", "o código está seguro?", "vulnerabilidades", ou "/flutter-security-audit".'
---

# Flutter & IoT Security Audit (SixF Smart Remote)

Especialista em auditoria defensiva de segurança para ecossistema **Flutter / Dart** e aplicações de controle remoto de Smart TVs / IoT (LG webOS e Samsung Tizen).

**Objetivo:** Identificar vulnerabilidades reais, vazamento de chaves locais, falhas de protocolo de rede e configurações inseguras de plataforma, apresentando um relatório estruturado em português com propostas de correção (sem alterar o código sem autorização).

---

## Princípios Fundamentais

1. **Evidência Real > Alarme Falso:** Nunca reportar um pacote só porque "saiu uma versão mais nova". Apenas vulnerabilidades conhecidas (CVE/GHSA/Advisories) ou práticas comprovadamente inseguras no código justificam alertas `CRITICAL` ou `HIGH`.
2. **Contexto de Rede Local (IoT / LAN):** Conexões para TVs ocorrem em rede local privada (`192.168.x.x`, `10.x.x.x`). TVs costumam usar certificados autoassinados (ex: LG webOS na porta 3001) ou conexões HTTP/WS diretas (Samsung Tizen porta 8001). Distinguir o que é limitação de protocolo da TV do que é negligência de segurança do app.
3. **Segredos e Tokens de Emparelhamento:** Tokens de cliente (LG Client Key, Samsung App Token) garantem autorização permanente na TV. Não devem ser versionados no Git nem gravados em texto puro onde backups de terceiros possam ler sem proteção.
4. **Patches são Propostas:** Nunca executar refatorações invasivas sem validação humana prévia.

---

## Fluxo de Execução (Passo a Passo)

### Step 1 — Mapeamento do Escopo e Stack Real
1. Inspecionar o `pubspec.yaml` e `pubspec.lock` para levantar as versões instaladas:
   - Framework: Versão do SDK Flutter / Dart.
   - Bibliotecas de rede e sockets: `web_socket_channel`, `http`, `network_info_plus`, etc.
   - Gerenciamento de estado e storage: `provider`, `shared_preferences`, etc.
   - Plugins de plataforma: `window_manager`, `tray_manager`.

### Step 2 — Dependências e Vulnerabilidades de Pacotes
1. Verificar integridade e advisories:
   - Rodar `dart pub outdated` para mapear defasagens críticas.
   - Inspecionar pacotes com histórico de falhas de buffer, sockets desprotegidos ou deserialização insegura.
   - Checar se versões no `pubspec.lock` possuem vulnerabilidades conhecidas no banco de dados de segurança do Dart/Pub (`osv.dev` / GitHub Advisory).

### Step 3 — Varredura de Segredos e Certificados (Secrets & Git Tracking)
1. Rodar `git ls-files` para verificar se há arquivos sensíveis sendo rastreados no Git:
   - Certificados SSL/TLS (`.pem`, `.crt`, `.key`, `.p12`, `.keystore`, `.jks`).
   - Arquivos de configuração de ambiente (`.env`, `secrets.json`, `google-services.json`).
2. Analisar o código em busca de:
   - Hardcoded IP, MAC Address, tokens estáticos ou senhas no código fonte ou nos testes.
   - Armazenamento em `SharedPreferences`: verificar se tokens sensíveis de emparelhamento estão sendo gravados sem criptografia básica ou se deveriam usar `flutter_secure_storage`.

### Step 4 — Auditoria de Protocolos e Superfície de Rede
Consultar `refs/audit-checklist.md`:
1. **WebSockets (LG webOS & Samsung Tizen):**
   - Validação de Handshake e Headers de Origem (`Origin: ...`).
   - Tratamento de certificados TLS no `SecurityContext` (porta 3001 da LG usa SSL autoassinado — checar se `badCertificateCallback` aceita cegamente qualquer certificado da internet ou se restringe ao contexto da TV/LAN).
   - Sanitização de payloads JSON recebidos via socket (proteção contra mensagens malformadas que causem crash na UI ou loop infinito).
2. **SSDP / UDP Broadcast & Wake-on-LAN:**
   - Tratamento de pacotes UDP inesperados ou com tamanho anômalo.
   - Timeout explícito em sockets UDP para não segurar portas abertas ou drenar bateria/CPU.
   - Validação do endereço MAC antes de disparar o pacote mágico Wake-on-LAN (evitar injeção de parâmetros ou broadcast descontrolado).

### Step 5 — Plataforma & Permissões (Android & Windows)
1. **Android (`android/app/src/main/AndroidManifest.xml`):**
   - Checar `android:usesCleartextTraffic`: necessário para portas WS sem TLS da Samsung (8001) e SSDP (1900), mas deve ser documentado e mitigado com `network_security_config.xml` se possível.
   - Permissões: verificar se há permissões perigosas ou desnecessárias (`INTERNET`, `ACCESS_NETWORK_STATE`, `CHANGE_WIFI_MULTICAST_STATE` são esperadas; qualquer outra deve ser justificada).
   - Componentes exportados (`android:exported="true"`) sem intenção explícita.
2. **Windows (`windows/runner/`):**
   - Configurações de firewall local e integridade de DLLs e binários gerados.

### Step 6 — Filtro de Falsos Positivos
Consultar `refs/false-positives.md` antes de gerar qualquer achado. Eliminar suposições que desconsiderem a natureza local de uma Smart TV.

### Step 7 — Relatório e Plano de Ação
Gerar o relatório seguindo o modelo em `refs/report-template.md`:
- Sumário Executivo.
- Tabela de Vulnerabilidades (ID, Severidade, Componente, Resumo).
- Detalhamento de cada Achado (Contexto, Impacto, Prova de Conceito/Trecho de Código, Mitigação Proposta).
- Código de Patch sugerido para itens `CRITICAL` e `HIGH`.
