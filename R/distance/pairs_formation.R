# -*- coding: utf-8 -*-
# ══════════════════════════════════════════════════════════════════════════════════════
#  Formação de Pares — Método da Distância (Gatev et al., 2006)
#  Tradução de new_aproach/src/distance/pairs_formation.ipynb
# ══════════════════════════════════════════════════════════════════════════════════════
#
# Para cada janela rolante de formação:
#   1. Filtra ativos com dados COMPLETOS no período
#   2. Normaliza preços: Q_i(t) = P_i(t) / P_i(0) — todos partem de 1
#   3. Mede a distância SSD entre todos os pares: D(i,j) = Σ (Q_i(t) − Q_j(t))²
#   4. Seleciona os top-20 pares de menor distância
#   5. Salva a média e o desvio do spread para uso na fase de negociação
#
# As janelas são definidas em meses calendário, com os mesmos parâmetros do método da
# cointegração — assim os dois métodos podem ser comparados janela a janela.
#
# Saída: distance/output/pares/pares_formados.csv (lido por pairs_trading.R e pairs_trading_dinamico.R).
# Rodar com o diretório de trabalho na pasta R/.

source("funcoes/comum.R", local = TRUE)
usar_pastas("distance")

# ── Janela rolante ────────────────────────────────────────────────────────────────────
MESES_FORMACAO   <- 12  # duração do período de formação (meses)
MESES_NEGOCIACAO <- 6   # duração do período de negociação (meses)
PASSO_MESES      <- 6   # avanço da janela a cada iteração
                        #   6 → semestral, ~69 janelas (ritmo original de Gatev et al.)
                        #   1 → mensal, ~400 janelas (= Rad et al.)

# ── Seleção de pares ──────────────────────────────────────────────────────────────────
TOP_K   <- 20    # pares selecionados por janela
SSD_MIN <- 0.01  # SSD mínimo aceito — ghost tickers (preços idênticos) têm SSD ≈ 0;
                 # pares reais têm SSD ~ 0.05–0.5

# ── Filtro de universo: preço mínimo ──────────────────────────────────────────────────
# Descarta o ticker da janela se o preço MÍNIMO durante a FORMAÇÃO for menor que
# PRECO_MIN. Usa só a formação: filtro de universo investível, SEM look-ahead.
# Elimina penny stocks com preço corrompido (AVATQ ~US$ 0,0001; PNAA ~US$ 0,08), que sem
# este corte produzem dias de +285% no portfólio. Do & Faff (2012) e Rad et al. (2016)
# usam preço ≥ $1. NULL = sem filtro.
PRECO_MIN <- 1.0

filtrar_preco_minimo <- function(precos, preco_min = PRECO_MIN) {
  if (is.null(preco_min)) return(precos)
  precos[, apply(precos, 2, min) >= preco_min, drop = FALSE]
}


# ── 1. Carregando os dados ────────────────────────────────────────────────────────────
base <- carregar_base()
cat(sprintf("Dias de pregão: %d\n", nrow(base$P)))
cat(sprintf("Ativos no universo total: %d\n", ncol(base$P)))
cat(sprintf("Período: %s até %s\n\n", base$datas[1], base$datas[length(base$datas)]))


# ── 2. Janelas temporais ──────────────────────────────────────────────────────────────
meses_unicos <- sort(unique(base$mes))
janelas <- janelas_formacao(meses_unicos, MESES_FORMACAO, MESES_NEGOCIACAO, PASSO_MESES)
cat(sprintf("Meses disponíveis: %d\n", length(meses_unicos)))
cat(sprintf("Primeiro: %s | Último: %s\n", num_mes(meses_unicos[1]), num_mes(max(meses_unicos))))
cat(sprintf("Janelas a processar: %d\n\n", length(janelas)))


# ── 3. Processando todas as janelas de formação ───────────────────────────────────────
resultados <- list()
for (jn in janelas) {
  form_inicio <- num_mes(jn$form[1]); form_fim <- num_mes(jn$form[length(jn$form)])
  neg_inicio  <- num_mes(jn$neg[1]);  neg_fim  <- num_mes(jn$neg[length(jn$neg)])
  janela_id   <- paste0(form_inicio, "_a_", form_fim)

  # Recorta a formação e mantém só ativos com dados completos
  precos <- filtrar_ativos_completos(base$P[base$mes %in% jn$form, , drop = FALSE])

  # Filtro de universo investível (olha apenas a janela de formação)
  n_antes_preco <- ncol(precos)
  precos <- filtrar_preco_minimo(precos)
  n_cortados <- n_antes_preco - ncol(precos)

  if (ncol(precos) < 2) {
    cat(janela_id, ": sem ativos suficientes, pulando.\n")
    next
  }

  # Normaliza, calcula distâncias e seleciona pares
  Q   <- normalizar_precos(precos)
  top <- candidatos_ssd(calcular_ssd(Q), TOP_K, SSD_MIN)

  # Média e desvio-padrão do spread na formação
  for (k in seq_len(nrow(top))) {
    spread <- Q[, top$ativo1[k]] - Q[, top$ativo2[k]]
    resultados[[length(resultados) + 1]] <- data.frame(
      janela = janela_id, formacao_inicio = form_inicio, formacao_fim = form_fim,
      negociacao_inicio = neg_inicio, negociacao_fim = neg_fim, rank = k,
      ativo1 = top$ativo1[k], ativo2 = top$ativo2[k], ssd = top$ssd[k],
      spread_media = mean(spread), spread_desvio = sd(spread),
      stringsAsFactors = FALSE)
  }

  cat(sprintf("%s: %4d ativos (-%d por preço < US$ %g) — negociação %s → %s\n",
              janela_id, ncol(precos), n_cortados, PRECO_MIN, neg_inicio, neg_fim))
}
pares_df <- do.call(rbind, resultados)


# ── 4. Resultados ─────────────────────────────────────────────────────────────────────
n_jan <- length(unique(pares_df$janela))
cat(sprintf("\nJanelas processadas:  %d\n", n_jan))
cat(sprintf("Pares registrados:    %d\n", nrow(pares_df)))
cat(sprintf("Pares por janela:     %.1f\n\n", nrow(pares_df) / n_jan))

arq <- file.path(PASTA_PARES, "pares_formados.csv")
utils::write.csv(pares_df, arq, row.names = FALSE)
cat("Pares salvos em:", arq, "\n\n")

cat("Pares da primeira janela:\n")
print(pares_df[pares_df$janela == pares_df$janela[1], ], row.names = FALSE)


# ── 5. Visualização: trajetórias normalizadas dos pares selecionados ──────────────────
# Janelas pré-crise financeira (formação até 2008-06), COVID (até 2020-06) e recente
# (até 2024-06); top-3 pares de cada. Linha de cima: Q_i(t) e Q_j(t). Linha de baixo:
# spread com banda μ ± 2σ.
FORMACAO_FIM_ALVO <- c("2008-06", "2020-06", "2024-06")
JANELAS_ALVO <- unique(pares_df$janela[pares_df$formacao_fim %in% FORMACAO_FIM_ALVO])
if (length(JANELAS_ALVO) == 0) JANELAS_ALVO <- pares_df$janela[1]
N_PARES     <- 3
SSD_MIN_VIZ <- 1e-5

arq <- abrir_png("pares_visualizacao.png", 5 * N_PARES, 3.5 * 2 * length(JANELAS_ALVO))
graphics::par(mfrow = c(2 * length(JANELAS_ALVO), N_PARES), mar = c(3, 4, 3, 1))
for (janela_id in JANELAS_ALVO) {
  pj <- head(pares_df[pares_df$janela == janela_id & pares_df$ssd >= SSD_MIN_VIZ, ], N_PARES)
  linhas <- linhas_periodo(base, pj$formacao_inicio[1], pj$formacao_fim[1])
  Q <- normalizar_precos(filtrar_ativos_completos(base$P[linhas, , drop = FALSE]))
  datas <- base$datas[linhas]
  # painéis de cima (preços) e de baixo (spread), coluna a coluna
  for (k in seq_len(N_PARES)) {
    if (k > nrow(pj)) { plot.new(); next }
    a1 <- pj$ativo1[k]; a2 <- pj$ativo2[k]
    plot(datas, Q[, a1], type = "l", col = "#2196F3", lwd = 1.6,
         ylim = range(Q[, c(a1, a2)]), xlab = "", ylab = "Q(t) = P(t)/P(0)",
         main = sprintf("%s\n%s / %s   SSD = %.4f", janela_id, a1, a2, pj$ssd[k]), cex.main = 0.85)
    graphics::lines(datas, Q[, a2], col = "#FF5722", lwd = 1.6, lty = 2)
    graphics::abline(h = 1, col = "gray", lty = 3)
    graphics::legend("topleft", c(a1, a2), col = c("#2196F3", "#FF5722"), lty = 1:2, bty = "n", cex = 0.8)
  }
  for (k in seq_len(N_PARES)) {
    if (k > nrow(pj)) { plot.new(); next }
    a1 <- pj$ativo1[k]; a2 <- pj$ativo2[k]
    mu <- pj$spread_media[k]; sg <- pj$spread_desvio[k]
    s <- Q[, a1] - Q[, a2]
    plot(datas, s, type = "l", col = "purple", lwd = 1.3, xlab = "",
         ylab = "Spread Qi - Qj", ylim = range(c(s, mu + c(-2, 2) * sg)))
    graphics::rect(min(datas), mu - 2 * sg, max(datas), mu + 2 * sg,
                   col = grDevices::adjustcolor("red", 0.08), border = NA)
    graphics::abline(h = mu, col = "black")
    graphics::abline(h = mu + c(-2, 2) * sg, col = "red", lty = 2)
  }
}
fechar_png(arq)
