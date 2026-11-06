# -*- coding: utf-8 -*-
"""
Estimador local linear da cointegração não paramétrica.

Modelo:   y_t = g(x_t) + u_t,   com y = Q_dep e x = Q_indep (preços normalizados P/P0).

Em cada ponto x o local linear resolve

    min_{a,b}  Σ_s [ y_s − a − b·(x_s − x) ]² · K((x_s − x)/h)

e devolve a curva de equilíbrio ĝ(x) = â(x) e o hedge ratio local β(x) = b̂(x).

Convenções:
  - Kernel gaussiano SEM a constante de normalização, de modo que K(0) = 1. Assim a soma
    dos pesos é diretamente um "número efetivo de observações" perto de x (usado no veto
    por suporte), e os pesos nunca zeram — o sistema 2×2 fica bem condicionado mesmo com
    h pequeno, exceto quando o h é tão pequeno que a exponencial underflowa.
  - h = np.inf dá peso 1 a todas as observações e reproduz o OLS exatamente: a reta é o
    caso-limite do método, e a grade de bandwidth a inclui explicitamente.
  - Pontos em que o sistema é singular (sem massa suficiente) devolvem NaN.

Usado por pairs_formation_np.ipynb (escolha do h), pairs_trading_np.ipynb (monitoramento
e curva congelada na entrada), valor_critico_np.ipynb e pairs_formation_np_propria.ipynb
(teste de cointegração não paramétrica, `teste_coint_np`).
"""
import numpy as np
from statsmodels.tsa.stattools import adfuller

# Limite de condicionamento: den / (S0·S2) = Var_w(d) / E_w(d²) ∈ [0, 1]. Abaixo disso a
# vizinhança ponderada não tem dispersão em x para identificar a inclinação.
COND_MIN = 1e-8


def pesos_kernel(d, h):
    """K(d/h) gaussiano com K(0) = 1. h = inf → pesos iguais a 1 (OLS)."""
    if np.isinf(h):
        return np.ones_like(d)
    return np.exp(-0.5 * (d / h) ** 2)


def loclin(x_eval, x, y, h, mascara=None):
    """
    Local linear avaliado em cada ponto de x_eval.

    x_eval  : (m,) pontos de avaliação
    x, y    : (n,) amostra
    h       : bandwidth, nas mesmas unidades de x (np.inf → OLS)
    mascara : (m, n) booleana, opcional. True = a observação s pode ser usada na avaliação
              do ponto i. É assim que se faz leave-one-out, leave-block-out e o
              "só o passado" do monitoramento.

    Retorna (a, b, massa), cada um (m,):
        a     = ĝ(x_eval)           curva de equilíbrio
        b     = β(x_eval)           inclinação local (hedge ratio)
        massa = Σ_s K((x_s − x)/h)  nº efetivo de observações usadas
    """
    x_eval = np.atleast_1d(np.asarray(x_eval, dtype=float))
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)

    d = x[None, :] - x_eval[:, None]
    w = pesos_kernel(d, h)
    if mascara is not None:
        w = w * mascara

    wd = w * d
    S0 = w.sum(axis=1)
    S1 = wd.sum(axis=1)
    S2 = (wd * d).sum(axis=1)
    T0 = w @ y
    T1 = wd @ y

    den = S0 * S2 - S1 ** 2
    with np.errstate(divide='ignore', invalid='ignore'):
        ok = (S0 > 0) & (den > COND_MIN * S0 * S2)
        a = np.where(ok, (S2 * T0 - S1 * T1) / den, np.nan)
        b = np.where(ok, (S0 * T1 - S1 * T0) / den, np.nan)
    return a, b, S0


def mascara_bloco(n, l):
    """(n, n) booleana: True onde |s − t| > l. l = 0 → leave-one-out."""
    idx = np.arange(n)
    return np.abs(idx[:, None] - idx[None, :]) > l


def cv_bloco(x, y, grade_h, l):
    """
    Escolhe h por validação cruzada leave-block-out (Burman, Chow & Nolan, 1994).

    Para cada h, ĝ(x_t) é estimado SEM as observações a menos de l pregões de t, e o
    critério é o erro quadrático médio dessa previsão. Com l = 0 é o LS-CV leave-one-out
    de Liang, Lin & Hsiao (2015) — que, com regressor I(1) e resíduo persistente,
    subsuaviza: os vizinhos de x_t no eixo do preço são os dias t±1, cujo erro é
    correlacionado com o de t.

    Um h em que algum ponto fica sem estimativa (massa insuficiente fora do bloco) é
    descartado: não é uma curva definida na amostra inteira.

    Retorna (h_escolhido, mse) — mse alinhado com grade_h, NaN nos h descartados.
    Se nenhum h for válido, devolve np.inf (a reta).
    """
    mascara = mascara_bloco(len(x), l)
    mse = np.full(len(grade_h), np.nan)
    for k, h in enumerate(grade_h):
        a, _, _ = loclin(x, x, y, h, mascara)
        if np.all(np.isfinite(a)):
            mse[k] = np.mean((y - a) ** 2)
    if np.all(np.isnan(mse)):
        return np.inf, mse
    return grade_h[np.nanargmin(mse)], mse


def mascara_unilateral(T, gap, t_min):
    """(T − t_min, T) booleana: para cada t ≥ t_min, True nas observações s ≤ t − gap."""
    t = np.arange(t_min, T)[:, None]
    s = np.arange(T)[None, :]
    return s <= t - gap


def cv_unilateral(x, y, grade_h, gap, t_min):
    """
    Escolhe h por validação cruzada UNILATERAL (origem móvel): ĝ(x_t) é estimado só com o
    passado s ≤ t − gap, para t = t_min … T−1. Nenhum dado posterior a t entra — é a mesma
    situação da negociação, em que a curva do dia t só conhece o passado.

    gap = 1  → reproduz o monitoramento (curva até t−1)
    gap = L  → exige que o passado usado tenha pelo menos L pregões de idade (análogo
               unilateral do bloco: a curva em x_t só pode vir de passagens antigas do preço)
    t_min    → primeiro dia avaliado; antes dele o passado é curto demais para estimar a curva

    Mesmas regras de cv_bloco: h com algum ponto sem estimativa é descartado; se nenhum h
    for válido, devolve np.inf. Retorna (h_escolhido, mse) alinhado com grade_h.
    """
    mascara = mascara_unilateral(len(x), gap, t_min)
    x_alvo, y_alvo = x[t_min:], y[t_min:]
    mse = np.full(len(grade_h), np.nan)
    for k, h in enumerate(grade_h):
        a, _, _ = loclin(x_alvo, x, y, h, mascara)
        if np.all(np.isfinite(a)):
            mse[k] = np.mean((y_alvo - a) ** 2)
    if np.all(np.isnan(mse)):
        return np.inf, mse
    return grade_h[np.nanargmin(mse)], mse


def residuos_unilaterais(x, y, h, gap, t_min):
    """Resíduo de previsão unilateral u_t = y_t − ĝ_{s ≤ t−gap}(x_t), para t ≥ t_min."""
    a, _, _ = loclin(x[t_min:], x, y, h, mascara_unilateral(len(x), gap, t_min))
    return y[t_min:] - a


def residuos_loo(x, y, h):
    """Resíduo leave-one-out u_t = y_t − ĝ_{−t}(x_t)."""
    a, _, _ = loclin(x, x, y, h, mascara_bloco(len(x), 0))
    return y - a


def monitoramento(x_form, y_form, x_neg, y_neg, h, l_suporte):
    """
    Curva "até t−1" avaliada em cada dia t da negociação.

    No dia t (k-ésimo da negociação) a curva usa a formação inteira mais os k primeiros
    dias da negociação — tudo estritamente anterior a t — e é avaliada em x_t. O ponto t
    fica de fora para que o próprio dado do dia não absorva o desvio que se quer operar.

    Retorna, cada um (m,):
        g      ĝ_{t−1}(x_t)          para o spread y_t − ĝ
        b      β_{t−1}(x_t)          hedge ratio candidato na entrada
        massa_antiga                  massa de kernel em x_t vinda só de observações
                                      anteriores a t − l_suporte: mede se a curva em x_t
                                      está identificada por dados que não são o próprio
                                      movimento recente (veto por suporte)
    """
    T, m = len(x_form), len(x_neg)
    x_all = np.concatenate([x_form, x_neg])
    y_all = np.concatenate([y_form, y_neg])
    s = np.arange(T + m)[None, :]
    t = (T + np.arange(m))[:, None]

    g, b, _ = loclin(x_neg, x_all, y_all, h, mascara=s < t)

    w_antigo = pesos_kernel(x_all[None, :] - np.asarray(x_neg, float)[:, None], h)
    massa_antiga = (w_antigo * (s < t - l_suporte)).sum(axis=1)
    return g, b, massa_antiga


def teste_coint_np(q_a, q_b, grade_rel, gap=20, t_min=126, autolag='AIC'):
    """
    Teste de cointegração não paramétrica de um par — o MESMO procedimento é usado na simulação
    do valor crítico (valor_critico_np.ipynb) e na formação própria (pairs_formation_np_propria),
    o que é condição para o valor crítico simulado valer.

    Passos:
      1. Para as duas direções (B ~ g(A) e A ~ g(B)), escolhe h pela CV unilateral
         (`cv_unilateral`, gap e t_min dados), numa grade relativa ao desvio do regressor.
      2. Fica com a direção de menor erro de CV RELATIVO (erro ÷ variância da dependente nos dias
         avaliados) — as duas direções têm dependentes diferentes, então o erro bruto não compara.
      3. Calcula os erros de previsão UM PASSO À FRENTE (curva só com s ≤ t−1, t ≥ t_min) no h
         escolhido: é a mesma natureza do spread monitorado na negociação.
      4. Estatística = ADF desses erros, com constante (regression='c': ao contrário do resíduo do
         OLS, o erro fora da amostra não tem média zero por construção) e lags por `autolag`.

    A estatística NÃO deve ser comparada com tabelas de Dickey–Fuller ou de Engle–Granger
    (MacKinnon): a curva é ajustada aos dados e o h é escolhido por CV, então a distribuição sob
    "sem cointegração" é outra (Phillips, 2009, regressão não paramétrica espúria). O valor
    crítico vem da simulação em valor_critico_np.ipynb.

    q_a, q_b : arrays de preços normalizados (Q = P/P0) dos ativos A (ativo1) e B (ativo2).
    Retorna dict com direcao ('B~A' → dependente = B; 'A~B' → dependente = A), h, h_rel,
    h_linear, cv_rel, cv_rel_linear, stat, mu, sigma, n_erros.
    """
    q_a = np.asarray(q_a, dtype=float)
    q_b = np.asarray(q_b, dtype=float)
    melhor = None
    for direcao, y, x in (('B~A', q_b, q_a), ('A~B', q_a, q_b)):
        sx = x.std()
        if sx < 1e-10 or y.std() < 1e-10:
            continue
        h, mse = cv_unilateral(x, y, np.asarray(grade_rel) * sx, gap, t_min)
        var_y = np.var(y[t_min:])
        cv_rel = np.nanmin(mse) / var_y if np.any(np.isfinite(mse)) else np.inf
        if melhor is None or cv_rel < melhor['cv_rel']:
            melhor = {'direcao': direcao, 'x': x, 'y': y, 'h': h, 'h_rel': h / sx,
                      'h_linear': bool(np.isinf(h)), 'cv_rel': cv_rel, 'cv_rel_linear': mse[-1] / var_y}
    falha = {'direcao': None, 'h': np.nan, 'h_rel': np.nan, 'h_linear': False, 'cv_rel': np.nan,
             'cv_rel_linear': np.nan, 'stat': np.nan, 'mu': np.nan, 'sigma': np.nan, 'n_erros': 0}
    if melhor is None or not np.isfinite(melhor['cv_rel']):
        return falha
    u = residuos_unilaterais(melhor['x'], melhor['y'], melhor['h'], 1, t_min)
    u = u[np.isfinite(u)]
    if len(u) < 30 or u.std() < 1e-12:
        return falha
    stat = float(adfuller(u, regression='c', autolag=autolag)[0])
    return {k: melhor[k] for k in ('direcao', 'h', 'h_rel', 'h_linear', 'cv_rel', 'cv_rel_linear')} | \
           {'stat': stat, 'mu': float(u.mean()), 'sigma': float(u.std()), 'n_erros': int(len(u))}
