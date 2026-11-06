# -*- coding: utf-8 -*-
# ══════════════════════════════════════════════════════════════════════════════════════
#  Formação de Pares — Cointegração Não Paramétrica sobre os PARES DA LINEAR (alternativa)
#  Tradução de new_aproach/src/nonparametric/pairs_formation_np.ipynb
# ══════════════════════════════════════════════════════════════════════════════════════
#
# Variante da formação: em vez de selecionar pares próprios (pairs_formation_np_propria.R), ajusta a curva nos pares
# que a cointegração LINEAR escolheu (cointegration/pairs_formation_coint.R), com a direção do OLS que ela escolheu. Contra a
# linear, a única diferença passa a ser reta × curva (comparação pareada). Usada pelo
# diagnóstico de Wang & Phillips (seção 3) e disponível para a negociação (pairs_trading_np.R) via ARQUIVO_PARES.
#
# A relação de equilíbrio é uma curva desconhecida estimada por regressão local linear:
#   Q_dep(t) = g(Q_indep(t)) + u_t
# Para cada par:
#   1. normaliza pelo início da formação, Q = P/P0;
#   2. escolhe h por validação cruzada UNILATERAL (cada dia previsto só com o passado de pelo
#      menos 20 pregões de idade) — a CV de bloco usaria o futuro, que não existe na negociação;
#   3. μ e σ do spread = média e desvio do erro de previsão um passo à frente no h escolhido
#      (resíduos dentro da amostra subestimariam a dispersão com h pequeno);
#   4. diagnósticos: ADF dos erros, dispersão do β(x) local e o h do LS-CV leave-one-out.
# A curva não é salva: na negociação ela é re-estimada todo dia com os dados até t−1. O h
# escolhido aqui fica fixo na negociação.
#
# Saída: nonparametric/output/pares/pares_formados_np.csv.
# ⏱️ ~8 mil pares; dezenas de minutos (o h leave-one-out dobra o tempo: CALCULAR_H_LOO).

source("funcoes/comum.R", local = TRUE)
source("funcoes/adf.R", local = TRUE)
source("funcoes/paralelo.R", local = TRUE)
source("nonparametric/kernel_np.R", local = TRUE)
source("nonparametric/formacao_utils.R", local = TRUE)
source("nonparametric/negociacao_utils.R", local = TRUE)
source("nonparametric/especificacao_np.R", local = TRUE)
usar_pastas("nonparametric")

# ── Origem dos pares candidatos ───────────────────────────────────────────────────────
ORIGEM_PARES <- file.path(pasta_saida("cointegration", "pares"), "pares_formados_coint.csv")   # saída de cointegration/pairs_formation_coint.R

# ── Bandwidth ─────────────────────────────────────────────────────────────────────────
# Grade em unidades do desvio de Q_indep na formação; Inf = OLS (a reta entra na disputa).
GRADE_H_REL <- GRADE_H_REL_PADRAO

# Critério: 'unilateral' (padrão desde 2026-10-19) ou 'bloco' (bilateral, usa o futuro).
CRITERIO_H       <- "unilateral"
GAP_UNILATERAL   <- 20     # idade mínima do passado usado
T_MIN_UNILATERAL <- 126    # primeiro dia avaliado (~6 meses de passado)

# μ e σ do spread: 'unilateral' (erro um passo à frente) ou 'loo' (leave-one-out)
SIGMA_MODO <- "unilateral"

# Bloco excluído na CV de bloco (AR(1) mediano ≈ 0,88 → 0,88^20 ≈ 0,08)
L_BLOCO <- 20

# Diagnóstico: h do LS-CV leave-one-out (Liang, Lin & Hsiao, 2015). Dobra o tempo.
CALCULAR_H_LOO <- TRUE

N_PROCESSOS   <- max(1, parallel::detectCores() - 1)
ARQUIVO_SAIDA <- file.path(PASTA_PARES, "pares_formados_np.csv")


# ── 1. Dados ──────────────────────────────────────────────────────────────────────────
base <- carregar_base()
pares_origem <- ler_pares(ORIGEM_PARES)
cat(sprintf("Base de preços   : %s dias × %s tickers\n", milhar(nrow(base$P)), milhar(ncol(base$P))))
cat(sprintf("Pares candidatos : %s (%d janelas)\n", milhar(nrow(pares_origem)), length(unique(pares_origem$janela))))
cat(sprintf("Origem           : %s\n\n", ORIGEM_PARES))


# ── 2. Ajuste de um par ───────────────────────────────────────────────────────────────
ajustar_par <- function(par, cfg) {
  # Direção herdada da linear: 'B~A' → dependente = ativo2; 'A~B' → dependente = ativo1.
  o <- orientar(par$ativo1, par$ativo2, par$direcao)
  P <- recortar_par(base, o[["dep"]], o[["indep"]], par$formacao_inicio, par$formacao_fim)$P
  if (nrow(P) < 2 * cfg$l_bloco + 10) return(NULL)
  y <- P[, 1] / P[1, 1]; x <- P[, 2] / P[1, 2]
  sx <- desvio_pop(x)
  grade_h <- cfg$grade * sx
  cv <- switch(cfg$criterio,
               bloco = cv_bloco(x, y, grade_h, cfg$l_bloco),
               unilateral = cv_unilateral(x, y, grade_h, cfg$gap, cfg$t_min),
               stop("CRITERIO_H desconhecido: ", cfg$criterio))
  u <- switch(cfg$sigma_modo,
              loo = residuos_loo(x, y, cv$h),
              unilateral = residuos_unilaterais(x, y, cv$h, 1, cfg$t_min),
              stop("SIGMA_MODO desconhecido: ", cfg$sigma_modo))
  n_nan <- sum(!is.finite(u)); u <- u[is.finite(u)]
  b_loc <- loclin(x, x, y, cv$h)$b                      # β local nos pontos da amostra
  res <- data.frame(
    criterio_h = if (cfg$criterio == "bloco") "bloco" else paste0("unilateral_g", cfg$gap),
    sigma_modo = cfg$sigma_modo, n_resid_nan = n_nan, h = cv$h, h_rel = cv$h / sx,
    h_linear = is.infinite(cv$h), cv_mse = min(cv$mse, na.rm = TRUE),
    cv_mse_linear = cv$mse[length(cv$mse)], spread_media = mean(u), spread_desvio = desvio_pop(u),
    adf_resid = adf_estatistica(u, "AIC", "n"), beta_lin = stats::coef(stats::lm.fit(cbind(1, x), y))[[2]],
    beta_loc_p10 = stats::quantile(b_loc, 0.10, na.rm = TRUE, names = FALSE),
    beta_loc_med = stats::median(b_loc, na.rm = TRUE),
    beta_loc_p90 = stats::quantile(b_loc, 0.90, na.rm = TRUE, names = FALSE))
  if (cfg$h_loo) res$h_rel_loo <- cv_bloco(x, y, grade_h, 0)$h / sx
  res
}


# ── 3. Processando todos os pares ─────────────────────────────────────────────────────
cfg <- list(grade = GRADE_H_REL, criterio = CRITERIO_H, gap = GAP_UNILATERAL, t_min = T_MIN_UNILATERAL,
            sigma_modo = SIGMA_MODO, l_bloco = L_BLOCO, h_loo = CALCULAR_H_LOO)
COLS_ORIGEM <- c("janela", "formacao_inicio", "formacao_fim", "negociacao_inicio", "negociacao_fim",
                 "rank", "ativo1", "ativo2", "ssd", "direcao")
itens <- split(pares_origem[, COLS_ORIGEM], seq_len(nrow(pares_origem)))

cl <- iniciar_processos(N_PROCESSOS, com_base = TRUE, funcoes = list(ajustar_par = ajustar_par))
t0 <- Sys.time()
ajustes <- aplicar(cl, itens, function(par, cfg) ajustar_par(par, cfg), cfg, lote = 1000, rotulo = "pares")
encerrar_processos(cl)
ok <- !vapply(ajustes, is.null, logical(1))
pares_np <- cbind(pares_origem[ok, COLS_ORIGEM], do.call(rbind, ajustes[ok]),
                  origem = basename(ORIGEM_PARES))
rownames(pares_np) <- NULL
cat(sprintf("\nPares ajustados : %s  | sem dados suficientes: %d\n", milhar(nrow(pares_np)), sum(!ok)))
cat(sprintf("Tempo           : %.0f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))


# ── 4. Resultados — quanto de não linearidade os dados sustentam? ─────────────────────
q <- c(0.10, 0.25, 0.50, 0.75, 0.90)
fmt_q <- function(v) paste(sprintf("%.2f", stats::quantile(v, q, na.rm = TRUE)), collapse = " | ")
cat(sprintf("\nBandwidth escolhida (%s) | μ, σ: resíduo %s\n",
            if (CRITERIO_H == "bloco") sprintf("CV de bloco, L = %d pregões", L_BLOCO)
            else sprintf("CV unilateral, gap = %d, t_min = %d", GAP_UNILATERAL, T_MIN_UNILATERAL), SIGMA_MODO))
cat(sprintf("  pares em que a reta venceu (h = ∞) : %s\n", pct(mean(pares_np$h_linear), 1)))
cat(sprintf("  h/sd(x) dos demais — quantis       : %s\n", fmt_q(pares_np$h_rel[!pares_np$h_linear])))
if (CALCULAR_H_LOO) {
  cat("\nLS-CV leave-one-out (só diagnóstico)\n")
  cat(sprintf("  pares em que a reta venceu          : %s\n", pct(mean(is.infinite(pares_np$h_rel_loo)), 1)))
  cat(sprintf("  h/sd(x) — quantis                   : %s\n",
              fmt_q(pares_np$h_rel_loo[is.finite(pares_np$h_rel_loo)])))
}
ganho <- 1 - pares_np$cv_mse / pares_np$cv_mse_linear
cat(sprintf("\nRedução do erro de CV contra a reta (pares não lineares): mediana %s\n",
            pct(stats::median(ganho[!pares_np$h_linear]), 1)))
amplitude <- pares_np$beta_loc_p90 - pares_np$beta_loc_p10
cat(sprintf("Amplitude p90−p10 do β local (pares não lineares)      : mediana %.3f\n",
            stats::median(amplitude[!pares_np$h_linear])))
por_ano <- tapply(pares_np$h_linear, substr(pares_np$formacao_inicio, 1, 4), mean)
cat(sprintf("\nFração linear por ano de formação: mín %s | máx %s\n", pct(min(por_ano), 0), pct(max(por_ano), 0)))

utils::write.csv(pares_np, ARQUIVO_SAIDA, row.names = FALSE)
cat("Pares salvos em:", ARQUIVO_SAIDA, "\n")


# ── 5. Visualização ───────────────────────────────────────────────────────────────────
# Distribuição do h escolhido; e o par em que a curva mais reduziu o erro de CV: nuvem da
# formação, reta OLS, curva local linear e o hedge ratio local β(x).
ex <- pares_np[which.max(ganho), ]
o <- orientar(ex$ativo1, ex$ativo2, ex$direcao)
P <- recortar_par(base, o[["dep"]], o[["indep"]], ex$formacao_inicio, ex$formacao_fim)$P
y <- P[, 1] / P[1, 1]; x <- P[, 2] / P[1, 2]
xg <- seq(min(x), max(x), length.out = 200)
curva <- loclin(xg, x, y, ex$h)
B <- stats::coef(stats::lm.fit(cbind(1, x), y))

sufixo <- sub("\\.csv$", "", sub("pares_formados_np", "", basename(ARQUIVO_SAIDA)))
arq <- abrir_png(paste0("bandwidth_e_curva_exemplo", sufixo, ".png"), 17, 4.5)
graphics::par(mfrow = c(1, 3), mar = c(4.5, 4.5, 3, 1))
br <- seq(log10(0.04), log10(6), length.out = 30)        # escala log em h
hf <- log10(pmin(pmax(pares_np$h_rel[!pares_np$h_linear], 0.04), 6))
graphics::hist(hf, breaks = br, col = grDevices::adjustcolor("#1565C0", 0.7), border = NA, xaxt = "n",
               main = sprintf("h escolhido — reta venceu em %s (%s)", pct(mean(pares_np$h_linear), 0), CRITERIO_H),
               xlab = "h / sd(Q_indep)", ylab = "pares")
graphics::axis(1, at = log10(c(0.05, 0.1, 0.5, 1, 5)), labels = c(0.05, 0.1, 0.5, 1, 5))
if (CALCULAR_H_LOO) {
  hl <- pares_np$h_rel_loo[is.finite(pares_np$h_rel_loo)]
  graphics::hist(log10(pmin(pmax(hl, 0.04), 6)), breaks = br, add = TRUE, border = NA,
                 col = grDevices::adjustcolor("#EF6C00", 0.5))
  graphics::legend("topright", bty = "n", cex = 0.85, fill = c(grDevices::adjustcolor("#1565C0", 0.7),
                   grDevices::adjustcolor("#EF6C00", 0.5)), border = NA,
                   c(sprintf("CV %s — finito", CRITERIO_H), "LS-CV leave-one-out"))
}
plot(x, y, pch = 16, cex = 0.5, col = grDevices::adjustcolor("gray", 0.6),
     xlab = paste("Q", o[["indep"]]), ylab = paste("Q", o[["dep"]]),
     main = sprintf("%s: %s ~ g(%s)", ex$janela, o[["dep"]], o[["indep"]]))
graphics::lines(xg, B[1] + B[2] * xg, col = "#1565C0", lwd = 1.5)
graphics::lines(xg, curva$a, col = "#E65100", lwd = 2)
graphics::legend("topleft", bty = "n", cex = 0.85, col = c("#1565C0", "#E65100"), lwd = c(1.5, 2),
                 c(sprintf("OLS (β=%.2f)", B[2]), sprintf("local linear (h/sd=%.2f)", ex$h_rel)))
plot(xg, curva$b, type = "l", col = "#E65100", lwd = 2, xlab = paste("Q", o[["indep"]]),
     ylab = "hedge ratio", main = "Inclinação local = hedge ratio na entrada")
graphics::abline(h = B[2], col = "#1565C0", lty = 2)
fechar_png(arq)
