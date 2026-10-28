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
