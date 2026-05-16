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
    ├── src/                          # Notebooks (executar nesta ordem)
    │   ├── pipeline_base.ipynb       # 1. Constrói base_completa.csv
    │   ├── gathering.ipynb           # 2. Recupera tickers delistados/renomeados
    │   ├── cobertura_base.ipynb      # 3. Valida cobertura por semestre
    │   ├── analise_fronteira.ipynb   # 4. Análise de qualidade na fronteira professor/extensão
    │   ├── validacao_dados.ipynb     # (auxiliar) Valida tickers com problema na coleta
    │   ├── validacao_tipo_preco.ipynb# (auxiliar) Confirma tipo de preço da base do professor
    │   └── pairs_formation.ipynb     # 5. Formação de pares e seleção top-20
    │
    ├── data_bases/
    │   ├── base_completa.csv              # Base unificada 1990–2025 (~60 MB)
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
| `base_completa.csv` | 1990/S2 – 2025/S2 | ~1 343 | Concatenação das duas bases acima |

> **Tipo de preço:** `adj_close` (Yahoo Finance `auto_adjust=True` / Tiingo `adjClose`). A base do professor também usa adj_close, conforme confirmado em `validacao_tipo_preco.ipynb`. Cada ticker recebe `NaN` nos semestres em que não integrava o S&P 500.
> **Fronteira:** por terem datas de normalização diferentes (~2015 vs 2026), os adj_close das duas bases não se concatenam diretamente — a análise quantitativa dessa descontinuidade está em `analise_fronteira.csv` e `sobreposicao_2015_tabela.csv`.

### Preços brutos

| Pasta | Fonte | Uso |
|-------|-------|-----|
| `prices/` | Yahoo Finance (`auto_adjust=True`) | Coleta principal 2015–2025 |
| `prices_tiingo/` | Tiingo API (`adjClose`) | Tickers delistados, renomeados ou com cobertura incompleta no Yahoo |

### Composição histórica

`external/sp500_historico.csv` — snapshots diários da composição do S&P 500 de 1996 a 2026. Cada linha é uma data com a lista de tickers membros naquele dia. Usado para aplicar a membership mask na extensão.

---

## Notebooks

### `pipeline_base.ipynb` — Construção da base

Constrói `extensao_2016_2025.csv` e `base_completa.csv` em 7 partes:

| Parte | O que faz |
|-------|-----------|
| 1 | Consolida base do orientador — alinha datas reais de pregão NYSE via MSFT |
| 2 | Confirma tipo de preço da base do professor (adj_close) |
| 3 | Carrega composição histórica e lista tickers necessários (2016–2025) |
| 4 | Checkpoint — identifica tickers já coletados |
| 5 | Baixa adj_close faltante do Yahoo Finance (`auto_adjust=True`) |
| 6 | Constrói `extensao_2016_2025.csv` com membership mask |
| 7 | Concatena professor + extensão em `base_completa.csv` |

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

### `pairs_formation.ipynb` — Formação de pares

Implementa a fase de formação do método Gatev et al.:

- 69 janelas rolantes de 12 meses, avançando 6 meses por vez (1990/S2 – 2025/S2)
- Filtra tickers com dados completos na janela de formação
- Normaliza preços e calcula SSD via álgebra matricial sem loops (`norms[:, None] + norms[None, :] - 2 * G`)
- Seleciona top-20 pares por janela e calcula estatísticas do spread
- Salva resultado em `pares_formados.csv`

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
| Ausências estruturais | VIAC (privatizada), CDAY (2 janelas sem dados) |
| Ausências legítimas | BHGE 2016/S1–2017/S1 (empresa não existia); DOW 2016–mar/2019 (era DowDuPont/DWDP) |

Detalhamento completo em [`data_bases/external/ausencias_report.md`](new_aproach/data_bases/external/ausencias_report.md).

---

## Como reproduzir

```
1. pipeline_base.ipynb        → gera extensao_2016_2025.csv e base_completa.csv
2. gathering.ipynb             → recupera tickers problemáticos (rodar partes A–J)
3. cobertura_base.ipynb        → valida cobertura e gera tickers_ausentes.csv
4. analise_fronteira.ipynb     → analisa qualidade na fronteira e sobreposição 2015
5. pairs_formation.ipynb       → seleciona pares e salva pares_formados.csv
```

**Dependências:** `pandas`, `numpy`, `yfinance`, `requests`, `matplotlib`

**APIs utilizadas:**
- Yahoo Finance via `yfinance` (coleta principal)
- [Tiingo](https://api.tiingo.com/) (delistados — requer token gratuito)
- [NASDAQ Data Link WIKI](https://data.nasdaq.com/) (histórico pré-2018 — requer token gratuito)
- Financial Modeling Prep / Financial Data API (recuperação pontual)
