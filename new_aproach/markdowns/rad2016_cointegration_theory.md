# Método de Cointegração — Rad, Low & Faff (2016)

> **Referência:** Rad, H., Low, R.K.Y. & Faff, R. (2016). *The profitability of pairs trading strategies: distance, cointegration and copula methods.* Quantitative Finance, 16(10), 1541–1558.

## Contexto e Motivação

Rad et al. (2016) realizam um estudo abrangente comparando três estratégias de pairs trading — distância, cointegração e cópula — sobre o mercado acionário americano completo (base CRSP) de 1962 a 2014, com custos de transação variáveis no tempo. O objetivo central é avaliar se métodos mais sofisticados que o método de distância de Gatev et al. (2006) geram melhor desempenho.

Para o método de cointegração, os autores propõem uma abordagem de **dois passos computacionalmente eficiente** que combina o pré-filtro de distância (SSD) com testes formais de cointegração, tornando a estratégia operacionalizável em larga escala.

**Resultado empírico principal:** o método de cointegração gera retorno mensal médio em excesso de 85 bps antes e 33 bps após custos de transação. É a **estratégia superior em períodos de alta volatilidade e mercados turbulentos**.

---

## 1. Estrutura Temporal

A estratégia opera em janelas rolantes mensais com dois períodos distintos:

| Período | Duração | Função |
|---|---|---|
| **Formação** | 12 meses | Estimar parâmetros, selecionar pares |
| **Negociação** | 6 meses | Monitorar spread e executar trades |

**Janela mensal com sobreposição:** a estratégia é executada começando um novo portfólio a cada mês, sem aguardar o período de negociação anterior se encerrar. Isso resulta em **seis portfólios sobrepostos** ativos simultaneamente a cada mês. O retorno mensal da estratégia é a média igualmente ponderada desses seis portfólios.

```
Mês 1:  [--- Formação (12m) ---][--- Negociação (6m) ---]
Mês 2:   [--- Formação (12m) ---][--- Negociação (6m) ---]
Mês 3:    [--- Formação (12m) ---][--- Negociação (6m) ---]
...
```

A sobreposição suaviza o retorno agregado e reduz a sensibilidade ao timing de entrada — um portfólio iniciado num mês ruim é compensado pelos outros cinco.

---

## 2. Filtros de Dados (Fase de Formação)

Antes de qualquer cálculo, o universo de ativos é filtrado para garantir liquidez e qualidade dos dados:

- Excluem-se ações com **preço menor que US$ 1** no período de formação
- Excluem-se ações com **pelo menos um dia sem negociação** em qualquer período de formação do respectivo período de negociação
- Excluem-se ações com **baixo valor de mercado** e **baixa capitalização**

Esses filtros replicam um ambiente de trading prático e são consistentes com Do e Faff (2012).

---

## 3. Passo 1 — Pré-filtro por Distância (SSD)

Para aumentar a eficiência computacional, Rad et al. não testam cointegração em todos os $\binom{n}{2}$ pares possíveis. Em vez disso, **primeiro ordenam todos os pares pela SSD** e testam cointegração apenas nos candidatos com menor distância.

### 3.1 Normalização

O preço de cada ativo é transformado no índice de retorno acumulado, escalado para US$ 1 no início do período de formação:

$$Q_i(t) = \frac{P_i(t)}{P_i(0)}$$

### 3.2 Distância SSD

Para cada par $(i, j)$, a soma dos quadrados das diferenças durante o período de formação $[1, T]$:

$$D(i,j) = \sum_{t=1}^{T} \left[Q_i(t) - Q_j(t)\right]^2$$

### 3.3 Procedimento de seleção em dois passos

1. Ordenar todos os pares por $D(i,j)$ crescente
2. Testar o par de menor SSD para cointegração
3. Se cointegrado → incluir no portfólio; se não → descartar
4. Avançar para o próximo par na lista
5. Repetir até selecionar **20 pares cointegrados com menor SSD**

Esse procedimento garante que apenas pares com forte co-movimento histórico *e* relação de equilíbrio formal sejam selecionados, sem o custo computacional de testar todos os pares.

---

## 4. Passo 2 — Teste de Cointegração (Engle-Granger)

Para cada par candidato, aplica-se o **método de dois passos de Engle-Granger (1987)**.

### 4.1 Definição Formal

Uma série temporal não-estacionária $X_t$ é $I(1)$ se sua primeira diferença $\Delta X_t$ é estacionária $I(0)$. Dois processos $I(1)$, $X_{1,t}$ e $X_{2,t}$, são **cointegrados** se existe um número real não-nulo $\beta$ tal que:

$$X_{2,t} - \beta X_{1,t} = u_t \quad \text{com } u_t \sim I(0) \tag{1}$$

onde $\beta$ é o **coeficiente de cointegração** e $u_t$ é a série de erros de cointegração — estacionária por definição.

### 4.2 Representação ECM

Pelo teorema de Granger (Engle e Granger, 1987), a relação de cointegração é equivalentemente representada pelo **Modelo de Correção de Erros (ECM)**:

$$X_{2,t} - X_{2,t-1} = \alpha_{X_2}(X_{2,t-1} - \beta X_{1,t-1}) + \xi_{X_{2,t}} \tag{2a}$$

$$X_{1,t} - X_{1,t-1} = \alpha_{X_1}(X_{2,t-1} - \beta X_{1,t-1}) + \xi_{X_{1,t}} \tag{2b}$$

O termo $(X_{2,t-1} - \beta X_{1,t-1})$ é o desvio do equilíbrio no período anterior. Os coeficientes $\alpha_{X_1}$ e $\alpha_{X_2}$ são as **velocidades de ajuste** — medem o quanto cada série se move para corrigir o desvio. Séries cointegradas exibem equilíbrio de longo prazo: desvios de curto prazo são temporários e corrigidos ao longo do tempo pelo termo de erro do ECM.

### 4.3 Passo 1 do Engle-Granger — Regressão OLS

Estima-se o coeficiente de cointegração $\beta$ por **OLS** usando os índices de retorno acumulado $Q_i$ do período de formação:

$$Q_{2,t} = \alpha + \beta \cdot Q_{1,t} + \varepsilon_t \tag{3}$$

O OLS minimiza $\sum \varepsilon_t^2$, produzindo $\hat{\beta}$ e $\hat{\alpha}$. O resíduo estimado:

$$\hat{\varepsilon}_t = Q_{2,t} - \hat{\alpha} - \hat{\beta} \cdot Q_{1,t} \tag{4}$$

é o **spread** do par. Se o par for cointegrado, esse resíduo será estacionário $I(0)$.

**Importante:** os índices $Q_i(t)$ são usados na regressão (não os log-preços), pois a SSD também é calculada sobre $Q_i$. Isso mantém consistência entre o critério de pré-seleção e a estimação do spread.

### 4.4 Passo 2 do Engle-Granger — Teste ADF no Resíduo

Aplica-se o teste Aumentado de Dickey-Fuller (ADF) no resíduo $\hat{\varepsilon}_t$:

$$\Delta\hat{\varepsilon}_t = \rho \cdot \hat{\varepsilon}_{t-1} + \sum_{k=1}^{K} \phi_k \cdot \Delta\hat{\varepsilon}_{t-k} + \eta_t \tag{5}$$

- $H_0: \rho = 0$ — resíduo tem raiz unitária → par **não** cointegrado → descartar
- $H_1: \rho < 0$ — resíduo é estacionário → par **cointegrado** ✓

**Valor crítico:** usa-se o valor crítico de MacKinnon a 5%, que é aproximadamente $-3.34$ para resíduos de regressão de cointegração — mais exigente que o ADF usual ($-2.89$) porque $\hat{\varepsilon}_t$ foi estimado pelo OLS (que minimiza os resíduos por construção, tornando-os artificialmente mais estacionários).

Se o par **não passar** no teste ADF, ele é eliminado e o próximo par na lista SSD é testado.

---

## 5. Spread e Parâmetros de Trading

Para cada par cointegrado aprovado, calcula-se o spread e seus parâmetros estatísticos **com os dados do período de formação**:

$$\text{spread}_t = Q_{2,t} - \hat{\beta} \cdot Q_{1,t} \tag{6}$$

onde $\text{spread}_t = \hat{\varepsilon}_t \sim I(0)$ com média $\mu_e$ e desvio padrão $\sigma_e$.

O **spread normalizado** (z-score) é definido como:

$$z_t = \frac{\text{spread}_t - \mu_e}{\sigma_e} \tag{7}$$

Os parâmetros $\hat{\beta}$, $\mu_e$ e $\sigma_e$ são **estimados na formação e mantidos fixos** durante todo o período de negociação. Não há reatualização dos parâmetros intra-período.

---

## 6. Regras de Trading

### 6.1 Abertura de posição

Posições são abertas quando o z-score cruza o limiar de $\pm 2$ desvios padrão:

| Condição | Interpretação | Posição |
|---|---|---|
| $z_t < -2$ | Spread abaixo do equilíbrio — $Q_2$ barato relativo a $Q_1$ | Long \$1 em ativo 2 · Short $\hat{\beta}$ em ativo 1 |
| $z_t > +2$ | Spread acima do equilíbrio — $Q_2$ caro relativo a $Q_1$ | Short $\frac{1}{\hat{\beta}}$ em ativo 2 · Long \$1 em ativo 1 |

**Dimensionamento das posições:** por construção, o método garante uma posição long de \$1 em cada trade. As posições long e short **não são iguais em valor** (ao contrário do método de distância que é dollar-neutral 50/50) — o lado short é escalado por $\hat{\beta}$ para garantir neutralidade ao fator comum.

### 6.2 Fechamento de posição

As posições são fechadas quando o spread retorna a zero:

$$z_t \to 0 \quad \Leftrightarrow \quad \text{spread}_t = \mu_e$$

Isso corresponde ao par retornando ao equilíbrio de longo prazo. Após o fechamento, o par continua sendo monitorado para outros potenciais trades durante o restante do período de negociação — múltiplos round-trips são possíveis num mesmo período.

### 6.3 Fechamento compulsório

Ao final do período de negociação (6 meses), **todas as posições abertas são encerradas compulsoriamente**, independentemente do z-score. Esses são os **unconverged trades** — principal fonte de perdas da estratégia (média de −4.36% por trade não convergido).

---

## 7. Cálculo do Retorno

### 7.1 Retorno marcado a mercado

O retorno diário de um par com posição aberta é a variação do spread multiplicada pela direção da posição:

$$r_t = \text{position}_{t-1} \times (\text{spread}_t - \text{spread}_{t-1}) \tag{8}$$

onde $\text{position}_{t-1} \in \{-1, 0, +1\}$ é a posição do dia anterior (lag necessário para evitar look-ahead bias — a decisão é tomada ao fechamento do dia $t$, a execução ocorre no dia $t+1$).

### 7.2 Retorno sobre capital empregado (REC)

O retorno mensal sobre capital empregado para o mês $m$:

$$\text{REC}_m = \frac{\sum_{i=1}^{n} r_i}{n} \tag{14}$$

onde $n$ é o número de pares que efetivamente negociaram no mês $m$ (ignora pares que não abriram posição).

### 7.3 Retorno sobre capital comprometido (RCC)

Medida mais conservadora, divide pelo número total de pares nominados ($N_P = 20$), independentemente de terem negociado:

$$\text{RCC}_m = \frac{\sum_{i=1}^{n} r_i}{N_P}, \quad N_P = 20 \tag{15}$$

O RCC é equivalente ao que um hedge fund reportaria, pois considera o custo de oportunidade do capital alocado mas não utilizado.

### 7.4 Retorno do portfólio agregado

O retorno mensal final é a **média igualmente ponderada** dos seis portfólios sobrepostos ativos naquele mês:

$$R_m = \frac{1}{6}\sum_{p=1}^{6} \text{REC}_{m,p}$$

---

## 8. Custos de Transação Variáveis no Tempo

Rad et al. usam uma estrutura de custos variáveis no tempo, seguindo Do e Faff (2012), composta por dois elementos:

### 8.1 Comissão institucional

Parte de 70 bps em 1962 e declina gradualmente para 9 bps nos anos recentes, refletindo a queda histórica nos custos de corretagem.

### 8.2 Impacto de mercado (market impact)

- **1962–1988:** 30 bps por trade
- **1989 em diante:** 20 bps por trade

### 8.3 Aplicação

Cada trade completo (par) consiste em **dois round-trips** (abertura + fechamento de dois lados). Os custos são **dobrados** para cobrir o par completo. O custo total é deduzido no momento da abertura e fechamento da posição.

Ações com baixo valor de mercado e baixa capitalização são excluídas do universo, permitindo assumir que os custos de short-selling são desprezíveis para os ativos remanescentes.

---

## 9. Medidas de Performance

O artigo avalia a estratégia com as seguintes métricas:

| Métrica | Resultado (após custos) |
|---|---|
| Retorno mensal médio em excesso | 33 bps |
| Retorno mensal médio antes de custos | 85 bps |
| Sharpe Ratio (after-cost) | ~0.68 |
| Omega ratio (after-cost) | 2.68 |
| Sortino ratio (after-cost) | 0.68 |
| Kappa 3 (after-cost) | 0.41 |
| Maximum drawdown | 17.18% |
| Skewness dos retornos (after-cost) | **positiva** — única entre as 3 estratégias |
| % trades convergidos | 61.35% |
| % trades positivos (convergidos) | 98.64% |
| Dias médios aberto (convergidos) | 22.65 dias |

A cointegração é a **única estratégia com retornos positivamente assimétricos após custos** — as perdas são limitadas e os ganhos têm cauda mais longa. Isso é um resultado favorável do ponto de vista de risco.

---

## 10. Unconverged Trades — Principal Fonte de Risco

Trades não convergidos (spread não retorna a zero antes do fim do período) são a principal fonte de perdas:

| Trade type | % do total | Retorno médio | Sharpe |
|---|---|---|---|
| Convergido (C) | 61.35% | +4.37% | 1.62 |
| Não convergido (U) | 38.65% | −4.36% | −0.58 |

O custo assimétrico é claro: 61% dos trades geram retorno positivo médio de +4.37%, enquanto 39% geram perda média de −4.36%. O resultado líquido positivo vem do volume ligeiramente maior de trades convergidos.

---

## 11. Procedimento Completo — Resumo

```
PARA CADA MÊS m (janela inicia todo mês):
│
├── FASE DE FORMAÇÃO [m-12, m-1]
│   │
│   ├── 1. Aplicar filtros de universo
│   │       → Preço ≥ $1 em todos os dias
│   │       → Sem dias sem negociação
│   │
│   ├── 2. Normalizar: Q_i(t) = P_i(t) / P_i(0)
│   │
│   ├── 3. Calcular SSD para todos os pares
│   │       D(i,j) = Σ [Q_i(t) - Q_j(t)]²
│   │
│   ├── 4. Ordenar pares por D(i,j) crescente
│   │
│   └── 5. Para cada par na ordem (SSD crescente):
│           ├── Rodar OLS: Q₂ = α + β·Q₁ + ε
│           ├── Calcular resíduo ε̂ₜ = Q₂ₜ - α̂ - β̂·Q₁ₜ
│           ├── Teste ADF em ε̂ₜ → t < −3.34?
│           │       ├── Sim → par cointegrado ✓
│           │       │         armazenar (β̂, μ_e, σ_e)
│           │       └── Não → descartar, próximo par
│           └── Parar ao atingir 20 pares cointegrados
│
└── FASE DE NEGOCIAÇÃO [m, m+6]
    │
    ├── Para cada dia t e cada par cointegrado:
    │   ├── spread_t = Q₂ₜ - β̂·Q₁ₜ
    │   ├── z_t = (spread_t - μ_e) / σ_e
    │   └── Aplicar regras:
    │           z_t < -2  → Long $1 em ativo 2, Short β̂ em ativo 1
    │           z_t > +2  → Short 1/β̂ em ativo 2, Long $1 em ativo 1
    │           z_t → 0   → Fechar posição
    │           Fim do período → Fechar todas (unconverged)
    │
    └── Retorno diário: r_t = position_{t-1} × (spread_t - spread_{t-1})

RETORNO MENSAL = média dos 6 portfólios sobrepostos ativos no mês
```

---

## 12. Variáveis e Notação

| Símbolo | Descrição |
|---|---|
| $P_i(t)$ | Preço do ativo $i$ no instante $t$ |
| $Q_i(t)$ | Índice de retorno acumulado: $P_i(t)/P_i(0)$ |
| $D(i,j)$ | Distância SSD entre o par $(i,j)$ |
| $\beta$ | Coeficiente de cointegração (estimado por OLS) |
| $\alpha$ | Intercepto da regressão de cointegração |
| $\varepsilon_t$ | Resíduo da regressão de cointegração (o spread) |
| $\mu_e$ | Média do spread no período de formação |
| $\sigma_e$ | Desvio padrão do spread no período de formação |
| $z_t$ | Z-score do spread: $(\varepsilon_t - \mu_e)/\sigma_e$ |
| $\rho$ | Coeficiente de reversão no teste ADF |
| $\alpha_{X_1}, \alpha_{X_2}$ | Velocidades de ajuste no ECM |
| $\text{REC}_m$ | Retorno sobre capital empregado no mês $m$ |
| $\text{RCC}_m$ | Retorno sobre capital comprometido no mês $m$ |
| $N_P$ | Número de pares nominados por portfólio (= 20) |

---

## 13. Decisões de Implementação Relevantes

**γ estático:** ao contrário de Caldeira & Moura (2013), que atualizam $\gamma$ via Filtro de Kalman, Rad et al. mantêm $\hat{\beta}$ fixo durante todo o período de negociação. Isso reduz a complexidade computacional e o risco de overfitting intra-período.

**Sem restrição de setor:** pares de setores diferentes são aceitos, desde que passem no teste de cointegração. O critério estatístico substitui o filtro econômico.

**Limiar fixo de ±2σ:** não há ajuste dinâmico do limiar de entrada. O artigo testa sensibilidade a outros limiares e confirma que ±2σ é robusto.

**Posição de $1 longa garantida:** o método garante que o lado long sempre vale \$1. O lado short varia com $\hat{\beta}$, tornando a posição assimétrica em valor mas neutra ao fator comum.

**Sem rebalanceamento intra-trade:** uma vez aberta, a posição não é rebalanceada mesmo que os preços se movam e a neutralidade de mercado seja alterada.

---

## Referência

Rad, H., Low, R.K.Y. & Faff, R. (2016). The profitability of pairs trading strategies: distance, cointegration and copula methods. *Quantitative Finance*, 16(10), 1541–1558. DOI: 10.1080/14697688.2016.1164337
