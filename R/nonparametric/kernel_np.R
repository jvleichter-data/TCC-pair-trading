# -*- coding: utf-8 -*-
# Estimador local linear da cointegração não paramétrica — tradução de
# new_aproach/src/nonparametric/kernel_np.py.
#
# Modelo:  y_t = g(x_t) + u_t,  com y = Q_dep e x = Q_indep (preços normalizados P/P0).
# Em cada ponto x o local linear resolve
#     min_{a,b}  Σ_s [ y_s − a − b·(x_s − x) ]² · K((x_s − x)/h)
# e devolve a curva de equilíbrio ĝ(x) = â(x) e o hedge ratio local β(x) = b̂(x).
#
# Convenções (iguais às do Python):
#   - kernel gaussiano SEM a constante de normalização, K(0) = 1: a soma dos pesos é um
#     "número efetivo de observações" perto de x (usado no veto por suporte);
#   - h = Inf dá peso 1 a todas as observações e reproduz o OLS: a reta é o caso-limite;
#   - pontos em que o sistema 2×2 é singular devolvem NA.
#
# Requer funcoes/comum.R e funcoes/adf.R (desvio_pop, adf_estatistica).

# Limite de condicionamento: den / (S0·S2) = Var_w(d) / E_w(d²) ∈ [0, 1].
COND_MIN <- 1e-8

# Grade geométrica, calculada como o np.geomspace (10^linspace dos log10, extremos exatos).
grade_geometrica <- function(de, ate, n) {
  g <- 10^seq(log10(de), log10(ate), length.out = n)
  g[1] <- de; g[n] <- ate
  g
}
# Grade de bandwidth relativa ao desvio de Q_indep na formação; Inf = reta (OLS).
GRADE_H_REL_PADRAO <- c(grade_geometrica(0.05, 5, 25), Inf)


# ── Estimador ────────────────────────────────────────────────────────────────────────
pesos_kernel <- function(d, h) {
  # K(d/h) gaussiano com K(0) = 1. h = Inf → pesos iguais a 1 (OLS).
  if (is.infinite(h)) return(array(1, dim(d)))
  exp(-0.5 * (d / h)^2)
}

loclin <- function(x_eval, x, y, h, mascara = NULL) {
  # Local linear avaliado em cada ponto de x_eval.
  # mascara: matriz lógica (length(x_eval) × length(x)); TRUE = a observação s pode ser
  #          usada no ponto i (leave-one-out, leave-block-out, "só o passado").
  # Retorna list(a = ĝ(x_eval), b = β(x_eval), massa = Σ_s K).
  d <- outer(-x_eval, x, "+")                 # d[i, s] = x_s − x_eval_i
  w <- pesos_kernel(d, h)
  if (!is.null(mascara)) w <- w * mascara
  wd <- w * d
  S0 <- rowSums(w)
  S1 <- rowSums(wd)
  S2 <- rowSums(wd * d)
  T0 <- drop(w %*% y)
  T1 <- drop(wd %*% y)
  den <- S0 * S2 - S1^2
  ok <- (S0 > 0) & (den > COND_MIN * S0 * S2)
  list(a = ifelse(ok, (S2 * T0 - S1 * T1) / den, NA_real_),
       b = ifelse(ok, (S0 * T1 - S1 * T0) / den, NA_real_),
       massa = S0)
}

mascara_bloco <- function(n, l) {
  # TRUE onde |s − t| > l. l = 0 → leave-one-out.
  abs(outer(seq_len(n), seq_len(n), "-")) > l
}

mascara_unilateral <- function(T, gap, t_min) {
  # Para cada t = t_min … T−1 (contagem a partir de 0, como no Python), TRUE nas
  # observações s ≤ t − gap.
  t <- (t_min:(T - 1))
  s <- 0:(T - 1)
  outer(t, s, function(t, s) s <= t - gap)
}

# Erro quadrático médio da CV para cada h da grade, com as distâncias e a máscara montadas
# uma vez só: a CV é o trecho mais pesado do método (26 h × 2 direções por par testado).
# −d²/2 vai pré-calculado, com −Inf onde a observação não pode ser usada (peso exp(−Inf) = 0).
.mse_grade <- function(x_alvo, y_alvo, x, y, permitido, grade_h) {
  d <- outer(-x_alvo, x, "+")
  nd2 <- -0.5 * d * d
  nd2[!permitido] <- -Inf
  mse <- rep(NA_real_, length(grade_h))
  for (k in seq_along(grade_h)) {
    h <- grade_h[k]
    w <- if (is.infinite(h)) permitido + 0 else exp(nd2 / (h * h))
    wd <- w * d
    S0 <- rowSums(w); S1 <- rowSums(wd); S2 <- rowSums(wd * d)
    T0 <- drop(w %*% y); T1 <- drop(wd %*% y)
    den <- S0 * S2 - S1^2
    if (all(S0 > 0 & den > COND_MIN * S0 * S2))      # h com ponto sem estimativa é descartado
      mse[k] <- mean((y_alvo - (S2 * T0 - S1 * T1) / den)^2)
  }
  mse
}

cv_bloco <- function(x, y, grade_h, l) {
  # h por validação cruzada leave-block-out (Burman, Chow & Nolan, 1994). Um h em que algum
  # ponto fica sem estimativa é descartado. Nenhum h válido → Inf (a reta).
  mse <- .mse_grade(x, y, x, y, mascara_bloco(length(x), l), grade_h)
  if (all(is.na(mse))) return(list(h = Inf, mse = mse))
  list(h = grade_h[which.min(mse)], mse = mse)
}

cv_unilateral <- function(x, y, grade_h, gap, t_min) {
  # h por validação cruzada UNILATERAL (origem móvel): ĝ(x_t) só com o passado s ≤ t − gap,
  # para t = t_min … T−1 — a mesma situação da negociação. Regras de descarte iguais às de
  # cv_bloco.
  T <- length(x)
  alvo <- (t_min + 1):T
  usadas <- seq_len(T - gap)                 # observações que algum dia avaliado pode usar
  permitido <- mascara_unilateral(T, gap, t_min)[, usadas, drop = FALSE]
  mse <- .mse_grade(x[alvo], y[alvo], x[usadas], y[usadas], permitido, grade_h)
  if (all(is.na(mse))) return(list(h = Inf, mse = mse))
  list(h = grade_h[which.min(mse)], mse = mse)
}

residuos_unilaterais <- function(x, y, h, gap, t_min) {
  # u_t = y_t − ĝ_{s ≤ t−gap}(x_t), para t ≥ t_min.
  alvo <- (t_min + 1):length(x)
  y[alvo] - loclin(x[alvo], x, y, h, mascara_unilateral(length(x), gap, t_min))$a
}

residuos_loo <- function(x, y, h) {
  y - loclin(x, x, y, h, mascara_bloco(length(x), 0))$a
}

monitoramento <- function(x_form, y_form, x_neg, y_neg, h, l_suporte) {
  # Curva "até t−1" avaliada em cada dia t da negociação: no k-ésimo dia a curva usa a
  # formação inteira mais os k−1 primeiros dias da negociação.
  # Retorna list(g = ĝ_{t−1}(x_t), b = β_{t−1}(x_t), massa_antiga = massa de kernel vinda só
  # de observações anteriores a t − l_suporte).
  T <- length(x_form); m <- length(x_neg)
  x_all <- c(x_form, x_neg); y_all <- c(y_form, y_neg)
  s <- seq_len(T + m)
  t <- T + seq_len(m)                         # posição do dia t na série contínua
  r <- loclin(x_neg, x_all, y_all, h, mascara = outer(t, s, function(t, s) s < t))
  w_antigo <- pesos_kernel(outer(-x_neg, x_all, "+"), h)
  massa_antiga <- rowSums(w_antigo * outer(t, s, function(t, s) s < t - l_suporte))
  list(g = r$a, b = r$b, massa_antiga = massa_antiga)
}


# ── Teste de cointegração não paramétrica de um par ──────────────────────────────────
teste_coint_np <- function(q_a, q_b, grade_rel, gap = 20, t_min = 126, autolag = "AIC") {
  # O MESMO procedimento é usado na simulação do valor crítico e na formação própria.
  #   1. Nas duas direções (B ~ g(A) e A ~ g(B)), h pela CV unilateral numa grade relativa
  #      ao desvio do regressor.
  #   2. Fica a direção de menor erro de CV RELATIVO (erro ÷ variância da dependente).
  #   3. Erros de previsão UM PASSO À FRENTE (curva só com s ≤ t−1, t ≥ t_min) no h escolhido.
  #   4. Estatística = ADF desses erros, com constante e defasagens por `autolag`.
  # A estatística NÃO se compara com tabelas de Dickey–Fuller ou Engle–Granger: o valor
  # crítico vem da simulação (nonparametric/valor_critico_np.R).
  falha <- list(direcao = NA_character_, h = NA_real_, h_rel = NA_real_, h_linear = FALSE,
                cv_rel = NA_real_, cv_rel_linear = NA_real_, stat = NA_real_, mu = NA_real_,
                sigma = NA_real_, n_erros = 0L)
  melhor <- NULL
  for (dir in c("B~A", "A~B")) {
    if (dir == "B~A") { y <- q_b; x <- q_a } else { y <- q_a; x <- q_b }
    sx <- desvio_pop(x)
    if (sx < 1e-10 || desvio_pop(y) < 1e-10) next
    cv <- cv_unilateral(x, y, grade_rel * sx, gap, t_min)
    yt <- y[(t_min + 1):length(y)]
    var_y <- mean((yt - mean(yt))^2)
    cv_rel <- if (any(is.finite(cv$mse))) min(cv$mse, na.rm = TRUE) / var_y else Inf
    if (is.null(melhor) || cv_rel < melhor$cv_rel)
      melhor <- list(direcao = dir, x = x, y = y, h = cv$h, h_rel = cv$h / sx,
                     h_linear = is.infinite(cv$h), cv_rel = cv_rel,
                     cv_rel_linear = cv$mse[length(cv$mse)] / var_y)
  }
  if (is.null(melhor) || !is.finite(melhor$cv_rel)) return(falha)
  u <- residuos_unilaterais(melhor$x, melhor$y, melhor$h, 1, t_min)
  u <- u[is.finite(u)]
  if (length(u) < 30 || desvio_pop(u) < 1e-12) return(falha)
  stat <- adf_estatistica(u, autolag = autolag, regression = "c")
  list(direcao = melhor$direcao, h = melhor$h, h_rel = melhor$h_rel, h_linear = melhor$h_linear,
       cv_rel = melhor$cv_rel, cv_rel_linear = melhor$cv_rel_linear, stat = stat,
       mu = mean(u), sigma = desvio_pop(u), n_erros = length(u))
}
