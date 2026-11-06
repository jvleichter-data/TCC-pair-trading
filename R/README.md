# Versão em R — distância, cointegração e cointegração não paramétrica

Tradução para R dos notebooks de `new_aproach/src/`, com a mesma organização: uma pasta por
método e um script por notebook, com o mesmo nome. Cada script usa os mesmos parâmetros, as
mesmas regras e grava os mesmos arquivos de saída que o notebook correspondente.

| Script R | Notebook Python | O que faz |
| --- | --- | --- |
| `distance/pairs_formation.R` | `distance/pairs_formation.ipynb` | Formação: distância SSD, top-20 por janela semestral |
| `distance/pairs_trading.R` | `distance/pairs_trading.ipynb` | Negociação de Gatev et al. (2006), métricas e Tabela 7 |
| `distance/pairs_trading_dinamico.R` | `distance/pairs_trading_dinamico.ipynb` | Banda μ, σ re-estimada no sinal, com veto por SSD/dia |
| `cointegration/pairs_formation_coint.R` | `cointegration/pairs_formation_coint.ipynb` | Engle-Granger bilateral (ADF), janela mensal |
| `cointegration/pairs_trading_coint.R` | `cointegration/pairs_trading_coint.ipynb` | Negociação de Rad et al. (2016), REC e RCC |
| `cointegration/pairs_trading_coint_dinamico.R` | `cointegration/pairs_trading_coint_dinamico.ipynb` | Re-teste de cointegração no sinal |
| `nonparametric/valor_critico_np.R` | `nonparametric/valor_critico_np.ipynb` | Valor crítico do teste NP por simulação |
| `nonparametric/pairs_formation_np_propria.R` | `nonparametric/pairs_formation_np_propria.ipynb` | Formação própria do NP (curva kernel local linear) |
| `nonparametric/pairs_trading_np.R` | `nonparametric/pairs_trading_np.ipynb` | Negociação NP (tangente à curva, maior perna em $1) |
| `nonparametric/pairs_formation_np.R` | `nonparametric/pairs_formation_np.ipynb` | Variante: curva ajustada nos pares da linear |
| `nonparametric/diagnostico_wang_phillips.R` | `nonparametric/diagnostico_wang_phillips.ipynb` | Teste de linearidade de Wang & Phillips (2012) |

A construção da base não faz parte desta pasta. Os scripts leem o `base_unificada.csv` já pronto.

## Início rápido

1. Instale o R (≥ 4.2) e, se quiser, o RStudio.
2. Copie `base_unificada.csv` para a pasta `data_bases/`. A base não está no repositório
   (tem ~55 MB) e é enviada à parte; o `rf_diario.csv` já está lá.
3. Abra `TCC_pair_trading.Rproj` no RStudio. Isso já deixa esta pasta como diretório de
   trabalho.
4. No console, rode `source("rodar_tudo.R")`.

Rodar tudo leva cerca de 2 h, quase todo esse tempo no método não paramétrico. Para uma
conferência rápida da distância e da cointegração (~9 min), ponha `RODAR_NP <- FALSE` no topo
do `rodar_tudo.R`.

## Requisitos

- R ≥ 4.2. Foi testado com o R 4.6.2.
- Nenhum pacote é obrigatório. Se o `data.table` estiver instalado, ele é usado para ler o
  CSV de preços (55 MB) mais rápido: `install.packages("data.table")`. O paralelismo do
  método NP usa o pacote `parallel`, que já vem com o R.
- Os dados em `data_bases/`: `base_unificada.csv` (preços, ~55 MB) e `rf_diario.csv` (taxa
  livre de risco). O `rf_diario.csv` já vem no repositório; a base não, por causa do tamanho, e
  precisa ser copiada para essa pasta (ver `data_bases/README.md`). Para ler de outro lugar,
  mude `PASTA_DADOS` em `config.R`.

## Como rodar

O diretório de trabalho precisa ser esta pasta (`R/`), mesmo para os scripts que estão
dentro das subpastas. No RStudio, basta abrir o `TCC_pair_trading.Rproj`.

```r
source("rodar_tudo.R")                       # todos os métodos, em ordem
source("distance/pairs_trading.R")           # ou um script isolado
```

Pelo terminal: `Rscript rodar_tudo.R`. No topo do `rodar_tudo.R` dá para escolher quais
métodos rodar.

Tempos medidos numa máquina de 4 núcleos:

- distância: cerca de 3,5 min;
- cointegração: cerca de 5 min;
- não paramétrico: cerca de 1 h 50 min. O valor crítico leva ~6 min, a formação própria
  (`pairs_formation_np_propria.R`) ~1 h 45 min e a negociação ~2 min;
- diagnósticos do NP (`pairs_formation_np.R` e `diagnostico_wang_phillips.R`): mais ~25 min.
  Ficam desligados por padrão.

Ordem e dependências:

- **distance:** `pairs_formation` → `pairs_trading` → `pairs_trading_dinamico`
- **cointegration:** `pairs_formation_coint` → `pairs_trading_coint` → `pairs_trading_coint_dinamico`
- **nonparametric:** `valor_critico_np` → `pairs_formation_np_propria` → `pairs_trading_np`. O
  `pairs_trading_np` também compara com `cointegration/pairs_trading_coint`.

Os parâmetros ficam no topo de cada script, com os mesmos nomes do notebook
(`DELTA`, `PASSO_MESES`, `PERIODO_FIM`, `MAX_RAZAO_SSD`, `BETA_MIN`, …). O que no Python é
`None`, aqui é `NULL`. No método NP, `N_PROCESSOS` controla quantos processos rodam em
paralelo (padrão: núcleos − 1).

## Saídas

Cada método grava em `<método>/output/`, como em `new_aproach/src`:

- `pares/` guarda os pares formados.
- `resultados/` guarda o resultado por par, a série diária do portfólio, o REC/RCC mensal e o
  log de sinais.
- `imagens/` guarda os gráficos em PNG.
- No NP há ainda `valor_critico/` (simulação e JSON do valor crítico) e `diagnostico/`
  (teste de Wang & Phillips).

As tabelas de métricas saem no console.

## Equivalência com o Python

Os scripts foram rodados lado a lado com os notebooks sobre a mesma base, e as saídas foram
comparadas arquivo a arquivo.

- **Distância:** os mesmos 1.380 pares, os mesmos trades, os mesmos sinais e vetos e a mesma
  série diária. As diferenças ficam abaixo de 1e-12 (arredondamento de ponto flutuante). A
  tabela de sensibilidade do dinâmico também bate nos 9 cenários.
- **Cointegração:** 8.138 dos 8.139 pares são idênticos. A exceção é um empate exato de SSD
  entre dois tickers-fantasma do mesmo emissor (TKR e 291784Q, com preços idênticos em
  1993–94), que o numpy e o R desempatam de forma diferente. É o mesmo par econômico, com o
  mesmo β e a mesma estatística. Negociação estática e dinâmica: os mesmos 5.745 pares, os
  mesmos trades, os mesmos 14.968 sinais do dinâmico e o mesmo REC/RCC, com diferenças abaixo
  de 1e-15.
- **Não paramétrico, formação:** com o valor crítico do Python, os mesmos 8.011 pares nas
  409 janelas. A única diferença são dois pares ligados ao mesmo empate TKR/291784Q, que
  trocam de posição (8 e 9) numa janela. As contagens por janela são idênticas.
- **Não paramétrico, negociação:** sobre os mesmos pares, os mesmos 5.585 pares simulados e
  24.737 sinais com os mesmos vetos, a mesma série diária e o mesmo REC/RCC. O Sharpe é 1,11,
  como no TCC. Os z dos sinais diferem em até 2e-7, porque as regressões locais com h pequeno
  são mal condicionadas; nenhuma decisão muda.
- **Não paramétrico, variante e diagnóstico:** a formação sobre os pares da linear dá os mesmos
  8.139 pares, h e μ, σ que o Python (fora o par empatado TKR/291784Q herdado da linear). No
  teste de Wang & Phillips, a estatística Z, o p-valor pela normal e o φ coincidem até 1e-11; a
  taxa de rejeição pelo bootstrap também (18,3% no R e no Python nos pares próprios).

### O que depende de sorteio

O valor crítico do NP (`valor_critico_np.R`) e o p-valor do bootstrap de Wang & Phillips vêm
de simulação. O R não reproduz a sequência aleatória do numpy, então esses números saem
próximos, mas não idênticos. O valor crítico a 5% dá −3,506 no R e −3,518 no Python; a
diferença está dentro do erro de Monte Carlo.

Com o valor crítico do próprio R, a formação seleciona 8.039 pares em vez de 8.011, e 98% dos
pares coincidem. O resultado da negociação praticamente não muda: Sharpe 1,11, retorno de
3,93% a.a. (3,94% no TCC) e drawdown máximo de −9,2% (−9,7% no TCC).

Para reproduzir exatamente os pares e os números do TCC, aponte `ARQ_CRITICO` em
`nonparametric/pairs_formation_np_propria.R` para o JSON do Python:

```r
ARQ_CRITICO <- "../new_aproach/src/nonparametric/output/valor_critico/valor_critico_np.json"
```

### Pontos de implementação

- **ADF.** As funções prontas do R (`tseries::adf.test`, `urca::ur.df`) escolhem as
  defasagens de outro jeito e não reproduzem o `statsmodels.adfuller`. Por isso o ADF está
  implementado em `funcoes/adf.R` seguindo o `adfuller` passo a passo: maxlag de Schwert,
  busca por AIC ou BIC na mesma amostra e reestimação com a defasagem escolhida. Sobre 300
  séries simuladas, a estatística coincide com a do statsmodels até 1e-13.
- **Desvios-padrão.** O `spread_desvio` da distância usa `ddof = 1` (pandas). Na cointegração
  e no NP é o desvio populacional, `ddof = 0` (numpy), como nos notebooks.
- **Velocidade do NP.** O kernel em R é cerca de 3 vezes mais lento que no numpy, porque a
  função `exp` do R não é vetorizada. Por isso a formação própria roda em paralelo; com 3
  processos ela leva cerca de 1 h 15 min a 1 h 45 min.

## Estrutura

```text
R/
├── config.R                     caminhos da base e das saídas
├── rodar_tudo.R
├── TCC_pair_trading.Rproj
├── data_bases/                  rf_diario.csv; base_unificada.csv (copiar para cá)
├── funcoes/                     compartilhadas pelos métodos
│   ├── comum.R                  base, janelas, filtros, SSD, mesmo emissor, portfólio, REC/RCC, gráficos
│   ├── metricas.R               tradução de src/metricas.py (blocos do orientador, Gatev e Rad)
│   ├── adf.R                    OLS e ADF (réplica do statsmodels)
│   └── paralelo.R               execução em vários processos
├── distance/
│   ├── funcoes_distancia.R      simulação estática de um par
│   ├── pairs_formation.R · pairs_trading.R · pairs_trading_dinamico.R
│   └── output/
├── cointegration/
│   ├── funcoes_coint.R          teste de Engle-Granger (ADF/CRDW) e simulação estática de um par
│   ├── pairs_formation_coint.R · pairs_trading_coint.R · pairs_trading_coint_dinamico.R
│   └── output/
└── nonparametric/
    ├── kernel_np.R              local linear, validação cruzada, teste de cointegração NP
    ├── formacao_utils.R         seleção da formação própria, leitura do valor crítico
    ├── negociacao_utils.R       simulação de um par e laço da negociação
    ├── especificacao_np.R       teste de Wang & Phillips (2012)
    ├── valor_critico_np.R · pairs_formation_np_propria.R · pairs_trading_np.R
    ├── pairs_formation_np.R · diagnostico_wang_phillips.R
    └── output/
```
