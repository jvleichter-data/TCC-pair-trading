# -*- coding: utf-8 -*-
# OLS com intercepto e teste ADF — usados pela cointegração linear e pela não paramétrica.
#
# O ADF é implementado aqui, sem pacote: as funções prontas do R (tseries::adf.test,
# urca::ur.df) escolhem as defasagens de outro jeito e não reproduzem o
# statsmodels.tsa.stattools.adfuller usado nos notebooks. adf_estatistica() segue o
# adfuller passo a passo (maxlag de Schwert, busca por AIC/BIC na mesma amostra, reestimação
# com a defasagem escolhida).


# ── OLS com intercepto: y = alpha + beta·x + resíduo ─────────────────────────────────
ols_residuo <- function(y, x) {
  xm <- mean(x); ym <- mean(y)
  dx <- x - xm
  beta  <- sum(dx * (y - ym)) / sum(dx * dx)
  alpha <- ym - beta * xm
  list(alpha = alpha, beta = beta, resid = y - alpha - beta * x)
}

desvio_pop <- function(x) sqrt(mean((x - mean(x))^2))   # numpy .std() (ddof = 0)


# ── Augmented Dickey-Fuller, idêntico ao statsmodels.adfuller ────────────────────────
adf_estatistica <- function(x, autolag = "AIC", regression = "n") {
  # regression: "n" (sem termos determinísticos) ou "c" (constante).
  # autolag   : "AIC" ou "BIC".
  # Devolve a estatística t do coeficiente do nível defasado.
  x <- as.numeric(x)
  n <- length(x)
  ntrend <- if (regression == "n") 0L else 1L
  maxlag <- ceiling(12 * (n / 100)^(1 / 4))
  maxlag <- min(n %/% 2 - ntrend - 1, maxlag)
  xdiff <- diff(x)

  # Regressores para L defasagens: [nível x_t, Δx_{t−1}, …, Δx_{t−L}], explicando Δx_t.
  # A amostra é a mesma para todo L ≤ maxlag na busca (como o adfuller faz).
  montar <- function(L) {
    E <- embed(xdiff, L + 1)               # colunas: Δx_t, Δx_{t−1}, …, Δx_{t−L}
    t <- (L + 1):(n - 1)
    E[, 1] <- x[t]                         # troca Δx_t pelo nível x_t
    list(y = xdiff[t], X = E)
  }

  # 1) Busca da defasagem: modelos encaixados sobre a amostra do maxlag.
  m <- montar(maxlag)
  X <- if (ntrend) cbind(1, m$X) else m$X
  nobs <- nrow(X)
  primeira <- ntrend + 1                   # nº de colunas do menor modelo (só o nível)
  qx <- qr(X)
  if (qx$rank == ncol(X) && all(qx$pivot == seq_len(ncol(X)))) {
    # Com colunas encaixadas, a SSR do modelo com as k primeiras colunas sai de uma só
    # decomposição QR: soma dos quadrados dos "effects" a partir de k+1.
    e2 <- qr.qty(qx, m$y)^2
    cauda <- rev(cumsum(rev(e2)))
    ssr <- cauda[(primeira:ncol(X)) + 1]
  } else {
    ssr <- vapply(primeira:ncol(X), function(k) {
      sum(stats::lm.fit(X[, 1:k, drop = FALSE], m$y)$residuals^2)
    }, numeric(1))
  }
  k <- primeira:ncol(X)
  llf <- -nobs / 2 * (log(2 * pi) + log(ssr / nobs) + 1)
  ic <- if (toupper(autolag) == "BIC") -2 * llf + log(nobs) * k else -2 * llf + 2 * k
  bestlag <- k[which.min(ic)] - primeira   # empate → menor defasagem, como o adfuller

  # 2) Reestima com a defasagem escolhida, na amostra mais longa que ela permite.
  m <- montar(bestlag)
  X <- if (ntrend) cbind(m$X, 1) else m$X  # o adfuller põe a constante no fim aqui
  qx <- qr(X)
  coef <- qr.coef(qx, m$y)
  res <- m$y - X %*% coef
  s2 <- sum(res^2) / (nrow(X) - ncol(X))
  XtXinv <- chol2inv(qr.R(qx))
  ord <- order(qx$pivot)
  coef[1] / sqrt(s2 * XtXinv[ord, ord, drop = FALSE][1, 1])
}
