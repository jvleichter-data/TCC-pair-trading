# -*- coding: utf-8 -*-
# ══════════════════════════════════════════════════════════════════════════════════════
#  Negociação de Pares — Cointegração Não Paramétrica (kernel local linear)
#  Tradução de new_aproach/src/nonparametric/pairs_trading_np.ipynb
# ══════════════════════════════════════════════════════════════════════════════════════
#
# Por padrão usa os pares, as direções e as bandwidths da FORMAÇÃO PRÓPRIA (pairs_formation_np_propria.R). Os pares da
# cointegração linear (pairs_formation_np.R) seguem disponíveis via ARQUIVO_PARES.
#
# Por que a curva não pode ficar congelada na formação: o kernel só tem informação onde o
# preço já esteve, e nos pares lineares ~40% dos dias de negociação têm Q_indep fora da
# faixa da formação. Por isso a estimação invade a negociação até o dia anterior ao sinal.
#
# O ciclo de um par:
#   Monitoramento (todo dia t, fora do mercado): S_t = Q_dep(t) − ĝ_{t−1}(Q_indep(t)),
#                 z_t = (S_t − μ)/σ, curva com formação + negociação até t−1
#   Sinal:        |z_t| > δ
#   Veto suporte: massa de kernel em Q_indep(t) vinda de dados com mais de L dias < MASSA_MIN
#                 (desligado por padrão: MASSA_MIN = 0 desde 22/10)
#   Veto de β:    β̂_{t−1}(Q_indep(t)) fora de [BETA_MIN, BETA_MAX]
#   Abertura:     congela x_e = Q_indep(t), ĝ_e = ĝ_{t−1}(x_e) e β_e = b̂_{t−1}(x_e)
#   Durante:      z_trade = (Q_dep − ref − μ)/σ, com a referência de MODO_SAIDA
#   Fechamento:   z_trade cruza 0, ou fim do período
# O ponto t fica fora da curva do dia t (com h pequeno ela "explicaria" o próprio desvio);
# a referência é congelada na entrada (senão ela perseguiria o preço — convergência falsa).
#
# MODO_SAIDA:
#   'tangente' (padrão)  reta tangente à curva na entrada, β_e fixo — o spread É o valor da
#                        carteira hedgeada (DECISOES.md, D14)
#   'curva'              curva congelada na entrada, β_e fixo
#   'curva_rebalanceada' curva congelada, β = inclinação da curva no dia (rebalanceia)
#
# Retorno (com o β do trade vigente, decisão em t e execução em t+1):
#   position −1 → +(ΔQ_dep − β·ΔQ_indep) × escala ;  position +1 → −(ΔQ_dep − β·ΔQ_indep) × escala
#   escala pelo DIMENSIONAMENTO: 'maior_perna' (padrão, ÷ max(1, β)), 'rad' (perna comprada $1)
#   ou 'slides' (1 : β).
# Rodar com o diretório de trabalho na pasta R/ (depois de pairs_formation_np_propria.R e, para a seção 7,
# de cointegration/pairs_trading_coint.R).

source("funcoes/comum.R", local = TRUE)
source("funcoes/adf.R", local = TRUE)
source("funcoes/paralelo.R", local = TRUE)
source("nonparametric/kernel_np.R", local = TRUE)
source("nonparametric/formacao_utils.R", local = TRUE)
source("nonparametric/negociacao_utils.R", local = TRUE)
source("nonparametric/especificacao_np.R", local = TRUE)
usar_pastas("nonparametric")

# === Parâmetros da estratégia (iguais aos da cointegração linear) ===
DELTA     <- 2.0    # gatilho de entrada: |z| > DELTA
SIGMA_MIN <- 0.01   # exclui pares com sigma patológico
# Veto de β: com β local pequeno a perna vendida explode. PADRÃO desde 2026-10-22: 0,50 ≈
# percentil 1 do β do OLS nos mesmos pares. ⚠️ escolhido depois de ver o resultado.
BETA_MIN  <- 0.50
# PADRÃO desde 2026-11-02: 0,50 ≤ β ≤ 2 (a perna menor vale ao menos metade da maior).
BETA_MAX  <- 2.0    # NULL = sem teto

# === Dimensionamento das pernas (DECISOES.md § 9) ===
#   'rad'         → perna comprada sempre $1; com z > 0 vende $1/β (alavancada se β < 1)
#   'slides'      → 1 unidade da dependente contra β da independente, nos dois sentidos
#   'maior_perna' → o hedge 1 : β dos slides com a MAIOR perna em $1 (sem alavancagem)
DIMENSIONAMENTO <- "maior_perna"

# === Filtro de qualidade de dados — IGUAL ao da linear (comparação pareada) ===
MAX_RETORNO_DIA <- 0.90   # ⚠️ look-ahead

# === Veto por suporte (desligado: MASSA_MIN = 0) ===
L_SUPORTE <- 20    # idade mínima (pregões) dos dados que contam como suporte
MASSA_MIN <- 0.0   # 0 → veto desligado; o valor antigo era 10

# === Referência de convergência durante o trade ===
MODO_SAIDA <- "tangente"   # 'tangente', 'curva' ou 'curva_rebalanceada'

# === μ e σ do z ===
#   'formacao'  → fixos, do erro um passo à frente na formação (padrão)
#   'expandido' → re-estimados todo dia com os erros até t−1
#   'movel'     → idem, só os últimos JANELA_MU_SIGMA valores
MU_SIGMA_MODO   <- "formacao"
JANELA_MU_SIGMA <- 126
T_MIN_RESID     <- 126    # = T_MIN_UNILATERAL da formação

# === Arquivos ===
# Padrão: formação PRÓPRIA (pairs_formation_np_propria.R). Pares da linear:
# "pares_formados_np.csv" (pairs_formation_np.R).
ARQUIVO_PARES <- file.path(PASTA_PARES, "pares_formados_np_propria.csv")
SUFIXO        <- ""   # anexado aos CSVs de saída (rodadas de sensibilidade)

COMMITTED_CAPITAL <- TRUE
N_PARES_NOMINADOS <- 20

PERIODO_INICIO <- NULL
PERIODO_FIM    <- "2015-12"


# ── 1. Carregando os dados ────────────────────────────────────────────────────────────
pares_raw <- ler_pares(ARQUIVO_PARES)
base      <- carregar_base()
pares     <- filtrar_periodo(pares_raw, PERIODO_INICIO, PERIODO_FIM)
cat(sprintf("Pares disponíveis : %s (%d janelas)\n", milhar(nrow(pares_raw)), length(unique(pares_raw$janela))))
cat(sprintf("Origem dos pares  : %s\n", pares_raw$origem[1]))
cat(sprintf("Período filtrado  : %s → %s  (%s pares, %d janelas)\n",
            if (is.null(PERIODO_INICIO)) min(pares_raw$negociacao_inicio) else PERIODO_INICIO,
            if (is.null(PERIODO_FIM)) max(pares_raw$negociacao_fim) else PERIODO_FIM,
            milhar(nrow(pares)), length(unique(pares$janela))))
cat(sprintf("Pares com h = ∞   : %s (a curva é a reta, re-estimada até t−1)\n", pct(mean(pares$h_linear), 1)))
cat(sprintf("Modo de saída     : %s\n\n", MODO_SAIDA))


# ── 2. Simulação completa ─────────────────────────────────────────────────────────────
# A simulação de um par (simular_par_np) e o laço sobre os pares (negociar_np) estão em
# nonparametric/negociacao_utils.R.
params <- list(delta = DELTA, beta_min = BETA_MIN, beta_max = BETA_MAX,
               dimensionamento = DIMENSIONAMENTO, l_suporte = L_SUPORTE, massa_min = MASSA_MIN,
               modo_saida = MODO_SAIDA, mu_sigma_modo = MU_SIGMA_MODO,
               janela_mu_sigma = JANELA_MU_SIGMA, t_min_resid = T_MIN_RESID)
t0 <- Sys.time()
neg <- negociar_np(pares, base, params, COMMITTED_CAPITAL, SIGMA_MIN, MAX_RETORNO_DIA)
resultados_df <- neg$resultados; eventos_df <- neg$eventos; portfolio <- neg$portfolio

cat(sprintf("Total de pares no arquivo  : %s\n", milhar(nrow(pares))))
cat(sprintf("  Pulados (sigma < %g) : %s\n", SIGMA_MIN, milhar(neg$skip[["sigma"]])))
cat(sprintf("  Pulados (ticker ausente)  : %s\n", milhar(neg$skip[["ticker"]])))
cat(sprintf("  Pulados (sem dados)       : %s\n", milhar(neg$skip[["dados"]])))
cat(sprintf("  Pulados (spike positivo)  : %s\n", milhar(neg$skip[["outlier"]])))
cat(sprintf("  Simulados com sucesso     : %s\n", milhar(nrow(resultados_df))))
cat(sprintf("Tempo                       : %.0f s\n\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))


# ── 3. Diagnóstico dos sinais ─────────────────────────────────────────────────────────
resumo_sinais <- function(ev) c(sinais = milhar(nrow(ev)), aprovados = pct(mean(ev$motivo == "aprovado"), 1),
                                veto_suporte = pct(mean(ev$motivo == "suporte"), 1),
                                veto_beta = pct(mean(ev$motivo == "beta"), 1))
print(noquote(rbind("todos" = resumo_sinais(eventos_df),
                    "h = ∞ (reta)" = resumo_sinais(eventos_df[eventos_df$h_linear, ]),
                    "h finito" = resumo_sinais(eventos_df[!eventos_df$h_linear, ]))))
b_ap <- eventos_df$beta[eventos_df$motivo == "aprovado"]
cat(sprintf("\nβ na entrada (trades aprovados): mediana %.3f | p10 %.3f | p90 %.3f\n\n",
            stats::median(b_ap), stats::quantile(b_ap, 0.1), stats::quantile(b_ap, 0.9)))


# ── 4. Resultado por par ──────────────────────────────────────────────────────────────
imprimir_estatisticas_trades(resultados_df)
cat("\n=== Reta × curva ===\n")
print(do.call(rbind, lapply(split(resultados_df, resultados_df$h_linear), function(d) data.frame(
  h_linear = d$h_linear[1], pares = nrow(d), trades_por_par = mean(d$n_trades),
  convergencia = sum(d$n_fechados) / sum(d$n_trades), retorno_medio_par = mean(d$retorno_total)))),
  row.names = FALSE)


# ── 5. Portfólio, curva de equity e REC/RCC ───────────────────────────────────────────
cat("\n"); imprimir_resumo_portfolio(portfolio)
plot_equity(portfolio, "Portfólio de Pairs Trading — Cointegração não paramétrica",
            paste0("equity_np", SUFIXO, ".png"))
cat("\n")
rr <- calcular_rec_rcc(neg$mensal, N_PARES_NOMINADOS)
imprimir_rec_rcc(rr, N_PARES_NOMINADOS)


# ── 6. Métricas de performance (série diária) — bruto × líquido de renda fixa ─────────
cat("\n"); imprimir_bruto_liquido(portfolio)


# ── 7. Comparação pareada — linear estática × não paramétrica ─────────────────────────
# Lê os resultados de cointegration/pairs_trading_coint.R. Pré-requisito: mesmo período.
arq_lin_port <- file.path(pasta_saida("cointegration", "resultados"), "negociacao_portfolio_coint.csv")
arq_lin_par  <- file.path(pasta_saida("cointegration", "resultados"), "negociacao_pares_coint.csv")
if (file.exists(arq_lin_port)) {
  lin_port <- utils::read.csv(arq_lin_port, stringsAsFactors = FALSE)
  lin_port$date <- as.Date(lin_port$date)
  lin_par <- utils::read.csv(arq_lin_par, stringsAsFactors = FALSE,
                             colClasses = c(ativo1 = "character", ativo2 = "character"))
  datas <- intersect(portfolio$date, lin_port$date)
  if (length(datas) < 0.95 * nrow(portfolio))
    cat(sprintf("⚠ só %s de %s dias em comum — comparação NÃO pareada.\n", milhar(length(datas)), milhar(nrow(portfolio))))
  m_lin <- metricas_performance(lin_port$retorno_diario[match(datas, lin_port$date)])
  m_np  <- metricas_performance(portfolio$retorno_diario[match(datas, portfolio$date)])
  cat("\n"); print(round(cbind("linear estática" = m_lin, "não paramétrica" = m_np), 4))

  chave <- c("janela", "ativo1", "ativo2")
  pp <- merge(resultados_df, lin_par[, c(chave, "retorno_total", "n_trades")], by = chave,
              suffixes = c("_np", "_lin"))
  dif <- pp$retorno_total_np - pp$retorno_total_lin
  cat(sprintf("\nPares pareados: %s de %s\n", milhar(nrow(pp)), milhar(nrow(resultados_df))))
  if (nrow(pp)) {
    cat(sprintf("Diferença de retorno por par (NP − linear): média %+.4f | mediana %+.4f | NP melhor em %s\n",
                mean(dif), stats::median(dif), pct(mean(dif > 0), 1)))
    print(do.call(rbind, lapply(split(dif, ifelse(pp$h_linear, "h = ∞ (reta re-estimada)", "h finito (curva)")),
                                function(v) c(size = length(v), mean = mean(v), median = stats::median(v)))))
  }
} else {
  cat("\nResultados da linear não encontrados — rode cointegration/pairs_trading_coint.R para a comparação pareada.\n")
}


# ── 8. Explorando um par específico ───────────────────────────────────────────────────
# Por padrão, o par com curva (h finito) que mais negociou.
cands_alvo <- if (any(!resultados_df$h_linear)) resultados_df[!resultados_df$h_linear, ] else resultados_df
alvo <- cands_alvo[which.max(cands_alvo$n_trades), ]
par_info <- pares[pares$janela == alvo$janela & pares$ativo1 == alvo$ativo1 & pares$ativo2 == alvo$ativo2, ][1, ]
o <- orientar(par_info$ativo1, par_info$ativo2, par_info$direcao)
rf_ <- recortar_par(base, o[["dep"]], o[["indep"]], par_info$formacao_inicio, par_info$formacao_fim)
rn_ <- recortar_par(base, o[["dep"]], o[["indep"]], par_info$negociacao_inicio, par_info$negociacao_fim)
sim <- simular_par_np(rf_$P, rn_$P, as.numeric(par_info$h), par_info$spread_media, par_info$spread_desvio, params)
res <- sim$diario; ev <- sim$eventos; datas <- base$datas[rn_$linhas]

arq <- abrir_png(paste0("par_exemplo_np", SUFIXO, ".png"), 13, 9)
graphics::layout(matrix(1:3), heights = c(2, 2, 1))
graphics::par(mar = c(1, 5, 2, 1), oma = c(2, 0, 2, 0))
plot(datas, res$z, type = "l", col = "gray", xaxt = "n", xlab = "", ylab = "z",
     ylim = range(c(res$z, res$z_trade, -DELTA, DELTA), na.rm = TRUE))
graphics::lines(datas, res$z_trade, col = "purple", lwd = 1.6)
graphics::abline(h = c(-DELTA, DELTA), col = "red", lty = 2); graphics::abline(h = 0)
ok <- ev$motivo == "aprovado"
graphics::points(datas[ev$t[ok]], ev$z[ok], pch = 1, col = "green", cex = 1.4, lwd = 1.5)
graphics::points(datas[ev$t[!ok]], ev$z[!ok], pch = 4, col = "red", cex = 1.2, lwd = 1.5)
graphics::legend("topleft", bty = "n", cex = 0.8, lty = c(1, 1, NA, NA), pch = c(NA, NA, 1, 4),
                 col = c("gray", "purple", "green", "red"),
                 c("z monitoramento (curva até t−1)", sprintf("z do trade (%s, congelada)", MODO_SAIDA),
                   "sinal aprovado", "sinal vetado"))
graphics::mtext(sprintf("%s ~ g(%s) — %s  h/sd=%.2f", o[["dep"]], o[["indep"]], par_info$janela,
                        par_info$h_rel), outer = TRUE, font = 2)
plot(datas, pmax(res$massa_antiga, 1e-3), type = "l", log = "y", col = "#00695C", lwd = 1.3,
     xaxt = "n", xlab = "", ylab = sprintf("massa de kernel\n(> %d dias)", L_SUPORTE))
if (MASSA_MIN > 0) graphics::abline(h = MASSA_MIN, col = "red", lty = 2)
graphics::par(mar = c(3, 5, 1, 1))
plot(datas, cumprod(1 + res$retorno_diario), type = "l", col = "#1565C0", lwd = 1.5,
     xlab = "", ylab = "equity do par")
graphics::abline(h = 1, col = "gray", lty = 2)
fechar_png(arq)


# ── 9. Salvando resultados ────────────────────────────────────────────────────────────
S <- SUFIXO
utils::write.csv(resultados_df, file.path(PASTA_RESULTADOS, paste0("negociacao_pares_np", S, ".csv")), row.names = FALSE)
utils::write.csv(eventos_df, file.path(PASTA_RESULTADOS, paste0("eventos_sinal_np", S, ".csv")), row.names = FALSE)
utils::write.csv(portfolio, file.path(PASTA_RESULTADOS, paste0("negociacao_portfolio_np", S, ".csv")), row.names = FALSE)
utils::write.csv(rr$port_mes, file.path(PASTA_RESULTADOS, paste0("negociacao_portfolio_mes_np", S, ".csv")), row.names = FALSE)
utils::write.csv(rr$mensal, file.path(PASTA_RESULTADOS, paste0("negociacao_retorno_mensal_np", S, ".csv")), row.names = FALSE)
cat(sprintf("\nSalvo em nonparametric/output/resultados/ (sufixo '%s', modo %s):\n", S, MODO_SAIDA))
cat(sprintf("  negociacao_pares_np%s.csv          — resultado por par\n", S))
cat(sprintf("  eventos_sinal_np%s.csv             — cada sinal, aprovado ou vetado\n", S))
cat(sprintf("  negociacao_portfolio_np%s.csv      — série diária do portfólio\n", S))
cat(sprintf("  negociacao_portfolio_mes_np%s.csv  — REC/RCC por portfólio-mês\n", S))
cat(sprintf("  negociacao_retorno_mensal_np%s.csv — REC/RCC mensais agregados\n", S))
