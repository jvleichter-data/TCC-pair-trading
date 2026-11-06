# -*- coding: utf-8 -*-
"""
Utilitários de seleção de pares para a formação PRÓPRIA do método não paramétrico.

Universo, normalização, SSD e exclusão de mesmo emissor são cópias das funções de
../cointegration/pairs_formation_coint.ipynb — mantidas idênticas de propósito, para que a
única diferença entre a seleção linear e a não paramétrica seja o teste de cointegração.

Referência do desenho em dois passos (pré-filtro SSD → teste de cointegração em ordem de SSD):
Rad, Low & Faff (2016), Quantitative Finance 16(10), § 4.2.
"""
import numpy as np
import pandas as pd


def filtrar_ativos_completos(precos):
    """Remove ativos com qualquer dado faltante no período."""
    return precos.dropna(axis=1, how='any')


def normalizar_precos(precos):
    """Q_i(t) = P_i(t) / P_i(0): todos os ativos partem de 1."""
    return precos.div(precos.iloc[0])


def calcular_ssd(Q):
    """D(i,j) = Σ_t (Q_i − Q_j)² via álgebra matricial."""
    arr = Q.values
    G = arr.T @ arr
    norms = np.diag(G)
    ssd = norms[:, None] + norms[None, :] - 2 * G
    return pd.DataFrame(ssd, index=Q.columns, columns=Q.columns)


# Lista explícita de mesmo emissor — idêntica à da formação linear (ver comentário lá:
# classes duais e renomeações; diagnóstico em validation/notas/revisao_completa_2026-09-13.md § 4).
MESMO_EMISSOR = [
    {"GOOGL", "GOOG"}, {"FOXA", "FOX"}, {"NWSA", "NWS"}, {"DISCA", "DISCK"},
    {"CMCSA", "CMCSK"}, {"UA", "UAA"}, {"BRK_A", "BRK_B"}, {"BF_A", "BF_B"},
    {"RTN", "RTN_B"}, {"TAP", "TAP_B"}, {"VIAB", "VIAC"}, {"LEN", "LEN_B"},
    {"TKR", "1288453D", "291784Q"}, {"JCI", "1436513D"}, {"LSI", "1431816D"},
    {"DTV", "1448062D"}, {"BF_B", "1958Q"}, {"MHFI", "SPGI"},
]
_EMISSOR = {}
for _k, _g in enumerate(MESMO_EMISSOR):
    for _t in _g:
        _EMISSOR.setdefault(_t, set()).add(_k)


def mesmo_emissor(t1, t2):
    """True se os dois tickers são a mesma empresa (classe distinta ou renomeação)."""
    return bool(_EMISSOR.get(t1, set()) & _EMISSOR.get(t2, set()))


def candidatos_ssd(Q, n, ssd_min=0.01):
    """
    Lista de (ativo1, ativo2, ssd) com os n pares de menor SSD, em ordem crescente.
    Exclui SSD < ssd_min (ghost tickers) e pares de mesmo emissor — como a formação linear.
    """
    ssd_df = calcular_ssd(Q)
    tickers = ssd_df.columns.tolist()
    i_idx, j_idx = np.triu_indices(len(tickers), k=1)
    ssds = ssd_df.values[i_idx, j_idx]
    ok = ssds >= ssd_min
    i_idx, j_idx, ssds = i_idx[ok], j_idx[ok], ssds[ok]
    order = np.argsort(ssds)
    out = []
    for k in order:
        a, b = tickers[i_idx[k]], tickers[j_idx[k]]
        if mesmo_emissor(a, b):
            continue
        out.append((a, b, float(ssds[k])))
        if len(out) >= n:
            break
    return out


def janelas_formacao(indice, meses_formacao=12, meses_negociacao=6, passo=1):
    """Lista de (meses_form, meses_neg) em meses calendário — mesma construção das outras formações."""
    meses = sorted(pd.PeriodIndex(indice, freq='M').unique())
    fim = len(meses) - meses_formacao - meses_negociacao + 1
    return [(meses[i:i + meses_formacao], meses[i + meses_formacao:i + meses_formacao + meses_negociacao])
            for i in range(0, fim, passo)]


def seleciona_pares_janela(Q, p):
    """
    Formação própria do método NP numa janela (passos 3 a 7 de pairs_formation_np_propria.ipynb).

    Q : DataFrame de preços normalizados da janela de formação (já filtrado e normalizado).
    p : dict de parâmetros — n_pre_ssd, ssd_min, grade_rel, gap, t_min, autolag, crit,
        beta_med_min, top_k, ranking ('ssd' ou 'adf').

    Para cada candidato do pré-filtro SSD (em ordem crescente de SSD):
      • teste_coint_np (as duas direções; escolhe a de menor erro de CV relativo; ADF dos erros
        um passo à frente) → aprovado se stat < crit (valor crítico SIMULADO);
      • filtro de hedge: mediana do β local na amostra da formação ≥ beta_med_min.
    ranking 'ssd' → testa em ordem de SSD e para ao reunir top_k aprovados (como a formação linear,
                    Rad et al. 2016 § 4.2);
    ranking 'adf' → testa todos e fica com os top_k de estatística mais negativa.

    Retorna (lista de dicts dos pares selecionados, dict de contagens).
    """
    from kernel_np import teste_coint_np, loclin

    cands = candidatos_ssd(Q, p['n_pre_ssd'], p['ssd_min'])
    aprovados, n_test, n_coint = [], 0, 0
    for a, b, ssd in cands:
        n_test += 1
        r = teste_coint_np(Q[a].values, Q[b].values, p['grade_rel'], p['gap'], p['t_min'], p['autolag'])
        if r['direcao'] is None or not (r['stat'] < p['crit']):
            continue
        n_coint += 1
        x, y = (Q[a].values, Q[b].values) if r['direcao'] == 'B~A' else (Q[b].values, Q[a].values)
        _, b_loc, _ = loclin(x, x, y, r['h'])
        beta_med = float(np.nanmedian(b_loc))
        if not (beta_med >= p['beta_med_min']):
            continue
        aprovados.append({'ativo1': a, 'ativo2': b, 'ssd': ssd, **r, 'beta_loc_med': beta_med,
                          'beta_loc_p10': float(np.nanpercentile(b_loc, 10)),
                          'beta_loc_p90': float(np.nanpercentile(b_loc, 90))})
        if p['ranking'] == 'ssd' and len(aprovados) >= p['top_k']:
            break
    if p['ranking'] == 'adf':
        aprovados = sorted(aprovados, key=lambda d: d['stat'])
    sel = aprovados[:p['top_k']]
    log = {'n_candidatos': len(cands), 'n_testados': n_test, 'n_coint': n_coint,
           'n_aprovados': len(aprovados), 'n_selecionados': len(sel)}
    return sel, log
