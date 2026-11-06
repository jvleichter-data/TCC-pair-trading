# -*- coding: utf-8 -*-
"""Monta output/resultados_consolidado.html a partir de:

  · output/resultados/resultados_consolidado.csv        — as 40 execuções de 20 pares (etapa 2)
  · output/resultados/resultados_npares_parcial.csv     — as execuções de 5 e 35 pares (etapa 2b)
  · output/resultados/resultados_sem_media_parcial.csv  — Distância com gatilho sem μ (etapa 2e)
  · output/resultados/resultados_dinamica_reteste_parcial.csv — dinâmica: reteste e jan.252 (etapa 2f)
  · ../validation/custos/output/resultados_custos_todos.csv — aba Custos de transação (03/11/2026)
  · templates/painel.tpl.html                — a página, com __DATA__ e __CUSTOS__ no lugar dos payloads

As linhas da etapa 2 que não têm `n_pares` recebem 20 — é o TOP_K com que foram rodadas.
A chave de deduplicação é (rotulo, capital, amostra, n_pares), então reexecutar é seguro.

Uso:  python construir_html.py
"""
import io, os, sys, json, math
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', line_buffering=True)
import pandas as pd

AQUI = os.path.dirname(os.path.abspath(__file__))
SAIDA = os.path.join(os.path.dirname(AQUI), 'validation', 'output', 'resultados')
BASE = os.path.join(SAIDA, 'resultados_consolidado.csv')
NOVO = os.path.join(SAIDA, 'resultados_npares_parcial.csv')
DELTA = os.path.join(SAIDA, 'resultados_delta_parcial.csv')
SEM_MEDIA = os.path.join(SAIDA, 'resultados_sem_media_parcial.csv')   # etapa 2e
DIN_RETESTE = os.path.join(SAIDA, 'resultados_dinamica_reteste_parcial.csv')   # etapa 2f
TPL = os.path.join(AQUI, 'templates', 'painel.tpl.html')
HTML = os.path.join(AQUI, 'resultados_consolidado.html')
UNIFICADO = os.path.join(SAIDA, 'resultados_todos_npares.csv')
CUSTOS = os.path.join(os.path.dirname(AQUI), 'validation', 'custos', 'output', 'resultados_custos_todos.csv')
COLS_CUSTOS = ['rotulo', 'familia', 'metodo', 'capital', 'amostra', 'cenario', 'esquema',
               'ret_anual_bruto_%', 'ret_anual_liquido_%', 'sharpe', 'sharpe_liquido',
               'volatilidade_anual_%', 'drawdown_max_%', 'custo_anual_%', 'equilibrio_mult',
               'n_trades_custeados', 'custo_medio_por_trade_bps', 'aberturas']

CHAVE = ['rotulo', 'capital', 'amostra', 'n_pares']


def carrega():
    d = pd.read_csv(BASE, encoding='utf-8-sig')
    if 'n_pares' not in d.columns:
        d['n_pares'] = 20
    d['n_pares'] = d['n_pares'].fillna(20).astype(int)
    partes = [d]
    for extra in (NOVO, DELTA, SEM_MEDIA, DIN_RETESTE):
        if os.path.exists(extra):
            n = pd.read_csv(extra, encoding='utf-8-sig')
            if len(n):
                n['n_pares'] = n['n_pares'].astype(int)
                partes.append(n)
    R = pd.concat(partes, ignore_index=True, sort=False)
    if 'erro' in R.columns:
        R = R[R['erro'].isna()].drop(columns=['erro'])
    R = R.drop_duplicates(subset=CHAVE, keep='last').reset_index(drop=True)
    R = R.sort_values(['n_pares', 'amostra', 'capital', 'ret_anual_bruto_%'],
                      ascending=[True, True, True, False]).reset_index(drop=True)
    return R


def para_json(R):
    recs = []
    for _, r in R.iterrows():
        o = {}
        for c in R.columns:
            v = r[c]
            if v is None or (isinstance(v, float) and math.isnan(v)):
                o[c] = None
            elif isinstance(v, (int,)) or 'int' in str(type(v)):
                o[c] = int(v)
            elif isinstance(v, float):
                o[c] = round(float(v), 6)
            else:
                o[c] = str(v)
        recs.append(o)
    return json.dumps(recs, ensure_ascii=False, separators=(',', ':'))


def main():
    R = carrega()
    R.to_csv(UNIFICADO, index=False, encoding='utf-8-sig')

    js = para_json(R)
    if '</script' in js or '<!--' in js:
        raise SystemExit('payload contém sequência que quebraria o <script>')

    C = pd.read_csv(CUSTOS, encoding='utf-8-sig') if os.path.exists(CUSTOS) else pd.DataFrame(columns=COLS_CUSTOS)
    js_c = para_json(C[[c for c in COLS_CUSTOS if c in C.columns]])
    if '</script' in js_c or '<!--' in js_c:
        raise SystemExit('payload de custos contém sequência que quebraria o <script>')

    tpl = io.open(TPL, encoding='utf-8').read()
    for marca in ('__DATA__', '__CUSTOS__'):
        if marca not in tpl:
            raise SystemExit('marcador %s ausente em %s' % (marca, TPL))
    io.open(HTML, 'w', encoding='utf-8', newline='\n').write(
        tpl.replace('__CUSTOS__', js_c).replace('__DATA__', js))
    print('custos: %d linhas | %s' % (len(C), os.path.basename(CUSTOS)))

    print('linhas: %d | %s' % (len(R), os.path.basename(UNIFICADO)))
    for n, g in R.groupby('n_pares'):
        print('  n=%-2d  %2d execuções · %2d estratégias · %s'
              % (n, len(g), g['rotulo'].nunique(), ', '.join(sorted(g['rotulo'].unique()))[:96]))
    falta = [n for n in R['n_pares'].unique()
             if len(R[R['n_pares'] == n]) % 4 != 0]
    if falta:
        print('  ⚠ n com contagem não múltipla de 4 (capital × amostra): %s' % falta)
    print('HTML: %s (%.0f KB)' % (os.path.basename(HTML), os.path.getsize(HTML) / 1024))


if __name__ == '__main__':
    main()
