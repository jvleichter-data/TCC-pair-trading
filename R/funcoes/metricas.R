# -*- coding: utf-8 -*-
# Bloco de métricas comparáveis — tradução de new_aproach/src/metricas.py.
#
# Cada artigo reporta numa frequência diferente. Só a MÉDIA converte entre elas;
# desvio, Sharpe, assimetria, curtose, mínimo, máximo e % de negativos NÃO convertem.
#
#   orientador (QREF 2023)  → série DIÁRIA, média × 252, Sharpe × √252
#   Gatev (RFS 2006)        → série MENSAL, média por mês, sem anualizar
#   Rad et al. (QF 2016)    → série MENSAL, Sharpe = média/desvio MENSAL (não anualizado)
#
# Requer funcoes/comum.R (assimetria, curtose_excedente).

DIAS_ANO  <- 252
MESES_ANO <- 12

# ── Referências publicadas ───────────────────────────────────────────────────────────
# Orientador, Tabela 4: Distance, Top 20, Committed Capital, sem custos,
# Jul/1991–Dez/2015, 6.173 observações diárias, S&P 500.
REF_ORIENTADOR <- c(
  "Mean Return (% a.a.)" = 3.600, "Annualized STD (%)" = 5.000,
  "Sharpe Ratio" = 0.703, "Sortino Ratio" = 1.233, "t-stat (Newey-West)" = 3.636,
  "% de retornos negativos" = 47.58, "Skewness" = 0.343, "Kurtosis" = 10.12,
  "Mínimo diário (%)" = -2.800, "Máximo diário (%)" = 2.900,
  "MDD1 (%)" = 3.950, "MDD2 (%)" = 11.73, "Observações" = 6173)
# Gatev et al. (2006), Tabela 1 Painel A, Top 20, série MENSAL, fully invested.
REF_GATEV <- c(
  "Média mensal" = 0.01436, "Desvio-padrão mensal" = 0.01688,
  "t-stat (Newey-West)" = 11.56, "Mediana mensal" = 0.01235,
  "Skewness" = 1.39, "Kurtosis" = 10.54,
  "Mínimo mensal" = -0.06629, "Máximo mensal" = 0.13295,
  "% de meses negativos" = 15.0, "Observações" = 474)
GATEV_CC_MEDIA <- 0.00805   # committed capital; Gatev não publica o desvio da série CC
# Rad et al. (2016), Tabela 3 Seção 2 Painel B (committed capital, antes de custos).
REF_RAD_DIST <- c(
  "Média mensal" = 0.0068, "Desvio-padrão mensal" = 0.0102,
  "t-stat (Newey-West)" = 7.0284, "Sharpe MENSAL" = 0.6729,
  "Skewness" = 0.8152, "Kurtosis" = 14.6456)
REF_RAD_COINT <- c(
  "Média mensal" = 0.0068, "Desvio-padrão mensal" = 0.0097,
  "t-stat (Newey-West)" = 7.0365, "Sharpe MENSAL" = 0.6969,
  "Skewness" = 1.3934, "Kurtosis" = 10.8547)


# ── Estatísticas auxiliares ──────────────────────────────────────────────────────────
t_newey_west <- function(x, lags = 6) {
  # t-statistic da média com erro-padrão de Newey-West (Bartlett).
  x <- x[!is.na(x)]
  n <- length(x)
  e <- x - mean(x)
  s2 <- sum(e * e) / n
  for (L in seq_len(lags))
    s2 <- s2 + 2 * (1 - L / (lags + 1)) * (sum(e[(L + 1):n] * e[1:(n - L)]) / n)
  mean(x) / sqrt(s2 / n)
}

downside_deviation <- function(x, mar = 0) {
  # Raiz da média de min(r − MAR, 0)², sobre TODAS as observações.
  sqrt(mean(pmin(x - mar, 0)^2))
}

mdd_janela <- function(r, dias) {
  # Maior queda percentual entre dois pregões separados por no máximo `dias`.
  # dias = 1 → pior retorno de um dia; dias = 126 → pior drawdown em seis meses.
  eq <- cumprod(1 + r)
  topo <- eq
  for (k in seq_len(dias)) topo <- pmax(topo, c(rep(-Inf, k), eq[seq_len(length(eq) - k)]))
  min(eq / topo - 1)
}

para_mensal <- function(datas, r) {
  # Compõe a série diária dentro de cada mês (é o que Gatev faz).
  m <- retorno_composto(r, format(datas, "%Y-%m"))
  stats::setNames(m$retorno, m$grupo)
}


# ── Os dois blocos ───────────────────────────────────────────────────────────────────
metricas_diarias <- function(r) {
  # Convenção do ORIENTADOR (Tabela 4).
  eq <- cumprod(1 + r)
  c("Mean Return (% a.a.)"    = mean(r) * DIAS_ANO * 100,
    "Annualized STD (%)"      = sd(r) * sqrt(DIAS_ANO) * 100,
    "Sharpe Ratio"            = mean(r) / sd(r) * sqrt(DIAS_ANO),
    "Sortino Ratio"           = mean(r) / downside_deviation(r) * sqrt(DIAS_ANO),
    "t-stat (Newey-West)"     = t_newey_west(r, 6),
    "% de retornos negativos" = mean(r < 0) * 100,
    "Skewness"                = assimetria(r),
    "Kurtosis"                = curtose_excedente(r) + 3,
    "Mínimo diário (%)"       = min(r) * 100,
    "Máximo diário (%)"       = max(r) * 100,
    "MDD1 (%)"                = -mdd_janela(r, 2) * 100,
    "MDD2 (%)"                = -mdd_janela(r, 126) * 100,
    "Observações"             = length(r),
    # fora da Tabela 4, mas úteis:
    "Retorno acumulado (%)"   = (eq[length(eq)] - 1) * 100,
    "CAGR (% a.a.)"           = (eq[length(eq)]^(DIAS_ANO / length(r)) - 1) * 100,
    "Drawdown máximo (%)"     = -min((eq - cummax(eq)) / cummax(eq)) * 100)
}

metricas_mensais <- function(datas, r) {
  # Convenção de GATEV e RAD. Série diária composta dentro do mês.
  m <- para_mensal(datas, r)
  c("Média mensal"         = mean(m),
    "Desvio-padrão mensal" = sd(m),
    "Sharpe MENSAL"        = mean(m) / sd(m),
    "t-stat (Newey-West)"  = t_newey_west(m, 6),
    "Mediana mensal"       = stats::median(m),
    "Skewness"             = assimetria(m),
    "Kurtosis"             = curtose_excedente(m) + 3,
    "Mínimo mensal"        = min(m),
    "Máximo mensal"        = max(m),
    "% de meses negativos" = mean(m < 0) * 100,
    "Observações"          = length(m),
    # pontes:
    "Média × 12 (% a.a.)"  = mean(m) * MESES_ANO * 100,
    "Sharpe × √12"         = mean(m) / sd(m) * sqrt(MESES_ANO))
}


# ── Impressão ────────────────────────────────────────────────────────────────────────
.tab <- function(titulo, nosso, ref, ordem, rotulo_ref, digitos = 3) {
  f <- function(v) drt(if (is.na(v)) "—" else sprintf(paste0("%.", digitos, "f"), v), 14)
  cat(strrep("=", 74), "\n", titulo, "\n", strrep("=", 74), "\n", sep = "")
  cat(esq("", 26), drt(rotulo_ref, 14), drt("nosso", 14), drt("diferença", 14), "\n", sep = "")
  cat(strrep("-", 74), "\n", sep = "")
  for (k in ordem) {
    n <- if (k %in% names(nosso)) nosso[[k]] else NA
    r <- if (k %in% names(ref)) ref[[k]] else NA
    cat(esq(k, 26), f(r), f(n), f(n - r), "\n", sep = "")
  }
}

relatorio <- function(datas, r, mostrar_gatev_rad = TRUE) {
  d  <- metricas_diarias(r)
  mm <- metricas_mensais(datas, r)

  .tab(paste0("BLOCO A — convenção do ORIENTADOR (série diária anualizada)\n",
              "Alvo: Tabela 4, Distance, Top 20, Committed Capital, sem custos"),
       d, REF_ORIENTADOR,
       c("Mean Return (% a.a.)", "Annualized STD (%)", "Sharpe Ratio", "Sortino Ratio",
         "t-stat (Newey-West)", "% de retornos negativos", "Skewness", "Kurtosis",
         "Mínimo diário (%)", "Máximo diário (%)", "MDD1 (%)", "MDD2 (%)", "Observações"),
       "artigo")
  cat("\n  Extras (não estão na Tabela 4):\n")
  for (k in c("Retorno acumulado (%)", "CAGR (% a.a.)", "Drawdown máximo (%)"))
    cat("    ", esq(k, 26), sprintf("%12.3f", d[[k]]), "\n", sep = "")
  cat("\n")

  if (!mostrar_gatev_rad) return(invisible(list(diario = d, mensal = mm)))

  cat(strrep("=", 74), "\nBLOCO B — convenção de GATEV (2006) e RAD et al. (2016): série MENSAL\n",
      strrep("=", 74), "\n", sep = "")
  cat("  Nossa série mensal (committed capital, composta dentro do mês):\n")
  for (k in c("Média mensal", "Desvio-padrão mensal", "Sharpe MENSAL", "t-stat (Newey-West)",
              "Mediana mensal", "Skewness", "Kurtosis", "Mínimo mensal", "Máximo mensal",
              "% de meses negativos", "Observações"))
    cat("    ", esq(k, 26), sprintf("%12.5f", mm[[k]]), "\n", sep = "")
  cat("\n  ── Gatev (2006), Tab.1 Painel A, Top 20 · CRSP 1963–2002, 474 meses ──\n")
  cat(sprintf("    committed capital, média mensal : %.5f  (= %.2f%% a.a.)\n",
              GATEV_CC_MEDIA, GATEV_CC_MEDIA * 12 * 100))
  cat(sprintf("    NOSSO committed capital         : %.5f  (= %.2f%% a.a.)\n",
              mm[["Média mensal"]], mm[["Média × 12 (% a.a.)"]]))
  cat("    ⚠ é a ÚNICA estatística de committed capital que Gatev publica.\n")
  cat("      O resto da Tabela 1 dele é da série FULLY INVESTED, que não se\n")
  cat("      compara com a nossa — para isso, rodar com COMMITTED_CAPITAL = FALSE:\n")
  cat(sprintf("        fully invested Top 20: média %.5f · sd %.5f · skew %.2f · curt %.2f · %.0f%% de meses negativos\n\n",
              REF_GATEV[["Média mensal"]], REF_GATEV[["Desvio-padrão mensal"]],
              REF_GATEV[["Skewness"]], REF_GATEV[["Kurtosis"]], REF_GATEV[["% de meses negativos"]]))
  .tab(paste0("Rad et al. (2016) Tab.3 Seção 2 Painel B — committed capital, antes de custos\n",
              "CRSP 1962–2014, formação 12m / negociação 6m"),
       mm, REF_RAD_DIST,
       c("Média mensal", "Desvio-padrão mensal", "Sharpe MENSAL", "t-stat (Newey-West)",
         "Skewness", "Kurtosis"),
       "Rad DM", digitos = 4)
  cat(sprintf("\n  Rad, cointegração (para o outro método do TCC): média %.4f · sd %.4f · Sharpe mensal %.4f\n\n",
              REF_RAD_COINT[["Média mensal"]], REF_RAD_COINT[["Desvio-padrão mensal"]],
              REF_RAD_COINT[["Sharpe MENSAL"]]))
  cat("  ⚠ Gatev e Rad iniciam uma carteira por MÊS e tiram a média das 6 sobrepostas.\n")
  cat("    Nosso PASSO_MESES = 6 usa semestres NÃO sobrepostos, como o orientador.\n")
  cat("    Para comparar com eles de verdade, rodar a formação com PASSO_MESES = 1.\n")
  cat("    As amostras também diferem: eles usam a CRSP inteira (inclui small caps),\n")
  cat("    nós usamos o S&P 500. Diferença de nível é esperada.\n")
  invisible(list(diario = d, mensal = mm))
}
