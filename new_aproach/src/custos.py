# -*- coding: utf-8 -*-
"""
Custos de transação — compartilhado pelos três métodos (distância, cointegração linear, NP).

Dois esquemas (decisão do usuário, 03/11/2026; registro em validation/custos/DECISOES_CUSTOS.md):

  'rad'        Rad et al. (2016) § 4.4, com Do & Faff (2012): por dólar negociado em cada perna,
               em cada compra ou venda, taxa = comissão(ano) + impacto de mercado(ano).
               · impacto: 30 bps até 1988, 20 bps de 1989 em diante (Rad; Do & Faff).
               · comissão: Do & Faff vão de 70 bps (1962/63) a 9 bps (2009). A tabela anual
                 deles não está no repositório (artigo pago); até obtê-la, 1991–2009 cai em
                 linha reta de 15 bps (1991, nível implícito em Fil 2020, Tab. 1: 35 bps de
                 custo total one-way em 1990 − 20 de impacto) a 9 bps (2009).
               · depois de 2009 segura o último valor (9 + 20 = 29 bps), como Rad, cuja
                 amostra vai até 2014 com "9 bps for recent years".
  'rad_metade' A mesma tabela × 0,5: leitura alternativa de "double these costs … two
               round-trip trades" (comissão + impacto por ida-e-volta, e não por ordem).
  'professor'  Código de referência dos alunos do orientador (distance_gatev.py, ramo sem
               espera de um dia) e Sabino da Silva et al. (2023): 20 bps fixos por trade,
               descontados do retorno do par no dia do fechamento (inclusive o fechamento
               forçado no fim do período), independentemente do tamanho das pernas.

Quando o custo é cobrado (convenção de execução dos notebooks: o sinal no fechamento de s é
executado no fechamento de s; o retorno corre a partir de s+1):
  · abertura no fechamento de s  → custo lançado no dia s+1 (primeiro dia com posição; é o
    dia em que o trade já conta como ativo em "fully invested"). Valor das pernas: preços de s.
  · fechamento no fechamento de tc → custo lançado em tc. Valor das pernas: preços de tc.
  · posição aberta no último dia do período (s = último): nunca carregada; sem custo (a
    posição não chega a existir — equivale a não abrir no último dia).
"""
import numpy as np
import pandas as pd

ESQUEMAS = ('rad', 'rad_metade', 'professor')
PROF_BPS = 20.0


def taxa_rad(datas):
    """Taxa one-way por dólar negociado (fração) para cada data — comissão + impacto."""
    y = pd.DatetimeIndex(datas).year.values.astype(float)
    comissao = np.where(y <= 1991, 15.0,
                        np.where(y >= 2009, 9.0, 15.0 - 6.0 * (y - 1991) / 18.0))
    impacto = np.where(y >= 1989, 20.0, 30.0)
    return (comissao + impacto) / 1e4


def segmentos(position):
    """Trades como (s, e, sinal): posição de sinal (sem lag) ≠ 0 e constante de s a e."""
    p = np.asarray(position, float)
    out, s = [], None
    for t in range(len(p)):
        if p[t] != 0 and (s is None or p[t] != p[s]):
            if s is not None:
                out.append((s, t - 1, int(np.sign(p[s]))))
            s = t
        elif p[t] == 0 and s is not None:
            out.append((s, t - 1, int(np.sign(p[s]))))
            s = None
    if s is not None:
        out.append((s, len(p) - 1, int(np.sign(p[s]))))
    return out


def custos_trades(datas, position, valor_abre, valor_fecha):
    """
    Custo diário (fração do $1 do par) em cada esquema.

    valor_abre(s, sinal)      → valor bruto das duas pernas negociadas na abertura (fecho de s)
    valor_fecha(s, tc, sinal) → idem no fechamento (fecho de tc)
    Devolve dict esquema → array, e dict de diagnóstico (n_trades, volume total).
    """
    m = len(position)
    taxa = taxa_rad(datas)
    c = {k: np.zeros(m) for k in ESQUEMAS}
    vol = np.zeros(m)
    n = 0
    for s, e, sg in segmentos(position):
        if s >= m - 1:
            continue                       # aberta no último fechamento: nunca carregada
        n += 1
        tc = e + 1 if e < m - 1 else m - 1
        va, vf = valor_abre(s, sg), valor_fecha(s, tc, sg)
        vol[s + 1] += va
        vol[tc] += vf
        c['rad'][s + 1] += taxa[s] * va
        c['rad'][tc] += taxa[tc] * vf
        c['professor'][tc] += PROF_BPS / 1e4
    c['rad_metade'] = 0.5 * c['rad']
    return c, {'n_trades': n, 'volume': vol}


# ── valor negociado por método ───────────────────────────────────────────────────────────
def custos_distancia(df, precos_neg, a1, a2):
    """Gatev: $1 comprado + $1 vendido na abertura; no fechamento, o valor das pernas
    (pesos buy-and-hold do próprio notebook × retorno do dia)."""
    r = precos_neg[[a1, a2]].pct_change().fillna(0).reindex(df.index).fillna(0).values
    wl, ws = df['peso_long'].values, df['peso_short'].values

    def fecha(s, tc, sg):
        rl, rs = (r[tc, 0], r[tc, 1]) if sg > 0 else (r[tc, 1], r[tc, 0])
        return wl[tc] * (1 + rl) + ws[tc] * (1 + rs)
    return custos_trades(df.index, df['position'].values, lambda s, sg: 2.0, fecha)


def custos_spread(df, q_dep, q_ind, beta_trade, escala_fn):
    """Cointegração (linear e NP): 1 unidade de Q_dep contra β de Q_ind, escalada como o
    retorno do notebook (escala_fn(sinal, β)). Valor = escala × (Q_dep + β·Q_ind), na mesma
    unidade do P&L (Δspread × escala)."""
    def valor(t, s, sg):
        b = beta_trade(s)
        return escala_fn(sg, b) * (q_dep[t] + b * q_ind[t])
    return custos_trades(df.index, df['position'].values,
                         lambda s, sg: valor(s, s, sg), lambda s, tc, sg: valor(tc, s, sg))


def escala_rad(sg, b):
    return 1.0 / b if sg > 0 else 1.0


def escala_np(dimensionamento):
    if dimensionamento == 'rad':
        return escala_rad
    if dimensionamento == 'slides':
        return lambda sg, b: 1.0
    if dimensionamento == 'maior_perna':
        return lambda sg, b: 1.0 / max(1.0, b)
    raise ValueError(dimensionamento)
