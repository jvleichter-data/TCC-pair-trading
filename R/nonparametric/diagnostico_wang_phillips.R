# -*- coding: utf-8 -*-
# ══════════════════════════════════════════════════════════════════════════════════════
#  Diagnóstico de linearidade — teste de Wang & Phillips (2012)
#  Tradução de new_aproach/src/nonparametric/diagnostico_wang_phillips.ipynb
# ══════════════════════════════════════════════════════════════════════════════════════
#
# Pergunta (slide 29): a relação de equilíbrio é de fato não linear?
#   H0: g(x) = α + βx   contra   H1: g não linear
# É a versão formal do que a CV faz informalmente quando escolhe h = ∞.
# Papel no método: DIAGNÓSTICO. Não seleciona pares — num par sem cointegração o resíduo
# linear passeia e o teste rejeitaria "reta" com força (DECISOES.md § 8.2).
#
# O teste (Wang & Phillips, 2012, Annals of Statistics 40(2), eq. (2) e Teorema 3.1):
#   S_n = Σ_{s≠t} û_s û_t K((x_t − x_s)/h),  V_n² = Σ_{s≠t} û_s² û_t² K²(·),  Z_n = S_n/(√2·V_n)
# com û os resíduos do OLS; rejeita para Z_n grande. Adaptações (DECISOES.md § 9): kernel
# gaussiano; x dividido pelo desvio do incremento diário e h = n^(−1/3); relação contemporânea.
# ⚠️ O artigo supõe erro diferença de martingal; nossos spreads têm AR(1) ≈ 0,9 e a N(0,1)
# rejeita a reta demais. O p-valor usado vem de um BOOTSTRAP sob H0 com erro AR(1).
#
# Requer: pairs_formation_np_propria.R (pares próprios), pairs_formation_np.R (pares da linear)
# e cointegration/pairs_trading_coint.R (resultados da linear).
# ⚠️ Usa o gerador aleatório do R: os p-valores do bootstrap e a validação simulada diferem
# dos do Python por sorteio; Z_n, p-valor N(0,1) e φ são determinísticos e coincidem.
# ⏱️ ~16 mil testes com 199 réplicas cada; dezenas de minutos com processos em paralelo.

source("funcoes/comum.R", local = TRUE)
source("funcoes/adf.R", local = TRUE)
source("funcoes/paralelo.R", local = TRUE)
source("nonparametric/kernel_np.R", local = TRUE)
source("nonparametric/formacao_utils.R", local = TRUE)
source("nonparametric/negociacao_utils.R", local = TRUE)
source("nonparametric/especificacao_np.R", local = TRUE)
usar_pastas("nonparametric")

B           <- 199       # réplicas do bootstrap por par
H_EXPOENTE  <- 1 / 3     # h = n^(−1/3) em unidades de incremento diário
NIVEL       <- 0.05
SEMENTE     <- 20261102
N_SIM       <- 150       # pares simulados por cenário na validação
N_PROCESSOS <- max(1, parallel::detectCores() - 1)

SAIDA <- pasta_saida("nonparametric", "diagnostico")

# Negociação NP sobre os pares da linear (seção 3): mesmos parâmetros-padrão de nonparametric/pairs_trading_np.R
PARAMS_NEGOCIACAO <- list(delta = 2.0, beta_min = 0.50, beta_max = 2.0, dimensionamento = "maior_perna",
                          l_suporte = 20, massa_min = 0, modo_saida = "tangente",
                          mu_sigma_modo = "formacao", janela_mu_sigma = 126, t_min_resid = 126)

# Cada teste fixa a própria semente: o resultado não depende do número de processos.
roda_wp <- function(tarefa, B, h_expoente) {
  set.seed(tarefa$semente)
  teste_wp(tarefa$x, tarefa$y, B = B, h_expoente = h_expoente)
}
cl <- iniciar_processos(N_PROCESSOS)


# ── 1. Validação: o teste rejeita a reta quando ela é verdadeira? ─────────────────────
# y = 1 + 0,9(x − 1) + c(x − 1)² + u, x um passeio com volatilidade diária de 1,5%, u AR(1)
# com desvio 0,02. c = 0: reta verdadeira (rejeição deveria ser 5%); c = −1: curva (poder).
set.seed(SEMENTE)
passeio <- function(n = 252) c(1, cumprod(1 + stats::rnorm(n - 1, 0.0003, 0.015)))
ar1 <- function(n, phi, s = 0.02) {
  e <- stats::rnorm(n + 100, 0, s * sqrt(1 - phi^2))
  u <- numeric(n + 100)
  for (t in 2:(n + 100)) u[t] <- phi * u[t - 1] + e[t]
  u[-(1:100)]
}
tarefas <- list(); rot <- list()
for (phi in c(0, 0.8, 0.9, 0.95)) for (cc in c(0, -1)) for (k in seq_len(N_SIM)) {
  x <- passeio()
  tarefas[[length(tarefas) + 1]] <- list(x = x, y = 1 + 0.9 * (x - 1) + cc * (x - 1)^2 + ar1(252, phi),
                                         semente = SEMENTE + length(tarefas) + 1)
  rot[[length(rot) + 1]] <- data.frame(phi = phi, relacao = if (cc != 0) "curva" else "reta")
}
t0 <- Sys.time()
r <- aplicar(cl, tarefas, roda_wp, B, H_EXPOENTE)
val <- cbind(do.call(rbind, rot), p_boot = vapply(r, `[[`, numeric(1), "p_boot"),
             p_normal = vapply(r, `[[`, numeric(1), "p_normal"))
utils::write.csv(val, file.path(SAIDA, "wp_validacao.csv"), row.names = FALSE)
tab_val <- do.call(rbind, lapply(split(val, list(val$relacao, val$phi)), function(d) data.frame(
  relacao = d$relacao[1], phi = d$phi[1], rejeita_bootstrap = mean(d$p_boot < NIVEL),
  rejeita_normal = mean(d$p_normal < NIVEL))))
rownames(tab_val) <- NULL
print(transform(tab_val, rejeita_bootstrap = pct(rejeita_bootstrap, 1), rejeita_normal = pct(rejeita_normal, 1)),
      row.names = FALSE)
cat(sprintf("%.0f s\n\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))


# ── 2. Aplicação aos pares da formação própria ────────────────────────────────────────
# Cada par na direção escolhida pela formação (dependente ~ g(independente)), na formação.
base <- carregar_base()
tarefas_de <- function(pares, semente_base) {
  tarefas <- list(); chaves <- list()
  for (k in seq_len(nrow(pares))) {
    p <- pares[k, ]
    o <- orientar(p$ativo1, p$ativo2, p$direcao)
    P <- recortar_par(base, o[["dep"]], o[["indep"]], p$formacao_inicio, p$formacao_fim)$P
    if (nrow(P) < 100) next
    tarefas[[length(tarefas) + 1]] <- list(x = P[, 2] / P[1, 2], y = P[, 1] / P[1, 1], semente = semente_base + k - 1)
    chaves[[length(chaves) + 1]] <- data.frame(janela = p$janela, ativo1 = p$ativo1, ativo2 = p$ativo2)
  }
  list(tarefas = tarefas, chaves = do.call(rbind, chaves))
}
resultados_wp <- function(td) {
  r <- aplicar(cl, td$tarefas, roda_wp, B, H_EXPOENTE, lote = 2000, rotulo = "pares")
  cbind(td$chaves, z = vapply(r, `[[`, numeric(1), "z"), p_normal = vapply(r, `[[`, numeric(1), "p_normal"),
        p_boot = vapply(r, `[[`, numeric(1), "p_boot"), phi = vapply(r, `[[`, numeric(1), "phi"),
        h = vapply(r, `[[`, numeric(1), "h"))
}

propria <- ler_pares(file.path(PASTA_PARES, "pares_formados_np_propria.csv"))
t0 <- Sys.time()
wp_prop <- merge(propria, resultados_wp(tarefas_de(propria, SEMENTE)), by = c("janela", "ativo1", "ativo2"), sort = FALSE)
utils::write.csv(wp_prop, file.path(SAIDA, "wang_phillips_propria.csv"), row.names = FALSE)
cat(sprintf("Pares: %s | %.0f s\n", milhar(nrow(wp_prop)), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
cat(sprintf("Rejeitam a reta (bootstrap, 5%%): %s  | pela N(0,1) do artigo: %s\n",
            pct(mean(wp_prop$p_boot < NIVEL), 1), pct(mean(wp_prop$p_normal < NIVEL), 1)))
cat(sprintf("AR(1) do resíduo linear: mediana %.2f\n", stats::median(wp_prop$phi)))
print(round(prop.table(table(ifelse(wp_prop$h_linear, "CV escolheu a reta", "CV escolheu curva"),
                             ifelse(wp_prop$p_boot < NIVEL, "W&P rejeita a reta", "W&P não rejeita")), 1), 3))


# ── 3. A não linearidade significativa prevê vantagem do NP? ──────────────────────────
# Nos pares da formação LINEAR dá para comparar NP e linear par a par (mesmo par, mesma
# janela). Pergunta: nos pares em que o teste rejeita a reta, o NP ganha da linear?
lin_np <- ler_pares(file.path(PASTA_PARES, "pares_formados_np.csv"))      # 09
t0 <- Sys.time()
wp_lin <- merge(lin_np, resultados_wp(tarefas_de(lin_np, SEMENTE + 10^6)), by = c("janela", "ativo1", "ativo2"), sort = FALSE)
encerrar_processos(cl)
utils::write.csv(wp_lin, file.path(SAIDA, "wang_phillips_pares_linear.csv"), row.names = FALSE)
cat(sprintf("\nPares: %s | %.0f s | rejeitam a reta: %s\n", milhar(nrow(wp_lin)),
            as.numeric(difftime(Sys.time(), t0, units = "secs")), pct(mean(wp_lin$p_boot < NIVEL), 1)))

# Resultado da negociação NP nesses pares (parâmetros de pairs_trading_np.R) e da linear (pairs_trading_coint.R), 1991–2015
cat("Negociando os pares da linear com o método NP...\n")
neg <- negociar_np(filtrar_periodo(lin_np, NULL, "2015-12"), base, PARAMS_NEGOCIACAO, verboso = FALSE)
utils::write.csv(neg$resultados, file.path(PASTA_RESULTADOS, "negociacao_pares_np_pares_linear.csv"), row.names = FALSE)
lin_res <- utils::read.csv(file.path(pasta_saida("cointegration", "resultados"), "negociacao_pares_coint.csv"), stringsAsFactors = FALSE,
                           colClasses = c(ativo1 = "character", ativo2 = "character"))
K <- c("janela", "ativo1", "ativo2")
m <- merge(merge(wp_lin[, c(K, "p_boot")], neg$resultados[, c(K, "retorno_total")], by = K),
           lin_res[, c(K, "retorno_total")], by = K, suffixes = c("_np", "_lin"))
m$dif <- m$retorno_total_np - m$retorno_total_lin
m$grupo <- ifelse(m$p_boot < NIVEL, "W&P rejeita a reta", "W&P não rejeita")
tab3 <- do.call(rbind, lapply(split(m, m$grupo), function(d) data.frame(
  grupo = d$grupo[1], pares = nrow(d), ret_np = mean(d$retorno_total_np),
  ret_lin = mean(d$retorno_total_lin), np_menos_lin = mean(d$dif))))
print(tab3, row.names = FALSE, digits = 4)
mz <- merge(wp_lin[, c(K, "z")], m[, c(K, "dif")], by = K)
cat("Correlação de postos entre o Z_n e a vantagem NP − linear:",
    round(stats::cor(mz$z, mz$dif, method = "spearman"), 3), "\n")

# Resumo em JSON (mesmo conteúdo do notebook)
num <- function(v) sprintf("%.17g", v)
linhas_val <- paste0('  "', tab_val$relacao, "_", tab_val$phi, '": {"boot": ', num(tab_val$rejeita_bootstrap),
                     ', "normal": ', num(tab_val$rejeita_normal), '}', collapse = ",\n")
json <- paste0('{\n "validacao": {\n', linhas_val, '\n },\n',
               ' "propria": {"pares": ', nrow(wp_prop), ', "rejeita_boot": ', num(mean(wp_prop$p_boot < NIVEL)),
               ', "rejeita_normal": ', num(mean(wp_prop$p_normal < NIVEL)), ', "phi_mediano": ', num(stats::median(wp_prop$phi)), '},\n',
               ' "pares_linear": {"pares": ', nrow(wp_lin), ', "rejeita_boot": ', num(mean(wp_lin$p_boot < NIVEL)),
               ', "np_menos_lin": {', paste0('"', tab3$grupo, '": ', num(tab3$np_menos_lin), collapse = ", "), '}},\n',
               ' "parametros": {"B": ', B, ', "h_expoente": ', num(H_EXPOENTE), ', "nivel": ', NIVEL,
               ', "semente": ', SEMENTE, ', "gerado_por": "R"}\n}\n')
writeLines(json, file.path(SAIDA, "wang_phillips_resumo.json"), useBytes = TRUE)
cat("Resumo salvo em", file.path(SAIDA, "wang_phillips_resumo.json"), "\n")
