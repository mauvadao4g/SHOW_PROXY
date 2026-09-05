# SHOW_PROXY

Proxy MITM (man-in-the-middle) pra monitorar, inspecionar e exportar as requisições
HTTP/HTTPS de um app Android (APK) rodando num dispositivo físico na mesma rede Wi-Fi
— ou no próprio dispositivo, quando rodado direto no Termux.

O projeto detecta automaticamente o ambiente e usa o backend certo:

- **Linux (PC/notebook)**: usa [mitmproxy](https://mitmproxy.org/) via `pipx`.
- **Termux (Android)**: usa [proxy.py](https://github.com/abhinavsingh/proxy.py), um proxy
  100% Python puro. O mitmproxy moderno depende de um componente nativo em Rust
  (`mitmproxy-rs`) sem build pronto pra Android — compilar do zero no celular chega a
  levar horas e ainda assim não é garantido funcionar. O proxy.py faz interceptação TLS
  chamando o binário `openssl` (via subprocess), então não precisa compilar nada.

Os dois modos gravam capturas e exportam pra texto legível e `.har`; os detalhes de
cada flag estão na seção **Uso** abaixo.

## Requisitos

### Linux
- `python3` e `bash`
- Acesso de administrador (sudo) apenas se o `pipx` ainda não estiver instalado

### Termux (Android)
- Termux atualizado, com `pkg`/`apt` funcionando
- Opcionalmente, acesso root — só é necessário se você quiser instalar o certificado
  da CA como certificado de **sistema** (pra interceptar HTTPS de apps de terceiros no
  Android 7+). Sem root, ainda dá pra capturar HTTP puro e instalar o certificado como
  certificado de usuário (funciona pro navegador e apps que não travam a lista de
  confiança).

Em ambos os casos, celular e computador (ou só o celular, no caso do Termux) precisam
estar na mesma rede Wi-Fi.

## Instalação

```bash
./install.sh
```

No Termux, o script:
1. Instala `python`, `python-pip` e `openssl-tool` (o pacote `openssl` sozinho no Termux
   só traz as bibliotecas, não o binário de linha de comando — é o `openssl-tool` que
   fornece o `openssl` que a interceptação TLS precisa)
2. Instala `proxy.py` e `certifi` via `pip install --user` (puro Python, alguns segundos,
   sem compilar nada)
3. Gera uma CA própria (`certs/ca-cert.pem` + `certs/ca-key.pem`), reaproveitada em todas
   as capturas futuras
4. Dá permissão de execução nos scripts e cria a pasta `captures/`
5. **Se tiver `su` disponível**, já tenta instalar essa CA como certificado de **sistema**
   automaticamente (`configure.sh install-ca`) — sem isso, apps de terceiros no Android 7+
   não vão confiar no certificado (ver aviso na próxima seção). Se seu root for restrito
   (comum em root "sandboxed"), essa etapa avisa e falha de forma segura, sem alterar
   nada — você ainda pode instalar manualmente como certificado de usuário.

No Linux, o script segue o fluxo original: confere `python3`, instala `pipx` se precisar,
e instala o `mitmproxy` (que fornece `mitmdump`, `mitmproxy` e `mitmweb`) via `pipx`.

Rodar de novo depois é seguro — cada etapa é pulada se já estiver instalada, e a CA do
Termux só é gerada uma vez (reaproveitada, pra não precisar reinstalar o certificado no
celular a cada captura).

## Configurando o celular

### 1. Proxy — automático (Termux + root) ou manual

**Automático (recomendado, precisa de root):** o próprio `proxy_view.sh` já chama o
`configure.sh` sozinho — ao subir, configura o proxy do sistema pra apontar pra ele
mesmo; ao sair (`Ctrl+C`), desfaz e restaura o que estava configurado antes. Não precisa
fazer nada manualmente. Use `-C` se quiser desativar isso e configurar na mão.

Pra configurar/checar manualmente (ou num script seu):

```bash
bash configure.sh set 8080     # aponta o proxy do SISTEMA pra este dispositivo:8080
bash configure.sh status       # confere o valor atual
bash configure.sh unset        # restaura o que estava configurado antes
```

Ele usa `settings put global http_proxy` via `su`. Diferente do proxy manual do Wi-Fi
(abaixo), isso configura o proxy no nível do sistema Android e vale pra **qualquer tipo
de rede** — Wi-Fi, Ethernet/USB, etc. — o que é útil especialmente quando não tem opção
de proxy manual pra conexão cabeada. Funciona mesmo com root "restrito" (o mesmo que
falha pra gravar em `/system` — ver seção de CA de sistema abaixo — costuma continuar
liberando `settings put`, que não mexe no filesystem).

Sem `su` disponível, o `configure.sh` avisa e você cai no passo manual abaixo.

**Manual, via Wi-Fi:**
No Android: `Wi-Fi` → segure a rede conectada → `Modificar rede` → `Opções avançadas` →
`Proxy: Manual`
- **Hostname**: IP do computador na rede local (o `install.sh` e os scripts mostram esse
  IP; também dá pra ver com `hostname -I`). Se o proxy estiver rodando no próprio celular
  via Termux, pode usar `127.0.0.1`.
- **Porta**: `8080` (ou a porta que você passar com `-p`)

> Essa opção manual só existe pra redes Wi-Fi — não tem equivalente na UI do Android pra
> conexão Ethernet/USB. Se você está numa rede cabeada e não tem root, não dá pra
> configurar o proxy do sistema por essa via.

### 2. Instalar o certificado (necessário pra ver tráfego HTTPS)

**Linux (mitmproxy)**: com o proxy do celular já ativo, abra no navegador do celular
`http://mitm.it`, baixe o certificado pra Android e instale em `Configurações →
Segurança → Criptografia e credenciais → Instalar certificado → Certificado de CA`.

**Termux (proxy.py)**: com o proxy já ativo, abra no navegador do celular
`http://<ip-do-celular>:8080/ca-cert.pem` (o próprio `proxy_view.sh` serve esse arquivo
enquanto está rodando) e instale do mesmo jeito acima. O certificado também está em
`certs/ca-cert.pem` se preferir copiar manualmente.

> ⚠️ **Importante — Android 7+ (API 24+) e apps de terceiros:**
> a partir do Android 7, apps não confiam automaticamente em certificados instalados
> pelo usuário — só em certificados do sistema. Isso afeta a captura de HTTPS:
> - **Se o APK é seu** (você tem o código-fonte): adicione um
>   `network_security_config.xml` habilitando `<certificates src="user"/>` para builds de
>   debug.
> - **Se não tiver o código-fonte** (analisando um APK de terceiros): a alternativa é
>   rootear o dispositivo/emulador e instalar o certificado como CA do sistema. No Termux,
>   isso já é tentado automaticamente pelo `install.sh` (via `configure.sh install-ca`) —
>   se o seu root for restrito (comum em builds com SELinux/policy limitada), ele avisa e
>   explica as alternativas (módulo Magisk, certificado de usuário, Frida/objection).
> - Mesmo sem o certificado, requisições **HTTP simples** (não criptografadas) já
>   aparecem normalmente, só o conteúdo do HTTPS é que fica ilegível.

## Uso — `proxy_view.sh`

Script principal, com todos os modos de captura e exportação. Funciona igual nos dois
ambientes, com algumas flags específicas do Termux (marcadas abaixo).

### Captura ao vivo (escuta o proxy)

```bash
./proxy_view.sh                              # stream simples no terminal
./proxy_view.sh -p 8081                      # muda a porta (default: 8080)
./proxy_view.sh -w captures/capture.jsonl     # salva em um arquivo fixo (.jsonl no Termux, .flow no Linux)
./proxy_view.sh -f api.seuapp.com             # filtra só requests desse domínio (substring)
./proxy_view.sh -m POST                       # filtra só requests desse método [Termux]
./proxy_view.sh -v                           # verbose: headers completos
./proxy_view.sh -b                           # bem detalhado: headers + body
./proxy_view.sh -n                           # desativa interceptação TLS, só repassa HTTPS [Termux]
./proxy_view.sh -t                           # interface TUI interativa (mitmproxy) [Linux]
./proxy_view.sh -W                           # interface web (mitmweb no Linux; dashboard de conexões no Termux)
```

As flags são combináveis, ex: `./proxy_view.sh -f api.seuapp.com -p 8081 -b`.

Toda captura ao vivo é salva automaticamente em `captures/capture-<timestamp>.jsonl`
(Termux) ou `.flow` (Linux) — ou no caminho passado em `-w` — mesmo que você não peça
explicitamente.

### Reabrindo ou exportando uma captura salva (sem escutar o proxy)

```bash
./proxy_view.sh -r captures/capture.jsonl         # mostra formatado no terminal
./proxy_view.sh -x captures/capture.jsonl         # exporta pra texto legível (captures/dump-<timestamp>.txt)
./proxy_view.sh --har captures/capture.jsonl      # exporta pra .har (JSON padrão, mesmo diretório)
```

No Linux esses mesmos comandos funcionam com arquivos `.flow` (via `mitmproxy -r`,
`mitmdump -nr`); no Termux funcionam com os `.jsonl` gerados pelo `capture_plugin.py`
(via `tools/export_capture.py`).

### Todas as flags

| Flag | Descrição |
|---|---|
| `-p PORT` | porta do proxy (default: `8080`) |
| `-w FILE` | salva a captura ao vivo em `FILE` |
| `-f DOMINIO` | filtro de exibição/gravação por domínio (substring) |
| `-m METODO` | filtro por método HTTP (GET, POST, ...) — só Termux |
| `-v` | verbose — mostra headers completos |
| `-b` | bem detalhado — headers + body |
| `-n` | desativa interceptação TLS (só repassa HTTPS) — só Termux |
| `-C` | não configura o proxy do sistema automaticamente (com root) — só Termux |
| `-t` | interface TUI interativa (`mitmproxy`) — só Linux |
| `-W` | interface web (`mitmweb` no Linux) ou dashboard de conexões (Termux) |
| `-r FILE` | reabre/mostra um arquivo de captura salvo em vez de escutar o proxy |
| `-x FILE` | exporta uma captura salva pra texto (`dump.txt`) e sai |
| `--har FILE` | exporta uma captura salva pra `.har` e sai |
| `-h` | mostra a ajuda |

> No Linux, `-f` aceita a sintaxe de filtro completa do mitmproxy (ex:
> `-f "~d dominio.com & ~m POST"`); no Termux o filtro é simplificado pra substring de
> domínio (`-f`) e método exato (`-m`), já que o `proxy.py` não tem a mesma DSL de
> filtros do mitmproxy.

## Instalando o certificado como CA de sistema no Android (root)

Só necessário se você quer interceptar HTTPS de **apps de terceiros** no Android 7+
(ver aviso acima). No Termux, o `install.sh` já tenta isso automaticamente ao rodar (se
`su` estiver disponível). Pra rodar de novo manualmente (ex: depois de instalar um módulo
Magisk que libere a escrita em `/system`, ou pra confirmar o resultado):

```bash
bash configure.sh install-ca
```

O que ele faz:
1. Calcula o hash do certificado e o caminho que o Android espera
   (`/system/etc/security/cacerts/<hash>.0`).
2. Se já estiver instalado (mesmo conteúdo), não faz nada e confirma.
3. Senão, tenta remontar `/system` como gravável, copiar o certificado, remontar como
   somente leitura de novo, e confere se o conteúdo bate.
4. Se falhar (root restrito, partição somente leitura, dm-verity, etc.), explica as
   alternativas: módulo Magisk "Always Trust User Certificates", certificado de usuário,
   `network_security_config.xml` (se o APK for seu), ou Frida/objection pra apps com
   certificate pinning.

Não pede confirmação — só grava se conseguir de fato (falha com segurança, sem alterar
nada, se o root não permitir).

## Scripts auxiliares

- **`configure.sh`** — automações via root pro Termux: configura/desfaz o proxy do
  sistema Android (`set`/`unset`/`status`, já chamado sozinho pelo `proxy_view.sh`) e
  instala a CA como certificado de sistema (`install-ca`, já chamado sozinho pelo
  `install.sh`). Ver seções acima.
- **`start-proxy.sh`** — atalho pra subir direto no modo "web" (`-W`): mitmweb no Linux,
  dashboard de conexões + certificado servido via HTTP no Termux.
- **`start-proxy-cli.sh`** — atalho pra rodar em stream de texto com variáveis de
  ambiente (`PORT`, `FILTER`, `DETAIL`) em vez de flags. Útil pra rodar em background/CI.
- **`stop.sh`** — para um `proxy_view.sh` rodando em background (ex: iniciado com
  `setsid`/`nohup`, sem terminal interativo pra dar `Ctrl+C`). Manda o sinal pro grupo
  certo do processo, garantindo que o `trap` de limpeza (proxy do sistema) rode.

Pra uso do dia a dia, prefira o `proxy_view.sh` — ele cobre os dois modos e mais.

## Estrutura de pastas

```
SHOW_PROXY/
├── install.sh              # instala dependências (Termux: pkg+pip / Linux: pipx+mitmproxy)
├── configure.sh            # automações via root (Termux): proxy do sistema + CA de sistema
├── proxy_view.sh           # script principal (captura, replay, export)
├── start-proxy.sh          # atalho pra modo web/dashboard
├── start-proxy-cli.sh      # atalho pra stream de texto com env vars
├── plugins/
│   └── capture_plugin.py   # plugin do proxy.py que grava requests/responses (.jsonl) [Termux]
├── tools/
│   └── export_capture.py   # converte .jsonl pra texto legível / .har [Termux]
├── certs/                  # CA gerada pelo install.sh (ca-cert.pem, ca-key.pem) [Termux]
├── README.md
└── captures/               # capturas salvas (.jsonl/.flow), exports (.txt, .har)
```

## Troubleshooting

- **`address already in use`**: já tem um proxy rodando nessa porta. No Linux, veja com
  `pgrep -af mitm`; no Termux, `pgrep -af proxy` ou `ss -ltnp | grep <porta>`. Finalize o
  processo antigo ou use `-p` pra escolher outra porta.
- **`Certificate verify failed` nos logs**: o celular ainda não confia no certificado
  pra aquele domínio/app específico — revise a seção de certificado acima.
- **Celular não conecta a nada com o proxy ativo**: confirme que celular e computador
  estão na mesma rede Wi-Fi (ou que o proxy no Termux está ouvindo em `0.0.0.0`, não só
  `127.0.0.1`) e que nenhum firewall está bloqueando a porta.
- **App usa certificate pinning** (não confia em nenhuma CA customizada, nem instalando
  o certificado): precisa de Frida/objection pra contornar, ou analisar o tráfego só até
  a camada TCP/TLS (sem decriptar) com `-n`.
- **No Termux, `openssl: command not found`**: o pacote `openssl` do Termux só traz as
  bibliotecas; rode `pkg install openssl-tool` pra ter o binário de linha de comando.
