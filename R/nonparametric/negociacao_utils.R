# -*- coding: utf-8 -*-
# Negociação do método NP — tradução das funções de
# new_aproach/src/nonparametric/pairs_trading_np.ipynb (simular_par_np e o laço sobre os pares).
# Fica fora do script de negociação porque o diagnóstico de Wang & Phillips também negocia
# (os pares da linear, na seção 3).
# Requer funcoes/comum.R, funcoes/adf.R e nonparametric/kernel_np.R.


# ── Negociação: simulação de um par ──────────────────────────────────────────────────
simular_par_np <- function(precos_form, precos_neg, h, mu, sigma, p) {
  # precos_form, precos_neg : matrizes [dep, indep] sem NA
  # h                       : bandwidth da formação (Inf → reta)
  # mu, sigma               : média e desvio do erro um passo à frente da formação
  # p : parâmetros — delta, beta_min, beta_max, dimensionamento, l_suporte, massa_min,
  #     modo_saida, mu_sigma_modo, janela_mu_sigma, t_min_resid
  # Retorna list(diario = data.frame, eventos = data.frame com dia (índice), z, massa_antiga,
  # beta, motivo).
  if (!p$modo_saida %in% c("tangente", "curva", "curva_rebalanceada"))
    stop("MODO_SAIDA desconhecido: ", p$modo_saida)
  P0 <- precos_form[1, ]
  y_f <- precos_form[, 1] / P0[1]; x_f <- precos_form[, 2] / P0[2]
  y_n <- precos_neg[, 1] / P0[1];  x_n <- precos_neg[, 2] / P0[2]
  T <- length(x_f); m <- length(x_n)
  x_all <- c(x_f, x_n); y_all <- c(y_f, y_n)

  # Monitoramento: curva até t−1, avaliada em x_t — todos os dias de uma vez
  mon <- monitoramento(x_f, y_f, x_n, y_n, h, p$l_suporte)
  g_mon <- mon$g; b_mon <- mon$b; massa <- mon$massa_antiga

  # μ e σ de cada dia
  if (p$mu_sigma_modo == "formacao") {
    mu_t <- rep(mu, m); sig_t <- rep(sigma, m)
  } else if (p$mu_sigma_modo %in% c("expandido", "movel")) {
    u_f <- residuos_unilaterais(x_f, y_f, h, 1, p$t_min_resid)
    pool <- c(u_f[is.finite(u_f)], y_n - g_mon)
    nf0 <- sum(is.finite(u_f))
    mu_t <- numeric(m); sig_t <- numeric(m)
    for (k in seq_len(m)) {
      v <- pool[seq_len(nf0 + k - 1)]                          # tudo até t−1
      if (p$mu_sigma_modo == "movel") v <- utils::tail(v, p$janela_mu_sigma)
      v <- v[is.finite(v)]
      if (length(v) > 10) { mu_t[k] <- mean(v); sig_t[k] <- desvio_pop(v) }
      else { mu_t[k] <- mu; sig_t[k] <- sigma }
    }
  } else stop("MU_SIGMA_MODO desconhecido: ", p$mu_sigma_modo)
  z_mon <- (y_n - g_mon - mu_t) / sig_t

  positions <- numeric(m); beta_dia <- rep(NA_real_, m); z_trade <- rep(NA_real_, m)
  ev_t <- integer(0); ev_motivo <- character(0)

  t <- 1L
  while (t <= m) {
    zt <- z_mon[t]
    if (!(is.finite(zt) && abs(zt) > p$delta)) { t <- t + 1L; next }

    motivo <- if (massa[t] < p$massa_min) "suporte"
      else if (!is.finite(b_mon[t]) || b_mon[t] < p$beta_min ||
               (!is.null(p$beta_max) && b_mon[t] > p$beta_max)) "beta"
      else "aprovado"
    ev_t <- c(ev_t, t); ev_motivo <- c(ev_motivo, motivo)
    if (motivo != "aprovado") { t <- t + 1L; next }

    # Abertura: congela a referência (amostra até t−1)
    pos <- if (zt > 0) +1 else -1                    # +1: Q_dep caro → vende o spread
    beta_e <- b_mon[t]
    idx <- t:m
    if (p$modo_saida == "tangente") {
      # reta tangente à curva em x_e: o spread é o valor da carteira com β_e fixo
      ref <- g_mon[t] + beta_e * (x_n[idx] - x_n[t])
      betas <- rep(beta_e, length(idx))
    } else {
      n <- T + t - 1
      cc <- loclin(x_n[idx], x_all[seq_len(n)], y_all[seq_len(n)], h)
      ref <- cc$a
      if (p$modo_saida == "curva") {
        betas <- rep(beta_e, length(idx))
      } else {
        # 'curva_rebalanceada': β = inclinação da curva congelada no dia; se degenerar,
        # mantém o último β válido (ou β_e)
        betas <- ifelse(is.finite(cc$b) & cc$b >= p$beta_min, cc$b, NA)
        for (j in seq_along(betas)) if (is.na(betas[j])) betas[j] <- if (j > 1) betas[j - 1] else NA
        betas[is.na(betas)] <- beta_e
      }
    }
    z_c <- (y_n[idx] - ref - mu_t[t]) / sig_t[t]       # μ e σ congelados na abertura

    k <- 1L
    while (t + k - 1 <= m) {
      tk <- t + k - 1
      if (k > 1 && ((pos == +1 && z_c[k] <= 0) || (pos == -1 && z_c[k] >= 0))) {
        z_trade[tk] <- z_c[k]
        break                                          # fecha no dia tk (position = 0)
      }
      positions[tk] <- pos; beta_dia[tk] <- betas[k]; z_trade[tk] <- z_c[k]
      k <- k + 1L
    }
    t <- t + k                                         # no dia do fechamento não reabre
  }

  # Retorno: execução em t+1
  pos_lag <- defasar(positions)
  beta_lag <- c(NA, beta_dia[-m])
  d_dep <- c(0, diff(y_n)); d_indep <- c(0, diff(x_n))
  ativo <- pos_lag != 0
  retorno <- numeric(m)
  b <- beta_lag[ativo]
  escala <- switch(p$dimensionamento,
                   rad = ifelse(pos_lag[ativo] > 0, 1 / b, 1),
                   slides = rep(1, length(b)),
                   maior_perna = 1 / pmax(1, b),
                   stop("DIMENSIONAMENTO desconhecido: ", p$dimensionamento))
  retorno[ativo] <- -pos_lag[ativo] * escala * (d_dep[ativo] - b * d_indep[ativo])

  list(diario = data.frame(spread_mon = y_n - g_mon, z = z_mon, z_trade = z_trade,
                           massa_antiga = massa, position = positions, position_lag = pos_lag,
                           beta = beta_dia, retorno_diario = retorno),
       eventos = data.frame(t = ev_t, z = z_mon[ev_t], massa_antiga = massa[ev_t],
                            beta = b_mon[ev_t], motivo = ev_motivo, stringsAsFactors = FALSE))
}


# ── Negociação: todos os pares de um arquivo ─────────────────────────────────────────
negociar_np <- function(pares, base, p, committed_capital = TRUE, sigma_min = 0.01,
                        max_retorno_dia = 0.90, verboso = TRUE) {
  # Filtros de exclusão iguais aos da linear: sigma < sigma_min, ticker ausente, sem dados,
  # max_retorno_dia. O β não é filtrado aqui — o veto de β age sinal a sinal.
  # Retorna list(resultados, eventos, mensal, portfolio, skip).
  resultados <- vector("list", nrow(pares)); eventos <- vector("list", nrow(pares))
  mensal <- vector("list", nrow(pares))
  acc <- novo_acumulador(base)
  n_skip <- c(sigma = 0, ticker = 0, dados = 0, outlier = 0)

  for (i in seq_len(nrow(pares))) {
    par <- pares[i, ]
    o <- orientar(par$ativo1, par$ativo2, par$direcao)
    dep <- o[["dep"]]; indep <- o[["indep"]]
    if (par$spread_desvio < sigma_min) { n_skip["sigma"] <- n_skip["sigma"] + 1; next }
    if (!(dep %in% colnames(base$P)) || !(indep %in% colnames(base$P))) {
      n_skip["ticker"] <- n_skip["ticker"] + 1; next
    }
    rf_ <- recortar_par(base, dep, indep, par$formacao_inicio, par$formacao_fim)
    rn_ <- recortar_par(base, dep, indep, par$negociacao_inicio, par$negociacao_fim)
    if (nrow(rf_$P) == 0 || nrow(rn_$P) == 0) { n_skip["dados"] <- n_skip["dados"] + 1; next }
    if (!is.null(max_retorno_dia) && maior_retorno_dia(rn_$P) > max_retorno_dia) {
      n_skip["outlier"] <- n_skip["outlier"] + 1; next
    }

    sim <- simular_par_np(rf_$P, rn_$P, as.numeric(par$h), par$spread_media, par$spread_desvio, p)
    res <- sim$diario; ev <- sim$eventos
    tr <- contar_trades(res$position)
    resultados[[i]] <- data.frame(
      janela = par$janela, neg_inicio = par$negociacao_inicio, neg_fim = par$negociacao_fim,
      ativo1 = par$ativo1, ativo2 = par$ativo2, direcao = par$direcao, rank = par$rank,
      h_rel = par$h_rel, h_linear = par$h_linear, sigma = par$spread_desvio,
      n_sinais = nrow(ev), n_veto_suporte = sum(ev$motivo == "suporte"),
      n_veto_beta = sum(ev$motivo == "beta"),
      n_trades = tr[["abertos"]], n_fechados = tr[["fechados"]], n_forcados = tr[["forcados"]],
      beta_medio = if (tr[["abertos"]] > 0) mean(res$beta, na.rm = TRUE) else NA,
      retorno_total = sum(res$retorno_diario), stringsAsFactors = FALSE)
    if (nrow(ev))
      eventos[[i]] <- data.frame(janela = par$janela, ativo1 = par$ativo1, ativo2 = par$ativo2,
                                 h_linear = par$h_linear, dia = base$datas[rn_$linhas[ev$t]],
                                 z = ev$z, massa_antiga = ev$massa_antiga, beta = ev$beta,
                                 motivo = ev$motivo, stringsAsFactors = FALSE)
    mensal[[i]] <- mensal_do_par(base$datas[rn_$linhas], res$retorno_diario, res$position_lag,
                                 par$janela, par$ativo1, par$ativo2)
    acc <- acumular_par(acc, rn_, res$retorno_diario, res$position_lag, committed_capital)
    if (verboso && i %% 1000 == 0) cat(sprintf("  %6s / %s pares\n", milhar(i), milhar(nrow(pares))))
  }
  list(resultados = do.call(rbind, resultados), eventos = do.call(rbind, eventos),
       mensal = do.call(rbind, mensal), portfolio = serie_portfolio(acc, base), skip = n_skip)
}
