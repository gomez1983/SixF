# Biblioteca de mídia do SixF

Abra **Biblioteca de mídia** na barra inferior, ao lado de **Controle**, **Teclas & Mídia** e **Apps**. Em TVs LG, a barra também apresenta **Magic Trackpad**.

A biblioteca é organizada em três seções estilizadas no padrão **Liquid Glass** (com borda e gradiente violeta alinhados ao seletor de dispositivos):
- **Playlists**: playlists salvas com suporte a favoritar (exibidas no topo), renomear, excluir, reordenar itens com *drag & drop* e enviar para a fila.
- **Fila**: lista de execução temporária retrátil (*accordion*) com reordenação em tempo real sincronizada com a sessão ativa, salvamento como playlist e botão **Limpar tudo e parar** para abortar imediatamente qualquer leitura/transmissão travada.
- **Arquivos**: navegação por pastas locais, **Google Drive** e **OneDrive**, lembrando a última localização acessada. Reconhece vídeos (`.mp4`, `.mkv`, `.mov`, `.avi`, `.webm`, `.m4v`, `.ts`), áudios (`.mp3`, `.m4a`, `.flac`, `.wav`, `.ogg`, `.aac`) e fotos (`.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`, `.bmp`).

## Streaming sob demanda (Range Proxy) e Fotos

- **Vídeos e áudios na nuvem (Google Drive / OneDrive)**: não exigem o download do arquivo completo para o disco local. O `MediaServerService` opera como proxy HTTP Range (`206 Partial Content`), transmitindo sob demanda apenas os trechos requisitados pela Smart TV ou Chromecast para início rápido mesmo em arquivos de vários gigabytes (ex.: `.mkv` e `.mp4`).
- **Fotos e Imagens**: exibem miniaturas (*thumbnails*) na listagem. Ao tocar em uma foto, o SixF abre o visualizador interno com zoom, tira de miniaturas e navegação rápida (**Imagem anterior** / **Próxima imagem**), espelhando simultaneamente a foto em tempo real na TV ou Chromecast conectado.

## Configuração do login direto nas nuvens

Os identificadores abaixo pertencem à instalação do SixF. Passe-os ao Flutter usando `--dart-define-from-file=<caminho-para-json-fora-do-repositorio>` em `flutter run` ou `flutter build`.

| Campo JSON | Registro |
|---|---|
| `GOOGLE_WEB_CLIENT_ID` | No Google Cloud, habilite a Drive API e configure o consentimento para `drive.readonly`. Registre o cliente Android com o pacote `com.andregomez.sixf_remote` e o SHA-1 da assinatura utilizada. Informe neste campo o ID do cliente **Web** associado ao projeto. |
| `GOOGLE_DESKTOP_CLIENT_ID` | ID do cliente OAuth do tipo aplicativo de computador, para o Windows. |
| `GOOGLE_DESKTOP_CLIENT_SECRET` | Valor fornecido com o cliente de computador, quando exigido. |
| `ONEDRIVE_CLIENT_ID` | ID do aplicativo no Microsoft Entra (`Files.Read offline_access`). |

Após a primeira autenticação, o *refresh token* e a sessão OAuth são mantidos de forma persistente para evitar abrir o navegador a cada uso, contando com botão explícito para **Sair da conta** na aba **Arquivos**.

**Os dois builds (Windows e Android) precisam receber o mesmo arquivo:** `flutter build windows --dart-define-from-file=.local-secrets/drive-build.json` e `flutter build apk --dart-define-from-file=.local-secrets/drive-build.json`. Sem ele, o app mostra a mensagem de login não habilitado.

### Google Drive no Android

- Com `GOOGLE_WEB_CLIENT_ID` definido, o Android usa o login nativo (conta do aparelho).
- Sem ele, o Android usa o mesmo fluxo do Windows: abre o navegador, você autoriza e volta ao SixF. Esse fluxo só exige `GOOGLE_DESKTOP_CLIENT_ID`/`SECRET`, que já existem.

### Habilitar o OneDrive (passo a passo, uma única vez)

1. Acesse <https://entra.microsoft.com> com sua conta Microsoft → **Identidade › Aplicativos › Registros de aplicativo › Novo registro**.
2. Nome: `SixF Remote`. Tipos de conta: **Contas em qualquer diretório organizacional e contas pessoais da Microsoft**.
3. URI de redirecionamento: plataforma **Cliente público/nativo (móvel e área de trabalho)**, valor `http://localhost`. Registrar.
4. Em **Autenticação**, deixe **Permitir fluxos de cliente público = Sim**.
5. Em **Permissões de API**, confirme `Microsoft Graph › Files.Read` e `offline_access` (delegadas).
6. Copie o **ID do aplicativo (cliente)** e acrescente ao `.local-secrets/drive-build.json`: `"ONEDRIVE_CLIENT_ID": "<id>"`.
7. Recompile Windows e Android com `--dart-define-from-file` (acima). O mesmo ID serve para os dois.
