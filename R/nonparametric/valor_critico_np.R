# -*- coding: utf-8 -*-
# ══════════════════════════════════════════════════════════════════════════════════════
#  Valor crítico do teste de cointegração não paramétrica — por simulação
#  Tradução de new_aproach/src/nonparametric/valor_critico_np.ipynb
# ══════════════════════════════════════════════════════════════════════════════════════
#
# A formação própria do método NP (pairs_formation_np_propria.R) aprova um par se a estatística ADF dos ERROS FORA DA
# AMOSTRA da curva for "negativa o bastante". Este script descobre quanto é "o bastante":
# o valor que a estatística atinge POR ACASO em pares SEM cointegração.
#
# Por que não usar uma tabela:
#   ADF numa série de preços                  → ≈ −2,86   (Dickey & Fuller; MacKinnon 1996)
#   ADF no resíduo de uma RETA por OLS        → ≈ −3,34   (Engle & Granger; MacKinnon 1991, 2010)
#   ADF no erro de uma CURVA kernel, h por CV → não há tabela
# A curva se adapta aos dados muito mais que uma reta; com h pequeno ela "cola" no caminho e
# o erro parece estacionário mesmo sem equilíbrio (regressão não paramétrica espúria,
# Phillips 2009). Fazemos o que as tabelas de MacKinnon fazem — simular pares sem
# cointegração e ler o quantil de 5% —, com o NOSSO procedimento: teste_coint_np, a mesma
# função que a formação própria usa.
#
# Hipótese nula principal: pares reais (sorteados entre os candidatos do pré-filtro SSD)
# com os DIAS EMBARALHADOS, mantendo juntos os dois retornos de cada dia. Fica a correlação
# do mesmo dia, as caudas e a volatilidade; some o mecanismo de volta ao equilíbrio, que
# está na sequência dos dias. Nula de conferência: passeios gaussianos com a mesma média,
# volatilidade e correlação de cada par.
# Limitações: embaralhar apaga o agrupamento de volatilidade; o valor crítico controla o
# erro por par, não o da seleção dos 20 melhores entre centenas (testes múltiplos).
#
# ⚠️ Usa o gerador aleatório do R: o valor crítico sai PRÓXIMO do obtido no Python
# (−3,518 a 5%), não idêntico — os sorteios são outros. Para reproduzir exatamente os pares
# do TCC, aponte ARQ_CRITICO de nonparametric/pairs_formation_np_propria.R para o JSON do Python.
#
# Saída: nonparametric/output/valor_critico/ (valor_critico_np.json, simulacao_nula.csv,
#        simulacao_poder.csv, distribuicao_nula.png).
# ⏱️ ~6 mil testes; alguns minutos com processos em paralelo.

source("funcoes/comum.R", local = TRUE)
source("funcoes/adf.R", local = TRUE)
source("funcoes/paralelo.R", local = TRUE)
source("nonparametric/kernel_np.R", local = TRUE)
source("nonparametric/formacao_utils.R", local = TRUE)
source("nonparametric/negociacao_utils.R", local = TRUE)
source("nonparametric/especificacao_np.R", local = TRUE)
usar_pastas("nonparametric")

# ── Procedimento testado — TEM de ser igual ao da formação própria (pairs_formation_np_propria.R confere) ──────
GRADE_H_REL      <- GRADE_H_REL_PADRAO   # 25 valores geométricos de 0,05 a 5, e Inf (reta)
GAP_UNILATERAL   <- 20                   # CV unilateral (DECISOES.md § 6.1)
T_MIN_UNILATERAL <- 126
AUTOLAG_ADF      <- "AIC"                # = formação linear

# ── Amostra da hipótese nula ──────────────────────────────────────────────────────────
N_PRE_SSD     <- 300    # candidatos de onde os pares reais são sorteados (= formação própria)
PASSO_JANELAS <- 5      # 1 a cada 5 janelas de formação mensais → ~80 janelas
N_REAL        <- 3000   # pares da nula principal (reais com dias embaralhados)
N_GAUSS       <- 2000   # pares da nula de conferência (gaussiana)
N_PODER       <- 200    # pares cointegrados simulados por cenário de poder
SEMENTE       <- 20261024
NIVEIS        <- c(0.01, 0.05, 0.10)
CRIT_EG_5     <- -3.34  # Engle–Granger / MacKinnon, 2 variáveis, 5%
CRIT_DF_5     <- -2.86  # Dickey–Fuller com constante, 5%

N_PROCESSOS <- max(1, parallel::detectCores() - 1)   # 1 = serial

SAIDA <- pasta_saida("nonparametric", "valor_critico")
set.seed(SEMENTE)


# ── 1. Dados e janelas ────────────────────────────────────────────────────────────────
base <- carregar_base()
janelas <- janelas_formacao(sort(unique(base$mes)), 12, 6, 1)
jan_sel <- janelas[seq(1, length(janelas), by = PASSO_JANELAS)]
cat(sprintf("Janelas de formação: %d | usadas na simulação: %d (%s → %s)\n", length(janelas),
            length(jan_sel), num_mes(jan_sel[[1]]$form[1]), num_mes(max(jan_sel[[length(jan_sel)]]$form))))


# ── 2. Sorteio dos pares reais ────────────────────────────────────────────────────────
# Em cada janela usada, os pares são sorteados ENTRE OS N_PRE_SSD CANDIDATOS DE MENOR SSD —
# os mesmos que a formação própria testa —, para a nula ter o perfil dos pares que chegam
# ao teste.
por_janela <- ceiling(N_REAL / length(jan_sel))
amostra <- list()
for (jn in jan_sel) {
  precos <- filtrar_ativos_completos(base$P[base$mes %in% jn$form, , drop = FALSE])
  cands <- candidatos_ssd(calcular_ssd(normalizar_precos(precos)), N_PRE_SSD, 0.01)
  for (k in sample.int(nrow(cands), min(por_janela, nrow(cands)))) {
    p <- precos[, c(cands$ativo1[k], cands$ativo2[k])]
    r <- p[-1, ] / p[-nrow(p), ] - 1
    amostra[[length(amostra) + 1]] <- list(
      janela = paste0(num_mes(jn$form[1]), "_a_", num_mes(max(jn$form))),
      ativo1 = cands$ativo1[k], ativo2 = cands$ativo2[k], rank_ssd = k - 1L,
      r = unname(r), corr = stats::cor(r[, 1], r[, 2]))
  }
}
amostra <- amostra[seq_len(min(N_REAL, length(amostra)))]
cors <- vapply(amostra, `[[`, numeric(1), "corr")
cat(sprintf("Pares sorteados: %s\n", milhar(length(amostra))))
cat(sprintf("Correlação diária dos pares: mediana %.2f (p10 %.2f, p90 %.2f)\n", stats::median(cors),
            stats::quantile(cors, 0.1), stats::quantile(cors, 0.9)))


# ── 3. Simulação sob a hipótese nula ──────────────────────────────────────────────────
# Para cada par: reconstrói os preços a partir dos retornos (embaralhados, ou gaussianos),
# começando em 1, e roda teste_coint_np exatamente como na formação. Os sorteios são
# feitos aqui, em ordem; só os testes vão para os processos — o resultado não depende do
# número de processos.
caminho <- function(r) rbind(c(1, 1), apply(1 + r, 2, cumprod))   # (n+1) × 2

tarefas <- list(); rotulos <- list()
for (k in seq_along(amostra)) {
  s <- amostra[[k]]
  tarefas[[length(tarefas) + 1]] <- caminho(s$r[sample.int(nrow(s$r)), ])
  rotulos[[length(rotulos) + 1]] <- c(nula = "real_embaralhada", k = k)
  if (k <= N_GAUSS) {
    # gaussiana com a média, a volatilidade e a correlação do par
    S <- stats::cov(s$r)
    z <- matrix(stats::rnorm(2 * nrow(s$r)), ncol = 2) %*% chol(S)
    tarefas[[length(tarefas) + 1]] <- caminho(sweep(z, 2, colMeans(s$r), "+"))
    rotulos[[length(rotulos) + 1]] <- c(nula = "gaussiana", k = k)
  }
}

roda_teste <- function(Q, grade, gap, t_min, autolag)
  teste_coint_np(Q[, 1], Q[, 2], grade, gap, t_min, autolag)[c("stat", "h_linear", "h_rel")]

cl <- iniciar_processos(N_PROCESSOS)
t0 <- Sys.time()
res <- aplicar(cl, tarefas, roda_teste, GRADE_H_REL, GAP_UNILATERAL, T_MIN_UNILATERAL, AUTOLAG_ADF,
               lote = 1000, rotulo = "simulações")
nula <- do.call(rbind, lapply(seq_along(res), function(i) {
  s <- amostra[[as.integer(rotulos[[i]][["k"]])]]
  data.frame(nula = rotulos[[i]][["nula"]], janela = s$janela, ativo1 = s$ativo1, ativo2 = s$ativo2,
             rank_ssd = s$rank_ssd, corr = s$corr, stat = res[[i]]$stat,
             h_linear = res[[i]]$h_linear, h_rel = res[[i]]$h_rel, stringsAsFactors = FALSE)
}))
nula <- nula[!is.na(nula$stat), ]
utils::write.csv(nula, file.path(SAIDA, "simulacao_nula.csv"), row.names = FALSE)
cat(sprintf("Simulações válidas: gaussiana %d, real_embaralhada %d | %.0f s\n",
            sum(nula$nula == "gaussiana"), sum(nula$nula == "real_embaralhada"),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))


# ── 4. Valores críticos e o erro que as tabelas cometeriam ────────────────────────────
# "passariam com −3,34 / −2,86": com que frequência pares SEM cointegração passariam com a
# tabela de Engle–Granger ou de Dickey–Fuller. Num teste a 5% calibrado, isso seria 5%.
resumo <- function(d) c(stats::setNames(stats::quantile(d$stat, NIVEIS, names = FALSE),
                                        paste0("crítico ", NIVEIS * 100, "%")),
                        "passariam com −3,34 (EG)" = mean(d$stat < CRIT_EG_5),
                        "passariam com −2,86 (DF)" = mean(d$stat < CRIT_DF_5),
                        "reta escolhida (h = ∞)" = mean(d$h_linear),
                        "pares" = nrow(d))
tab <- cbind(gaussiana = resumo(nula[nula$nula == "gaussiana", ]),
             real_embaralhada = resumo(nula[nula$nula == "real_embaralhada", ]))
cat("\n"); print(round(tab, 3))

quantis <- function(nome) stats::setNames(
  stats::quantile(nula$stat[nula$nula == nome], NIVEIS, names = FALSE), paste0(NIVEIS * 100, "%"))
CRIT   <- quantis("real_embaralhada")
CRIT_G <- quantis("gaussiana")
cat(sprintf("\nValor crítico a 5%% (nula principal): %.3f   | gaussiana: %.3f\n", CRIT[["5%"]], CRIT_G[["5%"]]))

arq <- abrir_png("distribuicao_nula.png", 11, 4, pasta = SAIDA)
br <- seq(stats::quantile(nula$stat, 0.001), stats::quantile(nula$stat, 0.999), length.out = 60)
dentro <- function(v) v[v >= min(br) & v <= max(br)]
graphics::par(mar = c(4.5, 4, 1, 1))
graphics::hist(dentro(nula$stat[nula$nula == "real_embaralhada"]), breaks = br, border = NA,
               col = grDevices::adjustcolor("#E65100", 0.55), main = "", ylab = "pares",
               xlab = "estatística ADF dos erros fora da amostra (pares SEM cointegração)")
graphics::hist(dentro(nula$stat[nula$nula == "gaussiana"]), breaks = br, add = TRUE, border = NA,
               col = grDevices::adjustcolor("#607D8B", 0.55))
graphics::abline(v = c(CRIT[["5%"]], CRIT_EG_5, CRIT_DF_5), lty = c(1, 2, 3), lwd = 1.3)
graphics::legend("topleft", bty = "n", cex = 0.8,
                 c("real embaralhada", "gaussiana", sprintf("crítico simulado 5%% (%.2f)", CRIT[["5%"]]),
                   "Engle–Granger 5% (−3,34)", "Dickey–Fuller 5% (−2,86)"),
                 fill = c(grDevices::adjustcolor("#E65100", 0.55), grDevices::adjustcolor("#607D8B", 0.55), NA, NA, NA),
                 border = NA, lty = c(NA, NA, 1, 2, 3))
fechar_png(arq)


# ── 5. Poder: o teste detecta cointegração quando ela existe? ─────────────────────────
# Pares cointegrados por construção: x é o caminho (embaralhado) de uma ação real e
#   y_t = 1 + 0,9·(x_t − 1) + c·(x_t − 1)² + u_t,   u_t = φ·u_{t−1} + ε_t
# c = 0: equilíbrio linear; c = −1: curvo. φ ∈ {0,80; 0,90; 0,95}: meias-vidas de ~3, ~7 e
# ~14 pregões. Desvio de u = 0,02, a ordem do σ do spread nos pares reais.
SIGMA_U <- 0.02
tarefas_p <- list(); rot_p <- list()
for (phi in c(0.80, 0.90, 0.95)) for (cc in c(0, -1)) for (k in seq_len(N_PODER)) {
  s <- amostra[[sample.int(length(amostra), 1)]]
  x <- caminho(s$r[sample.int(nrow(s$r)), ])[, 1]
  u <- numeric(length(x))
  u[1] <- stats::rnorm(1, 0, SIGMA_U)
  eps <- stats::rnorm(length(x), 0, SIGMA_U * sqrt(1 - phi^2))
  for (t in 2:length(x)) u[t] <- phi * u[t - 1] + eps[t]
  tarefas_p[[length(tarefas_p) + 1]] <- cbind(x, 1 + 0.9 * (x - 1) + cc * (x - 1)^2 + u)
  rot_p[[length(rot_p) + 1]] <- data.frame(phi = phi, meia_vida = log(0.5) / log(phi),
                                           curva = if (cc != 0) "curva" else "reta")
}
t0 <- Sys.time()
res_p <- aplicar(cl, tarefas_p, roda_teste, GRADE_H_REL, GAP_UNILATERAL, T_MIN_UNILATERAL, AUTOLAG_ADF)
encerrar_processos(cl)
poder <- cbind(do.call(rbind, rot_p), stat = vapply(res_p, function(r) r$stat, numeric(1)),
               h_linear = vapply(res_p, function(r) r$h_linear, logical(1)))
poder <- poder[!is.na(poder$stat), ]
utils::write.csv(poder, file.path(SAIDA, "simulacao_poder.csv"), row.names = FALSE)
cat("\nPoder (fração de pares cointegrados detectados):\n")
g <- split(poder, list(poder$curva, poder$phi), drop = TRUE)
print(do.call(rbind, lapply(g, function(d) data.frame(
  curva = d$curva[1], phi = d$phi[1], meia_vida = round(d$meia_vida[1], 1),
  detectados_simulado = pct(mean(d$stat < CRIT[["5%"]]), 1),
  detectados_EG = pct(mean(d$stat < CRIT_EG_5), 1),
  reta_escolhida = pct(mean(d$h_linear), 1)))), row.names = FALSE)
cat(sprintf("%.0f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))


# ── 6. Salvando o valor crítico ───────────────────────────────────────────────────────
# Mesmo formato do JSON do notebook, para nonparametric/pairs_formation_np_propria.R ler qualquer um dos dois.
num <- function(v) if (is.infinite(v)) "null" else sprintf("%.17g", v)
bloco <- function(v) paste0("{\n", paste0('  "', names(v), '": ', vapply(v, num, ""), collapse = ",\n"), "\n }")
n_sim <- table(nula$nula)
json <- paste0('{\n "valor_critico": ', bloco(CRIT),
               ',\n "valor_critico_gaussiana": ', bloco(CRIT_G),
               ',\n "nula_principal": "real_embaralhada"',
               ',\n "n_simulacoes": {\n', paste0('  "', names(n_sim), '": ', as.integer(n_sim), collapse = ",\n"), '\n }',
               ',\n "falso_positivo_com_EG_334": ', num(mean(nula$stat[nula$nula == "real_embaralhada"] < CRIT_EG_5)),
               ',\n "parametros": {\n  "grade_h_rel": [', paste(vapply(GRADE_H_REL, num, ""), collapse = ", "), ']',
               ',\n  "gap_unilateral": ', GAP_UNILATERAL, ',\n  "t_min_unilateral": ', T_MIN_UNILATERAL,
               ',\n  "autolag_adf": "', AUTOLAG_ADF, '",\n  "n_pre_ssd": ', N_PRE_SSD, ',\n  "semente": ', SEMENTE,
               ',\n  "gerado_por": "R"\n }',
               ',\n "gerado_em": "', format(Sys.time(), "%Y-%m-%d %H:%M"), '"\n}\n')
writeLines(json, file.path(SAIDA, "valor_critico_np.json"), useBytes = TRUE)
cat(sprintf("\nValor crítico salvo em %s\n", file.path(SAIDA, "valor_critico_np.json")))
print(round(rbind(nula_principal = CRIT, gaussiana = CRIT_G), 3))
