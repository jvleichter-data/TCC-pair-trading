# -*- coding: utf-8 -*-
# ══════════════════════════════════════════════════════════════════════════════════════
#  Negociação de Pares — Cointegração DINÂMICA (re-estimação no sinal)
#  Tradução de new_aproach/src/cointegration/pairs_trading_coint_dinamico.ipynb
# ══════════════════════════════════════════════════════════════════════════════════════
#
# Variante de cointegration/pairs_trading_coint.R. A formação é IDÊNTICA (mesmo
# pares_formados_coint.csv); o que muda é o que acontece no instante do sinal.
#
# No dia em que o z-score cruza ±δ, o par é RE-TESTADO com toda a informação disponível
# até aquele dia — a formação inteira mais o trecho já decorrido da negociação. Se a
# cointegração não sobreviver, o trade não é aberto. Se sobreviver, o trade é aberto com
# os parâmetros RE-ESTIMADOS (β, α, μ, σ), não com os da formação.
#
#   Quando há sinal            → z de monitoramento, com β, μ, σ da FORMAÇÃO (fixos)
#   Se o trade abre            → re-teste de cointegração (+ z reconfirmado, opcional)
#   Como o trade corre e fecha → spread redefinido pelos parâmetros re-estimados
#
# A direção do OLS (dependente/independente) é a da formação o período todo. O P&L segue a
# convenção do estático, com o β do trade vigente; Δspread é acumulado DENTRO do trade,
# nunca atravessando uma redefinição do spread.
# Sem look-ahead: a re-estimação em t usa dados até t inclusive; P&L a partir de t+1.
#
# ⏱️ Cada sinal dispara um OLS + ADF (dobrado com BILATERAL_RETESTE = TRUE).
# Rodar com o diretório de trabalho na pasta R/ (depois de pairs_formation_coint.R e pairs_trading_coint.R).

source("funcoes/comum.R", local = TRUE)
source("funcoes/adf.R", local = TRUE)
source("cointegration/funcoes_coint.R", local = TRUE)
usar_pastas("cointegration")

# === Parâmetros da estratégia (idênticos ao estático) ===
DELTA     <- 2.0
STOP      <- NULL
SIGMA_MIN <- 0.01
BETA_MIN  <- 0.05   # aplicado ao β da formação e ao β re-estimado no sinal

MAX_RETORNO_DIA   <- 0.90
COMMITTED_CAPITAL <- TRUE
N_PARES_NOMINADOS <- 20

PERIODO_INICIO <- NULL
PERIODO_FIM    <- "2015-12"

# ══════════════════════════════════════════════════════════════════════════════════════
#  RE-ESTIMAÇÃO DINÂMICA
# ══════════════════════════════════════════════════════════════════════════════════════
# Amostra da re-estimação, sempre terminando no dia do sinal:
#   NULL → EXPANDING desde o 1º dia da FORMAÇÃO (T ≈ 252 → ≈ 378)
#   int  → ROLLING dos últimos N pregões (ex.: 252)
JANELA_REESTIMACAO <- NULL

# Quando re-testar, estando fora do mercado:
#   'cruzamento' → só no dia em que |z| atravessa δ vindo de dentro da banda
#   'diario'     → todo dia em que |z| > δ (bem mais lento)
RETESTE_MODO <- "cruzamento"

AUTOLAG_ADF <- "AIC"            # defasagens do ADF: "AIC" ou "BIC"
METODO_COINT_RETESTE <- "ADF"   # "ADF" (MacKinnon) ou "CRDW" (Engle-Granger 1987)
BILATERAL_RETESTE    <- TRUE    # TRUE → as duas direções precisam passar (como na formação)
                                # A direção do trade é SEMPRE a da formação.

CRIT_COINT_5PCT    <- -3.34     # ADF: MacKinnon 5%
CRDW_CRIT_REF_T100 <- 0.386     # CRDW: crítico para T ≈ 100, reescalado por 100/T

# Dupla confirmação: além de passar no teste, exige |z| > DELTA com os parâmetros NOVOS.
EXIGE_Z_REESTIMADO <- FALSE


# ── 1. Carregando os dados ────────────────────────────────────────────────────────────
pares_raw <- ler_pares(file.path(pasta_saida("cointegration", "pares"), "pares_formados_coint.csv"))
base      <- carregar_base()
pares     <- filtrar_periodo(pares_raw, PERIODO_INICIO, PERIODO_FIM)
cat(sprintf("Teste na formação : %s | bilateral (ambas as direções)\n", pares_raw$metodo[1]))
imprimir_cabecalho_pares(pares_raw, pares, base, PERIODO_INICIO, PERIODO_FIM)


# ── 2. Funções ────────────────────────────────────────────────────────────────────────
reestimar_par <- function(q_dep, q_ind, metodo = METODO_COINT_RETESTE, bilateral = BILATERAL_RETESTE) {
  # Re-estima a relação de cointegração sobre a amostra dada. A orientação é IMPOSTA pelo
  # chamador (é a da formação). bilateral = TRUE exige que a direção inversa também passe.
  falha <- list(cointegrado = FALSE, alpha = NA, beta = NA, mu = NA, sigma = NA, stat = NA)
  if (length(q_dep) < 30 || desvio_pop(q_dep) < 1e-10 || desvio_pop(q_ind) < 1e-10) return(falha)

  d <- ols_residuo(q_dep, q_ind)
  e <- estatistica_residuo(d$resid, metodo)
  passou <- e$passou
  if (passou && bilateral) {
    inv <- ols_residuo(q_ind, q_dep)
    passou <- passou && estatistica_residuo(inv$resid, metodo)$passou
  }
  if (!passou) { falha$stat <- e$stat; return(falha) }
  list(cointegrado = TRUE, alpha = d$alpha, beta = d$beta, mu = mean(d$resid),
       sigma = desvio_pop(d$resid), stat = e$stat)
}

simular_par_coint_dinamico <- function(precos_form, precos_neg, alpha, beta, mu, sigma,
                                       direcao = "B~A", delta = DELTA, stop = STOP,
                                       janela = JANELA_REESTIMACAO, modo = RETESTE_MODO,
                                       metodo = METODO_COINT_RETESTE, bilateral = BILATERAL_RETESTE,
                                       exige_z = EXIGE_Z_REESTIMADO) {
  # Convenção de sinal (idêntica ao estático):
  #   +1 → spread alto: LONG $1 em Q_indep, SHORT $1/β em Q_dep
  #   −1 → spread baixo: LONG $1 em Q_dep,  SHORT $β  em Q_indep
  # Retorna list(df, info) ou NULL se o par não puder ser simulado.
  if (sigma == 0 || !is.finite(beta) || beta <= 0) return(NULL)

  o <- orientar(colnames(precos_form)[1], colnames(precos_form)[2], direcao)

  # Série contínua formação + negociação, normalizada pelo 1º preço da FORMAÇÃO
  T_form <- nrow(precos_form)
  Q_all <- sweep(rbind(precos_form, precos_neg), 2, precos_form[1, ], "/")
  q_dep <- Q_all[, o[["dep"]]]
  q_ind <- Q_all[, o[["indep"]]]
  g_neg <- T_form + seq_len(nrow(precos_neg))
  n <- length(g_neg)

  # z de MONITORAMENTO: parâmetros congelados da formação, idêntico ao estático
  z_mon <- ((q_dep[g_neg] - alpha - beta * q_ind[g_neg]) - mu) / sigma

  positions <- numeric(n); positions_lag <- numeric(n); retorno <- numeric(n)
  z_trade <- rep(NA_real_, n); beta_vig <- rep(NA_real_, n)
  pos <- 0; par_viv <- NULL; s_ant <- NA; z_hoje <- NA
  ev <- list(); n_sinais <- 0; n_aprov <- 0; n_rej_coint <- 0; n_rej_z <- 0; n_rej_beta <- 0
  betas_ab <- numeric(0)

  for (k in seq_len(n)) {
    g <- g_neg[k]
    positions_lag[k] <- pos

    # P&L do dia k: variação do spread na definição do trade vigente
    if (pos != 0) {
      s_hoje <- q_dep[g] - par_viv$alpha - par_viv$beta * q_ind[g]
      escala <- if (pos > 0) 1 / par_viv$beta else 1
      retorno[k] <- -pos * escala * (s_hoje - s_ant)
      z_hoje <- (s_hoje - par_viv$mu) / par_viv$sigma
      s_ant <- s_hoje
      z_trade[k] <- z_hoje; beta_vig[k] <- par_viv$beta
    }

    if (pos == 0) {
      acima <- abs(z_mon[k]) > delta
      gatilho <- if (modo == "cruzamento") acima && (k == 1 || abs(z_mon[k - 1]) <= delta) else acima

      if (gatilho) {
        n_sinais <- n_sinais + 1
        ini <- if (is.null(janela)) 1L else max(1L, g - janela + 1L)
        novo <- reestimar_par(q_dep[ini:g], q_ind[ini:g], metodo = metodo, bilateral = bilateral)

        z_novo <- NA
        if (!novo$cointegrado) {
          n_rej_coint <- n_rej_coint + 1; motivo <- "sem_cointegracao"
        } else if (!is.finite(novo$beta) || novo$beta < BETA_MIN || novo$sigma < SIGMA_MIN) {
          n_rej_beta <- n_rej_beta + 1; motivo <- "beta_ou_sigma"
        } else {
          s_novo <- q_dep[g] - novo$alpha - novo$beta * q_ind[g]
          z_novo <- (s_novo - novo$mu) / novo$sigma
          if (exige_z && abs(z_novo) <= delta) {
            n_rej_z <- n_rej_z + 1; motivo <- "z_reestimado_dentro_da_banda"
          } else {
            # Abre com os parâmetros NOVOS; a direção vem do z re-estimado.
            pos <- if (z_novo > 0) +1 else -1
            par_viv <- novo; s_ant <- s_novo
            z_trade[k] <- z_novo; beta_vig[k] <- novo$beta
            n_aprov <- n_aprov + 1; betas_ab <- c(betas_ab, novo$beta)
            motivo <- "aprovado"
          }
        }
        ev[[length(ev) + 1]] <- c(g = g, n_amostra = g - ini + 1, z_monitor = z_mon[k],
                                  z_novo = z_novo, stat_novo = novo$stat, beta_novo = novo$beta)
        attr(ev[[length(ev)]], "motivo") <- motivo
      }
    } else {
      # Posicionado: regras de saída com os parâmetros DO TRADE
      if ((!is.null(stop) && abs(z_hoje) > stop) ||
          (pos == +1 && z_hoje <= 0) || (pos == -1 && z_hoje >= 0)) {
        pos <- 0; par_viv <- NULL; s_ant <- NA
      }
    }
    positions[k] <- pos
  }

  eventos <- NULL
  if (length(ev)) {
    m <- do.call(rbind, ev)
    eventos <- data.frame(g = m[, "g"], motivo = vapply(ev, attr, character(1), "motivo"),
                          n_amostra = m[, "n_amostra"], z_monitor = m[, "z_monitor"],
                          z_novo = m[, "z_novo"], stat_novo = m[, "stat_novo"],
                          beta_novo = m[, "beta_novo"], stringsAsFactors = FALSE)
  }
  list(df = data.frame(z_monitor = z_mon, z_trade = z_trade, beta_vigente = beta_vig,
                       position = positions, position_lag = positions_lag, retorno_diario = retorno),
       info = list(n_sinais = n_sinais, n_aprovados = n_aprov, n_rej_coint = n_rej_coint,
                   n_rej_z = n_rej_z, n_rej_beta = n_rej_beta,
                   beta_medio = if (length(betas_ab)) mean(betas_ab) else NA, eventos = eventos))
}


# ── 3. Simulação completa ─────────────────────────────────────────────────────────────
# Os cinco filtros do estático valem antes da simulação; o filtro dinâmico age dentro
# dela, sinal a sinal.
t0 <- Sys.time()
cat(sprintf("\nRe-estimação: janela=%s | modo=%s | teste=%s%s | dupla confirmação=%s\n",
            if (is.null(JANELA_REESTIMACAO)) "expanding" else paste(JANELA_REESTIMACAO, "dias"),
            RETESTE_MODO, METODO_COINT_RETESTE, if (BILATERAL_RETESTE) " bilateral" else " unilateral",
            if (EXIGE_Z_REESTIMADO) "sim" else "não"))
cat(sprintf("Simulando %s pares...\n\n", milhar(nrow(pares))))

resultados_pares  <- vector("list", nrow(pares))
registros_mensais <- vector("list", nrow(pares))
eventos_log       <- vector("list", nrow(pares))
acc <- novo_acumulador(base)
n_skip <- c(sigma = 0, beta = 0, ticker = 0, dados = 0, outlier = 0)

for (i in seq_len(nrow(pares))) {
  par <- pares[i, ]
  a1 <- par$ativo1; a2 <- par$ativo2
  alpha <- par$alpha; beta <- par$beta
  mu <- par$spread_media; sigma <- par$spread_desvio; direcao <- par$direcao

  if (sigma < SIGMA_MIN) { n_skip["sigma"] <- n_skip["sigma"] + 1; next }
  if (!is.finite(beta) || beta < BETA_MIN) { n_skip["beta"] <- n_skip["beta"] + 1; next }
  if (!(a1 %in% colnames(base$P)) || !(a2 %in% colnames(base$P))) {
    n_skip["ticker"] <- n_skip["ticker"] + 1; next
  }
  rf_ <- recortar_par(base, a1, a2, par$formacao_inicio, par$formacao_fim)
  rn_ <- recortar_par(base, a1, a2, par$negociacao_inicio, par$negociacao_fim)
  if (nrow(rf_$P) == 0 || nrow(rn_$P) == 0) { n_skip["dados"] <- n_skip["dados"] + 1; next }
  if (!is.null(MAX_RETORNO_DIA) && maior_retorno_dia(rn_$P) > MAX_RETORNO_DIA) {
    n_skip["outlier"] <- n_skip["outlier"] + 1; next
  }

  sim <- simular_par_coint_dinamico(rf_$P, rn_$P, alpha, beta, mu, sigma, direcao = direcao)
  if (is.null(sim)) next
  res <- sim$df; info <- sim$info

  tr <- contar_trades(res$position)
  resultados_pares[[i]] <- data.frame(
    janela = par$janela, neg_inicio = par$negociacao_inicio, neg_fim = par$negociacao_fim,
    ativo1 = a1, ativo2 = a2, direcao = direcao, rank = par$rank, ssd = par$ssd,
    beta = beta, beta_medio = info$beta_medio, sigma = sigma, stat = par$stat,
    n_sinais = info$n_sinais, n_aprovados = info$n_aprovados, n_rej_coint = info$n_rej_coint,
    n_rej_z = info$n_rej_z, n_rej_beta = info$n_rej_beta,
    n_trades = tr[["abertos"]], n_fechados = tr[["fechados"]], n_forcados = tr[["forcados"]],
    retorno_total = sum(res$retorno_diario), stringsAsFactors = FALSE)

  if (!is.null(info$eventos)) {
    e <- info$eventos
    e$data <- base$datas[c(rf_$linhas, rn_$linhas)[e$g]]
    e$janela <- par$janela; e$ativo1 <- a1; e$ativo2 <- a2; e$rank <- par$rank
    eventos_log[[i]] <- e[, c("data", "motivo", "n_amostra", "z_monitor", "z_novo", "stat_novo",
                              "beta_novo", "janela", "ativo1", "ativo2", "rank")]
  }
  registros_mensais[[i]] <- mensal_do_par(base$datas[rn_$linhas], res$retorno_diario,
                                          res$position_lag, par$janela, a1, a2)
  acc <- acumular_par(acc, rn_, res$retorno_diario, res$position_lag, COMMITTED_CAPITAL)
}
resultados_df <- do.call(rbind, resultados_pares)
mensal_df     <- do.call(rbind, registros_mensais)
eventos_df    <- do.call(rbind, eventos_log)

cat(sprintf("Total de pares no arquivo  : %s\n", milhar(nrow(pares))))
cat(sprintf("  Pulados (sigma < %g) : %s\n", SIGMA_MIN, milhar(n_skip[["sigma"]])))
cat(sprintf("  Pulados (beta < %g)  : %s\n", BETA_MIN, milhar(n_skip[["beta"]])))
cat(sprintf("  Pulados (ticker ausente)  : %s\n", milhar(n_skip[["ticker"]])))
cat(sprintf("  Pulados (sem dados)       : %s\n", milhar(n_skip[["dados"]])))
cat(sprintf("  Pulados (spike positivo)  : %s\n", milhar(n_skip[["outlier"]])))
cat(sprintf("  Simulados com sucesso     : %s\n", milhar(nrow(resultados_df))))
cat(sprintf("\nTempo de execução          : %.0fs\n\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))


# ── 4. Diagnóstico da re-estimação ────────────────────────────────────────────────────
# O total de sinais NÃO é comparável um-a-um com os trades do estático: vetos devolvem o
# par ao monitoramento (mais sinais); trades mais longos engolem cruzamentos (menos sinais).
tot <- colSums(resultados_df[, c("n_sinais", "n_aprovados", "n_rej_coint", "n_rej_z", "n_rej_beta")])
cat(strrep("=", 64), "\n  FILTRO DINÂMICO — destino dos sinais\n", strrep("=", 64), "\n", sep = "")
cat(sprintf("Sinais gerados (z de monitoramento cruzou ±%.0f) : %s\n", DELTA, milhar(tot[["n_sinais"]])))
if (tot[["n_sinais"]] > 0) {
  linha <- function(rot, v) cat("  → ", esq(rot, 43), sprintf(": %s (%s)", milhar(v), pct(v / tot[["n_sinais"]], 1)), "\n", sep = "")
  linha("viraram trade", tot[["n_aprovados"]])
  linha("vetados: cointegração perdida", tot[["n_rej_coint"]])
  linha("vetados: |z| re-estimado dentro da banda", tot[["n_rej_z"]])
  linha("vetados: β ou σ degenerado", tot[["n_rej_beta"]])
}
cat(strrep("=", 64), "\n", sep = "")
mudos <- resultados_df$n_sinais > 0 & resultados_df$n_aprovados == 0
cat(sprintf("\nPares com sinal mas nenhum trade aprovado : %s (%s dos pares simulados)\n",
            milhar(sum(mudos)), pct(mean(mudos), 1)))
cat(sprintf("Pares sem nenhum sinal no período         : %s\n", milhar(sum(resultados_df$n_sinais == 0))))

cb <- resultados_df[!is.na(resultados_df$beta_medio), ]
if (nrow(cb)) {
  razao <- cb$beta_medio / cb$beta
  q <- stats::quantile(razao, c(.25, .75), names = FALSE)
  cat("\n=== β re-estimado ÷ β da formação (pares com ao menos 1 abertura) ===\n")
  cat(sprintf("Pares            : %s\nMediana da razão : %.4f\nQuartis          : %.4f — %.4f\nFora de ±10%%     : %s dos pares\n",
              milhar(nrow(cb)), stats::median(razao), q[1], q[2], pct(mean(abs(razao - 1) > 0.10), 1)))
}
if (!is.null(eventos_df)) {
  cat("\n=== Amostra da re-estimação ===\n")
  cat(sprintf("Observações por teste : mediana %.0f dias (mín %.0f, máx %.0f)\n",
              stats::median(eventos_df$n_amostra), min(eventos_df$n_amostra), max(eventos_df$n_amostra)))
  faixa <- cortar_faixas(eventos_df$n_amostra, 5)
  aprov <- eventos_df$motivo == "aprovado"
  tabela <- data.frame(faixa = levels(faixa), sinais = as.integer(table(faixa)),
                       aprovacao = round(100 * as.numeric(tapply(aprov, faixa, mean)), 1))
  cat("\n=== Taxa de aprovação (%) por maturidade da janela ===\n")
  print(tabela[tabela$sinais > 0, ], row.names = FALSE)

  arq <- abrir_png("diagnostico_coint_dinamica.png", 15, 4)
  graphics::par(mfrow = c(1, 3), mar = c(7, 4, 3, 1))
  ordem <- c("aprovado", "sem_cointegracao", "z_reestimado_dentro_da_banda", "beta_ou_sigma")
  cont <- sapply(ordem, function(m) sum(eventos_df$motivo == m))
  b <- graphics::barplot(cont, names.arg = c("aprovado", "sem cointegração", "|z| dentro da banda", "β/σ degenerado"),
                         col = c("#2E7D32", "#C62828", "#EF6C00", "#616161"), las = 2, cex.names = 0.8,
                         main = "Destino dos sinais", ylab = "nº de sinais", border = NA)
  graphics::text(b, cont, milhar(cont), pos = 3, cex = 0.8, xpd = TRUE)
  graphics::par(mar = c(4, 4, 3, 1))
  sa <- eventos_df$stat_novo[eventos_df$motivo == "aprovado"]
  sv <- eventos_df$stat_novo[eventos_df$motivo == "sem_cointegracao"]
  sa <- sa[!is.na(sa)]; sv <- sv[!is.na(sv)]
  br <- seq(min(c(sa, sv)), max(c(sa, sv)), length.out = 61)
  graphics::hist(sv, breaks = br, col = grDevices::adjustcolor("#C62828", 0.55), border = NA,
                 main = sprintf("Estatística %s no sinal", METODO_COINT_RETESTE), xlab = "estatística")
  graphics::hist(sa, breaks = br, add = TRUE, col = grDevices::adjustcolor("#2E7D32", 0.55), border = NA)
  if (METODO_COINT_RETESTE == "ADF") graphics::abline(v = CRIT_COINT_5PCT, lty = 2)
  if (nrow(cb)) {
    lim <- c(0, min(3, max(stats::quantile(cb$beta, 0.99), stats::quantile(cb$beta_medio, 0.99))))
    plot(cb$beta, cb$beta_medio, pch = 16, cex = 0.4, col = grDevices::adjustcolor("#1565C0", 0.25),
         xlim = lim, ylim = lim, xlab = "β da formação", ylab = "β médio nas aberturas",
         main = "Deslocamento do hedge ratio")
    graphics::abline(0, 1, col = "red", lty = 2)
  }
  fechar_png(arq)
}


# ── 5. Resultado por par ──────────────────────────────────────────────────────────────
cat("\n")
plot_pares_por_janela(resultados_df, max(pares$rank),
                      "Pares simulados por janela de negociação (cointegração dinâmica)",
                      "pares_por_janela_coint_dinamica.png")
cat("\n"); imprimir_estatisticas_trades(resultados_df)
cat("\n"); imprimir_top_bottom(resultados_df, c("neg_inicio", "ativo1", "ativo2", "rank", "beta",
                                               "n_trades", "n_fechados", "retorno_total"))


# ── 6. Portfólio, REC/RCC e métricas ──────────────────────────────────────────────────
portfolio <- serie_portfolio(acc, base)
cat("\n"); imprimir_resumo_portfolio(portfolio)
plot_equity(portfolio, "Portfólio de Pairs Trading — Cointegração dinâmica (re-estimação no sinal)",
            "equity_coint_dinamica.png")
cat("\n")
rr <- calcular_rec_rcc(mensal_df, N_PARES_NOMINADOS)
imprimir_rec_rcc(rr, N_PARES_NOMINADOS)
cat("\n"); imprimir_metricas_simples(portfolio$retorno_diario)
cat("\n"); imprimir_bruto_liquido(portfolio)
cat("\n"); imprimir_meses_positivos(portfolio)
plot_retorno_anual(portfolio, "Retorno anual do portfólio — cointegração dinâmica",
                   "retorno_anual_coint_dinamica.png")


# ── 7. Estático × dinâmico ────────────────────────────────────────────────────────────
# Rode cointegration/pairs_trading_coint.R antes, com os mesmos PERIODO_INICIO / PERIODO_FIM.
cat("\n")
comparar_estatico_dinamico(portfolio, resultados_df,
                           file.path(PASTA_RESULTADOS, "negociacao_portfolio_coint.csv"),
                           file.path(PASTA_RESULTADOS, "negociacao_pares_coint.csv"),
                           "Cointegração — estático × dinâmico (re-estimação no sinal)",
                           "estatico_vs_dinamico_coint.png")


# ── 8. Salvando resultados ────────────────────────────────────────────────────────────
SUFIXO <- "_coint_dinamico"
utils::write.csv(resultados_df, file.path(PASTA_RESULTADOS, paste0("negociacao_pares", SUFIXO, ".csv")), row.names = FALSE)
utils::write.csv(portfolio, file.path(PASTA_RESULTADOS, paste0("negociacao_portfolio", SUFIXO, ".csv")), row.names = FALSE)
utils::write.csv(rr$port_mes, file.path(PASTA_RESULTADOS, paste0("negociacao_portfolio_mes", SUFIXO, ".csv")), row.names = FALSE)
utils::write.csv(rr$mensal, file.path(PASTA_RESULTADOS, paste0("negociacao_retorno_mensal", SUFIXO, ".csv")), row.names = FALSE)
if (!is.null(eventos_df))
  utils::write.csv(eventos_df, file.path(PASTA_RESULTADOS, paste0("eventos_reteste", SUFIXO, ".csv")), row.names = FALSE)
cat("\nSalvo:\n")
cat(sprintf("  cointegration/output/resultados/negociacao_pares%s.csv           — resultado por par (+ contadores de veto)\n", SUFIXO))
cat(sprintf("  cointegration/output/resultados/negociacao_portfolio%s.csv       — série diária do portfólio\n", SUFIXO))
cat(sprintf("  cointegration/output/resultados/negociacao_portfolio_mes%s.csv   — REC/RCC por portfólio-mês\n", SUFIXO))
cat(sprintf("  cointegration/output/resultados/negociacao_retorno_mensal%s.csv  — REC/RCC mensais agregados\n", SUFIXO))
cat(sprintf("  cointegration/output/resultados/eventos_reteste%s.csv           — um registro por sinal avaliado\n", SUFIXO))
