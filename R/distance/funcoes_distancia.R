# -*- coding: utf-8 -*-
# Simulação de um par no método da distância (Gatev et al., 2006) — tradução de
# simular_par() de new_aproach/src/distance/pairs_trading.ipynb.
#
# Fica num arquivo próprio porque o script da distância dinâmica a usa no autoteste
# "o dinâmico neutralizado reproduz o estático".

simular_par_dist <- function(precos_form, precos_neg, mu, sigma,
                             delta = DELTA, stop = STOP,
                             fecha_no_cruzamento = FECHA_NO_CRUZAMENTO,
                             limiar_fechamento = LIMIAR_FECHAMENTO,
                             usar_media_spread = USAR_MEDIA_SPREAD) {
  # precos_form : matriz (T × 2) com os preços da formação [ativo1, ativo2]
  # precos_neg  : matriz (τ × 2) com os preços da negociação
  # mu, sigma   : média e desvio do spread na formação
  #
  # Retorna data.frame com z, position, position_lag, peso_long, peso_short,
  # retorno_diario, dev_preco — ou NULL se a simulação não for possível.
  if (sigma == 0) return(NULL)

  # Normaliza a negociação a partir do início da FORMAÇÃO
  P0    <- precos_form[1, ]
  Q_neg <- sweep(precos_neg, 2, P0, "/")
  q1 <- Q_neg[, 1]; q2 <- Q_neg[, 2]

  # Desvio de preço na abertura, como a Tabela 7 do artigo define:
  # "the price difference divided by the average of the prices"
  dev_preco <- abs(q1 - q2) / ((q1 + q2) / 2)

  # Z-score com parâmetros fixos da formação.
  mu_ef <- if (usar_media_spread) mu else 0
  z <- (q1 - q2 - mu_ef) / sigma

  # Nível de z do ALVO de fechamento:
  #   fecha_no_cruzamento = TRUE  → alvo é spread = 0
  #   fecha_no_cruzamento = FALSE → alvo é spread = mu
  z_alvo <- ((if (fecha_no_cruzamento) 0 else mu) - mu_ef) / sigma
  z_fecha_long  <- z_alvo - limiar_fechamento
  z_fecha_short <- z_alvo + limiar_fechamento

  # Posições dia a dia (sinal — sem lag)
  n <- length(z)
  positions <- numeric(n)
  pos <- 0
  for (t in seq_len(n)) {
    zt <- z[t]
    if (pos == 0) {
      if (zt > delta) pos <- -1          # vende a1, compra a2
      else if (zt < -delta) pos <- +1    # compra a1, vende a2
    } else {
      if (!is.null(stop) && abs(zt) > stop) pos <- 0                 # stop-loss
      else if (pos == +1 && zt >= z_fecha_long) pos <- 0             # fecha a longa
      else if (pos == -1 && zt <= z_fecha_short) pos <- 0            # fecha a curta
    }
    positions[t] <- pos
  }

  r1 <- retornos_simples(precos_neg[, 1])
  r2 <- retornos_simples(precos_neg[, 2])

  # A decisão ao fechamento de t é executada a partir de t+1.
  positions_lag <- defasar(positions)

  # P&L marcado a mercado, com pesos de buy-and-hold (Gatev et al., §2.3, eq. 2–3):
  # abre-se $1 comprado e $1 vendido e NÃO se rebalanceia. Os pesos voltam a 1 a cada
  # nova abertura.
  retorno <- numeric(n); peso_long <- numeric(n); peso_shrt <- numeric(n)
  wL <- 1; wS <- 1
  for (t in seq_len(n)) {
    p <- positions_lag[t]
    if (p == 0) { wL <- 1; wS <- 1; next }   # fora do mercado: reinicia
    # p = +1 → long a1 / short a2 ; p = -1 → long a2 / short a1
    if (p > 0) { rL <- r1[t]; rS <- r2[t] } else { rL <- r2[t]; rS <- r1[t] }
    peso_long[t] <- wL; peso_shrt[t] <- wS
    retorno[t] <- wL * rL - wS * rS
    wL <- wL * (1 + rL)
    wS <- wS * (1 + rS)
  }

  data.frame(z = z, position = positions, position_lag = positions_lag,
             peso_long = peso_long, peso_short = peso_shrt,
             retorno_diario = retorno, dev_preco = dev_preco)
}
