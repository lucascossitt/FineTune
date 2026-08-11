# FineTune — estado do fork local

Build em teste: **1.9.99 (9999)** — número alto de propósito, para o Sparkle
não substituir por uma versão do appcast. Assinatura ad-hoc.

## Repo

- Branch de trabalho: `integration` (a `main` está intocada)
- Branches `pr-*` guardadas para todos os PRs avaliados

```bash
cd ~/dev/FineTune
git log --oneline main..integration | grep "Merge branch"
```

## Mergeado (9 PRs — 985 testes passando, baseline era 965)

| PR | O que faz |
|----|-----------|
| #344 | Toggle para desligar DDC — corrige tela preta no hub USB-C (#279) ✅ validado |
| #412 | 10 bugs de UI: popups fora da tela, painel na tela errada, HUD fullscreen, Spotify vídeo mudo |
| #409 | Prewarm dos taps, AutoEQ no crossfade, corta CPU no startup |
| #396 | Mudança de sample rate/bit depth reconstrói o aggregate |
| #408 | Detecção de NaN no meio do buffer (distorção robótica) |
| #410 | Expoente αf correto no ISO 226 |
| #339 | AutoEQ nos alto-falantes internos |
| #314 | Apps "follow default" seguem na reconexão Bluetooth |
| #383 | Toggle para esconder o HUD mantendo as teclas de volume |
| #217 | URL scheme para volume de device |

## Pendentes de decisão

- **#388** (sons curtos cortados): muda o contrato de `advanceOutputGate` sem
  atualizar os testes. 6 testes precisam de ajuste mecânico, 4 afirmam o
  comportamento que ele deleta de propósito (re-arm por silêncio).
- **#303** (preamp anti-clipping no loudness): corte incondicional igual ao
  inverso do pico de boost — por construção a compensação nunca adiciona
  energia. Quebra `loudnessCompensatorModifiesOutput`, que codifica o
  propósito do recurso. Empurra na direção da issue #278.
- **#401** (grupos de apps, +1951): Fase B. Conflito mecânico em
  `URLHandler.swift` — unificar alvos `app`/`device`/`group` no parser.

## Descartados

`#392` `#397` (você descartou — sobreposição semântica de canal/balanço)
`#320` (curativo), `#386` (localização zh), `#17` (ícones antigos)

## Como rebuildar

```bash
scripts/build-local.sh ~/Desktop/FineTune-teste
```

Faz build Release, reassina ad-hoc, verifica e **testa o launch de verdade**.
Sem ele o app não abre: o projeto usa hardened runtime, e sob assinatura ad-hoc
a library validation recusa o Sparkle.framework embutido ("different Team IDs"),
matando o processo no dyld antes do `main()` — sem janela, sem ícone, sem aviso.
O script também carimba a versão acima do appcast para o Sparkle não substituir
o build por uma release pública.

## Armadilhas conhecidas

1. **`xcodebuild test` escreve no `~/Library/Application Support/FineTune/settings.json` real.**
   Rodar a suíte apaga configurações. Backup original:
   `settings.pre-ddc-test.backup.json` no mesmo diretório.

2. **`/Applications/FineTune.app` ainda é a 1.9.0 do Homebrew, sem o fix.**
   Abrir essa por engano (Spotlight/Launchpad) faz o monitor apagar.

3. **DDC precisa continuar desligado** para o monitor não piscar:
   Settings → Audio → toggle de volume DDC. Verificar via:
   ```bash
   python3 -c "import json;print(json.load(open('$HOME/Library/Application Support/FineTune/settings.json')).get('ddcVolumeControlEnabled'))"
   ```

## Se algo soar errado

Os merges de #409, #396 e #408 mexem no caminho de DSP e não têm cobertura
automatizada para crackle/latência. Para bissectar:

```bash
git checkout integration
git log --oneline main..HEAD | grep "Merge branch"   # ordem dos merges
git reset --hard <commit-anterior-ao-suspeito>       # e rebuildar
```
