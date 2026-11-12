# Guia Definitivo: Como Publicar Aplicativos nas Lojas Oficiais (Microsoft, Google e Apple)

Este guia serve como referência rápida para publicação de aplicativos (especialmente projetos desenvolvidos em Flutter/Multiplataforma) nas três principais lojas de aplicativos do mercado.

---

## 📑 Resumo Rápido de Custos e Requisitos

| Loja | Plataforma | Custo da Conta | Frequência | Exigência Especial |
| :--- | :--- | :--- | :--- | :--- |
| **Microsoft Store** | Windows (PC) | ~$19 USD (~R$ 100) | **Taxa única** (vitalícia) | Formato MSIX |
| **Google Play Store** | Android | $25 USD (~R$ 140) | **Taxa única** (vitalícia) | Teste fechado de 14 dias (20 testadores) |
| **Apple App Store** | iOS / iPadOS / macOS | $99 USD (~R$ 550) | **Anuidade** (por ano) | Exige computador Mac para compilar |

---

# 1. 🪟 Microsoft Store (Windows)

A Microsoft Store é a mais simples e rápida de aprovar entre as três.

### Passo 1: Cadastro
1. Acesse o [Microsoft Partner Center](https://partner.microsoft.com/dashboard/registration).
2. Cadastre-se como Desenvolvedor Individual (taxa única de ~$19 USD).
3. Conclua a validação de identidade básica da Microsoft.

### Passo 2: Reservar o Nome do Aplicativo
1. No painel do Partner Center, vá em **Apps and games** > **New product** > **MSIX or PWA app**.
2. Digite o nome desejado e clique em **Reserve product name**.
3. Guarde os dados gerados pela Microsoft:
   - **Identity Name (Package Name)** (ex: `12345Dev.LGSmartRemote`)
   - **Publisher ID** (ex: `CN=XXXXX-XXXX...`)
   - **Publisher Display Name**

### Passo 3: Configurar o Projeto (Flutter)
No arquivo `pubspec.yaml`, adicione o pacote `msix` em `dev_dependencies` e preencha as configurações da loja:
```yaml
msix_config:
  display_name: Nome do Aplicativo
  publisher_display_name: "Seu Nome de Desenvolvedor"
  identity_name: "ID_DA_MICROSOFT"
  publisher: "CN=SEU_PUBLISHER_ID"
  msix_version: 1.0.0.0
  logo_path: assets/icons/icone.png
  store: true
  capabilities: internetClient, privateNetworkClientServer
```

### Passo 4: Gerar o Pacote
No terminal do projeto:
```powershell
flutter build windows --release
dart run msix:create
```
Isso gerará o arquivo `.msix` assinado para envio à loja.

### Passo 5: Enviar para Publicação
1. No Partner Center, abra a submissão do app.
2. Faça o upload do arquivo `.msix`.
3. Preencha a descrição, categoria, classificação etária e adicione pelo menos 1 ou 2 capturas de tela (screenshots).
4. Clique em **Submit to the Store**. Aprovação em **24 a 72 horas**.

---

# 2. 🤖 Google Play Store (Android)

A maior loja mobile do mundo. Tem regras rígidas de teste para novas contas pessoais.

### Passo 1: Cadastro
1. Acesse o [Google Play Console](https://play.google.com/console).
2. Crie sua conta de desenvolvedor pagando a taxa única de **$25 USD**.
3. Envie comprovante de identidade (RG/CNH) e endereço solicitados pelo Google.

### Passo 2: Preparar o Projeto (Flutter)
1. **Permissões (`android/app/src/main/AndroidManifest.xml`)**:
   Declare apenas as permissões realmente necessárias (ex: `INTERNET`, `ACCESS_NETWORK_STATE`).
2. **Chave de Assinatura (Keystore)**:
   Gere uma chave privada segura via terminal:
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   Configure o arquivo `android/key.properties` apontando para essa chave.

### Passo 3: Gerar o Pacote Oficial (.aab)
A Play Store não aceita mais APK para publicação; deve ser Android App Bundle:
```bash
flutter build appbundle --release
```
O arquivo gerado fica em `build/app/outputs/bundle/release/app-release.aab`.

### Passo 4: Ficha da Loja e Requisitos Legais
No Play Console:
1. **Ficha da Loja**: Título, descrição curta, descrição completa, ícone (512x512) e imagem promocional (1024x500).
2. **Screenshots**: Pelo menos 2 prints de tela do app no celular.
3. **Política de Privacidade**: Link obrigatório explicando o tratamento de dados (pode ser uma página simples no GitHub Pages ou Notion).

### Passo 5: Teste Fechado Obrigatório (Regra 2023+)
- Para contas pessoais novas, você precisa convidar **20 testadores** (amigos ou comunidades de desenvolvedores).
- Os 20 testadores devem permanecer com o app instalado por **14 dias ininterruptos**.
- Após 14 dias, o Google libera a opção de solicitar publicação em **Produção**.

### Passo 6: Revisão Final
Envio para produção. Avaliação entre **2 e 5 dias úteis**.

---

# 3. 🍏 Apple App Store (iOS / macOS)

A loja com os usuários de maior poder de compra, porém a mais exigente em design, privacidade e infraestrutura técnica.

### Passo 1: Requisito Obrigatório de Hardware
- **Você DEVE ter um computador Mac (macOS)** com o **Xcode** instalado.
- Não é possível compilar ou enviar apps iOS nativos oficialmente a partir do Windows/Linux puro (a menos que use serviços em nuvem pagos como Codemagic ou GitHub Actions com runners macOS).

### Passo 2: Conta Apple Developer Program
1. Acesse o [Apple Developer](https://developer.apple.com/).
2. Crie uma conta no programa de desenvolvedor.
3. Custo: **$99 USD por ano** (renovação anual obrigatória para manter o app no ar).
4. A aprovação da conta exige validação em duas etapas (2FA) e pode levar 48h.

### Passo 3: Certificados e Identificadores
No portal do Apple Developer:
1. Crie um **App ID** (Bundle Identifier, ex: `com.seunome.controlelg`).
2. Crie um **Distribution Certificate** e um **Provisioning Profile** (o Xcode geralmente faz isso de forma automática se logado na sua conta).

### Passo 4: Compilação e Envio (Flutter + Xcode)
No terminal do Mac:
```bash
flutter build ipa --release
```
Ou abra a pasta `ios/` no Xcode:
1. Selecione o dispositivo alvo como **Any iOS Device (arm64)**.
2. Menu **Product** > **Archive**.
3. Na janela do Organizer, clique em **Distribute App** e selecione **App Store Connect**. O Xcode envia o app direto para a nuvem da Apple.

### Passo 5: App Store Connect
Acesse o [App Store Connect](https://appstoreconnect.apple.com/):
1. Crie um **Novo App** selecionando o Bundle ID registrado.
2. Adicione prints de tela obrigatórios para os tamanhos exigidos (iPhone de 6.7" e 6.5").
3. Preencha descrição, palavras-chave de busca, suporte e link da **Política de Privacidade**.
4. Responda ao questionário de criptografia e conformidade de conteúdo.
5. Selecione o pacote (*build*) enviado pelo Xcode.

### Passo 6: Revisão Humana da Apple
1. Clique em **Enviar para Revisão**.
2. A Apple realiza uma **revisão humana** criteriosa (testam em iPhones reais se há travamentos, botões quebrados ou violações de diretrizes de design).
3. Resposta em **24 a 48 horas**.
