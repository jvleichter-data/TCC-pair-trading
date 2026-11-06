# -*- coding: utf-8 -*-
# ══════════════════════════════════════════════════════════════════════════════════════
#  Negociação de Pares — Método da Cointegração (Rad et al., 2016)
#  Tradução de new_aproach/src/cointegration/pairs_trading_coint.ipynb
# ══════════════════════════════════════════════════════════════════════════════════════
#
# Usa os pares de cointegration/output/pares/pares_formados_coint.csv (pairs_formation_coint.R). Para cada par:
#   1. Lê a direção do OLS salva na formação ('direcao'): qual ativo é a variável
#      dependente (Q_dep) e qual é a independente (Q_indep)
#   2. Normaliza a negociação a partir do INÍCIO DA FORMAÇÃO — mesma base de β, α, μ, σ
#   3. Spread com os parâmetros fixos da formação: ε_t = Q_dep(t) − α − β·Q_indep(t)
#   4. z(t) = (ε_t − μ) / σ; abre quando |z| > δ, fecha quando z → 0
#   5. Retorno diário = variação do spread (Rad et al., eq. 5), reescalada para que a
#      perna comprada valha sempre $1 (§4.2.2 e §5.1):
#        position(t−1) = −1  (long $1 em Q_dep,   short $β   em Q_indep) → r = +Δε_t
#        position(t−1) = +1  (long $1 em Q_indep, short $1/β em Q_dep)   → r = −Δε_t/β
#
# Rodar com o diretório de trabalho na pasta R/.

source("funcoes/comum.R", local = TRUE)
source("funcoes/adf.R", local = TRUE)
source("cointegration/funcoes_coint.R", local = TRUE)
usar_pastas("cointegration")

# === Parâmetros da estratégia ===
DELTA     <- 2.0    # gatilho de entrada: abre posição quando |z| > DELTA
STOP      <- NULL   # Rad et al. não usa stop-loss — fecha por z → 0 ou fim do período
SIGMA_MIN <- 0.01   # exclui pares com sigma patológico (ghost tickers ~ 0.00002)

# Guarda numérica para o dimensionamento 1/β (§4.2.2): com β ≤ 0 a posição perde sentido
# econômico e com β → 0 o fator 1/β explode. O corte bloqueia só o caso degenerado.
BETA_MIN  <- 0.05

# === Filtro de qualidade de dados ===
# Spike positivo extremo = corrupção de dados. NULL = sem filtro.
MAX_RETORNO_DIA <- 0.90

# === Convenção do portfólio (série DIÁRIA agregada) ===
# TRUE  — "committed capital": denominador = N pares fixo; pares inativos contribuem 0.
# FALSE — "fully invested": denominador = pares com posição ativa no dia.
COMMITTED_CAPITAL <- TRUE

# === Retorno MENSAL (Rad et al., §4.5, eq. 14 e 15) ===
# REC — return on employed capital : soma dos retornos dos pares que negociaram no mês ÷ n
# RCC — return on committed capital: a mesma soma ÷ N_P pares nominados (20 no artigo)
N_PARES_NOMINADOS <- 20

# === Filtro de período (mês 'YYYY-MM' da negociação) ===
PERIODO_INICIO <- NULL
PERIODO_FIM    <- "2015-12"


# ── 1. Carregando os dados ────────────────────────────────────────────────────────────
pares_raw <- ler_pares(file.path(pasta_saida("cointegration", "pares"), "pares_formados_coint.csv"))
base      <- carregar_base()
pares     <- filtrar_periodo(pares_raw, PERIODO_INICIO, PERIODO_FIM)
cat(sprintf("Teste na formação : %s | bilateral (ambas as direções)\n", pares_raw$metodo[1]))
imprimir_cabecalho_pares(pares_raw, pares, base, PERIODO_INICIO, PERIODO_FIM)


# ── 2. Simulação completa ─────────────────────────────────────────────────────────────
# Cinco filtros de exclusão: sigma < SIGMA_MIN, beta < BETA_MIN, ticker ausente, dados
# ausentes e MAX_RETORNO_DIA. O loop também acumula o retorno mensal de cada par por
# janela — insumo do REC e do RCC.
resultados_pares  <- vector("list", nrow(pares))
registros_mensais <- vector("list", nrow(pares))
sem_dados_log     <- list()
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
  if (nrow(rf_$P) == 0 || nrow(rn_$P) == 0) {
    # Diagnóstico: quantos dias brutos existem e qual coluna tem NaN
    pf_b <- base$P[rf_$todas, c(a1, a2), drop = FALSE]
    pn_b <- base$P[rn_$todas, c(a1, a2), drop = FALSE]
    sem_dados_log[[length(sem_dados_log) + 1]] <- data.frame(
      ativo1 = a1, ativo2 = a2, janela = par$janela, neg_inicio = par$negociacao_inicio,
      dias_form_bruto = length(rf_$todas), dias_form_ok = nrow(rf_$P),
      dias_neg_bruto = length(rn_$todas), dias_neg_ok = nrow(rn_$P),
      nan_form_a1 = sum(is.na(pf_b[, 1])), nan_form_a2 = sum(is.na(pf_b[, 2])),
      nan_neg_a1 = sum(is.na(pn_b[, 1])), nan_neg_a2 = sum(is.na(pn_b[, 2])),
      stringsAsFactors = FALSE)
    n_skip["dados"] <- n_skip["dados"] + 1; next
  }

  if (!is.null(MAX_RETORNO_DIA) && maior_retorno_dia(rn_$P) > MAX_RETORNO_DIA) {
    n_skip["outlier"] <- n_skip["outlier"] + 1; next
  }

  res <- simular_par_coint(rf_$P, rn_$P, alpha, beta, mu, sigma, direcao = direcao)
  if (is.null(res)) next

  tr <- contar_trades(res$position)
  resultados_pares[[i]] <- data.frame(
    janela = par$janela, neg_inicio = par$negociacao_inicio, neg_fim = par$negociacao_fim,
    ativo1 = a1, ativo2 = a2, direcao = direcao, rank = par$rank, ssd = par$ssd,
    beta = beta, sigma = sigma, stat = par$stat,
    n_trades = tr[["abertos"]], n_fechados = tr[["fechados"]], n_forcados = tr[["forcados"]],
    retorno_total = sum(res$retorno_diario), stringsAsFactors = FALSE)

  registros_mensais[[i]] <- mensal_do_par(base$datas[rn_$linhas], res$retorno_diario,
                                          res$position_lag, par$janela, a1, a2)
  acc <- acumular_par(acc, rn_, res$retorno_diario, res$position_lag, COMMITTED_CAPITAL)
}
resultados_df <- do.call(rbind, resultados_pares)
mensal_df     <- do.call(rbind, registros_mensais)
sem_dados_df  <- do.call(rbind, sem_dados_log)

cat(sprintf("Total de pares no arquivo  : %s\n", milhar(nrow(pares))))
cat(sprintf("  Pulados (sigma < %g) : %s\n", SIGMA_MIN, milhar(n_skip[["sigma"]])))
cat(sprintf("  Pulados (beta < %g)  : %s\n", BETA_MIN, milhar(n_skip[["beta"]])))
cat(sprintf("  Pulados (ticker ausente)  : %s\n", milhar(n_skip[["ticker"]])))
cat(sprintf("  Pulados (sem dados)       : %s\n", milhar(n_skip[["dados"]])))
cat(sprintf("  Pulados (spike positivo)  : %s\n", milhar(n_skip[["outlier"]])))
cat(sprintf("  Simulados com sucesso     : %s\n\n", milhar(nrow(resultados_df))))

# Diagnóstico dos pares pulados por dados ausentes
if (is.null(sem_dados_df)) {
  cat("Nenhum par pulado por dados ausentes.\n\n")
} else {
  sem_dados_df$motivo <- apply(sem_dados_df, 1, function(r) {
    culpado <- function(nan1, nan2, bruto) {
      x <- c(if (as.integer(nan1) == as.integer(bruto)) r[["ativo1"]],
             if (as.integer(nan2) == as.integer(bruto)) r[["ativo2"]])
      if (length(x)) paste(x, collapse = "+") else "ambos"
    }
    if (as.integer(r[["dias_form_bruto"]]) == 0) return("form_fora_do_range")
    if (as.integer(r[["dias_neg_bruto"]]) == 0) return("neg_fora_do_range")
    if (as.integer(r[["dias_form_ok"]]) == 0)
      return(paste0("form_tudo_NaN: ", culpado(r[["nan_form_a1"]], r[["nan_form_a2"]], r[["dias_form_bruto"]])))
    if (as.integer(r[["dias_neg_ok"]]) == 0)
      return(paste0("neg_tudo_NaN: ", culpado(r[["nan_neg_a1"]], r[["nan_neg_a2"]], r[["dias_neg_bruto"]])))
    "parcial_dropna"
  })
  print(sem_dados_df[, c("ativo1", "ativo2", "janela", "neg_inicio", "dias_neg_bruto",
                         "dias_neg_ok", "motivo")], row.names = FALSE)
  cat("\n")
}


# ── 3. Resultado por par ──────────────────────────────────────────────────────────────
plot_pares_por_janela(resultados_df, max(pares$rank),
                      "Pares simulados por janela de negociação (cointegração)",
                      "pares_por_janela_coint.png")
cat("\n")
imprimir_estatisticas_trades(resultados_df)
cat("\n")
imprimir_top_bottom(resultados_df, c("neg_inicio", "ativo1", "ativo2", "rank", "beta",
                                     "n_trades", "n_fechados", "retorno_total"))


# ── 4. Portfólio e curva de equity (série diária) ─────────────────────────────────────
# Junta num único pool os pares de TODAS as janelas sobrepostas ativas no dia. Não é a
# medida do artigo: Rad et al. reportam retornos MENSAIS por portfólio (seção 5).
portfolio <- serie_portfolio(acc, base)
cat("\n"); imprimir_resumo_portfolio(portfolio)
plot_equity(portfolio, "Portfólio de Pairs Trading — Cointegração (Rad et al., 2016)",
            "equity_coint.png")


# ── 5. Retorno mensal — REC e RCC (Rad et al., §4.5) ──────────────────────────────────
# REC e RCC são calculados por portfólio (janela) e o retorno do mês é a média
# equiponderada dos portfólios sobrepostos ativos (no máximo seis). Mês sem trade num
# portfólio: REC indefinido (omitido da média), RCC = 0. r_i é a SOMA dos P&L diários do
# par no mês — cada dia é P&L em dólares sobre uma perna comprada de $1 fixa.
cat("\n")
rr <- calcular_rec_rcc(mensal_df, N_PARES_NOMINADOS)
imprimir_rec_rcc(rr, N_PARES_NOMINADOS)


# ── 6. Métricas de performance (série diária) ─────────────────────────────────────────
cat("\n"); imprimir_metricas_simples(portfolio$retorno_diario)
cat("\n"); imprimir_bruto_liquido(portfolio)
cat("\n"); imprimir_meses_positivos(portfolio)
plot_retorno_anual(portfolio, "Retorno anual do portfólio — cointegração", "retorno_anual_coint.png")


# ── 7. Explorando um par específico ───────────────────────────────────────────────────
NEG_INICIO_ALVO <- resultados_df$neg_inicio[1]   # primeiro período disponível
RANK_ALVO       <- 1

par_info <- pares[pares$negociacao_inicio == NEG_INICIO_ALVO & pares$rank == RANK_ALVO, ][1, ]
a1 <- par_info$ativo1; a2 <- par_info$ativo2
cat(sprintf("\nPar selecionado    : %s / %s\n", a1, a2))
cat(sprintf("Janela             : %s\n", par_info$janela))
cat(sprintf("Negociação         : %s → %s\n", par_info$negociacao_inicio, par_info$negociacao_fim))
cat(sprintf("Direção (OLS)      : %s\n", par_info$direcao))
cat(sprintf("Beta (hedge ratio) : %.4f\n", par_info$beta))
cat(sprintf("Alpha (intercepto) : %.4f\n", par_info$alpha))
cat(sprintf("Estatística (%s)  : %.4f\n", par_info$metodo, par_info$stat))
cat(sprintf("Spread μ           : %.6f\n", par_info$spread_media))
cat(sprintf("Spread σ           : %.6f\n", par_info$spread_desvio))

rf_ <- recortar_par(base, a1, a2, par_info$formacao_inicio, par_info$formacao_fim)
rn_ <- recortar_par(base, a1, a2, par_info$negociacao_inicio, par_info$negociacao_fim)
res <- simular_par_coint(rf_$P, rn_$P, par_info$alpha, par_info$beta, par_info$spread_media,
                         par_info$spread_desvio, direcao = par_info$direcao)
if (is.null(res)) {
  cat("Par não pode ser simulado.\n")
} else {
  tr <- contar_trades(res$position)
  cat(sprintf("Trades abertos  : %d\nFechados (z→0)  : %d\nForçados        : %d\n",
              tr[["abertos"]], tr[["fechados"]], tr[["forcados"]]))
  cat(sprintf("Retorno total   : %s\n", pct(sum(res$retorno_diario), 4, sinal = TRUE)))

  o <- orientar(a1, a2, par_info$direcao)
  datas <- base$datas[rn_$linhas]
  Q_neg <- sweep(rn_$P, 2, rf_$P[1, ], "/")
  arq <- abrir_png("par_exemplo_coint.png", 13, 9)
  graphics::layout(matrix(1:3), heights = c(2, 2, 1))
  graphics::par(mar = c(1, 5, 2, 1), oma = c(2, 0, 2, 0))
  plot(datas, Q_neg[, 1], type = "l", col = "#2196F3", lwd = 1.5, ylim = range(Q_neg),
       xaxt = "n", xlab = "", ylab = "Q(t) = P(t)/P0_form")
  graphics::lines(datas, Q_neg[, 2], col = "#FF5722", lwd = 1.5, lty = 2)
  graphics::legend("topleft", c(a1, a2), col = c("#2196F3", "#FF5722"), lty = 1:2, bty = "n")
  graphics::mtext(sprintf("%s / %s — negociação %s → %s  β=%.3f  %s=%.2f  [%s]", a1, a2,
                          par_info$negociacao_inicio, par_info$negociacao_fim, par_info$beta,
                          par_info$metodo, par_info$stat, par_info$direcao), outer = TRUE, font = 2)
  plot(datas, res$z, type = "n", xaxt = "n", xlab = "", ylab = "Z-score",
       ylim = range(c(res$z, -DELTA, DELTA)))
  u <- graphics::par("usr")
  for (t in which(res$position != 0))
    graphics::rect(datas[t], u[3], datas[min(t + 1, length(datas))], u[4], border = NA,
                   col = grDevices::adjustcolor(if (res$position[t] == +1) "#C8E6C9" else "#FFCDD2", 0.6))
  graphics::lines(datas, res$z, col = "purple", lwd = 1.3)
  graphics::abline(h = 0); graphics::abline(h = DELTA, col = "red", lty = 2)
  graphics::abline(h = -DELTA, col = "green", lty = 2)
  graphics::legend("topright", bty = "n", cex = 0.8, lty = 2, col = c("red", "green"),
                   c(sprintf("+%gσ (long %s / short %s)", DELTA, o[["indep"]], o[["dep"]]),
                     sprintf("-%gσ (long %s / short %s)", DELTA, o[["dep"]], o[["indep"]])))
  graphics::par(mar = c(3, 5, 1, 1))
  plot(datas, cumprod(1 + res$retorno_diario), type = "l", col = "#1565C0", lwd = 1.5,
       xlab = "", ylab = "Equity do par")
  graphics::abline(h = 1, col = "gray", lty = 2)
  fechar_png(arq)
}


# ── 8. Salvando resultados ────────────────────────────────────────────────────────────
utils::write.csv(resultados_df, file.path(PASTA_RESULTADOS, "negociacao_pares_coint.csv"), row.names = FALSE)
utils::write.csv(portfolio, file.path(PASTA_RESULTADOS, "negociacao_portfolio_coint.csv"), row.names = FALSE)
utils::write.csv(rr$port_mes, file.path(PASTA_RESULTADOS, "negociacao_portfolio_mes_coint.csv"), row.names = FALSE)
utils::write.csv(rr$mensal, file.path(PASTA_RESULTADOS, "negociacao_retorno_mensal_coint.csv"), row.names = FALSE)
cat("\nSalvo:\n")
cat("  cointegration/output/resultados/negociacao_pares_coint.csv           — resultado por par\n")
cat("  cointegration/output/resultados/negociacao_portfolio_coint.csv       — série diária do portfólio\n")
cat("  cointegration/output/resultados/negociacao_portfolio_mes_coint.csv   — REC/RCC por portfólio-mês\n")
cat("  cointegration/output/resultados/negociacao_retorno_mensal_coint.csv  — REC/RCC mensais agregados\n")
