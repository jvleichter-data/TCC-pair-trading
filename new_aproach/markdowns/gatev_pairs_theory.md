# Método de Distância de Gatev — Base Matemática e Teoria

## Contexto

O método de distância de Gatev, Goetzmann e Rouwenhorst (2006) é uma estratégia de *pairs trading* estatística. A lógica central é: dois ativos que historicamente co-evoluem tendem a reverter à relação histórica quando dela se afastam. O método opera em duas fases temporais separadas: **formação** e **negociação**.

---

## Fase de formação

### 1. Normalização dos preços

Dado um universo de $n$ ativos com séries de preços $P_i(0), P_i(1), \ldots, P_i(T)$, define-se o **índice de retorno acumulado** (cumulative return index):

$$Q_i(0) = 1$$

$$Q_i(t) = Q_i(t-1) \cdot \left(1 + r_i(t)\right), \quad r_i(t) = \frac{P_i(t)}{P_i(t-1)} - 1$$

Equivalentemente em forma fechada:

$$Q_i(t) = \prod_{s=1}^{t} \left(1 + r_i(s)\right) = \frac{P_i(t)}{P_i(0)}$$

**Propriedade fundamental:** $Q_i(t)$ representa o valor de R$1,00 investido no ativo $i$ no instante 0. Todos os ativos passam a ser comparáveis independentemente do preço absoluto inicial.

---

### 2. Métrica de distância — SSD

Para cada par ordenado $(i, j)$ com $i \neq j$, define-se o **spread normalizado** no instante $t$:

$$s_{ij}(t) = Q_i(t) - Q_j(t)$$

A **distância de Gatev** entre o par $(i, j)$ ao longo do período de formação $[1, T]$ é a soma dos quadrados das diferenças (Sum of Squared Differences):

$$D(i, j) = \sum_{t=1}^{T} \left[Q_i(t) - Q_j(t)\right]^2$$

**Interpretação geométrica:** $D(i,j)$ é proporcional à área quadrática entre as duas trajetórias no espaço dos índices normalizados. Quanto menor $D(i,j)$, mais as curvas co-evoluíram durante o período de formação.

---

### 3. Seleção dos pares

Com $n$ ativos, existem $\binom{n}{2} = \frac{n(n-1)}{2}$ pares candidatos.

O algoritmo ordena todos os pares por $D(i,j)$ em ordem crescente e seleciona os **top-$k$ pares** de menor distância. Na literatura original, $k = 20$ pares foi o valor utilizado.

Para cada par selecionado, estimam-se os parâmetros históricos do spread:

$$\bar{s}_{ij} = \frac{1}{T} \sum_{t=1}^{T} s_{ij}(t)$$

$$\sigma_{ij} = \sqrt{\frac{1}{T} \sum_{t=1}^{T} \left(s_{ij}(t) - \bar{s}_{ij}\right)^2}$$

---

## Fase de negociação

### 4. Z-score do spread

No período de negociação $[T+1, T+\tau]$, monitora-se o **spread padronizado** (z-score):

$$z_{ij}(t) = \frac{s_{ij}(t) - \bar{s}_{ij}}{\sigma_{ij}} = \frac{Q_i(t) - Q_j(t) - \bar{s}_{ij}}{\sigma_{ij}}$$

Os parâmetros $\bar{s}_{ij}$ e $\sigma_{ij}$ são fixos — calculados na fase de formação e não atualizados durante a negociação.

---

### 5. Regras de entrada e saída

Dado um gatilho $\delta$ (tipicamente $\delta = 2$):

| Condição | Posição |
|---|---|
| $z_{ij}(t) > +\delta$ | Vende $i$, compra $j$ |
| $z_{ij}(t) < -\delta$ | Compra $i$, vende $j$ |
| $z_{ij}(t) \to 0$ | Fecha a posição (reversão) |
| $\|z_{ij}(t)\| > \delta_{stop}$ | Stop-loss (opcional, $\delta_{stop} \approx 4$) |

A posição é **neutra em capital** (dollar-neutral): o valor comprado é igual ao valor vendido, eliminando exposição direcional ao mercado.

---

## Estrutura temporal padrão

Conforme o artigo original (Gatev et al., 2006):

- **Período de formação:** 12 meses
- **Período de negociação:** 6 meses imediatamente subsequentes
- As janelas rolam sequencialmente (sem sobreposição entre períodos de negociação)

---

## Premissas e limitações

**O método pressupõe:**
- Os spreads selecionados são estacionários durante o período de negociação (premissa de reversão à média)
- A relação histórica estimada na formação permanece válida fora da amostra
- Liquidez suficiente para executar ambos os lados simultaneamente

**Limitações conhecidas:**
- A SSD é uma medida de distância *não paramétrica* — não testa formalmente cointegração nem estacionariedade do spread
- Sensível ao período de formação escolhido (janela look-back)
- Não controla para exposição a fatores comuns (setor, mercado) — pares do mesmo setor tendem a dominar o ranking

---

## Extensões relevantes

**Cointegração (Engle-Granger):** abordagem mais rigorosa que testa explicitamente se existe combinação linear estacionária entre $\log P_i$ e $\log P_j$. O vetor de cointegração $\beta$ é estimado por OLS:

$$\log P_i(t) = \alpha + \beta \cdot \log P_j(t) + \varepsilon(t)$$

O spread estacionário passa a ser $\varepsilon(t) = \log P_i(t) - \alpha - \beta \cdot \log P_j(t)$.

**Razão de hedge dinâmica:** em vez de posição 1:1 em valor, ajusta-se o número de contratos pelo $\beta$ estimado para minimizar a variância do spread.

---

## Variáveis e notação resumida

| Símbolo | Descrição |
|---|---|
| $P_i(t)$ | Preço do ativo $i$ no instante $t$ |
| $r_i(t)$ | Retorno simples do ativo $i$ em $t$ |
| $Q_i(t)$ | Índice de retorno acumulado normalizado, $Q_i(0)=1$ |
| $s_{ij}(t)$ | Spread: $Q_i(t) - Q_j(t)$ |
| $D(i,j)$ | Distância SSD entre o par $(i,j)$ |
| $\bar{s}_{ij}$ | Média histórica do spread (fase de formação) |
| $\sigma_{ij}$ | Desvio padrão histórico do spread |
| $z_{ij}(t)$ | Z-score do spread no período de negociação |
| $\delta$ | Gatilho de entrada (padrão: 2) |
| $T$ | Comprimento do período de formação |
| $\tau$ | Comprimento do período de negociação |
| $k$ | Número de pares selecionados |
