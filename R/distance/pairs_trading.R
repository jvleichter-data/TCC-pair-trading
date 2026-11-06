# -*- coding: utf-8 -*-
# ══════════════════════════════════════════════════════════════════════════════════════
#  Negociação de Pares — Método da Distância (Gatev et al., 2006)
#  Tradução de new_aproach/src/distance/pairs_trading.ipynb
# ══════════════════════════════════════════════════════════════════════════════════════
#
# Usa os pares de distance/output/pares/pares_formados.csv (pairs_formation.R). Para cada par em cada janela:
#   1. Normaliza os preços da negociação a partir do INÍCIO DA FORMAÇÃO — mesma base que
#      gerou spread_media e spread_desvio
#   2. z(t) = (Q1(t) − Q2(t) − μ) / σ, com os parâmetros fixos da formação
#   3. Abre posição quando |z| > δ, fecha quando os preços normalizados se cruzam
#   4. Retorno diário = P&L marcado a mercado de $1 comprado e $1 vendido, em buy-and-hold:
#        r_par(t) = w_L(t)·r_L(t) − w_S(t)·r_S(t),  w_i(t) = w_i(t−1)·[1 + r_i(t−1)]
#      com w = 1 no dia da abertura (Gatev et al., §2.3, eq. 2–3)
#
# A decisão é tomada no fechamento de t e executada a partir de t+1 (position_lag).
# Rodar com o diretório de trabalho na pasta R/.

source("funcoes/comum.R", local = TRUE)
source("funcoes/metricas.R", local = TRUE)
source("distance/funcoes_distancia.R", local = TRUE)
usar_pastas("distance")

# === Parâmetros da estratégia ===
DELTA     <- 2.0    # gatilho de entrada: abre posição quando |z| > DELTA
STOP      <- NULL   # stop-loss: fecha quando |z| > STOP (NULL = desativado)
SIGMA_MIN <- 0.01   # exclui pares com sigma patológico (ghost tickers com sigma ~ 0.00002)

# === Filtro de qualidade de dados ===
# Exclui o par inteiro se algum retorno diário POSITIVO na NEGOCIAÇÃO passar deste limiar
# (OTC penny stocks com dados corrompidos: AVATQ +2450%, PNAA +5686%). NULL = sem filtro.
# ⚠️ É LOOK-AHEAD (olha a negociação para excluir o par); efeito medido em 1991–2015:
# 0,000 p.p. Padronizado em 2026-09-22 para comparabilidade entre os métodos.
MAX_RETORNO_DIA <- 0.90

# === Regra de fechamento ===
# TRUE  — fecha quando os preços normalizados CRUZAM (spread = 0): regra do artigo do
#         orientador e de Gatev et al.
# FALSE — fecha quando o spread volta a μ (média da formação).
FECHA_NO_CRUZAMENTO <- TRUE

# Quantos desvios-padrão ANTES do alvo a posição é encerrada. 0 = fecha no alvo (artigo);
# 0.75 é o closing_threshold do código de referência que circula entre os alunos.
LIMIAR_FECHAMENTO <- 0.0

# Gatilho em relação à média μ do spread na formação (TRUE) ou ao zero (FALSE).
USAR_MEDIA_SPREAD <- TRUE

# === Convenção do portfólio ===
# TRUE  — "committed capital" (Gatev et al.): denominador = N pares fixo.
# FALSE — "fully invested": denominador = pares com posição ativa no dia.
COMMITTED_CAPITAL <- TRUE

# === Filtro de período (mês 'YYYY-MM' da negociação) ===
PERIODO_INICIO <- NULL       # ex: '1992-01'
PERIODO_FIM    <- "2015-12"  # ex: '2015-12'


# ── 1. Carregando os dados ────────────────────────────────────────────────────────────
pares_raw <- ler_pares(file.path(PASTA_PARES, "pares_formados.csv"))
base      <- carregar_base()
pares     <- filtrar_periodo(pares_raw, PERIODO_INICIO, PERIODO_FIM)
imprimir_cabecalho_pares(pares_raw, pares, base, PERIODO_INICIO, PERIODO_FIM)


# ── 2. Simulação completa ─────────────────────────────────────────────────────────────
# Quatro filtros de exclusão antes de acumular o resultado: sigma < SIGMA_MIN, ticker
# ausente, dados ausentes e MAX_RETORNO_DIA.
resultados_pares <- vector("list", nrow(pares))
acc <- novo_acumulador(base)
devs_abertura <- numeric(0)   # 'Av Price Dev' da Tabela 7
duracoes      <- integer(0)   # dias em posição, por trade
n_skip <- c(sigma = 0, ticker = 0, dados = 0, outlier = 0)

for (i in seq_len(nrow(pares))) {
  par <- pares[i, ]
  a1 <- par$ativo1; a2 <- par$ativo2
  mu <- par$spread_media; sigma <- par$spread_desvio

  if (sigma < SIGMA_MIN) { n_skip["sigma"] <- n_skip["sigma"] + 1; next }
  if (!(a1 %in% colnames(base$P)) || !(a2 %in% colnames(base$P))) {
    n_skip["ticker"] <- n_skip["ticker"] + 1; next
  }

  rf_ <- recortar_par(base, a1, a2, par$formacao_inicio, par$formacao_fim)
  rn_ <- recortar_par(base, a1, a2, par$negociacao_inicio, par$negociacao_fim)
  if (nrow(rf_$P) == 0 || nrow(rn_$P) == 0) { n_skip["dados"] <- n_skip["dados"] + 1; next }

  # Spike positivo extremo = corrupção de dados. Quedas reais (falências) são preservadas.
  if (!is.null(MAX_RETORNO_DIA) && maior_retorno_dia(rn_$P) > MAX_RETORNO_DIA) {
    n_skip["outlier"] <- n_skip["outlier"] + 1; next
  }

  res <- simular_par_dist(rf_$P, rn_$P, mu, sigma)
  if (is.null(res)) next

  tr <- contar_trades(res$position)
  devs_abertura <- c(devs_abertura, res$dev_preco[aberturas_idx(res$position)])
  duracoes      <- c(duracoes, duracoes_trades(res$position))

  resultados_pares[[i]] <- data.frame(
    janela = par$janela, neg_inicio = par$negociacao_inicio, neg_fim = par$negociacao_fim,
    ativo1 = a1, ativo2 = a2, rank = par$rank, ssd = par$ssd, sigma = sigma,
    n_trades = tr[["abertos"]], n_fechados = tr[["fechados"]], n_forcados = tr[["forcados"]],
    retorno_total = sum(res$retorno_diario), stringsAsFactors = FALSE)

  # Portfólio: com janelas sobrepostas as carteiras coexistem e a média diária é tirada
  # sobre todos os pares ativos, de todas as janelas.
  acc <- acumular_par(acc, rn_, res$retorno_diario, res$position_lag, COMMITTED_CAPITAL)
}
resultados_df <- do.call(rbind, resultados_pares)

cat(sprintf("Total de pares no arquivo  : %s\n", milhar(nrow(pares))))
cat(sprintf("  Pulados (sigma < %g) : %s\n", SIGMA_MIN, milhar(n_skip[["sigma"]])))
cat(sprintf("  Pulados (ticker ausente)  : %s\n", milhar(n_skip[["ticker"]])))
cat(sprintf("  Pulados (sem dados)       : %s\n", milhar(n_skip[["dados"]])))
cat(sprintf("  Pulados (spike positivo)  : %s  ← corrupção de dados filtrada\n", milhar(n_skip[["outlier"]])))
cat(sprintf("  Simulados com sucesso     : %s\n\n", milhar(nrow(resultados_df))))


# ── 3. Resultado por par ──────────────────────────────────────────────────────────────
plot_pares_por_janela(resultados_df, max(pares$rank),
                      "Pares simulados por janela de negociação", "pares_por_janela_distancia.png")
cat("\n")
imprimir_estatisticas_trades(resultados_df)
cat("\n")
imprimir_top_bottom(resultados_df, c("neg_inicio", "ativo1", "ativo2", "rank", "n_trades",
                                     "n_fechados", "retorno_total"))


# ── 4. Portfólio e curva de equity ────────────────────────────────────────────────────
portfolio <- serie_portfolio(acc, base)
cat("\n"); imprimir_resumo_portfolio(portfolio)
plot_equity(portfolio, "Portfólio de Pairs Trading — Gatev et al. (2006)", "equity_distancia.png")


# ── 5. Métricas de performance ────────────────────────────────────────────────────────
# Comparáveis com os três artigos (definições em funcoes/metricas.R). Só a MÉDIA converte
# entre frequências: diário (orientador) → BLOCO A; mensal (Gatev, Rad) → BLOCO B.
cat("\n")
metr <- relatorio(portfolio$date, portfolio$retorno_diario)

# Tabela 7 do artigo — estatísticas de negociação (não dependem do retorno).
# "Av Price Dev trigger for open pairs is calculated as the price difference divided by
#  the average of the prices" (nota da Tabela 7)
K <- as.integer(max(pares$rank))
REF_T7 <- list("5"  = c(abertos = 355,  rt = 1.449, dias = 51.33, med = 39, dev = 0.060),
               "20" = c(abertos = 1330, rt = 1.358, dias = 52.09, med = 42, dev = 0.070),
               "35" = c(abertos = 2261, rt = 1.319, dias = 52.62, med = 42, dev = 0.074),
               "50" = c(abertos = 3145, rt = 1.284, dias = 53.76, med = 44, dev = 0.078))[[as.character(K)]]
n_periodos <- length(unique(resultados_df$neg_inicio))
nosso_t7 <- c(abertos = sum(resultados_df$n_trades),
              rt = sum(resultados_df$n_trades) / (K * n_periodos),
              dias = if (length(duracoes)) mean(duracoes) else NA,
              med = if (length(duracoes)) stats::median(duracoes) else NA,
              dev = if (length(devs_abertura)) mean(devs_abertura) else NA)
cat(sprintf("\nTop %d · %d períodos de negociação\n", K, n_periodos))
cat(strrep("=", 62), "\n", sep = "")
if (is.null(REF_T7)) {
  cat("(o artigo só publica Top 5, 20, 35 e 50 — sem referência para este K)\n")
  for (k in names(nosso_t7)) cat(sprintf("  %-28s%12.3f\n", k, nosso_t7[[k]]))
} else {
  cat(esq("", 28), drt("artigo", 11), drt("nosso", 11), drt("razão", 10), "\n", sep = "")
  cat(strrep("-", 62), "\n", sep = "")
  rot <- c(dev = "Av Price Dev", abertos = "Total de aberturas", rt = "Round-trips por par",
           dias = "Dias em posição (média)", med = "Dias em posição (mediana)")
  for (k in names(rot))
    cat(esq(rot[[k]], 28), sprintf("%11.3f%11.3f%10.3f", REF_T7[[k]], nosso_t7[[k]],
                                   nosso_t7[[k]] / REF_T7[[k]]), "\n", sep = "")
}
cat(strrep("=", 62), "\n\n", sep = "")

# Retorno bruto × líquido de renda fixa.
# ⚠️ O número comparável com a Tabela 4 do artigo é o BRUTO: a posição long-short já é
# retorno EXCEDENTE e o caixa ocioso rende zero por hipótese. Subtrair rf de novo é
# contagem dupla; a tabela fica como sensibilidade.
imprimir_bruto_liquido(portfolio)
cat("\n")
imprimir_meses_positivos(portfolio)
plot_retorno_anual(portfolio, "Retorno anual do portfólio — método da distância",
                   "retorno_anual_distancia.png")


# ── 6. Explorando um par específico ───────────────────────────────────────────────────
# Altere as variáveis abaixo para visualizar qualquer par em qualquer janela.
NEG_INICIO_ALVO <- "2020-07"   # mês inicial do período de negociação ('YYYY-MM')
RANK_ALVO       <- 1           # rank do par (1–TOP_K)

sel <- pares[pares$negociacao_inicio == NEG_INICIO_ALVO & pares$rank == RANK_ALVO, ]
if (nrow(sel) == 0)   # a janela pedida não existe na grade atual — usa a primeira
  sel <- pares[pares$negociacao_inicio == pares$negociacao_inicio[1] & pares$rank == RANK_ALVO, ]
par_info <- sel[1, ]
a1 <- par_info$ativo1; a2 <- par_info$ativo2
cat(sprintf("\nPar selecionado : %s / %s\n", a1, a2))
cat(sprintf("Janela          : %s\n", par_info$janela))
cat(sprintf("Negociação      : %s → %s\n", par_info$negociacao_inicio, par_info$negociacao_fim))
cat(sprintf("SSD             : %.6f\n", par_info$ssd))
cat(sprintf("Spread μ        : %.6f\n", par_info$spread_media))
cat(sprintf("Spread σ        : %.6f\n", par_info$spread_desvio))

rf_ <- recortar_par(base, a1, a2, par_info$formacao_inicio, par_info$formacao_fim)
rn_ <- recortar_par(base, a1, a2, par_info$negociacao_inicio, par_info$negociacao_fim)
res <- simular_par_dist(rf_$P, rn_$P, par_info$spread_media, par_info$spread_desvio)
if (is.null(res)) {
  cat("Par não pode ser simulado (sigma = 0 ou dados ausentes).\n")
} else {
  tr <- contar_trades(res$position)
  cat(sprintf("Trades abertos  : %d\nFechados (z→0)  : %d\nForçados        : %d\n",
              tr[["abertos"]], tr[["fechados"]], tr[["forcados"]]))
  cat(sprintf("Retorno total   : %s\n", pct(sum(res$retorno_diario), 4, sinal = TRUE)))

  datas <- base$datas[rn_$linhas]
  Q_neg <- sweep(rn_$P, 2, rf_$P[1, ], "/")
  arq <- abrir_png("par_exemplo_distancia.png", 13, 9)
  graphics::layout(matrix(1:3), heights = c(2, 2, 1))
  graphics::par(mar = c(1, 5, 2, 1), oma = c(2, 0, 2, 0))
  plot(datas, Q_neg[, 1], type = "l", col = "#2196F3", lwd = 1.5, ylim = range(Q_neg),
       xaxt = "n", xlab = "", ylab = "Q(t) = P(t)/P0_form")
  graphics::lines(datas, Q_neg[, 2], col = "#FF5722", lwd = 1.5, lty = 2)
  graphics::legend("topleft", c(a1, a2), col = c("#2196F3", "#FF5722"), lty = 1:2, bty = "n")
  graphics::mtext(sprintf("%s / %s — negociação %s → %s", a1, a2, par_info$negociacao_inicio,
                          par_info$negociacao_fim), outer = TRUE, font = 2)
  plot(datas, res$z, type = "n", xaxt = "n", xlab = "", ylab = "Z-score",
       ylim = range(c(res$z, -DELTA, DELTA)))
  u <- graphics::par("usr")
  for (t in which(res$position != 0))
    graphics::rect(datas[t], u[3], datas[min(t + 1, length(datas))], u[4], border = NA,
                   col = grDevices::adjustcolor(if (res$position[t] == -1) "#FFCDD2" else "#C8E6C9", 0.6))
  graphics::lines(datas, res$z, col = "purple", lwd = 1.3)
  graphics::abline(h = 0); graphics::abline(h = DELTA, col = "red", lty = 2)
  graphics::abline(h = -DELTA, col = "green", lty = 2)
  graphics::par(mar = c(3, 5, 1, 1))
  plot(datas, cumprod(1 + res$retorno_diario), type = "l", col = "#1565C0", lwd = 1.5,
       xlab = "", ylab = "Equity do par")
  graphics::abline(h = 1, col = "gray", lty = 2)
  fechar_png(arq)
}


# ── 7. Salvando resultados ────────────────────────────────────────────────────────────
utils::write.csv(resultados_df, file.path(PASTA_RESULTADOS, "negociacao_pares.csv"), row.names = FALSE)
utils::write.csv(portfolio, file.path(PASTA_RESULTADOS, "negociacao_portfolio.csv"), row.names = FALSE)
cat("\nSalvo:\n")
cat("  distance/output/resultados/negociacao_pares.csv     — resultado por par (trades, retorno)\n")
cat("  distance/output/resultados/negociacao_portfolio.csv — retorno diário do portfólio\n")
