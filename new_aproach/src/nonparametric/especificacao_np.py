# -*- coding: utf-8 -*-
"""
Teste de especificação de Wang & Phillips (2012), "A specification test for nonlinear nonstationary
models", Annals of Statistics 40(2), DOI 10.1214/12-AOS975 — usado como DIAGNÓSTICO de linearidade
(slide 29: H0: g(x) = α + βx), não como critério de seleção de pares.

Estatística (W&P 2012, Seção 2, eq. (2), e Teorema 3.1, eq. (6)):

    S_n   = Σ_{s≠t} û_s û_t K((x_t − x_s)/h)
    V_n²  = Σ_{s≠t} û_s² û_t² K²((x_t − x_s)/h)
    Z_n   = S_n / (√2 · V_n)  →  N(0, 1) sob H0;  rejeita para Z_n grande (unicaudal)

com û os resíduos do ajuste paramétrico sob H0 (aqui, OLS de y em x).

Escolhas e adaptações (todas declaradas em DECISOES.md § 9):
  • Kernel gaussiano (o artigo só exige K limitado e integrável — Assumption 3).
  • Escala de x: dividimos pelo desvio do incremento diário, para x ficar como no desenho de
    simulação do artigo (passeio com incrementos de variância 1); h = n^(−1/3), o meio da grade
    {n^(−1/4), n^(−1/3), n^(−1/2,5)} usada por eles (Seção 4).
  • Timing: o artigo usa y_{t+1} = f(x_t) + u_{t+1}; usamos a relação contemporânea y_t = g(x_t) + u_t,
    a mesma da cointegração do método.
  • ⚠️ O artigo supõe u_t diferença de martingal (Assumption 2(i)); nossos spreads têm AR(1) ≈ 0,9 e
    o próprio artigo diz que a extensão a erros serialmente correlacionados não está provada. Com
    resíduo autocorrelacionado a aproximação N(0,1) rejeita demais. Por isso o p-valor principal vem
    de um BOOTSTRAP SOB H0 com erro AR(1): y* = α̂ + β̂x + u*, u*_t = φ̂u*_{t−1} + e*_t, e* reamostrado
    dos resíduos do AR(1); x fica fixo; para cada réplica refaz o OLS e recalcula Z_n.
    Mesma lógica do valor crítico simulado da formação própria. O p-valor N(0,1) é reportado só
    para mostrar a distorção.
"""
import numpy as np
from scipy.signal import lfilter
from scipy.stats import norm


def _z(u, K, K2):
    """Z_n dado o resíduo u e as matrizes K, K² (diagonal zerada)."""
    S = u @ K @ u
    u2 = u * u
    V2 = u2 @ K2 @ u2
    return S / np.sqrt(2.0 * V2)


def _z_lote(U, K, K2):
    """Z_n para várias séries de resíduo (linhas de U)."""
    S = np.einsum('bi,ij,bj->b', U, K, U)
    U2 = U * U
    V2 = np.einsum('bi,ij,bj->b', U2, K2, U2)
    return S / np.sqrt(2.0 * V2)


def teste_wp(x, y, B=199, h_expoente=1 / 3, rng=None):
    """
    Teste de Wang & Phillips (2012) de H0: y = α + βx + u (linear) contra g não linear.

    x, y : arrays (preços normalizados Q, na direção escolhida: y dependente, x independente).
    Retorna dict: z, p_normal (aproximação assintótica, inválida com erro autocorrelacionado),
    p_boot (bootstrap AR(1) sob H0), phi (AR(1) do resíduo linear), h (em unidades padronizadas).
    """
    rng = np.random.default_rng() if rng is None else rng
    x = np.asarray(x, float)
    y = np.asarray(y, float)
    n = len(x)
    xs = x / np.std(np.diff(x))                    # incrementos de variância ~1, como no artigo
    h = n ** (-h_expoente)
    D = (xs[:, None] - xs[None, :]) / h
    K = np.exp(-0.5 * D * D)
    np.fill_diagonal(K, 0.0)
    K2 = K * K

    X = np.column_stack([np.ones(n), x])
    coef, *_ = np.linalg.lstsq(X, y, rcond=None)
    u = y - X @ coef
    z = float(_z(u, K, K2))

    # AR(1) do resíduo sob H0 e bootstrap
    phi = float(np.dot(u[1:], u[:-1]) / np.dot(u[:-1], u[:-1]))
    e = u[1:] - phi * u[:-1]
    e = e - e.mean()
    queima = 100                                   # descarta o início: u*_0 vem da distribuição estacionária
    E = rng.choice(e, size=(B, n + queima), replace=True)
    Ustar = lfilter([1.0], [1.0, -phi], E, axis=1)[:, queima:]   # u*_t = φ u*_{t−1} + e*_t
    Ystar = (X @ coef)[None, :] + Ustar
    P = X @ np.linalg.pinv(X)                      # projeção do OLS: resíduo = (I − P) y*
    Rstar = Ystar - Ystar @ P.T
    zs = _z_lote(Rstar, K, K2)
    p_boot = float((1 + np.sum(zs >= z)) / (B + 1))
    return {'z': z, 'p_normal': float(1 - norm.cdf(z)), 'p_boot': p_boot, 'phi': phi, 'h': h}


def aplica_lote(tarefas):
    """Para paralelizar: tarefas = lista de (x, y, B, h_expoente, semente) → lista de dicts de teste_wp."""
    return [teste_wp(x, y, B=B, h_expoente=he, rng=np.random.default_rng(s)) for x, y, B, he, s in tarefas]
