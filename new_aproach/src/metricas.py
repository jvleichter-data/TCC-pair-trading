# -*- coding: utf-8 -*-
"""
Bloco de métricas comparáveis — distância.

Cada artigo reporta numa frequência diferente. Só a MÉDIA converte entre elas;
desvio, Sharpe, assimetria, curtose, mínimo, máximo e % de negativos NÃO convertem.

  orientador (QREF 2023)  → série DIÁRIA, média × 252, Sharpe × √252
  Gatev (RFS 2006)        → série MENSAL, média por mês, sem anualizar
  Rad et al. (QF 2016)    → série MENSAL, Sharpe = média/desvio MENSAL (não anualizado)
"""
import numpy as np
import pandas as pd

DIAS_ANO = 252
MESES_ANO = 12

# ── Referências publicadas ───────────────────────────────────────────────────
# Orientador, Tabela 4: Distance, Top 20, Committed Capital, sem custos,
# Jul/1991–Dez/2015, 6.173 observações diárias, S&P 500.
REF_ORIENTADOR = {
    'Mean Return (% a.a.)': 3.600, 'Annualized STD (%)': 5.000,
    'Sharpe Ratio': 0.703, 'Sortino Ratio': 1.233, 't-stat (Newey-West)': 3.636,
    '% de retornos negativos': 47.58, 'Skewness': 0.343, 'Kurtosis': 10.12,
    'Mínimo diário (%)': -2.800, 'Máximo diário (%)': 2.900,
    'MDD1 (%)': 3.950, 'MDD2 (%)': 11.73, 'Observações': 6173,
}
# Gatev et al. (2006), Tabela 1 Painel A, Top 20, série MENSAL,
# 474 meses, Jul/1963–Dez/2002, CRSP inteira, carteiras SOBREPOSTAS.
REF_GATEV = {
    'Média mensal': 0.01436, 'Desvio-padrão mensal': 0.01688,
    't-stat (Newey-West)': 11.56, 'Mediana mensal': 0.01235,
    'Skewness': 1.39, 'Kurtosis': 10.54,
    'Mínimo mensal': -0.06629, 'Máximo mensal': 0.13295,
    '% de meses negativos': 15.0, 'Observações': 474,
}
GATEV_CC_MEDIA = 0.00805   # committed capital; Gatev não publica o desvio da série CC
# Rad et al. (2016), Tabela 3 Seção 2 Painel B (committed capital, antes de custos),
# série MENSAL, Jul/1962–Dez/2014, CRSP, carteiras SOBREPOSTAS.
REF_RAD_DIST = {
    'Média mensal': 0.0068, 'Desvio-padrão mensal': 0.0102,
    't-stat (Newey-West)': 7.0284, 'Sharpe MENSAL': 0.6729,
    'Skewness': 0.8152, 'Kurtosis': 14.6456,
}
REF_RAD_COINT = {
    'Média mensal': 0.0068, 'Desvio-padrão mensal': 0.0097,
    't-stat (Newey-West)': 7.0365, 'Sharpe MENSAL': 0.6969,
    'Skewness': 1.3934, 'Kurtosis': 10.8547,
}


# ── Estatísticas auxiliares ──────────────────────────────────────────────────
def t_newey_west(x, lags=6):
    """t-statistic da média com erro-padrão de Newey-West (Bartlett)."""
    x = np.asarray(x, float)
    x = x[~np.isnan(x)]
    n = len(x)
    e = x - x.mean()
    s2 = (e @ e) / n
    for L in range(1, lags + 1):
        s2 += 2 * (1 - L / (lags + 1)) * ((e[L:] @ e[:-L]) / n)
    return x.mean() / np.sqrt(s2 / n)


def downside_deviation(x, mar=0.0):
    """Desvio à esquerda: raiz da média de min(r−MAR,0)², sobre TODAS as
    observações (definição padrão do Sortino, não só sobre as negativas)."""
    x = np.asarray(x, float)
    return np.sqrt((np.minimum(x - mar, 0.0) ** 2).mean())


def mdd_janela(serie, dias):
    """Maior queda percentual entre dois pregões separados por no máximo `dias`.
    `dias=1` devolve o pior retorno de um dia; `dias=126`, o pior drawdown
    dentro de uma janela de seis meses.
    (A janela do rolling é dias+1 porque ela inclui o próprio dia t.)"""
    eq = (1 + serie).cumprod()
    return float((eq / eq.rolling(dias + 1, min_periods=1).max() - 1).min())


def para_mensal(serie_diaria):
    """Compõe a série diária dentro de cada mês — é o que Gatev faz:
    'the daily returns are compounded to obtain monthly returns'."""
    return serie_diaria.groupby(serie_diaria.index.to_period('M')).apply(
        lambda r: (1 + r).prod() - 1)


# ── Os dois blocos ───────────────────────────────────────────────────────────
def metricas_diarias(s):
    """Convenção do ORIENTADOR (Tabela 4). É o bloco a usar na comparação
    com o artigo dele."""
    eq = (1 + s).cumprod()
    return {
        'Mean Return (% a.a.)':    s.mean() * DIAS_ANO * 100,
        'Annualized STD (%)':      s.std() * np.sqrt(DIAS_ANO) * 100,
        'Sharpe Ratio':            s.mean() / s.std() * np.sqrt(DIAS_ANO),
        'Sortino Ratio':           s.mean() / downside_deviation(s) * np.sqrt(DIAS_ANO),
        't-stat (Newey-West)':     t_newey_west(s, 6),
        '% de retornos negativos': (s < 0).mean() * 100,
        'Skewness':                s.skew(),
        'Kurtosis':                s.kurtosis() + 3,
        'Mínimo diário (%)':       s.min() * 100,
        'Máximo diário (%)':       s.max() * 100,
        'MDD1 (%)':               -mdd_janela(s, 2) * 100,
        'MDD2 (%)':               -mdd_janela(s, 126) * 100,
        'Observações':             float(len(s)),
        # fora da Tabela 4, mas úteis:
        'Retorno acumulado (%)':   (eq.iloc[-1] - 1) * 100,
        'CAGR (% a.a.)':           (eq.iloc[-1] ** (DIAS_ANO / len(s)) - 1) * 100,
        'Drawdown máximo (%)':    -float(((eq - eq.cummax()) / eq.cummax()).min()) * 100,
    }


def metricas_mensais(s):
    """Convenção de GATEV e RAD. Série diária composta dentro do mês."""
    m = para_mensal(s)
    return {
        'Média mensal':          m.mean(),
        'Desvio-padrão mensal':  m.std(),
        'Sharpe MENSAL':         m.mean() / m.std(),
        't-stat (Newey-West)':   t_newey_west(m, 6),
        'Mediana mensal':        m.median(),
        'Skewness':              m.skew(),
        'Kurtosis':              m.kurtosis() + 3,
        'Mínimo mensal':         m.min(),
        'Máximo mensal':         m.max(),
        '% de meses negativos':  (m < 0).mean() * 100,
        'Observações':           float(len(m)),
        # pontes:
        'Média × 12 (% a.a.)':   m.mean() * MESES_ANO * 100,
        'Sharpe × √12':          m.mean() / m.std() * np.sqrt(MESES_ANO),
    }


# ── Impressão ────────────────────────────────────────────────────────────────
def _tab(titulo, nosso, ref, ordem, rotulo_ref, fmt=None):
    fmt = fmt or (lambda v: f'{v:>12.3f}')
    print('=' * 74)
    print(titulo)
    print('=' * 74)
    print(f"{'':<26}{rotulo_ref:>14}{'nosso':>14}{'diferença':>14}")
    print('-' * 74)
    for k in ordem:
        n = nosso.get(k, np.nan)
        r = ref.get(k, np.nan)
        sr = fmt(r) if r == r else f"{'—':>12}"
        sn = fmt(n) if n == n else f"{'—':>12}"
        sd = fmt(n - r) if (r == r and n == n) else f"{'—':>12}"
        print(f'{k:<26}{sr:>14}{sn:>14}{sd:>14}')


def relatorio(s, mostrar_gatev_rad=True):
    d = metricas_diarias(s)
    mm = metricas_mensais(s)

    _tab('BLOCO A — convenção do ORIENTADOR (série diária anualizada)\n'
         'Alvo: Tabela 4, Distance, Top 20, Committed Capital, sem custos',
         d, REF_ORIENTADOR,
         ['Mean Return (% a.a.)', 'Annualized STD (%)', 'Sharpe Ratio', 'Sortino Ratio',
          't-stat (Newey-West)', '% de retornos negativos', 'Skewness', 'Kurtosis',
          'Mínimo diário (%)', 'Máximo diário (%)', 'MDD1 (%)', 'MDD2 (%)', 'Observações'],
         'artigo')
    print()
    print('  Extras (não estão na Tabela 4):')
    for k in ['Retorno acumulado (%)', 'CAGR (% a.a.)', 'Drawdown máximo (%)']:
        print(f'    {k:<26}{d[k]:>12.3f}')
    print()

    if not mostrar_gatev_rad:
        return d, mm

    print('=' * 74)
    print('BLOCO B — convenção de GATEV (2006) e RAD et al. (2016): série MENSAL')
    print('=' * 74)
    print('  Nossa série mensal (committed capital, composta dentro do mês):')
    for k in ['Média mensal', 'Desvio-padrão mensal', 'Sharpe MENSAL', 't-stat (Newey-West)',
              'Mediana mensal', 'Skewness', 'Kurtosis', 'Mínimo mensal', 'Máximo mensal',
              '% de meses negativos', 'Observações']:
        print(f'    {k:<26}{mm[k]:>12.5f}')
    print()
    print('  ── Gatev (2006), Tab.1 Painel A, Top 20 · CRSP 1963–2002, 474 meses ──')
    print(f"    committed capital, média mensal : {GATEV_CC_MEDIA:.5f}  "
          f"(= {GATEV_CC_MEDIA*12*100:.2f}% a.a.)")
    print(f"    NOSSO committed capital         : {mm['Média mensal']:.5f}  "
          f"(= {mm['Média × 12 (% a.a.)']:.2f}% a.a.)")
    print('    ⚠ é a ÚNICA estatística de committed capital que Gatev publica.')
    print('      O resto da Tabela 1 dele é da série FULLY INVESTED, que não se')
    print('      compara com a nossa — para isso, rodar com COMMITTED_CAPITAL=False:')
    print(f"        fully invested Top 20: média {REF_GATEV['Média mensal']:.5f} · "
          f"sd {REF_GATEV['Desvio-padrão mensal']:.5f} · "
          f"skew {REF_GATEV['Skewness']:.2f} · curt {REF_GATEV['Kurtosis']:.2f} · "
          f"{REF_GATEV['% de meses negativos']:.0f}% de meses negativos")
    print()
    _tab('Rad et al. (2016) Tab.3 Seção 2 Painel B — committed capital, antes de custos\n'
         'CRSP 1962–2014, formação 12m / negociação 6m',
         mm, REF_RAD_DIST,
         ['Média mensal', 'Desvio-padrão mensal', 'Sharpe MENSAL', 't-stat (Newey-West)',
          'Skewness', 'Kurtosis'],
         'Rad DM', fmt=lambda v: f'{v:>12.4f}')
    print()
    print('  Rad, cointegração (para o outro método do TCC): '
          f"média {REF_RAD_COINT['Média mensal']:.4f} · sd {REF_RAD_COINT['Desvio-padrão mensal']:.4f} "
          f"· Sharpe mensal {REF_RAD_COINT['Sharpe MENSAL']:.4f}")
    print()
    print('  ⚠ Gatev e Rad iniciam uma carteira por MÊS e tiram a média das 6 sobrepostas.')
    print('    Nosso PASSO_MESES=6 usa semestres NÃO sobrepostos, como o orientador.')
    print('    Para comparar com eles de verdade, rodar a formação com PASSO_MESES=1.')
    print('    As amostras também diferem: eles usam a CRSP inteira (inclui small caps),')
    print('    nós usamos o S&P 500. Diferença de nível é esperada.')
    return d, mm
