# Filtro Anti-Falso-Positivo — Flutter & Smart Remote

Para garantir que o relatório de segurança seja respeitado e útil para engenheiros de software, evite os seguintes falsos positivos clássicos:

---

## 1. `usesCleartextTraffic="true"` no Android
- **Cenário:** O scanner tradicional de SAST marca `usesCleartextTraffic="true"` como vulnerabilidade ALTA ou CRÍTICA.
- **Contexto IoT/Smart TV:** As Smart TVs Samsung mais comuns comunicam-se via WebSocket sem criptografia na porta 8001 (`ws://<ip>:8001/api/v2/channels/...`). O protocolo SSDP de descoberta funciona em UDP puro (`239.255.255.250:1900`). Sem essa permissão, o app não funciona na rede local.
- **Classificação Correta:** `INFO` ou `LOW` (com recomendação de limitar domínios via `network_security_config.xml`, se aplicável, e nunca usar HTTP para servidores externos/APIs de nuvem).

---

## 2. Certificados Autoassinados na Conexão com TV LG (`badCertificateCallback`)
- **Cenário:** Aceitar certificados TLS não reconhecidos pela CA pública do sistema operacional.
- **Contexto IoT:** Toda TV LG webOS moderna gera um certificado SSL autoassinado no firmware para a porta 3001 (`wss://<ip>:3001`). Uma autoridade certificadora pública (Let's Encrypt, DigiCert) não pode emitir certificados para IPs locais como `192.168.1.50`. Logo, ignorar a validação padrão de CA para a TV é **obrigatório**.
- **O que REALMENTE é falha:** Aceitar cegamente certificados sem verificar se o IP destino é de fato da rede local (`192.168.x.x`, `10.x.x.x`) ou não validar o hash do certificado após o primeiro pareamento (*Certificate Pinning* local).

---

## 3. "Pacote com versão mais recente disponível"
- **Regra:** Nunca apontar `CRITICAL` ou `HIGH` apenas porque `dart pub outdated` indica que existe uma versão mais recente de um pacote (ex: `provider 6.1.2` vs `6.1.5`).
- **Critério:** Só reportar se houver um CVE registrado ou um aviso público de vulnerabilidade explorável que afete o caso de uso do app. Sem isso, classificar como `INFO` (manutenção de rotina).

---

## 4. `SharedPreferences` para configurações não sensíveis
- **Cenário:** Guardar preferências do usuário em `SharedPreferences` (volume inicial, tema escuro, último IP conectado).
- **Classificação:** Não é vulnerabilidade. Apenas tokens de longa duração e chaves de segurança críticas demandam armazenamento seguro (`flutter_secure_storage`).
