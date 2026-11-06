# -*- coding: utf-8 -*-
# ══════════════════════════════════════════════════════════════════════════════════════
#  Formação de Pares — Método da Cointegração (Rad et al., 2016)
#  Tradução de new_aproach/src/cointegration/pairs_formation_coint.ipynb
# ══════════════════════════════════════════════════════════════════════════════════════
#
# Para cada janela rolante de formação:
#   1. Filtra ativos com dados COMPLETOS no período
#   2. Normaliza preços: Q_i(t) = P_i(t) / P_i(0)
#   3. Pré-filtra os N pares de MENOR SSD como candidatos
#   4. Testa cointegração por Engle-Granger em dois passos:
#        Passo 1 — OLS: Q2 = α + β·Q1 + ε
#        Passo 2 — estacionariedade do resíduo, via METODO_COINT:
#          "ADF"  — Augmented Dickey-Fuller; cointegrado se ADF < −3.34 (MacKinnon 5%)
#          "CRDW" — Durbin-Watson da regressão de cointegração; cointegrado se
#                   DW > 0.386 × 100/T (≈0.153 para T ≈ 252)
#   5. Seleciona os top-20 pares cointegrados de menor SSD
#   6. Salva β, α, média e desvio do spread para a negociação
#
# O teste é sempre BILATERAL: as duas direções (Q2~Q1 e Q1~Q2) precisam rejeitar a raiz
# unitária, e salvam-se os parâmetros da direção mais fortemente estacionária. A coluna
# 'direcao' registra qual foi salva ('B~A' ou 'A~B').
#
# Saída: cointegration/output/pares/pares_formados_coint.csv (lido por pairs_trading_coint.R e pairs_trading_coint_dinamico.R).
# ⏱️ Com PASSO_MESES = 1 são ~409 janelas; leva alguns minutos.
# Rodar com o diretório de trabalho na pasta R/.

source("funcoes/comum.R", local = TRUE)
source("funcoes/adf.R", local = TRUE)
source("cointegration/funcoes_coint.R", local = TRUE)
usar_pastas("cointegration")

# ── Janela rolante ────────────────────────────────────────────────────────────────────
MESES_FORMACAO   <- 12  # duração do período de formação (meses)
MESES_NEGOCIACAO <- 6   # duração do período de negociação (meses)
PASSO_MESES      <- 1   # avanço da janela a cada iteração
                        #   6 → semestral, ~69 janelas (= ritmo do método da distância)
                        #   1 → mensal, ~400 janelas (= Rad et al.)

# ── Pré-filtro por distância SSD ──────────────────────────────────────────────────────
SSD_PRE_FILTER_N <- 100  # testa cointegração apenas nos N pares de menor SSD
                         # NULL → testa todos os pares válidos

# ── Seleção de pares ──────────────────────────────────────────────────────────────────
TOP_K_COINT <- 20    # máximo de pares cointegrados por janela
SSD_MIN     <- 0.01  # descarta ghost tickers (SSD ≈ 0)

# ── Teste de cointegração ─────────────────────────────────────────────────────────────
AUTOLAG_ADF  <- "AIC"   # critério de seleção de defasagens do ADF: "AIC" ou "BIC"
METODO_COINT <- "ADF"   # "ADF" (MacKinnon) ou "CRDW" (Engle-Granger 1987)

CRIT_COINT_5PCT <- -3.34   # ADF: MacKinnon 5% para resíduo de regressão de cointegração
                           #      (2 variáveis); cointegrado se stat < CRIT_COINT_5PCT
# CRDW: o crítico de tabela (0.386 a 5%, T ≈ 100) é reescalado por 100/T, porque a
# distribuição nula do CRDW escala com 1/T. Aplicar 0.386 direto a dados diários
# rejeitaria quase tudo (spreads diários são persistentes, ρ₁ ≈ 1).
CRDW_CRIT_REF_T100 <- 0.386


# ── 1. Carregando os dados ────────────────────────────────────────────────────────────
base <- carregar_base()
cat(sprintf("Dias de pregão:          %d\n", nrow(base$P)))
cat(sprintf("Ativos no universo total: %d\n", ncol(base$P)))
cat(sprintf("Período: %s até %s\n\n", base$datas[1], base$datas[length(base$datas)]))


# ── 2. Janelas temporais ──────────────────────────────────────────────────────────────
meses_unicos <- sort(unique(base$mes))
janelas <- janelas_formacao(meses_unicos, MESES_FORMACAO, MESES_NEGOCIACAO, PASSO_MESES)
cat(sprintf("Meses disponíveis: %d\n", length(meses_unicos)))
cat(sprintf("Primeiro: %s | Último: %s\n", num_mes(meses_unicos[1]), num_mes(max(meses_unicos))))
cat(sprintf("Janelas a processar: %d\n\n", length(janelas)))


# ── 3. Processando todas as janelas de formação ───────────────────────────────────────
# Para cada janela: SSD de todos os pares → SSD_PRE_FILTER_N candidatos de menor
# distância → teste de cointegração em ordem de SSD crescente, parando ao atingir
# TOP_K_COINT pares cointegrados.
cat(sprintf("Teste de cointegração: %s | bilateral (ambas as direções)\n\n", METODO_COINT))
t0 <- Sys.time()
resultados <- list()
for (jn in janelas) {
  form_inicio <- num_mes(jn$form[1]); form_fim <- num_mes(jn$form[length(jn$form)])
  neg_inicio  <- num_mes(jn$neg[1]);  neg_fim  <- num_mes(jn$neg[length(jn$neg)])
  janela_id   <- paste0(form_inicio, "_a_", form_fim)

  precos <- filtrar_ativos_completos(base$P[base$mes %in% jn$form, , drop = FALSE])
  if (ncol(precos) < 2) {
    cat(janela_id, ": sem ativos suficientes, pulando.\n")
    next
  }
  Q <- normalizar_precos(precos)
  candidatos <- candidatos_ssd(calcular_ssd(Q), SSD_PRE_FILTER_N, SSD_MIN)

  n_coint <- 0
  for (k in seq_len(nrow(candidatos))) {
    a1 <- candidatos$ativo1[k]; a2 <- candidatos$ativo2[k]
    res <- testar_cointegracao(Q[, a1], Q[, a2])
    if (!res$cointegrado) next
    n_coint <- n_coint + 1
    resultados[[length(resultados) + 1]] <- data.frame(
      janela = janela_id, formacao_inicio = form_inicio, formacao_fim = form_fim,
      negociacao_inicio = neg_inicio, negociacao_fim = neg_fim, rank = n_coint,
      ativo1 = a1, ativo2 = a2, ssd = candidatos$ssd[k], beta = res$beta, alpha = res$alpha,
      spread_media = res$spread_media, spread_desvio = res$spread_desvio, stat = res$stat,
      direcao = res$direcao, metodo = METODO_COINT, stringsAsFactors = FALSE)
    if (n_coint >= TOP_K_COINT) break
  }

  cat(sprintf("%s: %3d ativos | %4d testados | %2d cointegrados\n",
              janela_id, ncol(precos), nrow(candidatos), n_coint))
}
pares_df <- do.call(rbind, resultados)
cat(sprintf("\nTempo de execução: %.0fs\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))


# ── 4. Resultados ─────────────────────────────────────────────────────────────────────
n_jan <- length(unique(pares_df$janela))
cat(sprintf("\nMétodo (sempre bilateral):    %s\n", METODO_COINT))
cat(sprintf("Janelas processadas:          %d\n", n_jan))
cat(sprintf("Pares registrados:            %d\n", nrow(pares_df)))
cat(sprintf("Pares por janela (média):     %.1f\n", nrow(pares_df) / n_jan))
cat(sprintf("Janelas com %d pares cheios:   %s\n", TOP_K_COINT,
            pct(mean(tapply(pares_df$rank, pares_df$janela, max) >= TOP_K_COINT), 1)))
cat(sprintf("Estatística média (%s):     %.3f\n", METODO_COINT, mean(pares_df$stat)))
cat(sprintf("Direção salva — B~A: %s | A~B: %s\n\n",
            pct(mean(pares_df$direcao == "B~A"), 1), pct(mean(pares_df$direcao == "A~B"), 1)))

arq <- file.path(pasta_saida("cointegration", "pares"), "pares_formados_coint.csv")
utils::write.csv(pares_df, arq, row.names = FALSE)
cat("Pares salvos em:", arq, "\n\n")

cat("Pares da primeira janela:\n")
print(pares_df[pares_df$janela == pares_df$janela[1], ], row.names = FALSE)


# ── 5. Visualização: trajetórias e spreads de cointegração ────────────────────────────
# Primeira janela, primeira janela de 2019 (COVID) e última; top-3 pares de cada.
# Linha de cima: Q1(t) e Q2(t). Linha de baixo: ε_t = Q_dep − α − β·Q_indep com μ ± 2σ.
JANELAS_ALVO <- unique(c(pares_df$janela[1],
                         pares_df$janela[startsWith(pares_df$formacao_inicio, "2019")][1],
                         pares_df$janela[nrow(pares_df)]))
JANELAS_ALVO <- JANELAS_ALVO[!is.na(JANELAS_ALVO)]
N_PARES <- 3

arq <- abrir_png("pares_coint_visualizacao.png", 5 * N_PARES, 3.5 * 2 * length(JANELAS_ALVO))
graphics::par(mfrow = c(2 * length(JANELAS_ALVO), N_PARES), mar = c(3, 4, 3, 1))
for (janela_id in JANELAS_ALVO) {
  pj <- head(pares_df[pares_df$janela == janela_id, ], N_PARES)
  linhas <- linhas_periodo(base, pj$formacao_inicio[1], pj$formacao_fim[1])
  Q <- normalizar_precos(filtrar_ativos_completos(base$P[linhas, , drop = FALSE]))
  datas <- base$datas[linhas]
  for (k in seq_len(N_PARES)) {
    if (k > nrow(pj)) { plot.new(); next }
    a1 <- pj$ativo1[k]; a2 <- pj$ativo2[k]
    plot(datas, Q[, a1], type = "l", col = "#2196F3", lwd = 1.6, ylim = range(Q[, c(a1, a2)]),
         xlab = "", ylab = "Q(t) = P(t)/P(0)", cex.main = 0.85,
         main = sprintf("%s\n%s / %s   β=%.3f   %s=%.2f   [%s]", janela_id, a1, a2,
                        pj$beta[k], pj$metodo[k], pj$stat[k], pj$direcao[k]))
    graphics::lines(datas, Q[, a2], col = "#FF5722", lwd = 1.6, lty = 2)
    graphics::abline(h = 1, col = "gray", lty = 3)
    graphics::legend("topleft", c(a1, a2), col = c("#2196F3", "#FF5722"), lty = 1:2, bty = "n", cex = 0.8)
  }
  for (k in seq_len(N_PARES)) {
    if (k > nrow(pj)) { plot.new(); next }
    o <- orientar(pj$ativo1[k], pj$ativo2[k], pj$direcao[k])
    mu <- pj$spread_media[k]; sg <- pj$spread_desvio[k]
    s <- Q[, o[["dep"]]] - pj$alpha[k] - pj$beta[k] * Q[, o[["indep"]]]
    plot(datas, s, type = "l", col = "purple", lwd = 1.3, xlab = "",
         ylab = sprintf("ε = %s − α − β·%s", o[["dep"]], o[["indep"]]),
         ylim = range(c(s, mu + c(-2, 2) * sg)))
    graphics::rect(min(datas), mu - 2 * sg, max(datas), mu + 2 * sg,
                   col = grDevices::adjustcolor("red", 0.08), border = NA)
    graphics::abline(h = mu, col = "black")
    graphics::abline(h = mu + c(-2, 2) * sg, col = "red", lty = 2)
  }
}
fechar_png(arq)
