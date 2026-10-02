# Checklist de Auditoria — Flutter & IoT (SixF)

Este checklist guia a inspeção estática e dinâmica de segurança em aplicativos Flutter focados em Smart TV e dispositivos de rede local.

---

## 1. Superfície de Rede e WebSockets

- [ ] **Validação do `badCertificateCallback` (LG webOS / TLS):**
  - O aplicativo conecta na porta 3001 via TLS?
  - O callback aceita cegamente qualquer certificado da internet ou valida se o host é um IP de rede local privada (`192.168.x.x`, `10.x.x.x`, `172.16-31.x.x`)?
  - Há pinning de chave pública para o certificado emitido pela TV no primeiro pareamento?
- [ ] **Sanitização de Payloads de Entrada:**
  - O deserializador `jsonDecode` está protegido por bloco `try-catch` contra JSONs corrompidos ou maliciosos enviados por atores locais na rede?
  - Há validação de limites de tamanho nos pacotes de resposta da TV antes de alocar memória?
- [ ] **Origem e Headers no Handshake:**
  - O WebSocket da Samsung Tizen envia o Header de identificação correto e sem vazamento de metadados desnecessários do dispositivo do usuário?

---

## 2. SSDP / UDP Broadcast & Wake-on-LAN

- [ ] **Controle de Timeout no Socket UDP:**
  - O socket UDP de busca SSDP (`239.255.255.250:1900`) possui fechamento explícito (`socket.close()`) após timeout razoável (3 a 5 segundos)?
  - Há proteção contra loop infinito em caso de tempestade de pacotes (*broadcast storm*)?
- [ ] **Sanitização de Header HTTP/SSDP:**
  - O parser de cabeçalhos de resposta SSDP trata corretamente campos truncados, quebras de linha (`\r\n`) ou valores nulos sem causar vazamento de memória ou travamento do app?
- [ ] **Validação de Endereço MAC (Wake-on-LAN):**
  - O endereço MAC fornecido para o pacote mágico é validado com Regex antes do envio (`^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$`)?

---

## 3. Armazenamento e Segredos (Storage & Secrets)

- [ ] **Rastreamento de Certificados e Chaves no Git:**
  - Arquivos `.pem`, `.key`, `.keystore` ou `.jks` estão listados no `.gitignore`?
  - Estão acidentalmente versionados no repositório (`git ls-files`)?
- [ ] **Chaves de Pareamento do Usuário:**
  - A `client-key` da LG e o token da Samsung são salvos em `shared_preferences` em texto puro?
  - Em ambientes móveis (Android), esses tokens poderiam ser lidos via backup do ADB ou acessados por outros processos se o aparelho estiver rooteado?
  - Avaliação: Justifica-se a migração para `flutter_secure_storage` (Keystore / EncryptedSharedPreferences)?

---

## 4. Configuração de Plataforma (Android & Windows)

- [ ] **`AndroidManifest.xml`:**
  - `android:usesCleartextTraffic="true"`: É necessário para comunicação local HTTP/WS com a TV, mas deve ser documentado. Verificar se não há tráfego de internet pública sendo feito em HTTP puro.
  - Permissões: Existem apenas permissões de rede necessárias (`INTERNET`, `ACCESS_NETWORK_STATE`, `CHANGE_WIFI_MULTICAST_STATE`)?
  - Todas as Activities, Services ou Receivers têm `android:exported="false"` a menos que devam explicitamente ser chamados externamente?
- [ ] **Windows Runner:**
  - As bibliotecas de terceiros nativas (DLLs do `window_manager`, `tray_manager`) são de fontes confiáveis e suas versões estão travadas?
