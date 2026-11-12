# Diretrizes do Assistente de IA — SixF Smart Remote

Este documento estabelece as regras de desenvolvimento, padrões arquiteturais e a conexão com a base de conhecimento do **Segundo Cérebro** para agentes de IA atuando neste repositório.

---

## 1. Conexão com o Segundo Cérebro (Obsidian Vault)

A memória técnica, decisões históricas e cadernos de erros deste projeto estão centralizados no cofre do desenvolvedor:

- **Diretório Mestre do Projeto no Vault:**  
  `D:\Google Drive\Meu Drive\Pessoal\My Second Brain\Projetos\Projeto SixF\`
- **Documentação de Arquitetura e Visão Geral:**  
  `D:\Google Drive\Meu Drive\Pessoal\My Second Brain\Projetos\Projeto SixF\Projeto SixF.md`
- **Repositório de Post-Mortems (Caderno de Erros):**  
  `D:\Google Drive\Meu Drive\Pessoal\My Second Brain\Projetos\Projeto SixF\Post-Mortem\`
- **Template Padronizado de Post-Mortem:**  
  `D:\Google Drive\Meu Drive\Pessoal\My Second Brain\Projetos\Template - Bug Post-Mortem.md`

---

## 2. Padrões de Arquitetura e Código

1. **Stack Tecnológica:** Flutter & Dart, `provider` (gerenciamento de estado), `window_manager` e `tray_manager` (Windows), `shared_preferences`.
2. **Padrão Driver / Adapter:**
   - Todo suporte a dispositivos de TV deve implementar a interface base abstrata `TvDriver` (`lib/services/tv_driver.dart`).
   - Drivers concretos: `LgWebOsDriver` (webOS SSAP porta 3000/3001), `SamsungTizenDriver` (WebSocket portas 8001/8002) e `GoogleTvDriver` (Chromecast com Google TV, portas 6466/6467).
   - Instanciação centralizada exclusivamente pela `DriverFactory`.
3. **Restrições de Escopo e Decisões Históricas (Atenção Crítica):**
   - **Chromecast com Google TV (suporte ativo):** O antigo `AndroidTvDriver` (Google Cast v2 / porta 8443) foi descontinuado em 09/2026 por instabilidade de token e mTLS. O suporte foi **retomado por autorização expressa do desenvolvedor**, restrito ao **Chromecast com Google TV** (Android 14, modelo com controle físico), através do `GoogleTvDriver` (`lib/services/drivers/google_tv_driver.dart`):
     - Controle via **Android TV Remote Service v2** — porta de controle `6466`, pareamento por PIN hexadecimal na porta `6467`, identidade TLS (certificado RSA) persistente por aparelho.
     - Mídia via **Google Cast** (Default Media Receiver), protocolo distinto do controle.
     - Lista e abertura de aplicativos instalados via **ADB por Depuração sem fio** (`GoogleTvAppsAdb`), canal opcional autorizado separadamente pelo usuário.
     - Outros aparelhos Android TV (Sony, TCL, Philips etc.) **não** estão no escopo. Antes de alterar sessão, TLS, pareamento ou ADB do Chromecast, consulte o [BPM-001](file:///d:/Google%20Drive/Meu%20Drive/Pessoal/My%20Second%20Brain/Projetos/Projeto%20SixF/Post-Mortem/BPM-001%20-%20Instabilidade%20TLS%20e%20Sessao%20no%20Google%20Cast%20Remote%20v2.md) (inclui a seção de retomada) e o BPM-009 (colisão de identidades e falso repareamento).
4. **Descoberta de Rede:**
   - Descoberta automatizada via **SSDP / UDP Broadcast** e Wake-on-LAN (`wol`).

---

## 3. Protocolo de Investigação de Bugs e Post-Mortem

1. **Consulta Prévia Obrigatória:** Antes de propor refatorações em WebSockets, ciclo de vida do app em segundo plano no Android ou descoberta SSDP, consulte as notas em `D:\...\Projetos\Projeto SixF\Post-Mortem\` para identificar soluções já validadas e anti-padrões conhecidos.
2. **Critério de Registro de Post-Mortem:**
   - Erros simples de UI, layout ou refatorações pontuais **não devem** gerar notas no vault.
   - Somente crie um novo Post-Mortem para problemas complexos de protocolo, falhas de conectividade assíncrona ou quando expressamente solicitado pelo desenvolvedor.

---

## 4. Política de Versionamento Git

- O assistente **nunca deve executar `git commit` ou `git push`** de forma autônoma.
- Todas as alterações de código devem permanecer no *working tree* para inspeção e aprovação humana prévia.

---

## 5. Gatilhos Proativos de Auditoria de Segurança (`flutter-security-audit` e `auditoria-codigo`)

O assistente deve **identificar proativamente** os momentos ideais e **avisar/recomendar ao desenvolvedor** a execução da skill `flutter-security-audit` antes de concluir tarefas nas seguintes situações:
1. **Novas Dependências ou Upgrades:** Modificações no `pubspec.yaml` (adição de pacotes ou comandos de upgrade de dependências).
2. **Alterações em Rede e Protocolos:** Criação ou modificação de drivers (`TvDriver`), sockets (`WebSocket`, `RawDatagramSocket`), SSDP ou Wake-on-LAN.
3. **Persistência de Dados Sensíveis:** Mudanças no `StorageService` envolvendo chaves de TV, tokens ou senhas.
4. **Permissões de Plataforma:** Alterações no `AndroidManifest.xml` (permissões, flags de tráfego claro) ou runners nativos do Windows.
5. **Preparação de Release:** Sempre que o usuário mencionar publicação nas lojas (Google Play, Microsoft Store), builds de instalador (`.iss`, `.msix`) ou lançamento de versão.

**Divisão de uso entre as skills:**
- `flutter-security-audit`: auditoria padrão do SixF; conhece o escopo do projeto (drivers, Chromecast/Google TV, ADB) e deve ser a primeira escolha.
- `auditoria-codigo`: varredura complementar e mais ampla (segredos rastreados no Git, taint analysis, relatório em `docs/security/audits/`). Os achados devem ser conferidos contra os post-mortems (BPM-001, BPM-009) antes de serem aceitos, pois a skill não conhece as decisões históricas do projeto.

---

## 6. Protocolo de Contingência — Bloqueio de Ferramentas (`googlecloudtools.datacloud_telemetry`)

Se qualquer chamada de ferramenta falhar com o erro:
`JSON hook "jsonhook__googlecloudtools.datacloud_telemetry_PreToolUse_0_0" failed` ou `Cannot find module '...telemetry_hook_bundle.js'`, o assistente deve **informar imediatamente o usuário** de que o plugin de telemetria recriou o hook corrompido no Windows e exibir o caminho e o comando PowerShell abaixo prontos para cópia:

- **Caminho da pasta:** `C:\Users\andre\.gemini\config\plugins\googlecloudtools.datacloud_telemetry`
- **Comando de neutralização definitiva (PowerShell):**
```powershell
$telemetryDir = "C:\Users\andre\.gemini\config\plugins\googlecloudtools.datacloud_telemetry"
New-Item -ItemType Directory -Path "$telemetryDir\hooks" -Force | Out-Null
foreach ($f in @("$telemetryDir\plugin.json", "$telemetryDir\hooks.json", "$telemetryDir\hooks\hooks.json", "$telemetryDir\telemetry_hook_bundle.js")) {
    if (Test-Path $f) { Set-ItemProperty -Path $f -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue }
}
Set-Content -Path "$telemetryDir\plugin.json" -Value '{"name":"googlecloudtools.datacloud_telemetry","version":"1.0.0","hooks":{}}' -Force
Set-Content -Path "$telemetryDir\hooks.json" -Value '{"hooks":{}}' -Force
Set-Content -Path "$telemetryDir\hooks\hooks.json" -Value '{"hooks":{}}' -Force
Set-Content -Path "$telemetryDir\telemetry_hook_bundle.js" -Value '// neutralized' -Force
foreach ($f in @("$telemetryDir\plugin.json", "$telemetryDir\hooks.json", "$telemetryDir\hooks\hooks.json", "$telemetryDir\telemetry_hook_bundle.js")) {
    Set-ItemProperty -Path $f -Name IsReadOnly -Value $true
}
```

## 7. Política de Builds — Somente Release

Regra definida pelo desenvolvedor em 11/11/2026 para acabar com a confusão entre versões de teste, debug e produção.

1. **Somente Release.** O assistente gera sempre e apenas builds Release. Nunca usar `flutter run`, `flutter build ... --debug` nem `--profile`, e nunca indicar ao desenvolvedor um executável ou APK Debug para teste.
2. **Sem sobras de Debug.** Não deixar artefatos Debug executáveis em `build/` (pasta `build\windows\x64\runner\Debug`, `app-debug.apk`). Se existirem, apagar antes de entregar.
3. **Build ao final de toda alteração.** Ao terminar qualquer alteração de código, gerar os dois Releases, sempre com o arquivo de segredos (sem ele o login do Google Drive/OneDrive não funciona — ver `docs/BIBLIOTECA.md`):
   ```powershell
   flutter build windows --release --dart-define-from-file=.local-secrets/drive-build.json
   flutter build apk --release --dart-define-from-file=.local-secrets/drive-build.json
   ```
4. **Informar os caminhos completos** na resposta final, sempre os dois:
   - Windows: `C:\Projetos\SixF\build\windows\x64\runner\Release\sixf_remote.exe`
   - Android: `C:\Projetos\SixF\build\app\outputs\flutter-apk\app-release.apk`
5. **APK Release exige assinatura.** O build Android Release só compila com `android/key.properties` apontando para a chave de distribuição (ver `docs/DISTRIBUTION.md`, seção "Android release"). Se a chave não estiver configurada, o assistente **avisa o desenvolvedor e não gera APK Debug como substituto**; também não cria chave de assinatura por conta própria.
6. Se um dos builds falhar, dizer qual falhou e por quê, em vez de entregar só o outro em silêncio.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- A committed graphify-out/graph.json is rewritten whole on every build, so a large diff to it in a pull request is expected. Do not flag it as churn or suggest skipping the graph rebuild or its hooks.
