# SHOW_PROXY

Proxy MITM (man-in-the-middle) baseado em [mitmproxy](https://mitmproxy.org/) para monitorar,
inspecionar e exportar as requisições HTTP/HTTPS de um app Android (APK) rodando em um
dispositivo físico na mesma rede Wi-Fi.

## Requisitos

- Linux com `python3` e `bash`
- Celular Android na **mesma rede Wi-Fi** do computador
- Acesso de administrador (sudo) apenas se o `pipx` ainda não estiver instalado

## Instalação

```bash
./install.sh
```

O script:
1. Confere se `python3` existe
2. Instala o `pipx` caso não exista (via `apt` ou `pip --user`)
3. Instala o `mitmproxy` (que fornece `mitmdump`, `mitmproxy` e `mitmweb`) via `pipx`
4. Dá permissão de execução nos scripts e cria a pasta `captures/`

Rodar de novo depois é seguro — cada etapa é pulada se já estiver instalada.

## Configurando o celular

### 1. Proxy manual no Wi-Fi
No Android: `Wi-Fi` → segure a rede conectada → `Modificar rede` → `Opções avançadas` →
`Proxy: Manual`
- **Hostname**: IP do computador na rede local (o `install.sh` e os scripts mostram esse IP;
  também dá pra ver com `hostname -I`)
- **Porta**: `8080` (ou a porta que você passar com `-p`)

### 2. Instalar o certificado (necessário para ver tráfego HTTPS)
Com o proxy do celular já ativo, abra no **navegador do celular**: `http://mitm.it`, baixe o
certificado para Android e instale em
`Configurações → Segurança → Criptografia e credenciais → Instalar certificado → Certificado de CA`.

> ⚠️ **Importante — Android 7+ (API 24+) e apps de terceiros:**
> a partir do Android 7, apps não confiam automaticamente em certificados instalados pelo
> usuário — só em certificados do sistema. Isso afeta a captura de HTTPS:
> - **Se o APK é seu** (você tem o código-fonte): adicione um `network_security_config.xml`
>   habilitando `<certificates src="user"/>` para builds de debug.
> - **Se não tiver o código-fonte** (analisando um APK de terceiros): a alternativa é
>   rootear o dispositivo/emulador e instalar o certificado como CA do sistema, ou usar
>   Frida/objection para contornar certificate pinning.
> - Mesmo sem o certificado, requisições **HTTP simples** (não criptografadas) já aparecem
>   normalmente, só o conteúdo do HTTPS é que fica ilegível.

## Uso — `proxy_view.sh`

Script principal, com todos os modos de captura e exportação.

### Captura ao vivo (escuta o proxy)

```bash
./proxy_view.sh                              # stream simples no terminal (mitmdump)
./proxy_view.sh -p 8081                      # muda a porta (default: 8080)
./proxy_view.sh -w captures/capture.flow     # salva em um arquivo fixo (default: nome com timestamp)
./proxy_view.sh -f "~d api.seuapp.com"       # filtra só requests desse domínio
./proxy_view.sh -v                           # verbose: headers completos
./proxy_view.sh -b                           # bem detalhado: headers + body
./proxy_view.sh -t                           # interface TUI interativa (mitmproxy)
./proxy_view.sh -W                           # interface web (mitmweb, http://<ip>:8081)
```
As flags são combináveis, ex: `./proxy_view.sh -t -f "~d api.seuapp.com" -p 8081`.

Toda captura ao vivo é salva automaticamente em `captures/capture-<timestamp>.flow`
(ou no caminho passado em `-w`), mesmo que você não peça explicitamente.

### Reabrindo ou exportando uma captura salva (sem escutar o proxy)

```bash
./proxy_view.sh -r captures/capture.flow         # reabre, interativo (mitmproxy)
./proxy_view.sh -r captures/capture.flow -W      # reabre, na interface web (mitmweb)
./proxy_view.sh -x captures/capture.flow         # exporta pra texto legível (captures/dump-<timestamp>.txt)
./proxy_view.sh --har captures/capture.flow      # exporta pra .har (JSON padrão, mesmo diretório)
```

### Todas as flags

| Flag | Descrição |
|---|---|
| `-p PORT` | porta do proxy (default: `8080`) |
| `-w FILE` | salva a captura ao vivo em `FILE` |
| `-f FILTER` | filtro de exibição (sintaxe do mitmproxy, ex: `~d dominio.com`) |
| `-v` | verbose — mostra headers completos |
| `-b` | bem detalhado — headers + body (`flow_detail=3`) |
| `-t` | interface TUI interativa (`mitmproxy`) em vez do stream |
| `-W` | interface web (`mitmweb`) em vez do stream |
| `-r FILE` | reabre um `.flow` salvo em vez de escutar o proxy |
| `-x FILE` | exporta um `.flow` salvo pra texto (`dump.txt`) e sai |
| `--har FILE` | exporta um `.flow` salvo pra `.har` e sai |
| `-h` | mostra a ajuda |

## Scripts auxiliares

- **`start-proxy.sh`** — atalho pra subir direto a interface web (`mitmweb`), sem precisar
  passar `-W`. Bom pra deixar sempre nesse modo.
- **`start-proxy-cli.sh`** — atalho pra rodar em stream de texto (`mitmdump`) com variáveis
  de ambiente (`PORT`, `FILTER`, `DETAIL`) em vez de flags, salvando log em `.log` e `.flow`.
  Útil pra rodar em background/CI.

Pra uso do dia a dia, prefira o `proxy_view.sh` — ele cobre os dois modos e mais.

## Sintaxe de filtro (`-f`)

O mitmproxy usa uma sintaxe própria de filtro. Alguns exemplos úteis:

| Filtro | O que faz |
|---|---|
| `~d dominio.com` | requests para esse domínio |
| `~m POST` | só requests POST |
| `~c 200` | só respostas com esse status |
| `~u /api/` | URL contém esse caminho |
| `!~d google.com` | exclui esse domínio |
| `~d dominio.com & ~m POST` | combina condições (E) |

Lista completa: `mitmproxy --help` ou [docs oficiais](https://docs.mitmproxy.org/stable/concepts-filters/).

## Estrutura de pastas

```
SHOW_PROXY/
├── install.sh              # instala dependências (pipx + mitmproxy)
├── proxy_view.sh           # script principal (captura, replay, export)
├── start-proxy.sh          # atalho pra interface web
├── start-proxy-cli.sh      # atalho pra stream de texto com env vars
├── README.md
└── captures/               # capturas salvas (.flow), exports (.txt, .har)
```

## Troubleshooting

- **`address already in use`**: já tem um mitmproxy/mitmdump/mitmweb rodando nessa porta.
  Veja com `pgrep -af mitm` e finalize o processo antigo, ou use `-p` pra escolher outra porta.
- **`Certificate verify failed` nos logs**: o celular ainda não confia no certificado do
  mitmproxy para aquele domínio/app específico — revise a seção de certificado acima.
- **Celular não conecta a nada com o proxy ativo**: confirme que celular e computador estão
  na mesma rede Wi-Fi e que nenhum firewall do computador está bloqueando a porta (ex:
  `sudo ufw allow 8080`).
- **App usa certificate pinning** (não confia em nenhuma CA customizada, nem instalando o
  certificado): precisa de Frida/objection pra contornar, ou analisar o tráfego só até a
  camada TCP/TLS (sem decriptar).
