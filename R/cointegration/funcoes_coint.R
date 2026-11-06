# -*- coding: utf-8 -*-
# Teste de cointegração de Engle-Granger (ADF ou CRDW) e simulação de um par no método da
# cointegração (Rad et al., 2016) — tradução das funções de
# new_aproach/src/cointegration/pairs_formation_coint.ipynb e pairs_trading_coint.ipynb.
# Requer funcoes/comum.R e funcoes/adf.R.

durbin_watson <- function(e) sum(diff(e)^2) / sum(e^2)

crit_crdw <- function(T, crit_ref_t100 = CRDW_CRIT_REF_T100) {
  # Valor crítico do CRDW a 5%, reescalado para o tamanho de amostra T:
  # crit(T) = 0.386 × 100 / T  (T = 252 → ≈0.153; T = 100 → 0.386).
  crit_ref_t100 * 100 / T
}

estatistica_residuo <- function(residuo, metodo, autolag = AUTOLAG_ADF,
                                crit_adf = CRIT_COINT_5PCT) {
  # ADF  — regression = "n": o resíduo do OLS com intercepto já tem média zero.
  #        Passa se stat < crit_adf (MacKinnon 5%, −3.34).
  # CRDW — DW ≈ 2(1 − ρ). Passa se stat > crit_crdw(T).
  if (metodo == "ADF") {
    stat <- adf_estatistica(residuo, autolag = autolag, regression = "n")
    passou <- stat < crit_adf
  } else if (metodo == "CRDW") {
    stat <- durbin_watson(residuo)
    passou <- stat > crit_crdw(length(residuo))
  } else {
    stop("Método de cointegração desconhecido: ", metodo, " (use 'ADF' ou 'CRDW')")
  }
  list(stat = stat, passou = passou)
}

testar_cointegracao <- function(q_a, q_b, metodo = METODO_COINT) {
  # Engle-Granger em dois passos, sempre BILATERAL: as duas direções da regressão são
  # estimadas e o par só é aprovado se AMBAS rejeitarem a raiz unitária. Salvam-se os
  # parâmetros da direção mais fortemente estacionária.
  #   'B~A' → y = Q_b, x = Q_a ;  'A~B' → y = Q_a, x = Q_b
  falha <- list(cointegrado = FALSE, beta = NA, alpha = NA, spread_media = NA,
                spread_desvio = NA, stat = NA, direcao = NA)
  if (desvio_pop(q_a) < 1e-10 || desvio_pop(q_b) < 1e-10) return(falha)

  d1 <- ols_residuo(q_b, q_a); e1 <- estatistica_residuo(d1$resid, metodo)
  d2 <- ols_residuo(q_a, q_b); e2 <- estatistica_residuo(d2$resid, metodo)
  if (!(e1$passou && e2$passou)) return(falha)

  escolhe_1 <- if (metodo == "ADF") e1$stat <= e2$stat else e1$stat >= e2$stat
  d <- if (escolhe_1) d1 else d2
  list(cointegrado = TRUE, beta = d$beta, alpha = d$alpha,
       spread_media = mean(d$resid), spread_desvio = desvio_pop(d$resid),
       stat = if (escolhe_1) e1$stat else e2$stat,
       direcao = if (escolhe_1) "B~A" else "A~B")
}


# ── Simulação de um par (versão estática) ────────────────────────────────────────────
simular_par_coint <- function(precos_form, precos_neg, alpha, beta, mu, sigma,
                              direcao = "B~A", delta = DELTA, stop = STOP) {
  # Convenção de sinal (position é a direção do trade sobre o spread):
  #   +1 → z > +δ: LONG $1 em Q_indep, SHORT $1/β em Q_dep → r = −Δspread/β
  #   −1 → z < −δ: LONG $1 em Q_dep,  SHORT $β  em Q_indep → r = +Δspread
  # O denominador do retorno é o $1 da perna comprada (Rad et al., §5.1).
  if (sigma == 0 || !is.finite(beta) || beta <= 0) return(NULL)

  o <- orientar(colnames(precos_form)[1], colnames(precos_form)[2], direcao)

  # Normaliza a negociação a partir do início da formação (mesma base do OLS)
  P0    <- precos_form[1, ]
  Q_neg <- sweep(precos_neg, 2, P0, "/")

  spread <- Q_neg[, o[["dep"]]] - alpha - beta * Q_neg[, o[["indep"]]]
  z <- (spread - mu) / sigma

  n <- length(z)
  positions <- numeric(n)
  pos <- 0
  for (t in seq_len(n)) {
    zt <- z[t]
    if (pos == 0) {
      if (zt > delta) pos <- +1          # spread alto → aposta na queda
      else if (zt < -delta) pos <- -1    # spread baixo → aposta na alta
    } else {
      if (!is.null(stop) && abs(zt) > stop) pos <- 0
      else if (pos == +1 && zt <= 0) pos <- 0
      else if (pos == -1 && zt >= 0) pos <- 0
    }
    positions[t] <- pos
  }
  positions_lag <- defasar(positions)

  d_spread <- c(0, diff(spread))
  escala   <- ifelse(positions_lag > 0, 1 / beta, 1)
  retorno  <- -positions_lag * escala * d_spread

  data.frame(spread = spread, z = z, position = positions,
             position_lag = positions_lag, retorno_diario = retorno)
}
