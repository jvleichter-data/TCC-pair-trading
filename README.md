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

**Normalização:** $Q_i(t) = P_i(t) / P_i(0)$ — todos os ativos partem de 1 no início de cada janela de formação, tornando os preços comparáveis independentemente do nível absoluto.

**Distância SSD:** $D(i,j) = \sum_{t=1}^{T} [Q_i(t) - Q_j(t)]^2$ — mede a área quadrática acumulada entre as duas trajetórias normalizadas.

---

## Estrutura do repositório

```
TCC-pair-trading/
└── new_aproach/
    ├── src/                        # Notebooks de análise
    │   ├── pipeline_base.ipynb
    │   ├── validacao_dados.ipynb
    │   ├── cobertura_base.ipynb
    │   └── pairs_formation.ipynb
    ├── data_bases/                 # Dados processados
    │   ├── base_completa.csv
    │   ├── extensao_2016_2025.csv
    │   ├── professor_consolidado.csv
    │   ├── pares_formados.csv
    │   ├── prices/                 # Séries diárias Yahoo Finance (601 tickers)
    │   ├── prices_tiingo/          # Séries diárias Tiingo API (86 tickers)
    │   ├── professor/              # Base original do orientador (1990–2015)
    │   └── external/               # Composição histórica S&P 500 e reports
    └── markdowns/                  # Documentação técnica
        ├── gatev_pairs_theory.md
        └── ssd_matrix_computation.md
```

---

## Dados

### Base de preços

| Arquivo | Período | Dias | Tickers únicos | Tamanho |
|---------|---------|------|----------------|---------|
| `professor_consolidado.csv` | 1990/S2 – 2015/S2 | 6 425 | 1 100 | 36 MB |
| `extensao_2016_2025.csv` | 2016/S1 – 2025/S2 | 2 513 | 708 | 20 MB |
| `base_completa.csv` | 1990/S2 – 2025/S2 | 8 938 | 1 343 | 60 MB |

- **Tipo de preço:** Close sem dividendos (split-adjusted) — equivalente ao `Close` do Yahoo Finance com `auto_adjust=False` e ao `close` do Tiingo
- **Calendário:** dias reais de pregão NYSE (extraído do histórico MSFT via Yahoo)
- **Membership mask:** cada ticker recebe `NaN` nos semestres em que não integrava o S&P 500

### Composição histórica (`external/sp500_historico.csv`)

Snapshots diários da composição do S&P 500 de 1996 a 2026, usados para:
- Filtrar quais tickers estavam no índice em cada semestre
- Validar cobertura da base

### Preços brutos

| Pasta | Fonte | Tickers | Uso |
|-------|-------|---------|-----|
| `prices/` | Yahoo Finance (`yfinance`) | 601 | Coleta principal 2015–2025 |
| `prices_tiingo/` | Tiingo API | 86 | Tickers delistados/renomeados com histórico recuperado |

### Pares formados (`pares_formados.csv`)

Resultado da fase de formação: 69 janelas × 20 pares = **1 380 registros**.

Colunas: `janela`, `formacao_inicio`, `formacao_fim`, `negociacao`, `rank`, `ativo1`, `ativo2`, `ssd`, `spread_media`, `spread_desvio`

---

## Notebooks

### `pipeline_base.ipynb`

Constrói a base de dados completa em 7 partes:

| Parte | O que faz |
|-------|-----------|
| 1 | Consolida base do orientador — alinha datas reais NYSE via correlação com MSFT Yahoo |
| 2 | Confirma tipo de preço: Close sem dividendos (ratio professor/Yahoo = 1.0000) |
| 3 | Carrega composição S&P 500 e lista tickers necessários (2016–2025) |
| 4 | Verifica quais preços já foram baixados (checkpoint) |
| 5 | Baixa preços faltantes do Yahoo Finance |
| 6 | Constrói `extensao_2016_2025.csv` com membership mask aplicada |
| 7 | Concatena professor + extensão em `base_completa.csv` |

### `validacao_dados.ipynb`

Valida cobertura dos tickers com problema na coleta original. Em 10 partes:

- Identifica quando cada ticker estava no S&P 500 e se os dados cobrem esse período
- Tenta recuperar histórico via Tiingo API com datas específicas de membership
- Deleta arquivos de tickers reciclados (dados de outra empresa)
- Gera `coleta_report_validacao.csv` com status final de cada ticker

### `cobertura_base.ipynb`

Valida a base gerada cruzando com a composição histórica do S&P 500:

- Cobertura por semestre (% de tickers esperados com dados presentes)
- Lista de tickers cronicamente ausentes
- Cruzamento com `coleta_report_validacao.csv` para classificar cada ausência

### `pairs_formation.ipynb`

Implementa a fase de formação do método Gatev et al.:

- Janelas rolantes de 12 meses, avançando 6 meses por vez (69 janelas no total)
- Filtra tickers com dados completos no período
- Calcula SSD via álgebra matricial (`Q.T @ Q`) sem loops — ordens de magnitude mais rápido
- Seleciona top-20 pares por janela e calcula estatísticas do spread
- Visualiza trajetórias normalizadas e spread para janelas representativas

---

## Cobertura da base (2016–2025)

| Métrica | Valor |
|---------|-------|
| Cobertura média | 97.4% |
| Pior semestre | 2016/S1 — 93.9% |
| Melhor semestre | 2024/S2 — 99.8% |
| Tickers com ≥ 1 semestre ausente | 37 |
| Irrecuperáveis (falência, reciclagem) | 31 |
| Ausências legítimas (empresa não existia) | 2 (BHGE, DOW) |
| Parciais (dados incompletos no período) | 4 (FOX, FOXA, IR, KORS) |

Detalhamento completo em [`data_bases/external/ausencias_report.md`](new_aproach/data_bases/external/ausencias_report.md).

---

## Documentação técnica

| Arquivo | Conteúdo |
|---------|---------|
| [`markdowns/gatev_pairs_theory.md`](new_aproach/markdowns/gatev_pairs_theory.md) | Fundamentos matemáticos do método — normalização, SSD, spread, sinais de entrada/saída |
| [`markdowns/ssd_matrix_computation.md`](new_aproach/markdowns/ssd_matrix_computation.md) | Derivação da implementação matricial da SSD — da fórmula à operação `norms[:, None] + norms[None, :] - 2 * G` |

---

## Como reproduzir

Execute os notebooks na ordem abaixo a partir de `new_aproach/src/`:

```
1. pipeline_base.ipynb       → gera base_completa.csv
2. validacao_dados.ipynb     → valida e recupera tickers problemáticos
3. cobertura_base.ipynb      → valida cobertura por semestre
4. pairs_formation.ipynb     → seleciona pares e salva pares_formados.csv
```

**Dependências:** `pandas`, `numpy`, `yfinance`, `requests`, `matplotlib`

**APIs utilizadas:**
- Yahoo Finance via `yfinance` (coleta principal)
- [Tiingo](https://api.tiingo.com/) (recuperação de histórico de delistados — requer token)
