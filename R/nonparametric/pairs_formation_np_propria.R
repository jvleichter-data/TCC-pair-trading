# -*- coding: utf-8 -*-
# ══════════════════════════════════════════════════════════════════════════════════════
#  Formação de Pares Própria — Cointegração Não Paramétrica (kernel local linear)
#  Tradução de new_aproach/src/nonparametric/pairs_formation_np_propria.ipynb
# ══════════════════════════════════════════════════════════════════════════════════════
#
# O par entra se houver equilíbrio ao longo da CURVA, testado com o valor crítico calibrado
# para o nosso procedimento (nonparametric/valor_critico_np.R). Em cada janela de formação (12 meses,
# passo mensal):
#
#   0  valor crítico simulado (valor_critico_np.R) MacKinnon (1991, 2010): tabelas de cointegração são
#                                         simulação; Phillips (2009): a curva "inventa"
#                                         cointegração, a tabela de −3,34 não vale
#   1  universo: dados completos na janela, sem mesmo emissor (igual à linear)
#   2  Q = P/P0
#   3  pré-filtro: os N_PRE_SSD pares de menor SSD (Rad, Low & Faff 2016 § 4.2); N maior que
#      os 100 da linear, para dar espaço a relações curvas
#   4  curva nas DUAS direções; fica a de menor erro de CV relativo (a curva não é simétrica)
#   5  teste: ADF dos erros fora da amostra < valor crítico simulado
#   6  filtro de hedge: mediana do β local ≥ 0,50 (= piso de β da negociação)
#   7  ranking → top 20 ('ssd': em ordem de SSD até 20 aprovados, como a linear; ou 'adf')
#
# Não usamos o teste de Wang & Phillips (2012) para selecionar: ele testa a FORMA da relação
# supondo que ela exista, e premiaria pares quebrados (DECISOES.md § 8).
#
# Saída: nonparametric/output/pares/pares_formados_np_propria.csv (+ _log.csv), lido por 10.
# ⏱️ ~74 mil testes de cointegração; cerca de 1 h com 3 processos (o kernel em R é mais
# lento que no numpy — o exp do R não é vetorizado).

source("funcoes/comum.R", local = TRUE)
source("funcoes/adf.R", local = TRUE)
source("funcoes/paralelo.R", local = TRUE)
source("nonparametric/kernel_np.R", local = TRUE)
source("nonparametric/formacao_utils.R", local = TRUE)
source("nonparametric/negociacao_utils.R", local = TRUE)
source("nonparametric/especificacao_np.R", local = TRUE)
usar_pastas("nonparametric")

# ── Janelas (iguais às dos outros métodos) ────────────────────────────────────────────
MESES_FORMACAO   <- 12
MESES_NEGOCIACAO <- 6
PASSO_MESES      <- 1

# ── Seleção ───────────────────────────────────────────────────────────────────────────
N_PRE_SSD    <- 300     # candidatos por janela (linear: 100)
TOP_K        <- 20      # pares por janela (Rad et al. 2016)
SSD_MIN      <- 0.01    # ghost tickers (igual à linear)
RANKING      <- "ssd"   # 'ssd': em ordem de SSD, para nos TOP_K aprovados (como a linear)
                        # 'adf': testa todos e fica com as TOP_K estatísticas mais negativas
BETA_MED_MIN <- 0.50    # mediana do β local na formação (= piso de β da negociação)

# ── Teste (TEM de ser igual ao da simulação do valor crítico) ─────────────────────────
GRADE_H_REL      <- GRADE_H_REL_PADRAO
GAP_UNILATERAL   <- 20
T_MIN_UNILATERAL <- 126
AUTOLAG_ADF      <- "AIC"
NIVEL            <- "5%"
# JSON do valor crítico: o gerado por valor_critico_np.R em R (padrão) ou, para reproduzir exatamente os
# pares do TCC, o do notebook Python:
#   ARQ_CRITICO <- "../new_aproach/src/nonparametric/output/valor_critico/valor_critico_np.json"
ARQ_CRITICO <- file.path(pasta_saida("nonparametric", "valor_critico"), "valor_critico_np.json")

# ── Execução e saída ──────────────────────────────────────────────────────────────────
N_PROCESSOS    <- max(1, parallel::detectCores() - 1)   # janelas em paralelo (1 = serial)
LIMITE_JANELAS <- NULL   # só para testes: processa as primeiras N janelas
ARQUIVO_SAIDA  <- file.path(PASTA_PARES, "pares_formados_np_propria.csv")


# ── 1. Valor crítico e conferência do procedimento ────────────────────────────────────
crit_json <- ler_valor_critico(ARQ_CRITICO)
stopifnot("O procedimento difere do usado na simulação: rode nonparametric/valor_critico_np.R de novo." =
            isTRUE(all.equal(crit_json$grade_h_rel, GRADE_H_REL)) &&
            crit_json$gap_unilateral == GAP_UNILATERAL &&
            crit_json$t_min_unilateral == T_MIN_UNILATERAL &&
            crit_json$autolag_adf == AUTOLAG_ADF)
CRIT <- crit_json$valor_critico[[NIVEL]]
cat(sprintf("Valor crítico (%s, nula '%s', gerado em %s): %.3f\n", NIVEL, crit_json$nula_principal,
            crit_json$gerado_em, CRIT))
cat(sprintf("Para comparação: Engle–Granger 5%% = −3,34; a tabela aprovaria %s dos pares SEM cointegração.\n",
            pct(crit_json$falso_positivo_com_EG_334, 1)))


# ── 2. Dados e janelas ────────────────────────────────────────────────────────────────
base <- carregar_base()
janelas <- janelas_formacao(sort(unique(base$mes)), MESES_FORMACAO, MESES_NEGOCIACAO, PASSO_MESES)
if (!is.null(LIMITE_JANELAS)) janelas <- janelas[seq_len(LIMITE_JANELAS)]
cat(sprintf("Janelas: %d (%s → %s)\n\n", length(janelas), num_mes(janelas[[1]]$form[1]),
            num_mes(max(janelas[[length(janelas)]]$neg))))


# ── 3. Seleção em todas as janelas ────────────────────────────────────────────────────
# A lógica de cada janela está em seleciona_pares_janela (nonparametric/formacao_utils.R).
params <- list(n_pre_ssd = N_PRE_SSD, ssd_min = SSD_MIN, grade_rel = GRADE_H_REL,
               gap = GAP_UNILATERAL, t_min = T_MIN_UNILATERAL, autolag = AUTOLAG_ADF,
               crit = CRIT, beta_med_min = BETA_MED_MIN, top_k = TOP_K, ranking = RANKING)

roda_janela <- function(jn, p) {
  Q <- normalizar_precos(filtrar_ativos_completos(base$P[base$mes %in% jn$form, , drop = FALSE]))
  c(seleciona_pares_janela(Q, p), n_ativos = ncol(Q))
}

cl <- iniciar_processos(N_PROCESSOS, com_base = TRUE)
t0 <- Sys.time()
saidas <- aplicar(cl, janelas, roda_janela, params, lote = 25, rotulo = "janelas")
encerrar_processos(cl)
cat(sprintf("Tempo: %.0f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))

info_janela <- function(jn, n_ativos) data.frame(
  janela = paste0(num_mes(jn$form[1]), "_a_", num_mes(max(jn$form))),
  formacao_inicio = num_mes(jn$form[1]), formacao_fim = num_mes(max(jn$form)),
  negociacao_inicio = num_mes(jn$neg[1]), negociacao_fim = num_mes(max(jn$neg)),
  n_ativos = n_ativos, stringsAsFactors = FALSE)
resultados <- list(); logs <- list()
for (k in seq_along(janelas)) {
  info <- info_janela(janelas[[k]], saidas[[k]]$n_ativos)
  logs[[k]] <- cbind(info, saidas[[k]]$log)
  if (!is.null(saidas[[k]]$sel))
    resultados[[k]] <- cbind(info, rank = seq_len(nrow(saidas[[k]]$sel)), saidas[[k]]$sel)
}


# ── 4. Salvando no formato da negociação ──────────────────────────────────────────────
# spread_media e spread_desvio são a média e o desvio dos erros um passo à frente; adf_np é a
# estatística do teste.
pares <- do.call(rbind, resultados)
names(pares)[match(c("mu", "sigma", "stat", "cv_rel", "cv_rel_linear"), names(pares))] <-
  c("spread_media", "spread_desvio", "adf_np", "cv_mse", "cv_mse_linear")
pares$origem <- "propria"
pares$criterio_h <- paste0("unilateral_g", GAP_UNILATERAL)
pares$sigma_modo <- "unilateral"
pares$valor_critico <- CRIT
log_df <- do.call(rbind, logs)
utils::write.csv(pares, ARQUIVO_SAIDA, row.names = FALSE)
utils::write.csv(log_df, sub("\\.csv$", "_log.csv", ARQUIVO_SAIDA), row.names = FALSE)
cat(sprintf("Pares: %s em %d janelas → %s\n", milhar(nrow(pares)), length(unique(pares$janela)), ARQUIVO_SAIDA))


# ── 5. Diagnóstico ────────────────────────────────────────────────────────────────────
cat(sprintf("\nPares por janela: média %.1f | janelas com %d: %s | janelas vazias: %d\n",
            mean(log_df$n_selecionados), TOP_K, pct(mean(log_df$n_selecionados >= TOP_K), 1),
            sum(log_df$n_selecionados == 0)))
cat(sprintf("Candidatos testados: %s | aprovados no teste: %s | aprovados também no filtro de β: %s\n",
            milhar(sum(log_df$n_testados)), pct(sum(log_df$n_coint) / sum(log_df$n_testados), 1),
            pct(sum(log_df$n_aprovados) / max(sum(log_df$n_coint), 1), 1)))
cat(sprintf("Reta escolhida (h = ∞) entre os selecionados: %s\n", pct(mean(pares$h_linear), 1)))
cat(sprintf("Estatística ADF dos selecionados: mediana %.2f (valor crítico %.2f)\n",
            stats::median(pares$adf_np), CRIT))

# Sobreposição com os pares da formação linear (mesma janela, mesmo par sem ordem)
arq_lin <- file.path(pasta_saida("cointegration", "pares"), "pares_formados_coint.csv")
if (file.exists(arq_lin)) {
  lin <- ler_pares(arq_lin)
  chave <- function(d) paste(d$janela, pmin(d$ativo1, d$ativo2), pmax(d$ativo1, d$ativo2), sep = "|")
  comum <- intersect(chave(pares), chave(lin))
  cat(sprintf("Pares também escolhidos pela formação linear: %s (%s de %s)\n",
              pct(length(comum) / nrow(pares), 1), milhar(length(comum)), milhar(nrow(pares))))
}

arq <- abrir_png("formacao_propria_diagnostico.png", 13, 3.8)
graphics::par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
datas <- as.Date(paste0(log_df$negociacao_inicio, "-01"))
plot(datas, log_df$n_selecionados, type = "l", col = "#E65100", xlab = "", ylab = "",
     main = "Pares selecionados por janela")
graphics::abline(h = TOP_K, col = "gray", lty = 2)
graphics::hist(pares$adf_np, breaks = 40, col = grDevices::adjustcolor("#E65100", 0.7), border = NA,
               main = "Estatística do teste nos pares selecionados", xlab = "", ylab = "")
graphics::abline(v = CRIT, lwd = 1.2)
fechar_png(arq)
