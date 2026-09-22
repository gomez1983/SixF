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
   - Drivers concretos: `LgWebOsDriver` (webOS SSAP porta 3000/3001) e `SamsungTizenDriver` (WebSocket portas 8001/8002).
   - Instanciação centralizada exclusivamente pela `DriverFactory`.
3. **Restrições de Escopo e Decisões Históricas (Atenção Crítica):**
   - **Android TV / Google Cast v2:** O suporte a Android TV foi oficialmente **descontinuado** devido a instabilidades crônicas de expiração de token e mTLS no protocolo Cast v2. **Não tente reescrever ou reativar o `AndroidTvDriver` sem consultar o [BPM-001](file:///d:/Google%20Drive/Meu%20Drive/Pessoal/My%20Second%20Brain/Projetos/Projeto%20SixF/Post-Mortem/BPM-001%20-%20Instabilidade%20TLS%20e%20Sessao%20no%20Google%20Cast%20Remote%20v2.md).**
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
