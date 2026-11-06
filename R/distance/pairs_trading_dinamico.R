# -*- coding: utf-8 -*-
# ══════════════════════════════════════════════════════════════════════════════════════
#  Negociação de Pares — Distância DINÂMICA (banda re-estimada no sinal)
#  Tradução de new_aproach/src/distance/pairs_trading_dinamico.ipynb
# ══════════════════════════════════════════════════════════════════════════════════════
#
# Variante de distance/pairs_trading.R. A formação é IDÊNTICA (mesmo pares_formados.csv);
# o que muda é o que acontece no instante do sinal. No dia do sinal o spread s = Q1 − Q2 é
# RE-MEDIDO com toda a informação disponível até aquele dia — a formação inteira mais o
# trecho já decorrido da negociação. Se o par já não se parece com um par (a SSD por dia
# explodiu), o trade não é aberto; se ainda se parece, abre contra a banda re-estimada.
#
# Três canais, cada um com seu parâmetro:
#   Gatilho      MODO_BANDA          'formacao': mesmo sinal do estático
#                                    'movel'   : banda ±δ·σ_t recalculada todo dia
#   Veto         MAX_RAZAO_SSD       recusa o sinal se o par se afastou demais
#   Alvo saída   FECHA_NO_CRUZAMENTO TRUE: sai em s = 0 (não depende de μ e σ)
#                                    FALSE: sai em s = μ re-estimado
#
# Com o default ('formacao' + MAX_RAZAO_SSD + saída no cruzamento) o dinâmico é um filtro
# estrito sobre os trades do estático: pode recusar trades, nunca inventar.
#
# O P&L não muda de convenção: buy-and-hold marcado a mercado de $1 / $1, como no estático.
# Sem look-ahead: a re-estimação em t usa dados até t inclusive, e a posição só produz
# P&L a partir de t+1.
# Rodar com o diretório de trabalho na pasta R/ (depois de pairs_formation.R e pairs_trading.R).

source("funcoes/comum.R", local = TRUE)
source("distance/funcoes_distancia.R", local = TRUE)
usar_pastas("distance")

# ══════════════════════════════════════════════════════════════════════════════════════
#  Parâmetros herdados do estático — mantidos iguais de propósito.
# ══════════════════════════════════════════════════════════════════════════════════════
DELTA     <- 2.0    # gatilho de entrada: |z| > DELTA
STOP      <- NULL   # stop-loss (NULL = desativado, como em Gatev)
SIGMA_MIN <- 0.01   # exclui pares com sigma patológico

MAX_RETORNO_DIA <- 0.90   # spike positivo extremo (LOOK-AHEAD; efeito medido 0,000 p.p.)

# TRUE  — fecha quando os preços normalizados CRUZAM (spread = 0). Esse nível não depende
#         de μ nem de σ: com TRUE a re-estimação NÃO move o alvo de saída.
# FALSE — fecha quando o spread volta ao μ RE-ESTIMADO do trade em curso.
FECHA_NO_CRUZAMENTO <- TRUE

# Só para o autoteste contra o estático (simular_par_dist); o dinâmico implementa o caso
# k = 0 e μ da formação.
LIMIAR_FECHAMENTO <- 0.0
USAR_MEDIA_SPREAD <- TRUE

COMMITTED_CAPITAL <- TRUE   # TRUE → denominador = N pares fixo (inativos contribuem 0)

PERIODO_INICIO <- NULL
PERIODO_FIM    <- "2015-12"

# ══════════════════════════════════════════════════════════════════════════════════════
#  RE-ESTIMAÇÃO DINÂMICA
# ══════════════════════════════════════════════════════════════════════════════════════
# Amostra da re-estimação:
#   NULL → EXPANDING desde o 1º dia da FORMAÇÃO (T ≈ 252 → ≈ 378 ao longo da negociação)
#   int  → ROLLING dos últimos N pregões (252 ≈ 12 meses)
JANELA_REESTIMACAO <- NULL

# Observações mínimas para a re-estimação valer.
MIN_OBS_REESTIMACAO <- 30

# Quem dispara o sinal: 'formacao' (z da formação, como no estático) ou 'movel'
# (banda ±δ·σ_t recalculada todo dia com a amostra que termina em t).
MODO_BANDA <- "formacao"

# Quando re-testar, estando fora do mercado:
#   'diario'     → todo dia em que |z| > δ (a regra do estático; é o modo em que a ÚNICA
#                  diferença entre os dois é a re-estimação)
#   'cruzamento' → só no dia em que |z| atravessa δ vindo de dentro da banda
RETESTE_MODO <- "diario"

# Revalidação "este par ainda é um par?": SSD por dia, ssd_dia = (1/T)·Σ (Q1 − Q2)² = μ² + σ²
# (populacional) — capta deriva do nível e alargamento da dispersão num só número.
#   MAX_RAZAO_SSD = k → veta o sinal se ssd_dia(sinal) / ssd_dia(formação) > k
#   4.0 ⇒ a distância típica entre as trajetórias dobrou; NULL desliga a revalidação.
MAX_RAZAO_SSD <- 4.0

# Dupla confirmação (só em MODO_BANDA = 'formacao'): exige |z| > DELTA também com os
# parâmetros NOVOS.
EXIGE_Z_REESTIMADO <- TRUE


# ── 1. Carregando os dados ────────────────────────────────────────────────────────────
pares_raw <- ler_pares(file.path(PASTA_PARES, "pares_formados.csv"))
base      <- carregar_base()
pares     <- filtrar_periodo(pares_raw, PERIODO_INICIO, PERIODO_FIM)
imprimir_cabecalho_pares(pares_raw, pares, base, PERIODO_INICIO, PERIODO_FIM)


# ── 2. Re-estimação do spread ─────────────────────────────────────────────────────────
reestimar_spread <- function(q1, q2, ssd_dia_form = NA, max_razao = NULL,
                             min_obs = MIN_OBS_REESTIMACAO) {
  # Re-mede o spread s = Q1 − Q2 sobre UMA amostra (a que termina no dia do sinal).
  # Retorna list(valido, mu, sigma, ssd_dia, razao_ssd).
  s <- q1 - q2
  if (length(s) < min_obs || !all(is.finite(s)))
    return(list(valido = FALSE, mu = NA, sigma = NA, ssd_dia = NA, razao_ssd = NA))
  mu <- mean(s); sigma <- sd(s); ssd_dia <- mean(s^2)
  razao <- if (is.finite(ssd_dia_form) && ssd_dia_form > 0) ssd_dia / ssd_dia_form else NA
  valido <- !(!is.null(max_razao) && is.finite(razao) && razao > max_razao)
  list(valido = valido, mu = mu, sigma = sigma, ssd_dia = ssd_dia, razao_ssd = razao)
}

parametros_moveis <- function(s, g, janela = NULL, min_obs = MIN_OBS_REESTIMACAO) {
  # μ_t, σ_t e SSD/dia_t nos dias g, cada um sobre a amostra que termina em t inclusive.
  # janela = NULL → expanding; int → rolling. Menos de min_obs observações → NA.
  out <- t(vapply(g, function(t) {
    ini <- if (is.null(janela)) 1L else max(1L, t - janela + 1L)
    x <- s[ini:t]
    if (length(x) < min_obs) c(NA, NA, NA, length(x))
    else c(mean(x), sd(x), mean(x^2), length(x))
  }, numeric(4)))
  colnames(out) <- c("mu", "sigma", "ssd", "n")
  out
}


# ── 3. Simulação de um par com re-estimação no sinal ──────────────────────────────────
simular_par_dist_dinamico <- function(precos_form, precos_neg, mu, sigma,
                                      delta = DELTA, stop = STOP, janela = JANELA_REESTIMACAO,
                                      modo = RETESTE_MODO, modo_banda = MODO_BANDA,
                                      max_razao = MAX_RAZAO_SSD, exige_z = EXIGE_Z_REESTIMADO,
                                      fecha_no_cruzamento = FECHA_NO_CRUZAMENTO,
                                      sigma_min = SIGMA_MIN) {
  # Convenção de sinal (idêntica ao estático):
  #   −1 → z > +δ: vende ativo1, compra ativo2 ;  +1 → z < −δ: compra ativo1, vende ativo2
  # max_razao = NULL desliga a revalidação.
  # Retorna list(df, info) ou NULL se o par não puder ser simulado.
  if (sigma == 0 || !is.finite(sigma)) return(NULL)

  # Série contínua formação + negociação, normalizada pelo 1º preço da FORMAÇÃO
  T_form <- nrow(precos_form)
  Q_all <- sweep(rbind(precos_form, precos_neg), 2, precos_form[1, ], "/")
  s_all <- Q_all[, 1] - Q_all[, 2]
  g_neg <- T_form + seq_len(nrow(precos_neg))
  n <- length(g_neg)

  # Referência da revalidação: SSD por dia na FORMAÇÃO, na própria série normalizada
  ssd_dia_form <- mean(s_all[seq_len(T_form)]^2)

  pm <- parametros_moveis(s_all, g_neg, janela)
  mu_t <- pm[, "mu"]; sg_t <- pm[, "sigma"]; ssd_t <- pm[, "ssd"]; nobs_t <- pm[, "n"]

  z_mon <- (s_all[g_neg] - mu) / sigma            # z de MONITORAMENTO (formação)
  z_mov <- (s_all[g_neg] - mu_t) / sg_t           # z MÓVEL (banda recalculada)
  z_gat <- if (modo_banda == "movel") z_mov else z_mon

  r1 <- retornos_simples(precos_neg[, 1])
  r2 <- retornos_simples(precos_neg[, 2])

  positions <- numeric(n); positions_lag <- numeric(n); retorno <- numeric(n)
  peso_long <- numeric(n); peso_shrt <- numeric(n)
  z_trade <- rep(NA_real_, n); mu_vig <- rep(NA_real_, n); sigma_vig <- rep(NA_real_, n)

  pos <- 0; par_viv <- NULL; z_hoje <- NA; wL <- 1; wS <- 1
  ev <- list(); n_sinais <- 0; n_aprov <- 0; n_rej_ssd <- 0; n_rej_sigma <- 0; n_rej_z <- 0
  sig_ab <- numeric(0); mu_ab <- numeric(0); raz_ab <- numeric(0)

  for (k in seq_len(n)) {
    g <- g_neg[k]
    positions_lag[k] <- pos

    # P&L do dia k: marcação a mercado da posição herdada
    if (pos != 0) {
      if (pos > 0) { rL <- r1[k]; rS <- r2[k] } else { rL <- r2[k]; rS <- r1[k] }
      peso_long[k] <- wL; peso_shrt[k] <- wS
      retorno[k] <- wL * rL - wS * rS
      wL <- wL * (1 + rL); wS <- wS * (1 + rS)
      z_hoje <- (s_all[g] - par_viv$mu) / par_viv$sigma
      z_trade[k] <- z_hoje; mu_vig[k] <- par_viv$mu; sigma_vig[k] <- par_viv$sigma
    }

    if (pos == 0) {
      # Fora do mercado: há sinal?
      acima <- is.finite(z_gat[k]) && abs(z_gat[k]) > delta
      gatilho <- if (modo == "cruzamento") {
        acima && (k == 1 || !(is.finite(z_gat[k - 1]) && abs(z_gat[k - 1]) > delta))
      } else acima

      if (gatilho) {
        n_sinais <- n_sinais + 1
        novo <- list(valido = is.finite(sg_t[k]), mu = mu_t[k], sigma = sg_t[k], ssd_dia = ssd_t[k],
                     razao_ssd = if (is.finite(ssd_dia_form) && ssd_dia_form > 0) ssd_t[k] / ssd_dia_form else NA)
        if (!is.null(max_razao) && is.finite(novo$razao_ssd) && novo$razao_ssd > max_razao)
          novo$valido <- FALSE

        z_novo <- NA
        if (!novo$valido) {
          n_rej_ssd <- n_rej_ssd + 1; motivo <- "par_se_afastou"
        } else if (!is.finite(novo$sigma) || novo$sigma < sigma_min) {
          n_rej_sigma <- n_rej_sigma + 1; motivo <- "sigma_degenerado"
        } else {
          z_novo <- (s_all[g] - novo$mu) / novo$sigma
          if (exige_z && modo_banda != "movel" && abs(z_novo) <= delta) {
            n_rej_z <- n_rej_z + 1; motivo <- "z_reestimado_dentro_da_banda"
          } else {
            # Abre com os parâmetros NOVOS; a direção vem do GATILHO, como no estático.
            pos <- if (z_gat[k] > 0) -1 else +1
            par_viv <- novo; wL <- 1; wS <- 1
            z_trade[k] <- z_novo; mu_vig[k] <- novo$mu; sigma_vig[k] <- novo$sigma
            n_aprov <- n_aprov + 1
            sig_ab <- c(sig_ab, novo$sigma); mu_ab <- c(mu_ab, novo$mu); raz_ab <- c(raz_ab, novo$razao_ssd)
            motivo <- "aprovado"
          }
        }
        ev[[length(ev) + 1]] <- list(g = g, motivo = motivo, n_amostra = nobs_t[k],
                                     z_monitor = z_mon[k], z_movel = z_mov[k], z_novo = z_novo,
                                     mu_novo = novo$mu, sigma_novo = novo$sigma,
                                     razao_ssd = novo$razao_ssd)
      }
    } else {
      # Posicionado: regras de saída com os parâmetros DO TRADE
      #   cruzamento → spread = 0 ⇒ z_fecha = −μ_trade/σ_trade ; senão z_fecha = 0
      z_fecha <- if (fecha_no_cruzamento) -par_viv$mu / par_viv$sigma else 0
      if (!is.null(stop) && abs(z_hoje) > stop) pos <- 0
      else if (pos == +1 && z_hoje >= z_fecha) pos <- 0
      else if (pos == -1 && z_hoje <= z_fecha) pos <- 0
      if (pos == 0) { par_viv <- NULL; wL <- 1; wS <- 1 }
    }
    positions[k] <- pos
  }

  eventos <- if (length(ev)) data.frame(
    g = vapply(ev, `[[`, numeric(1), "g"),
    motivo = vapply(ev, `[[`, character(1), "motivo"),
    n_amostra = vapply(ev, `[[`, numeric(1), "n_amostra"),
    z_monitor = vapply(ev, `[[`, numeric(1), "z_monitor"),
    z_movel = vapply(ev, function(e) as.numeric(e$z_movel), numeric(1)),
    z_novo = vapply(ev, function(e) as.numeric(e$z_novo), numeric(1)),
    mu_novo = vapply(ev, function(e) as.numeric(e$mu_novo), numeric(1)),
    sigma_novo = vapply(ev, function(e) as.numeric(e$sigma_novo), numeric(1)),
    razao_ssd = vapply(ev, function(e) as.numeric(e$razao_ssd), numeric(1)),
    stringsAsFactors = FALSE) else NULL

  list(df = data.frame(z_monitor = z_mon, z_movel = z_mov, z_trade = z_trade,
                       mu_vigente = mu_vig, sigma_vigente = sigma_vig, position = positions,
                       position_lag = positions_lag, peso_long = peso_long, peso_short = peso_shrt,
                       retorno_diario = retorno),
       info = list(n_sinais = n_sinais, n_aprovados = n_aprov, n_rej_ssd = n_rej_ssd,
                   n_rej_sigma = n_rej_sigma, n_rej_z = n_rej_z,
                   sigma_medio = if (length(sig_ab)) mean(sig_ab) else NA,
                   mu_medio = if (length(mu_ab)) mean(mu_ab) else NA,
                   razao_media = if (length(raz_ab)) mean(raz_ab, na.rm = TRUE) else NA,
                   ssd_dia_form = ssd_dia_form, eventos = eventos))
}


# ── 3.1 Verificações ──────────────────────────────────────────────────────────────────
# (a) Ausência de look-ahead: μ_t, σ_t e SSD/dia_t não podem mudar quando o futuro depois
#     de t é descartado.
set.seed(42)
s_teste <- cumsum(rnorm(500, 0, 0.01)) + rnorm(500, 0, 0.02)
cat("\n=== 1. look-ahead ===\n")
for (jan in list(NULL, 252)) {
  piores <- sapply(c(121, 301, 500), function(t) {
    completo <- parametros_moveis(s_teste, t, jan)
    truncado <- parametros_moveis(s_teste[1:t], t, jan)
    max(abs(completo[1, 1:3] - truncado[1, 1:3]))
  })
  cat(sprintf("  janela=%9s : desvio máximo ao truncar o futuro = %.2e\n",
              if (is.null(jan)) "expanding" else jan, max(piores)))
}
pm <- parametros_moveis(s_teste, 401)
cat(sprintf("  ssd_dia[400] = %.8f   mu² + sigma²_pop = %.8f\n", pm[1, "ssd"],
            pm[1, "mu"]^2 + pm[1, "sigma"]^2 * (pm[1, "n"] - 1) / pm[1, "n"]))

# (b) O dinâmico neutralizado (sem veto, sem dupla confirmação, gatilho da formação,
#     re-teste diário, SIGMA_MIN = 0) tem de reproduzir o estático bit a bit.
set.seed(7)
amostra <- pares[sample(nrow(pares), min(250, nrow(pares))), ]
n_ok <- 0; n_dif <- 0; err_max <- 0
for (i in seq_len(nrow(amostra))) {
  p <- amostra[i, ]
  if (p$spread_desvio < SIGMA_MIN || !(p$ativo1 %in% colnames(base$P)) || !(p$ativo2 %in% colnames(base$P))) next
  pf <- recortar_par(base, p$ativo1, p$ativo2, p$formacao_inicio, p$formacao_fim)$P
  pn <- recortar_par(base, p$ativo1, p$ativo2, p$negociacao_inicio, p$negociacao_fim)$P
  if (nrow(pf) == 0 || nrow(pn) == 0) next
  est <- simular_par_dist(pf, pn, p$spread_media, p$spread_desvio)
  din <- simular_par_dist_dinamico(pf, pn, p$spread_media, p$spread_desvio, max_razao = NULL,
                                   exige_z = FALSE, modo_banda = "formacao", modo = "diario",
                                   sigma_min = 0)
  if (is.null(est) || is.null(din)) next
  e <- max(abs(est$retorno_diario - din$df$retorno_diario))
  err_max <- max(err_max, e)
  if (e < 1e-12 && identical(est$position, din$df$position)) n_ok <- n_ok + 1 else n_dif <- n_dif + 1
}
cat("\n=== 2. o dinâmico neutralizado reproduz o estático ===\n")
cat(sprintf("  pares comparados : %d\n  idênticos        : %d\n  divergentes      : %d   (esperado: 0)\n  erro máximo P&L  : %.3e\n\n",
            n_ok + n_dif, n_ok, n_dif, err_max))


# ── 4. Simulação completa ─────────────────────────────────────────────────────────────
t0 <- Sys.time()
cat("Configuração dinâmica\n")
cat(sprintf("  gatilho          : banda %s\n", if (MODO_BANDA == "movel") "MÓVEL (recalculada todo dia)" else "da FORMAÇÃO (idêntica ao estático)"))
cat(sprintf("  amostra          : %s  (mín. %d obs.)\n",
            if (is.null(JANELA_REESTIMACAO)) "expanding desde o início da formação"
            else sprintf("rolling de %d pregões", JANELA_REESTIMACAO), MIN_OBS_REESTIMACAO))
cat(sprintf("  re-teste         : %s\n", RETESTE_MODO))
cat(sprintf("  revalidação SSD  : %s\n", if (is.null(MAX_RAZAO_SSD)) "desligada" else sprintf("veta se razão > %gx", MAX_RAZAO_SSD)))
cat(sprintf("  dupla confirmação: %s\n", if (EXIGE_Z_REESTIMADO && MODO_BANDA != "movel") "sim" else "não"))
cat(sprintf("  saída            : %s\n", if (FECHA_NO_CRUZAMENTO) "cruzamento dos preços normalizados (spread = 0)" else "spread = μ re-estimado do trade"))
cat(sprintf("Simulando %s pares...\n\n", milhar(nrow(pares))))

resultados_pares <- vector("list", nrow(pares))
eventos_log <- vector("list", nrow(pares))
recortes <- list()   # reaproveitados na análise de sensibilidade (seção 9)
acc <- novo_acumulador(base)
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
  recortes[[length(recortes) + 1]] <- list(mu = mu, sigma = sigma, pf = rf_$P, rn = rn_)

  if (!is.null(MAX_RETORNO_DIA) && maior_retorno_dia(rn_$P) > MAX_RETORNO_DIA) {
    n_skip["outlier"] <- n_skip["outlier"] + 1; next
  }

  sim <- simular_par_dist_dinamico(rf_$P, rn_$P, mu, sigma)
  if (is.null(sim)) next
  res <- sim$df; info <- sim$info

  tr <- contar_trades(res$position)
  resultados_pares[[i]] <- data.frame(
    janela = par$janela, neg_inicio = par$negociacao_inicio, neg_fim = par$negociacao_fim,
    ativo1 = a1, ativo2 = a2, rank = par$rank, ssd = par$ssd,
    sigma = sigma, sigma_medio = info$sigma_medio, mu = mu, mu_medio = info$mu_medio,
    razao_ssd_med = info$razao_media, n_sinais = info$n_sinais, n_aprovados = info$n_aprovados,
    n_rej_ssd = info$n_rej_ssd, n_rej_sigma = info$n_rej_sigma, n_rej_z = info$n_rej_z,
    n_trades = tr[["abertos"]], n_fechados = tr[["fechados"]], n_forcados = tr[["forcados"]],
    retorno_total = sum(res$retorno_diario), stringsAsFactors = FALSE)

  if (!is.null(info$eventos)) {
    e <- info$eventos
    e$data <- base$datas[c(rf_$linhas, rn_$linhas)[e$g]]
    e$g <- NULL
    e$janela <- par$janela; e$ativo1 <- a1; e$ativo2 <- a2; e$rank <- par$rank
    eventos_log[[i]] <- e[, c("data", "motivo", "n_amostra", "z_monitor", "z_movel", "z_novo",
                              "mu_novo", "sigma_novo", "razao_ssd", "janela", "ativo1", "ativo2", "rank")]
  }
  acc <- acumular_par(acc, rn_, res$retorno_diario, res$position_lag, COMMITTED_CAPITAL)
}
resultados_df <- do.call(rbind, resultados_pares)
eventos_df    <- do.call(rbind, eventos_log)

cat(sprintf("Total de pares no arquivo  : %s\n", milhar(nrow(pares))))
cat(sprintf("  Pulados (sigma < %g) : %s\n", SIGMA_MIN, milhar(n_skip[["sigma"]])))
cat(sprintf("  Pulados (ticker ausente)  : %s\n", milhar(n_skip[["ticker"]])))
cat(sprintf("  Pulados (sem dados)       : %s\n", milhar(n_skip[["dados"]])))
cat(sprintf("  Pulados (spike positivo)  : %s  ← corrupção de dados filtrada\n", milhar(n_skip[["outlier"]])))
cat(sprintf("  Simulados com sucesso     : %s\n", milhar(nrow(resultados_df))))
cat(sprintf("\nTempo de execução          : %.0fs\n\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))


# ── 5. Diagnóstico do filtro dinâmico ─────────────────────────────────────────────────
tot <- colSums(resultados_df[, c("n_sinais", "n_aprovados", "n_rej_ssd", "n_rej_sigma", "n_rej_z")])
cat(strrep("=", 64), "\n  FILTRO DINÂMICO — destino dos sinais\n", strrep("=", 64), "\n", sep = "")
cat(sprintf("Sinais gerados (z de monitoramento cruzou ±%.0f) : %s\n", DELTA, milhar(tot[["n_sinais"]])))
if (tot[["n_sinais"]] > 0) {
  linha <- function(rot, v) cat("  → ", esq(rot, 43), sprintf(": %s (%s)", milhar(v), pct(v / tot[["n_sinais"]], 1)), "\n", sep = "")
  linha("viraram trade", tot[["n_aprovados"]])
  linha("vetados: par se afastou (SSD/dia)", tot[["n_rej_ssd"]])
  linha("vetados: σ re-estimado degenerado", tot[["n_rej_sigma"]])
  linha("vetados: |z| re-estimado dentro da banda", tot[["n_rej_z"]])
}
cat(strrep("=", 64), "\n", sep = "")
mudos <- resultados_df$n_sinais > 0 & resultados_df$n_aprovados == 0
cat(sprintf("\nPares com sinal mas nenhum trade aprovado : %s (%s dos pares simulados)\n",
            milhar(sum(mudos)), pct(mean(mudos), 1)))
cat(sprintf("Pares sem nenhum sinal no período         : %s\n", milhar(sum(resultados_df$n_sinais == 0))))

comp <- resultados_df[!is.na(resultados_df$sigma_medio), ]
if (nrow(comp)) {
  razao_sigma <- comp$sigma_medio / comp$sigma
  q <- stats::quantile(razao_sigma, c(.25, .75), names = FALSE)
  cat("\n=== σ re-estimado ÷ σ da formação (pares com ao menos 1 abertura) ===\n")
  cat(sprintf("Pares            : %s\nMediana da razão : %.4f\nQuartis          : %.4f — %.4f\nFora de ±10%%     : %s dos pares\n",
              milhar(nrow(comp)), stats::median(razao_sigma), q[1], q[2], pct(mean(abs(razao_sigma - 1) > 0.10), 1)))
  deriva_mu <- (comp$mu_medio - comp$mu) / comp$sigma
  cat("\n=== Deriva de μ, em σ da formação ===\n")
  cat(sprintf("Mediana de |Δμ|/σ : %.4f\nAcima de 0,5σ     : %s dos pares\nAcima de 1,0σ     : %s dos pares\n",
              stats::median(abs(deriva_mu)), pct(mean(abs(deriva_mu) > 0.5), 1), pct(mean(abs(deriva_mu) > 1.0), 1)))
}
if (!is.null(eventos_df)) {
  cat("\n=== Amostra da re-estimação ===\n")
  cat(sprintf("Observações por teste : mediana %.0f dias (mín %.0f, máx %.0f)\n",
              stats::median(eventos_df$n_amostra), min(eventos_df$n_amostra), max(eventos_df$n_amostra)))
  faixa <- cortar_faixas(eventos_df$n_amostra, 5)
  aprov <- eventos_df$motivo == "aprovado"
  tabela <- data.frame(faixa = levels(faixa),
                       sinais = as.integer(table(faixa)),
                       aprovacao = round(100 * as.numeric(tapply(aprov, faixa, mean)), 1),
                       razao_ssd_mediana = round(as.numeric(tapply(eventos_df$razao_ssd, faixa, stats::median, na.rm = TRUE)), 3))
  cat("\n=== Aprovação (%) e afastamento por maturidade da janela ===\n")
  print(tabela[tabela$sinais > 0, ], row.names = FALSE)

  arq <- abrir_png("diagnostico_distancia_dinamica.png", 15, 4)
  graphics::par(mfrow = c(1, 3), mar = c(7, 4, 3, 1))
  ordem <- c("aprovado", "par_se_afastou", "z_reestimado_dentro_da_banda", "sigma_degenerado")
  cont <- sapply(ordem, function(m) sum(eventos_df$motivo == m))
  b <- graphics::barplot(cont, names.arg = c("aprovado", "par se afastou", "|z| dentro da banda", "σ degenerado"),
                         col = c("#2E7D32", "#C62828", "#EF6C00", "#616161"), las = 2, cex.names = 0.8,
                         main = "Destino dos sinais", ylab = "nº de sinais", border = NA)
  graphics::text(b, cont, milhar(cont), pos = 3, cex = 0.8, xpd = TRUE)
  graphics::par(mar = c(4, 4, 3, 1))
  ra <- pmin(eventos_df$razao_ssd[eventos_df$motivo == "aprovado"], 12)
  rv <- pmin(eventos_df$razao_ssd[eventos_df$motivo == "par_se_afastou"], 12)
  br <- seq(0, 12, length.out = 61)
  graphics::hist(ra[!is.na(ra)], breaks = br, col = grDevices::adjustcolor("#2E7D32", 0.55), border = NA,
                 main = "SSD/dia no sinal ÷ SSD/dia da formação", xlab = "razão (truncada em 12)")
  if (length(rv[!is.na(rv)])) graphics::hist(rv[!is.na(rv)], breaks = br, add = TRUE,
                                             col = grDevices::adjustcolor("#C62828", 0.55), border = NA)
  if (!is.null(MAX_RAZAO_SSD)) graphics::abline(v = MAX_RAZAO_SSD, lty = 2)
  graphics::abline(v = 1, lty = 3, col = "gray")
  if (nrow(comp)) {
    lim <- c(0, max(stats::quantile(comp$sigma, 0.99), stats::quantile(comp$sigma_medio, 0.99)))
    plot(comp$sigma, comp$sigma_medio, pch = 16, cex = 0.4, col = grDevices::adjustcolor("#1565C0", 0.25),
         xlim = lim, ylim = lim, xlab = "σ da formação", ylab = "σ médio nas aberturas",
         main = "Deslocamento da banda")
    graphics::abline(0, 1, col = "red", lty = 2)
  }
  fechar_png(arq)
}


# ── 6. Resultado por par ──────────────────────────────────────────────────────────────
cat("\n")
plot_pares_por_janela(resultados_df, max(pares$rank),
                      "Pares simulados por janela de negociação — distância dinâmica",
                      "pares_por_janela_distancia_dinamica.png")
cat("\n"); imprimir_estatisticas_trades(resultados_df)
cat("\n"); imprimir_top_bottom(resultados_df, c("neg_inicio", "ativo1", "ativo2", "rank", "sigma",
                                               "sigma_medio", "n_sinais", "n_trades", "n_fechados",
                                               "retorno_total"))


# ── 7. Portfólio, curva de equity e métricas ──────────────────────────────────────────
portfolio <- serie_portfolio(acc, base)
cat("\n"); imprimir_resumo_portfolio(portfolio)
plot_equity(portfolio, "Portfólio de Pairs Trading — Distância dinâmica (re-estimação no sinal)",
            "equity_distancia_dinamica.png")
cat("\n"); imprimir_metricas_simples(portfolio$retorno_diario)
cat("\n"); imprimir_bruto_liquido(portfolio)
cat("\n"); imprimir_meses_positivos(portfolio)
plot_retorno_anual(portfolio, "Retorno anual do portfólio — distância dinâmica",
                   "retorno_anual_distancia_dinamica.png")


# ── 8. Estático × dinâmico ────────────────────────────────────────────────────────────
# Compara com o portfólio de distance/pairs_trading.R nas mesmas datas (rode o pairs_trading.R antes,
# com os mesmos PERIODO_INICIO / PERIODO_FIM).
cat("\n")
comparar_estatico_dinamico(portfolio, resultados_df,
                           file.path(PASTA_RESULTADOS, "negociacao_portfolio.csv"),
                           file.path(PASTA_RESULTADOS, "negociacao_pares.csv"),
                           "Distância — estático × dinâmico (re-estimação no sinal)",
                           "estatico_vs_dinamico_distancia.png")
if (MODO_BANDA != "movel" && FECHA_NO_CRUZAMENTO) {
  cat("Config atual: gatilho e saída idênticos ao estático → o dinâmico é um FILTRO\n")
  cat("estrito sobre os trades do estático. Toda a diferença de desempenho vem dos\n")
  cat("sinais recusados pela revalidação / dupla confirmação.\n")
}


# ── 9. Sensibilidade às escolhas dinâmicas ────────────────────────────────────────────
# Roda o portfólio inteiro em cada configuração. A 1ª linha é o estático reproduzido aqui
# (não o CSV), então a comparação não depende de o baseline estar atualizado.
# Como no notebook, aqui o filtro MAX_RETORNO_DIA não é aplicado.
rodar_cenario <- function(...) {
  acc_c <- novo_acumulador(base); n_tr <- 0; n_fe <- 0; n_si <- 0; n_ap <- 0
  for (rc in recortes) {
    sim <- simular_par_dist_dinamico(rc$pf, rc$rn$P, rc$mu, rc$sigma, ...)
    if (is.null(sim)) next
    tr <- contar_trades(sim$df$position)
    n_tr <- n_tr + tr[["abertos"]]; n_fe <- n_fe + tr[["fechados"]]
    n_si <- n_si + sim$info$n_sinais; n_ap <- n_ap + sim$info$n_aprovados
    acc_c <- acumular_par(acc_c, rc$rn, sim$df$retorno_diario, sim$df$position_lag, COMMITTED_CAPITAL)
  }
  s <- serie_portfolio(acc_c, base)$retorno_diario
  eq <- cumprod(1 + s)
  c("a.a." = eq[length(eq)]^(252 / length(s)) - 1, "Sharpe" = mean(s) / sd(s) * sqrt(252),
    "DD máx" = min((eq - cummax(eq)) / cummax(eq)), "trades" = n_tr,
    "conv." = if (n_tr) n_fe / n_tr else NA, "sinais" = n_si, "aprov." = if (n_si) n_ap / n_si else NA)
}
CENARIOS <- list(
  "estático (reproduzido aqui)"             = list(max_razao = NULL, exige_z = FALSE, modo_banda = "formacao", modo = "diario"),
  "DEFAULT: formação + veto + dupla conf."  = list(),
  "  só veto de afastamento"                = list(exige_z = FALSE),
  "  só dupla confirmação"                  = list(max_razao = NULL),
  "  default, rolling 252"                  = list(janela = 252),
  "  default, saída em μ re-estimado"       = list(fecha_no_cruzamento = FALSE),
  "banda MÓVEL, expanding"                  = list(modo_banda = "movel"),
  "  banda MÓVEL, rolling 252"              = list(modo_banda = "movel", janela = 252),
  "  banda MÓVEL, rolling 126"              = list(modo_banda = "movel", janela = 126))
sens <- t(sapply(CENARIOS, function(kw) do.call(rodar_cenario, kw)))
cat("\n")
print(data.frame(`a.a.` = pct(sens[, "a.a."]), Sharpe = sprintf("%.2f", sens[, "Sharpe"]),
                 `DD máx` = pct(sens[, "DD máx"], 1), trades = milhar(sens[, "trades"]),
                 `conv.` = pct(sens[, "conv."], 0), sinais = milhar(sens[, "sinais"]),
                 `aprov.` = pct(sens[, "aprov."], 0), row.names = rownames(sens), check.names = FALSE))
cat("\nLeitura: a diferença entre a 1ª linha e cada uma das outras é atribuível APENAS à\n")
cat("decisão dinâmica indicada — mesma base, mesmos pares, mesma convenção de P&L.\n")


# ── 10. Salvando resultados ───────────────────────────────────────────────────────────
utils::write.csv(resultados_df, file.path(PASTA_RESULTADOS, "negociacao_pares_dinamico.csv"), row.names = FALSE)
utils::write.csv(portfolio, file.path(PASTA_RESULTADOS, "negociacao_portfolio_dinamico.csv"), row.names = FALSE)
if (!is.null(eventos_df))
  utils::write.csv(eventos_df, file.path(PASTA_RESULTADOS, "eventos_reteste_dinamico.csv"), row.names = FALSE)
cat("\nSalvo:\n")
cat("  distance/output/resultados/negociacao_pares_dinamico.csv      — resultado por par (+ contadores de veto)\n")
cat("  distance/output/resultados/negociacao_portfolio_dinamico.csv  — série diária do portfólio\n")
cat("  distance/output/resultados/eventos_reteste_dinamico.csv       — um registro por sinal avaliado\n")
