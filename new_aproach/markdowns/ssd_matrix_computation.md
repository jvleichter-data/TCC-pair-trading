# Cálculo da SSD via Álgebra Matricial

## Contexto

O método de Gatev et al. (2006) exige calcular a distância SSD entre todos os pares de ativos do universo. Com $n$ ativos, isso representa $\binom{n}{2} = \frac{n(n-1)}{2}$ pares — na ordem de centenas de milhares para um universo típico do S&P 500. Este documento explica como sair da fórmula da teoria e chegar no código numpy sem loops.

---

## A fórmula original

Da seção *Métrica de distância — SSD* do `gatev_pairs_theory.md`:

$$D(i, j) = \sum_{t=1}^{T} \left[Q_i(t) - Q_j(t)\right]^2$$

onde $Q_i(t) = P_i(t) / P_i(0)$ é o índice de retorno acumulado normalizado (todos os ativos partem de 1 no início do período de formação).

---

## Expansão algébrica

Expandindo o quadrado termo a termo:

$$D(i, j) = \sum_{t=1}^{T} \left[ Q_i(t)^2 - 2\,Q_i(t)\,Q_j(t) + Q_j(t)^2 \right]$$

Separando as somas:

$$D(i, j) = \underbrace{\sum_{t=1}^{T} Q_i(t)^2}_{\|q_i\|^2} \;-\; 2\underbrace{\sum_{t=1}^{T} Q_i(t)\,Q_j(t)}_{\langle q_i,\,q_j\rangle} \;+\; \underbrace{\sum_{t=1}^{T} Q_j(t)^2}_{\|q_j\|^2}$$

Cada termo tem um nome em álgebra linear:

| Termo | Notação | Significado |
|---|---|---|
| $\sum_t Q_i(t)^2$ | $\lVert q_i \rVert^2$ | Norma ao quadrado da série $i$ — o quanto ela variou ao longo do período |
| $\sum_t Q_i(t)\,Q_j(t)$ | $\langle q_i, q_j \rangle$ | Produto interno — quão parecidos foram os movimentos dos dois ativos dia a dia |
| $\sum_t Q_j(t)^2$ | $\lVert q_j \rVert^2$ | Norma ao quadrado da série $j$ |

**Intuição geométrica:** quanto maior o produto interno (movimentos parecidos) e menores as normas individuais, menor a distância — as trajetórias permaneceram próximas. Isso é equivalente à interpretação do artigo de que $D(i,j)$ mede a área quadrática entre as duas curvas normalizadas.

---

## Da fórmula ao código

### Organização dos dados

Organizamos os preços normalizados em uma matriz $Q$ de shape $(T \times n)$:

$$Q = \begin{bmatrix} Q_1(1) & Q_2(1) & \cdots & Q_n(1) \\ Q_1(2) & Q_2(2) & \cdots & Q_n(2) \\ \vdots & \vdots & \ddots & \vdots \\ Q_1(T) & Q_2(T) & \cdots & Q_n(T) \end{bmatrix}$$

- Cada **linha** é um dia de pregão
- Cada **coluna** é a série normalizada de um ativo

### Gram matrix

O produto $G = Q^\top Q$ tem shape $(n \times n)$ e cada elemento é:

$$G[i,\,j] = \langle q_i,\, q_j \rangle = \sum_{t=1}^{T} Q_i(t)\cdot Q_j(t)$$

Ou seja, $G$ contém **todos os produtos internos entre todos os pares** em uma única operação matricial. A diagonal de $G$ dá as normas:

$$G[i,\,i] = \langle q_i, q_i \rangle = \lVert q_i \rVert^2$$

### Montando a SSD para todos os pares

Substituindo na expressão expandida:

$$D[i, j] = G[i,i] + G[j,j] - 2\,G[i,j]$$

Para calcular isso para **todos os pares $(i,j)$ simultaneamente**, usamos broadcasting do numpy:

```python
arr   = Q.values            # (T, n) — matriz de preços normalizados
G     = arr.T @ arr         # (n, n) — Gram matrix: G[i,j] = <q_i, q_j>
norms = np.diag(G)          # (n,)   — normas ao quadrado: norms[i] = ||q_i||²

ssd   = norms[:, None] + norms[None, :] - 2 * G
#        ^^^^^^^^^^^^     ^^^^^^^^^^^^^
#        coluna (n,1)     linha (1,n)
#        → numpy expande e gera matriz (n,n)
#        ssd[i,j] = norms[i] + norms[j] - 2*G[i,j] = D(i,j)
```

### O que é broadcasting?

`norms[:, None]` transforma o vetor $(n,)$ em coluna $(n \times 1)$.  
`norms[None, :]` transforma o vetor $(n,)$ em linha $(1 \times n)$.

Ao somar uma coluna com uma linha, o numpy replica cada uma para preencher uma matriz $(n \times n)$:

$$\text{norms}[:, \text{None}] + \text{norms}[\text{None}, :] \;=\; \begin{bmatrix} n_1+n_1 & n_1+n_2 & \cdots \\ n_2+n_1 & n_2+n_2 & \cdots \\ \vdots & \vdots & \ddots \end{bmatrix}$$

onde $n_i = \lVert q_i \rVert^2$. O elemento $[i,j]$ dessa matriz vale exatamente $\lVert q_i \rVert^2 + \lVert q_j \rVert^2$, que é o que precisamos.

---

## Por que não usar loops?

A alternativa direta seria:

```python
for i in range(n):
    for j in range(i + 1, n):
        ssd[i, j] = np.sum((Q[:, i] - Q[:, j]) ** 2)
```

Para $n = 700$ ativos e $T = 250$ dias:
- **Pares a calcular:** $\binom{700}{2} \approx 245.000$
- **Operações por par:** $250$ subtrações + $250$ quadrados + $250$ somas
- **Total:** $\approx 183$ milhões de operações em loop Python → lento

A abordagem matricial faz tudo em uma multiplicação de matrizes $(n \times T) \cdot (T \times n)$ executada em C pelo numpy — ordens de magnitude mais rápida, com resultado matematicamente idêntico.

---

## Resumo: da teoria ao código

| Conceito (teoria) | Expressão matemática | Código numpy |
|---|---|---|
| Preços normalizados | $Q_i(t) = P_i(t)/P_i(0)$ | `precos.div(precos.iloc[0])` |
| Todos os produtos internos | $G = Q^\top Q$ | `arr.T @ arr` |
| Normas ao quadrado | $\lVert q_i \rVert^2 = G[i,i]$ | `np.diag(G)` |
| SSD de todos os pares | $D[i,j] = \lVert q_i \rVert^2 + \lVert q_j \rVert^2 - 2G[i,j]$ | `norms[:, None] + norms[None, :] - 2 * G` |
| Top-$k$ pares | $\min_k D(i,j)$ | `np.argsort(ssds)[:top_k]` |
