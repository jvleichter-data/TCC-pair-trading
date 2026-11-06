# TCC — Pair Trading com S&P 500

Trabalho de Conclusão de Curso em Engenharia Física.

Implementação do método de distância de **Gatev, Goetzmann e Rouwenhorst (2006)** aplicado a ações do S&P 500, com base de dados estendida de **1990/S2 a 2025/S2**.

---

## Método

A estratégia opera em duas fases que se alternam semestralmente:

| Fase | Duração | O que faz |
|------|---------|-----------|
| **Formação** | 12 meses (2 semestres) | Normaliza preços, calcula SSD entre todos os pares e seleciona os top-20 de menor distância |
| **Negociação** | 6 meses (1 semestre) | Monitora o spread dos pares formados; abre posição quando spread > 2σ, fecha na reversão |

**Normalização:** $Q_i(t) = P_i(t) / P_i(0)$ — todos os ativos partem de 1 no início de cada janela de formação.

**Distância SSD:** $D(i,j) = \sum_{t=1}^{T} [Q_i(t) - Q_j(t)]^2$ — área quadrática acumulada entre as duas trajetórias normalizadas.

---

## Estrutura do repositório

```
TCC-pair-trading/
└── new_aproach/
    ├── src/
    │   ├── database_formation/
    │   │   ├── pipeline_base.ipynb    # 1. ÚNICO notebook da base: professor + extensão
    │   │   │                          #    → base_completa.csv E base_unificada.csv
    │   │   ├── gathering.ipynb        # (auxiliar) Recupera tickers delistados/renomeados
    │   │   ├── cobertura_base.ipynb   # (auxiliar) Valida cobertura por semestre
    │   │   ├── analise_fronteira.ipynb# (auxiliar) Qualidade na fronteira professor/extensão
    │   │   ├── serie_rf.ipynb         # 2. Taxa livre de risco → rf_diario.csv
    │   │   ├── validacao_dados.ipynb  # (auxiliar) Valida tickers com problema na coleta
    │   │   └── validacao_tipo_preco.ipynb # (auxiliar) Confirma tipo de preço do orientador
    │   ├── distance/
    │   │   ├── pairs_formation.ipynb  # 3. Formação de pares e seleção top-20
    │   │   └── pairs_trading.ipynb    # 4. Negociação e análise de resultados
    │   ├── cointegration/             # Mesma estrutura, método da cointegração
    │   ├── nonparametric/             # Cointegração não paramétrica (kernel local linear)
    │   │   ├── kernel_np.py           #    estimador, CV unilateral, teste de cointegração NP
    │   │   ├── formacao_utils.py      #    universo, SSD e seleção da formação própria
    │   │   ├── valor_critico_np.ipynb #    valor crítico do teste por simulação
    │   │   ├── pairs_formation_np_propria.ipynb  # formação própria (padrão)
    │   │   ├── pairs_formation_np.ipynb          # alternativa: pares da linear
    │   │   ├── pairs_trading_np.ipynb
    │   │   ├── diagnostico_wang_phillips.ipynb  # teste de linearidade (diagnóstico)
    │   │   ├── especificacao_np.py    #    estatística de Wang & Phillips (2012) + bootstrap
    │   │   └── DECISOES.md            #    decisões de método, validação e resultados
    │   └── validation/                # Diagnósticos, contrafactuais e relatórios
    │
    ├── data_bases/
    │   ├── base_unificada.csv             # Base reconstruída por retornos 1990–2025 (~62 MB) ← usar esta
    │   ├── base_completa.csv              # Base concatenada diretamente 1990–2025 (~60 MB)
    │   ├── extensao_2016_2025.csv         # Extensão coletada 2016–2025 (~20 MB)
    │   ├── professor_consolidado.csv      # Base original do orientador 1990–2015 (~36 MB)
    │   ├── prices/                        # Séries diárias Yahoo Finance adj_close
    │   ├── prices_tiingo/                 # Séries diárias Tiingo adj_close (delistados)
    │   ├── professor/                     # Arquivos originais do orientador
    │   └── external/                      # Metadados e relatórios
    │       ├── sp500_historico.csv        # Composição diária S&P 500 (1996–2026)
    │       ├── coleta_report.csv          # Status de coleta de cada ticker
    │       ├── analise_fronteira.csv      # Saltos na fronteira dez/2015→jan/2016
    │       ├── sobreposicao_2015_tabela.csv # Consistência adj_close na sobreposição 2015
    │       ├── outliers_report.md         # Documentação de todos os outliers >30% da base
    │       └── ausencias_report.md        # Detalhamento de tickers irrecuperáveis
    │
    └── markdowns/                         # Documentação matemática
        ├── gatev_pairs_theory.md          # Fundamentos do método Gatev et al.
        └── ssd_matrix_computation.md      # Derivação da implementação matricial da SSD
```

---

## Bases de dados

### Arquivos principais

| Arquivo | Período | Tickers únicos | Descrição |
|---------|---------|----------------|-----------|
| `professor_consolidado.csv` | 1990/S2 – 2015/S2 | ~1 100 | Base original do orientador, adj_close coletado em ~dez/2015 |
| `extensao_2016_2025.csv` | 2016/S1 – 2025/S2 | ~708 | Extensão coletada em 2026 via Yahoo/Tiingo, adj_close_2026 |
| `base_completa.csv` | 1990/S2 – 2025/S2 | ~1 343 | Concatenação direta das duas bases (descontinuidade na fronteira) |
| **`base_unificada.csv`** | 1990/S2 – 2025/S2 | ~1 343 | **Base recomendada** — extensão reconstruída por retornos, sem salto na fronteira |

> **Tipo de preço:** `adj_close` (Yahoo Finance `auto_adjust=True` / Tiingo `adjClose`). A base do professor também usa adj_close, conforme confirmado em `validacao_tipo_preco.ipynb`. Cada ticker recebe `NaN` nos semestres em que não integrava o S&P 500.
>
> **Fronteira 2015/S2 → 2016/S1:** as duas bases têm datas de normalização diferentes (~2015 vs 2026). Um split ocorrido nesse período (ex: split 4-for-1 da AAPL em 2020) faz o adj_close da extensão diferir por um fator constante do professor. `base_unificada.csv` corrige isso reconstruindo a extensão via retornos: $P_{\text{uni}}(t) = P_{\text{prof}}(t_{\text{fim}}) \times P_{\text{ext}}(t) / P_{\text{ext}}(t_0)$, preservando todos os retornos diários e eliminando o salto artificial. Correlação de retornos entre original e reconstruído: 1.0000000000.

### Preços brutos

| Pasta | Fonte | Uso |
|-------|-------|-----|
| `prices/` | Yahoo Finance (`auto_adjust=True`) | Coleta principal 2015–2025 |
| `prices_tiingo/` | Tiingo API (`adjClose`) | Tickers delistados, renomeados ou com cobertura incompleta no Yahoo |

### Composição histórica

`external/sp500_historico.csv` — snapshots diários da composição do S&P 500 de 1996 a 2026. Cada linha é uma data com a lista de tickers membros naquele dia. Usado para aplicar a membership mask na extensão.

---

## Notebooks

### `pipeline_base.ipynb` — Construção da base (notebook único)

Regenera **todas** as bases, do `Pt.csv` do orientador aos dois arquivos finais. Antes isso
estava dividido entre `pipeline_base` e `base_unificada`; os dois foram fundidos em
2026-09-13.

| Parte | O que faz | Saída |
|-------|-----------|-------|
| 0 | Flags de construção — todas as decisões num lugar só | — |
| 1 | Bloco do orientador: datas reais, correções de qualidade, máscara opcional | `professor_consolidado.csv` |
| 2 | Extensão 2016–2025: composição do índice, coleta, montagem | `extensao_2016_2025.csv` |
| 3 | Concatenação direta | `base_completa.csv` |
| 4 | Emenda por retornos na fronteira | `base_unificada.csv` |
| 5 | Validação numérica das duas | — |

**Flags principais** (Parte 0):

| Flag | Padrão | O que faz |
|---|---|---|
| `CORRIGIR_SERIES_DESLOCADAS` | `True` | Realinha `SPGI`, `MRO`, `KATE`, `ARB`, `BF_B` |
| `PRECO_ZERO_VIRA_NAN` | `True` | 8.564 células com preço 0 viram `NaN` |
| `RECUPERAR_ULTIMO_PREGAO` | `True` | Usa as 6.426 linhas do `Pt.csv` (recupera 2015-12-31) |
| `APLICAR_MASCARA_INDICE` | `True` | Restringe ao `ticker_sem.csv` — **ver aviso abaixo** |
| `BAIXAR_FALTANTES` | `False` | Coleta do Yahoo; desligado para rodar offline |
| `REMOVER_TRECHOS_INTERPOLADOS` | `True` | Apaga trechos de preço interpolados (47 séries, 0,40% das células) |
| `LIMITE_SALTO_FRONTEIRA` | `0.25` | Trava a emenda quando a âncora está em outra convenção |

> ⚠️ **`APLICAR_MASCARA_INDICE`** tem dois efeitos opostos e é a decisão metodológica
> central do projeto.
>
> *Contra:* ligar **não reproduz o artigo do orientador**, que usa as 1.100 séries do
> `Pt.csv` com o único filtro de *"stocks listed during the formation period"*. Medido:
> `False` → 3,015% a.a. / Sharpe 0,705 (artigo: 3,600 / 0,703); `True` → ~1,3% / ~0,27.
> E essa queda não é remoção de viés: um corte **aleatório** do mesmo tamanho dá 0,92%,
> 2,04% e 3,08% em três sorteios — é efeito de tamanho de universo.
>
> *A favor:* ligar remove dado fabricado, e isso um corte aleatório não faz. Os trechos
> interpolados do `Pt.csv` são justamente os períodos em que a empresa não integrava o
> índice. A contaminação dos pares selecionados cai de 3,8% para 0,7% só com a máscara
> (e para 0,0% somando o `REMOVER_TRECHOS_INTERPOLADOS`).
>
> Ver [`src/validation/revisao_completa_2026-09-13.md`](new_aproach/src/validation/revisao_completa_2026-09-13.md) § 1.1 e § 4.3.

### `gathering.ipynb` — Recuperação de tickers problemáticos

Tickers que o Yahoo não cobre diretamente (delistados, empresas renomeadas, histórico pré-2016) são recuperados aqui usando múltiplas fontes: NASDAQ Data Link WIKI, Tiingo, Financial Data API e FMP. O notebook organiza a coleta em partes (A–J), cada uma focada em um grupo de casos específico, e salva o resultado direto em `prices/` ou `prices_tiingo/`.

Exemplos de casos tratados: CBS→VIAC, FOX/FOXA (21st Century Fox), CDAY→DAY, IR→TT, BHI/BHGE, GPS→GAP, entre outros.

### `cobertura_base.ipynb` — Validação de cobertura

Cruza a extensão gerada com o `sp500_historico.csv` e calcula, semestre a semestre, quantos tickers esperados têm dados presentes. Gera `tickers_ausentes.csv` e imprime relatório de cobertura. Cobertura final: **~100%** (apenas ausências estruturais documentadas permanecem).

### `analise_fronteira.ipynb` — Qualidade na fronteira e sobreposição 2015

Dois tipos de análise sem chamadas externas de API:

**Parte 1 — Fronteira dez/2015 → jan/2016:**
Para cada ticker na interseção professor ∩ extensão, calcula o salto percentual `(ext[jan/4] / prof[dez/30] - 1)`. Quantifica a descontinuidade artificial causada pelas diferentes datas de normalização das duas bases. Resultado em `analise_fronteira.csv`.

**Parte 2 — Sobreposição 2015:**
Coleta adj_close de 2015 para todos os tickers da interseção e calcula o ratio `nosso_adj_close / prof_adj_close` para cada data. Se o ratio for constante (CV ≈ 0%), confirma que ambas as séries são adj_close com a mesma estrutura, apenas com bases de normalização diferentes. Resultado em `sobreposicao_2015_tabela.csv`.

### A emenda da fronteira (Parte 4 do `pipeline_base.ipynb`)

Resolve a descontinuidade de adj_close na fronteira 2015/S2 → 2016/S1: as duas metades foram coletadas em datas diferentes (~2015 e ~2026), de modo que splits ocorridos no intervalo (ex: AAPL 4:1 em 2020) introduzem um fator constante de escala. A correção reescala a extensão por uma constante por ticker, ancorada no último preço do orientador:

$$P_{\text{uni}}(t) = P_{\text{ext}}(t) \times \frac{P_{\text{prof}}(t_f)}{P_{\text{sobr}}(t_f)}$$

onde $t_f$ é o último pregão em que o orientador tem preço para aquele ticker e $P_{\text{sobr}}(t_f)$ é o preço da mesma data **na convenção da extensão**. Isso preserva todos os retornos diários da extensão (correlação 1,0; desvio máximo 4e-16) e elimina o salto.

A âncora vem, em ordem: (1) do **próprio arquivo** de `prices/` que gera a extensão — eles começam em 2015-07, então já contêm $t_f$; (2) de `prices_sobreposição/`; (3) do primeiro dia da extensão, forçando retorno zero. A ordem importa: `prices_sobreposição` foi baixada em data diferente de `prices/` e diverge em 34 dos 465 tickers da interseção.

Resultado na fronteira (2016-01-04, 465 tickers): `|r| > 20%` cai de **254** na `base_completa` para **1** na `base_unificada`.

### `pairs_formation.ipynb` — Formação de pares

Implementa a fase de formação do método Gatev et al.:

- Janelas rolantes definidas em meses calendário, com os **mesmos parâmetros do método da cointegração** (`MESES_FORMACAO=12`, `MESES_NEGOCIACAO=6`, `PASSO_MESES`) para permitir comparação direta entre as metodologias. Com `PASSO_MESES=6` são 69 janelas (ritmo original de Gatev); com `PASSO_MESES=1`, ~400 janelas (Rad et al.)
- Filtra tickers com dados completos na janela de formação
- Normaliza preços e calcula SSD via álgebra matricial sem loops (`norms[:, None] + norms[None, :] - 2 * G`)
- Seleciona top-20 pares por janela e calcula estatísticas do spread
- Salva resultado em `pares_formados.csv`

### `pairs_trading.ipynb` — Negociação

Simula a fase de negociação sobre os pares selecionados:

- Estratégia: entra quando |z| > δ=2, fecha na reversão (z=0), stop-loss em |z| > 4
- **Lag de posição:** decisão tomada no fechamento do dia t → execução a partir de t+1 (`np.roll(positions, 1)`). Correto pela convenção de mercado: não é possível negociar no mesmo instante da observação do sinal.
- **Capital comprometido (Gatev):** todos os N pares entram no denominador do portfólio, mesmo os inativos. Isso dilui o retorno nos períodos sem posição — metodologia fiel ao artigo original.
- **Filtro de outliers:** pares com retorno diário máximo > 30% são descartados (identifica penny stocks OTC com preços corrompidos na base, ex: AVATQ ~$0,0001).
- Saídas: `negociacao_pares.csv` (resultado por par) e `negociacao_portfolio.csv` (série temporal do portfólio)

---

### `nonparametric/` — Cointegração não paramétrica (terceiro método)

Troca a reta da cointegração por uma curva desconhecida, $Q_{dep} = g(Q_{indep}) + u$, estimada
por **regressão local linear** com kernel gaussiano. A inclinação local $\hat g'(x)$ é o hedge
ratio na entrada. Base teórica: slides *Cointegração Não Paramétrica via Kernel* (ECO 02091,
FCE/UFRGS) e Wang & Phillips.

- **Formação própria:** 300 pares de menor SSD; para cada um, a curva nas duas direções com bandwidth
  por validação cruzada **unilateral** (só o passado, gap de 20 pregões; grade com $h = \infty$, a reta);
  o par entra se o ADF dos erros fora da amostra passar de um **valor crítico simulado** (−3,52,
  pares reais com os dias embaralhados) e o β local mediano for ≥ 0,50; os 20 primeiros em ordem de SSD.
- **Negociação:** a curva é re-estimada todo dia com os dados até $t-1$ (formação + negociação
  decorrida), porque ~40% dos dias de negociação caem fora do suporte da formação. Sinal em
  $|z| > 2$; veto quando não há dado antigo perto do preço atual; na entrada congela a tangente à
  curva e fecha quando o spread contra ela cruza a média. Pernas na razão 1 : β dos slides, com a maior
  perna em $1; só abre com 0,50 ≤ β ≤ 2.
- **Resultado (sem custos):** Sharpe 1,11 em 1991–2015 e 0,87 em 1991–2025 (linear: 0,93 e 0,66; com a
  mesma convenção de pernas, 1,02 e 0,71). A diferença não é estatisticamente significativa (p ≈ 0,24).

Todas as decisões, a validação (o motor reproduz a linear estática em 1e-15) e os primeiros
resultados estão em [`DECISOES.md`](new_aproach/src/nonparametric/DECISOES.md).

---

## Qualidade dos dados

Todos os outliers de retorno diário > 30% na extensão foram revisados e documentados em [`data_bases/external/outliers_report.md`](new_aproach/data_bases/external/outliers_report.md).

**87 outliers identificados em 63 tickers** — todos em datas consecutivas de pregão. Nenhum é erro de dado. Classificação:

- **Eventos macroeconômicos:** crash do petróleo mar/2020 (10), COVID crash + rally (24), vacina Pfizer nov/2020 (8)
- **Eventos corporativos:** M&A (5), PG&E/falência (2), SMCI/fraude contábil (4)
- **Earnings extremos:** Netflix, Paycom, DexCom, Biogen/FDA, entre outros (17)
- **Limitações intrínsecas:** BHGE merger BHI→GE (2) e XRX spinoff Conduent (1) — documentados

Correções aplicadas durante a análise: COL, HAR, CHK (reverse split falência), IR, NKTR, DHR (Tiingo adjClose para spinoff Fortive), XRX, FSLR, KDP, FISV, PCG.

---

## Cobertura da extensão (2016–2025)

| Métrica | Valor |
|---------|-------|
| Cobertura geral | ~100% |
| Ausência parcial | VIAC: cobre dez/2019–dez/2021 (faltam ~6 semanas até fev/2022, data de privatização) |
| Ausências legítimas | BHGE: sem dados 2016/S1–2017/S1 (empresa só existiu a partir de jul/2017); DOW: sem dados 2016–mar/2019 (era DowDuPont/DWDP, ticker diferente) |

---

## Como reproduzir

```
database_formation/
  1. pipeline_base.ipynb   → professor_consolidado.csv, extensao_2016_2025.csv,
                             base_completa.csv E base_unificada.csv  (notebook único)
  2. serie_rf.ipynb        → rf_diario.csv (Rf do professor + T-bill do FRED)

distance/  (e cointegration/, mesma sequência)
  3. pairs_formation.ipynb → pares_formados.csv
  4. pairs_trading.ipynb   → negociacao_pares.csv, negociacao_portfolio.csv

nonparametric/
  5. valor_critico_np.ipynb           → valor_critico_np.json      (~12 min, só ao mudar o teste)
  6. pairs_formation_np_propria.ipynb → pares_formados_np_propria.csv (~45 min, 3 processos)
  7. pairs_trading_np.ipynb           → negociacao_*_np.csv        (~1,5 min)

auxiliares — só se for recoletar dados ou reauditar:
  gathering.ipynb          → recupera tickers delistados/renomeados (partes A–J)
  cobertura_base.ipynb     → valida cobertura e gera tickers_ausentes.csv
  analise_fronteira.ipynb  → qualidade na fronteira e sobreposição 2015
```

> ⚠️ `data_bases/prices/RF.csv` **não é renda fixa** — é a ação *Regions Financial* (ticker `RF`, constituinte do S&P 500). A taxa livre de risco vem de `professor/Rf.csv`, estendida por `serie_rf.ipynb`.

**Dependências:** `pandas`, `numpy`, `yfinance`, `requests`, `matplotlib`

**APIs utilizadas:**
- Yahoo Finance via `yfinance` (coleta principal)
- [Tiingo](https://api.tiingo.com/) (delistados — requer token gratuito)
- [NASDAQ Data Link WIKI](https://data.nasdaq.com/) (histórico pré-2018 — requer token gratuito)
- Financial Modeling Prep / Financial Data API (recuperação pontual)
