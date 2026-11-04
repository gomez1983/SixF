# SixF — implementação e escopo futuro

## Implementado no código

- [x] Windows e Android; drivers LG webOS, Samsung Tizen e Google TV (Remote Service v2).
- [x] Sessões independentes, aparelhos salvos e alternância de controle ativo.
- [x] Credenciais por marca/IP, cancelamento e limpeza de operações.
- [x] Arquivos locais via SSAP/DLNA, URL exclusiva, HEAD/Range e revogação ao encerrar.
- [x] Estado de mídia e controles conforme informações da TV; envio separado de reprodução confirmada.
- [x] Diagnóstico por aparelho, repetição de D-Pad/volume/canais, favoritos persistidos por TV.
- [x] Janela compacta Windows com restauração da geometria e sobreposição anteriores.
- [x] Documentação do escopo real, versões alinhadas, assinatura release independente de debug e CI de validação/build.

Implementado não equivale a homologado em todos os modelos de TV. Consulte docs/DISTRIBUTION.md para a matriz manual e os resultados locais registrados.

## Dependências externas da distribuição

- [ ] Homologar em TVs LG e Samsung físicas e Android/Windows reais.
- [ ] Configurar chave Android e certificado/identidade de distribuição Windows.
- [ ] Assinar, revisar instaladores e publicar nas lojas mediante autorização.

## Evoluções fora dos cinco blocos de estabilização

- [ ] Primeiro uso sem cadastro legado predefinido.
- [ ] Identidade estável de aparelho e armazenamento de credenciais protegido pelo sistema operacional.
- [ ] Seleção de interface de rede por rota, revisão de descoberta e validação uniforme dos destinos.
- [ ] Separar responsabilidades restantes do RemoteController e medir custo de notificações.
- [ ] Comandos explícitos de energia/mudo na bandeja e validação de volume absoluto por driver.
- [ ] Rever dependências diretas herdadas do suporte descontinuado, com validação dos builds.
- [ ] Atalhos globais adicionais, widgets e Quick Settings Android.
- [ ] Captura/espelhamento de tela e eventual transcodificação: recursos distintos, não implementados.
- [ ] Monetização, Apple TV, Roku e automações: propostas sem implementação.

Google TV retomado com identidade persistente e protocolo Remote Service v2 (6466/6467), pendente de homologação física. Google Cast para fotos/vídeos e controles de reprodução implementado; Chromecast clássico não oferece o controle de navegação Remote Service v2. iOS não possui projeto/plataforma neste checkout.

Versão 1.0.6: inventário e abertura de apps via ADB autorizados e validados com 23 apps no Chromecast. Transporte de voz corrigido e reconhecimento sintético confirmado; captura física Windows/Android permanece para reteste.

## Biblioteca de mídia vinculada ao aparelho ativo — requisitos acordados em 03/11/2026

**Esta seção é a especificação para a próxima implementação.** O usuário pediu que as decisões abaixo fiquem registradas para que outro agente, inclusive Antigravity, consiga continuar sem reinterpretar a conversa. Os itens permanecem pendentes de implementação e homologação, mesmo que existam peças parciais no código atual.

**Etapa 1 implementada em 03/11/2026:** Biblioteca de mídia como aba inferior do layout móvel, acessível no mesmo nível de Controle, Teclas & Mídia e Apps. O play na biblioteca usa somente o aparelho ativo. O seletor de reprodução local e o player interno foram retirados, junto com suas dependências. A biblioteca continua com o layout provisório, login em memória e seleção que exige playlist. As etapas de fila temporária, visual, login persistente e controles completos permanecem pendentes. A janela larga do Windows também apresenta a barra inferior; a próxima etapa visual deve refinar a transição entre o painel amplo existente e as abas.

### Passagem imediata para Antigravity

- Todo o trabalho atual está **no working tree**, sem commit ou push. Preserve as alterações existentes, inclusive as mudanças de UI que já estavam presentes antes da biblioteca. Não descarte nem sobrescreva arquivos modificados sem revisar o diff.
- A etapa 1 passou em `flutter analyze --no-pub` e `flutter test --no-pub`, com **221 testes aprovados**. O teste `test/media_library_navigation_test.dart` abre a aba na largura Android e Windows. O Graphify foi atualizado após a alteração do código.
- APK Android atualizado em `build/app/outputs/flutter-apk/app-debug.apk`. Executável Windows Release atualizado em `build/windows/x64/runner/Release/sixf_remote.exe`. O build Windows usa `--dart-define-from-file=.local-secrets/drive-build.json`. Em cada etapa posterior, recompilar **ambos** e informar seus caminhos e o resultado da validação ao usuário.
- O cliente OAuth Google de **desktop** e o JSON de build estão em `.local-secrets/`, ignorado pelo Git. Não exibir nem versionar o segredo. A Drive API está ativada no projeto Google Cloud `sixf-remote`. O usuário conseguiu acessar a lista de arquivos no Windows após se cadastrar como testador, mas hoje o login reaparece porque `LibrarySources` mantém o token apenas em memória e uma nova instância é criada ao reabrir a biblioteca. Clientes OAuth Android e Web ainda não foram registrados/configurados para o APK.
- Próxima etapa funcional prioritária, conforme o usuário: **lista de execução temporária** separada de **Criar playlist**, com play direcionado ao aparelho ativo e controles da sessão remota na própria aba. Em seguida, persistência segura do login e refinamento visual no padrão SixF. Seguir os critérios de aceite abaixo. Consultar os post-mortems do vault antes de alterar WebSocket, ciclo de vida Android ou descoberta SSDP. Recomendar `flutter-security-audit` antes de concluir alterações em dependências, rede, credenciais ou permissões.

### Navegação e aparência

- [x] **Biblioteca de mídia** deve ser um quarto item da barra inferior da tela principal, no mesmo nível de **Controle**, **Teclas & Mídia** e **Apps**. Ao tocar nele, mostrar a biblioteca como aba principal. Remover o card/atalho de biblioteca de dentro de **Teclas & Mídia**. Manter o nome **Biblioteca de mídia**. Em LG com Magic Trackpad, a barra apresenta também essa aba específica.
- [x] A aba acompanha o aparelho **ativo e selecionado** no SixF. Com Chromecast selecionado, todos os comandos da biblioteca se destinam ao Chromecast. Ao selecionar uma Smart TV LG ou Samsung, o destino passa a ser essa TV. Usar a mesma identidade de sessão que os controles de volume e mudo usam e refletir claramente o aparelho de destino na interface. Não escolher um aparelho diferente por conta própria.
- [x] O SixF deve navegar, organizar e controlar a reprodução **no aparelho conectado**. A reprodução de vídeo dentro da janela do SixF ou no próprio smartphone ficou **fora do escopo atual**. Remover o player local e o seletor “Neste aparelho / Dispositivo conectado” da experiência principal. A biblioteca não deve começar com reprodução local como padrão.
- [x] A interface da aba, pastas, arquivos, filas e playlists segue o sistema visual já adotado no aplicativo (Liquid Glass). Evitar menus e listas com aparência de ferramenta separada do SixF. Tornar playlists e a fila visíveis e fáceis de alcançar, com estados de carregamento e erro específicos, sem bloquear a navegação inteira durante uma busca ou preparação de episódio.

### Fontes e navegação de arquivos

- [x] Oferecer navegação por pastas e arquivos dentro da aba, para arquivos locais e serviços de nuvem, principalmente **Google Drive** e **OneDrive**. Exibir hierarquia de pastas, voltar, busca/filtro e seleção múltipla. Lembrar a última fonte e a última pasta acessada quando o aplicativo for reaberto, desde que o acesso ainda seja válido.
- [x] Depois da primeira autorização Google, manter a sessão de forma segura para que abrir o Drive novamente não exija confirmação de login a cada visita. Tratar expiração, renovação, revogação e saída da conta. O cliente Windows OAuth já está configurado localmente. O Android ainda requer os clientes OAuth Android e Web no mesmo projeto Google Cloud. Não colocar segredos ou tokens no Git nem em `shared_preferences` sem proteção adequada.
- [x] Guardar playlists usando referências estáveis aos arquivos do provedor, e resolver o acesso no momento da reprodução. Se um arquivo foi movido, excluído ou perdeu autorização, mostrar qual episódio falhou e permitir continuar a fila. Preservar a ordem salva.

### Duas maneiras de selecionar episódios

- [x] **Adicionar à lista de execução / Tocar na TV** adiciona os arquivos selecionados a uma fila temporária, pronta para tocar no aparelho ativo, sem obrigar o usuário a criar ou nomear uma playlist.
- [x] **Criar playlist** salva os arquivos selecionados para uso futuro. Permite nomear, reabrir, adicionar/remover episódios, favoritar e manter as playlists favoritas facilmente visíveis.
- [x] Em ambas, episódios na ordem efetiva com reordenação por **pressionar/clicar e arrastar** (drag & drop no Android e Windows). Fila temporária e playlists salvas com estados separados e persistência de playlists.

### Reprodução e controle remoto de mídia

- [x] Dar play em um arquivo, lista de execução ou playlist envia ao **aparelho ativo**. O SixF orquestra a passagem automática para o episódio seguinte quando receber confirmação confiável de término. Reavaliar o destino ao trocar o aparelho ativo, evitando enviar comandos atrasados ao aparelho anterior.
- [x] Enquanto a mídia toca na TV ou no Chromecast, a aba Biblioteca de mídia mostra controles integrados da sessão remota: play/pause, próximo, anterior, repeat, shuffle, avançar e recuar segundos e progresso/seek. Os comandos controlam a sessão da mídia na TV, não um player dentro do SixF. Indicar indisponibilidade quando o transporte ou modelo não confirmar suporte a determinado comando. Preservar a distinção já existente entre “envio aceito” e “reprodução confirmada”.
- [x] Para fotos, mostrar **próxima imagem** e **imagem anterior** com resposta rápida e navegação pela ordem escolhida. O fluxo não deve exigir reabrir o seletor de arquivos a cada foto.
- [ ] Validar em Chromecast, LG webOS e Samsung Tizen físicos. Testar episódios locais e da nuvem, formatos diferentes, app em segundo plano/tela Android bloqueada, troca de aparelho ativo, fim natural, pausa, seek, repetição, ordem aleatória e falhas de rede/autorização. Não presumir que um comando suportado pelo Chromecast funcione nas TVs sem confirmação do driver.

### Estado atual que precisa ser corrigido

- `lib/ui/views/remote_view.dart` agora inclui a quarta aba inferior e retirou o card de **Teclas & Mídia**. No layout largo Windows, a barra inferior abre a biblioteca integrada, mas as demais entradas continuam mostrando o painel amplo legado.
- `lib/ui/views/media_library.dart` envia a mídia ao aparelho ativo e não contém mais `_LocalPlayer`. Ainda exige escolher/criar uma playlist para adicionar a seleção. Falta a fila temporária independente e a interface visual integrada.
- `lib/controllers/media_cast_controller.dart` já possui partes aproveitáveis: fila, anterior/próximo, loop, shuffle, seek e telemetria Cast, além de distinção entre transportes. Conferir a confirmação de capacidades e o avanço de sequência em cada transporte antes de ligar novos botões.
- `lib/services/library_sources.dart` já lista Drive, OneDrive e pastas locais e resolve arquivos, mas o login precisa persistir com segurança e a experiência precisa lembrar a última localização. `docs/BIBLIOTECA.md` descreve o protótipo anterior e deverá ser atualizado junto da implementação final.

### Critérios de aceite

1. Com Chromecast selecionado, o usuário abre a **quarta aba**, navega no Drive sem repetir o login normal, escolhe episódios, coloca-os na lista de execução sem criar playlist e dá play. O vídeo aparece no Chromecast, e a aba mostra os controles da sessão.
2. O mesmo fluxo com uma LG ou Samsung selecionada envia a mídia para essa TV, com controles limitados às capacidades confirmadas nela.
3. O usuário salva uma playlist, favorita, arrasta episódios para mudar a ordem, fecha e reabre o SixF e encontra a ordem e o favorito preservados.
4. Durante vídeo, play/pause, anterior/próximo, repeat, shuffle e saltos de tempo atuam na sessão remota quando suportados. Durante fotos, anterior/próximo troca a imagem rapidamente.
5. Entregar **ambos os artefatos atualizados**, com caminhos explícitos para o APK Android e o executável Windows, em toda alteração que seja apresentada para teste. Seguir a política do repositório: deixar mudanças no working tree, sem `git commit` ou `git push` automáticos.

### Rodada de 03/11/2026 (tarde) — implementado, pendente de homologação no Windows

- **Login persistente:** o refresh token do Google Drive/OneDrive (Windows) fica salvo; o access token fica só em memória e é renovado sem abrir o navegador. Botão **Sair da conta** na aba Arquivos. Pendência de segurança: o refresh token está em `shared_preferences` sem proteção do sistema operacional; migrar para armazenamento protegido (ex.: `flutter_secure_storage`/DPAPI) exige nova dependência e aprovação.
- **Streaming sob demanda:** vídeos/áudios da nuvem não são mais baixados inteiros. O `MediaServerService` atua como proxy HTTP Range (206) e repassa só o trecho pedido pela TV; o token não é gravado no descritor em disco e é renovado durante filmes longos. Compatibilidade de MKV continua dependendo do decodificador do aparelho (Chromecast não suporta MKV oficialmente; LG/Samsung variam por codec).
- **Fotos:** imagens (jpg, jpeg, png, webp, gif, bmp) aparecem com miniatura; tocar abre visualizador no app com anterior/próxima e tira de miniaturas, espelhando na TV ativa.
- **Limpar fila / Cancelar:** aborta downloads, para o servidor local e a sessão, zera o estado e limpa a fila.
- **Última pasta:** a aba Arquivos reabre na última pasta quando o acesso continua válido. Item que falha na fila fica marcado em vermelho e a reprodução avança para o próximo.
- **Visual:** seletor Playlists/Fila/Arquivos no mesmo padrão das pílulas de aparelho (borda e gradiente violeta). Botões de texto Play/Pausar removidos da linha do tempo (ficam só −10 s e +10 s); Play/Pause do topo não esperam mais o polling de 1 s.
- **Nesta fase, testes só no Windows.** Build Android adiado a pedido do usuário até a interface ser validada no PC.
