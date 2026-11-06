# -*- coding: utf-8 -*-
# ── Teste de Wang & Phillips (2012) — diagnóstico de linearidade ─────────────────────
# Tradução de especificacao_np.py. H0: y = α + βx + u (linear) contra g não linear.
#   S_n = Σ_{s≠t} û_s û_t K((x_t − x_s)/h),  V_n² = Σ_{s≠t} û_s² û_t² K²(·),
#   Z_n = S_n / (√2·V_n) → N(0,1); rejeita para Z_n grande.
# Com erro autocorrelacionado a N(0,1) rejeita demais; o p-valor principal vem de um
# bootstrap sob H0 com erro AR(1) (ver o notebook diagnostico_wang_phillips).
teste_wp <- function(x, y, B = 199, h_expoente = 1 / 3) {
  # Usa o gerador aleatório do R: fixe a semente (set.seed) antes de chamar.
  n <- length(x)
  xs <- x / desvio_pop(diff(x))                  # incrementos de variância ~1, como no artigo
  h <- n^(-h_expoente)
  D <- outer(xs, xs, "-") / h
  K <- exp(-0.5 * D * D); diag(K) <- 0
  K2 <- K * K
  X <- cbind(1, x)
  coef <- qr.coef(qr(X), y)
  ajuste <- drop(X %*% coef)
  u <- y - ajuste
  z_de <- function(U) {                          # U: réplicas nas linhas
    S <- rowSums((U %*% K) * U)
    U2 <- U * U
    S / sqrt(2 * rowSums((U2 %*% K2) * U2))
  }
  z <- z_de(matrix(u, nrow = 1))

  phi <- sum(u[-1] * u[-n]) / sum(u[-n] * u[-n])
  e <- u[-1] - phi * u[-n]
  e <- e - mean(e)
  queima <- 100
  E <- matrix(sample(e, B * (n + queima), replace = TRUE), nrow = B)
  Ustar <- t(apply(E, 1, function(v) stats::filter(v, phi, method = "recursive")))[, -(1:queima), drop = FALSE]
  Ystar <- sweep(Ustar, 2, ajuste, "+")
  P <- X %*% solve(crossprod(X), t(X))           # projeção do OLS: resíduo = (I − P) y*
  Rstar <- Ystar - Ystar %*% t(P)
  zs <- z_de(Rstar)
  list(z = z, p_normal = 1 - stats::pnorm(z), p_boot = (1 + sum(zs >= z)) / (B + 1), phi = phi, h = h)
}
