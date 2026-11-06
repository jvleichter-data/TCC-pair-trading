# Relatório da rodada noturna — 2026-11-02

Pedido (01/11): (1) corrigir o dimensionamento das pernas seguindo os slides e a linear; (2) testar se
o NP "supera" a linear; (4) avaliar o teste de cointegração a partir do dia 63; (6) diagnóstico de
Wang & Phillips (2012). Tudo rodou sem erro. Detalhes, tabelas completas e referências em
`DECISOES.md` § 9; página atualizada: https://claude.ai/artifact/EmAQP4n7QWKY6dgFUpNAcE (versão 4).

## Resumo em quatro linhas

1. **Dimensionamento novo (padrão):** hedge dos slides (1 : β nos dois sentidos) com a maior perna em $1,
   e 0,50 ≤ β ≤ 2. O NP sobe para **Sharpe 1,11** em 1991–2015 (era 0,90) e **0,87** em 1991–2025 (era
   0,72), com volatilidade 3,5% e drawdown −9,7%. A linear também melhora com a mesma convenção (0,93 → 1,02).
2. **Significância:** nenhuma diferença NP × linear é significativa a 5%. Mesma convenção, 1991–2025:
   +0,16 de Sharpe, p = 0,24; 2016–2025: +0,35, p = 0,08. Conclusão: **comparável**, com indício de
   vantagem depois de 2016.
3. **Poder do teste (dia 63):** o poder dobra, mas a negociação piora (0,87 → 0,77). Mantido o dia 126.
4. **Wang & Phillips:** 18% dos pares rejeitam a reta; onde rejeitam, o NP **perde** da linear. Não
   linearidade significativa não é vantagem — o ganho do NP vem do teste de cointegração próprio.

## 1. Dimensionamento das pernas

- Os slides (17–18) usam 1 unidade de P1 contra β de P2, "ou a posição inversa": a mesma razão nos dois
  sentidos. A convenção de Rad (linear e NP até ontem) fixa a perna comprada em $1 e vende 1/β com z > 0
  — alavancava com β pequeno — e vende β com z < 0 — alavancava com β grande (houve β = 3,08).
- Escolha (sua, abordagem b): o hedge dos slides com a maior perna normalizada em $1. Retorno =
  −posição × Δspread ÷ max(1, β). Faixa 0,50 ≤ β ≤ 2 (a perna menor vale ao menos metade da maior).

| NP, formação própria | Sharpe 91–15 | vol | DD máx. | Sharpe 91–25 |
|---|---|---|---|---|
| Rad (anterior) | 0,90 | 4,37% | −13,4% | 0,72 |
| Rad + teto 2 | 0,95 | 4,22% | −14,2% | 0,74 |
| slides 1 : β | 0,95 | 4,26% | −10,6% | 0,80 |
| **maior perna, 0,50 ≤ β ≤ 2 (padrão)** | **1,11** | **3,53%** | **−9,7%** | **0,87** |

Linear com as mesmas convenções (em memória, sem tocar no notebook dela): Rad 0,93 / 0,66; maior perna
1,02 / 0,71.

## 2. Significância (bootstrap em blocos de 21 pregões, 5.000 réplicas)

| NP atual × | período | dif. Sharpe | p | IC 95% |
|---|---|---|---|---|
| linear, maior perna | 1991–2025 | +0,16 | 0,24 | [−0,10; +0,42] |
| linear, maior perna | 2016–2025 | +0,35 | 0,08 | [−0,05; +0,75] |
| linear, Rad | 1991–2025 | +0,21 | 0,12 | [−0,05; +0,47] |

## 3. Poder: erros a partir do dia 63

Valor crítico −3,67 (era −3,52); poder para meia-vida de 7 pregões 46% (era 27%); 19,5% dos candidatos
aprovados (era 11,8%); 42% dos pares em comum com a linear (era 24%). Sharpe 1991–2025 0,77 (padrão: 0,87).
O teste mais fraco funciona como filtro exigente — **mantido o dia 126**.

## 4. Wang & Phillips (2012)

O artigo supõe resíduo sem autocorrelação; nossos spreads têm AR(1) ≈ 0,89, e a N(0,1) do artigo chamaria
de curva 73% dos pares **lineares** (simulação). P-valor por bootstrap AR(1) sob a reta: erro de 3–7%.
- Formação própria: 18% rejeitam a reta (N(0,1): 83%, inválido). 77% das curvas que a CV escolhe não são
  significativamente diferentes da reta.
- Pares da linear: onde W&P rejeita a reta, NP − linear = −1,20 p.p. por par; onde não rejeita, −0,03.

## Decisões pendentes (suas)

1. **Adotar a convenção "maior perna = $1" na cointegração linear** (estática e dinâmica). Hoje a
   comparação do painel mistura convenções.
2. **Regenerar as saídas gravadas da linear**: `cointegration/output/resultados/*` são de 14/09, antes da
   mudança de `SIGMA_MIN` de 22/09 (0,937 no arquivo × 0,934 no notebook atual).
3. **Custos de transação** nos três métodos, antes das conclusões do TCC.

## Arquivos novos

- `pairs_trading_np.ipynb`: `DIMENSIONAMENTO` (`'maior_perna'` padrão; `'rad'`, `'slides'`) e `BETA_MAX` (2,0).
- `especificacao_np.py` + `diagnostico_wang_phillips.ipynb` → `output/diagnostico/`.
- `output/valor_critico_t63/`, `output/pares/pares_formados_np_propria_t63*.csv`, `*_np_t63*.csv`.
- Saídas Rad preservadas: `*_np_dim_rad*.csv`; variantes: `*_np_dim_*.csv`.
- `validation/auditoria/nonparametric/`: `teste_sharpe.py`, `lin_variantes.py` (+ `lin_*.csv`),
  `compara_dim.py` → `relatorio_dim.md`, `relatorio_t63.md`, lotes e logs.
