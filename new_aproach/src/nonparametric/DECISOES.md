# Método 3 — Cointegração não paramétrica: decisões, validação e primeiros resultados

**Versão:** 4 · **Data:** 2026-11-02 · **Estado:** primeira versão rodando de ponta a ponta;
todas as decisões abaixo estão abertas para discussão. **Configuração atual e novidades de
18 a 22/10 na § 6 e § 7** (CV unilateral, piso de β, veto de suporte desligado).

Cada decisão traz **quem decidiu**:

- **[usuário]** — decidido pelo João na conversa de 2026-10-06;
- **[assumida]** — tomada por mim na ausência do usuário, com o motivo; **discutir**;
- **[herdada]** — copiada da cointegração linear para manter a comparação pareada.

Arquivos do método (`src/nonparametric/`):

| Arquivo | Papel |
|---|---|
| `kernel_np.py` | estimador local linear, CV de bloco, resíduo leave-one-out, monitoramento até t−1 |
| `pairs_formation_np.ipynb` | escolhe o h de cada par → `output/pares/pares_formados_np.csv` |
| `pairs_trading_np.ipynb` | negociação → `output/resultados/*_np*.csv` |
| `DECISOES.md` | este documento |

Material usado: slides *Cointegração Não Paramétrica via Kernel — Aplicação em Pairs Trading*
(ECO 02091, FCE/UFRGS, em `articles/`), citados como "slide N"; Rad, Low & Faff (2016) para tudo
o que é herdado da cointegração linear; Wang & Phillips (2023, *Econometric Theory* 39(6),
1325–1337) para a bandwidth com regressor I(1).

---

## 1. O método em uma tela

Para cada par (dependente $y = Q_{dep}$, independente $x = Q_{indep}$, com $Q = P/P_0$):

1. **Formação (12 meses):** escolhe a bandwidth $h$ por validação cruzada *leave-block-out*,
   numa grade que inclui $h = \infty$ (a reta). Calcula $\mu, \sigma$ do resíduo *leave-one-out*.
2. **Monitoramento diário (6 meses):** em cada dia $t$ fora do mercado, ajusta o local linear
   com **todos os dados até $t-1$** (formação + negociação decorrida) e calcula
   $z_t = \big(y_t - \hat g_{t-1}(x_t) - \mu\big)/\sigma$.
3. **Sinal:** $|z_t| > 2$. Vetos: suporte insuficiente em $x_t$, ou $\hat\beta < 0{,}05$.
4. **Abertura:** congela a reta tangente à curva em $x_e = x_t$: nível $\hat g_e$, inclinação
   $\beta_e = \hat b_{t-1}(x_e)$. Carteira com perna comprada de \$1 (convenção de Rad).
5. **Fechamento:** quando o spread contra a tangente congelada cruza $\mu$, ou no fim do período.

---

## 2. Decisões

### D1. Pasta e notebook de formação próprios — [usuário]

`src/nonparametric/` com formação e negociação separadas, como os outros métodos. A formação é
própria mesmo usando, por enquanto, os pares da linear: a seleção vai mudar e o lugar dela é ali.

### D2. Pares candidatos = pares da cointegração linear — [usuário, provisório]

`ORIGEM_PARES = '../cointegration/output/pares/pares_formados_coint.csv'`.

- **Motivo:** comparação pareada. Contra a linear estática (e a dinâmica), a única diferença é
  reta × curva — mesmos pares, mesmas janelas, mesmos parâmetros de negociação.
- **Consequência a declarar:** viés de seleção **a favor da reta**. Os pares foram escolhidos
  porque passam num teste de cointegração *linear*; um par com relação genuinamente curva pode
  ter sido reprovado lá. A fração "reta venceu" (§ 4) é, portanto, um limite superior para a
  amostra inteira.

### D3. Direção da regressão herdada da linear — [assumida]

$g$ não é simétrica: $Q_2 = g(Q_1)$ não é a inversa de $Q_1 = g(Q_2)$. Herdo a coluna
`direcao` da formação linear (a direção mais estacionária no ADF bilateral).

- **Alternativa natural:** ajustar as duas direções e ficar com a de menor erro de CV. Deixei de
  fora porque dobra o custo e mistura "efeito da curva" com "efeito da direção" na comparação
  pareada. Candidata para a seleção própria (D2).

### D4. Variáveis normalizadas $Q = P/P_0$ — [assumida]

Os slides escrevem $P_1 = g(P_2)$ em preços. Uso $Q$, a mesma base dos outros métodos.

- **Por que não perde nada:** o local linear é equivariante a mudanças afins de escala em $x$ e
  $y$ desde que $h$ escale junto, e a grade de $h$ é definida em unidades de $\text{sd}(x)$ (D7).
  A curva em $Q$ é a curva em $P$ reescalada.
- **Por que ajuda:** o retorno usa a convenção de Rad em espaço $Q$ (D16), e $\beta$ fica
  diretamente comparável ao $\beta$ da linear.

### D5. Local linear, não Nadaraya–Watson — [usuário, slides 12–13]

O local linear entrega a inclinação local $\hat b(x)$ diretamente — o hedge ratio (slide 14).
Há um segundo motivo, específico do nosso desenho: no monitoramento, $x_t$ fica quase sempre
**na borda** dos dados (o preço do dia é, com frequência, o mais alto ou o mais baixo já visto).
Na borda o Nadaraya–Watson tem viés de ordem $h$ (achata para o nível dos vizinhos internos);
o local linear corrige esse viés de borda. Com h = ∞ o local linear é exatamente o OLS.

### D6. Kernel gaussiano, com $K(0) = 1$ — [assumida]

Os slides não especificam o kernel.

- **Gaussiano, e não Epanechnikov:** o Epanechnikov tem suporte compacto; com regressor I(1),
  pontos sem nenhum vizinho a menos de $h$ (comum quando o preço está em nível novo) dão sistema
  singular. O gaussiano nunca zera os pesos.
- **Sem a constante $1/\sqrt{2\pi}$:** com $K(0)=1$, a soma dos pesos perto de $x$ é um "número
  efetivo de observações", o que dá ao veto de suporte (D12) uma unidade interpretável.
- A escolha do kernel costuma importar muito menos que a do $h$.

### D7. Bandwidth por CV *leave-block-out*, $L = 20$ pregões — [usuário: bloco; assumida: L e grade] · ⚠️ SUBSTITUÍDA em 19/10 pela CV unilateral (§ 6.1)

$$\text{CV}(h) = \tfrac1T \textstyle\sum_t \big[y_t - \hat g_{-[t-L,\,t+L]}(x_t)\big]^2$$

- **Por que não o LS-CV *leave-one-out*** (Liang, Lin & Hsiao 2015, citado no slide 23): com
  regressor I(1), os vizinhos de $x_t$ no eixo do preço são os dias $t\pm1, t\pm2,\ldots$, e o
  resíduo é persistente. Tirar só o ponto $t$ deixa vizinhos com erro correlacionado, e o CV
  premia $h$ pequeno. Medido na formação: LOO escolhe $h \approx 0{,}16\,\text{sd}(x)$ e a reta
  em só 1,5% dos pares; o bloco escolhe a reta em 52%. O slide 24 já avisa para não importar
  regras de bandwidth do caso estacionário.
- **Por que $L = 20$:** o AR(1) mediano do resíduo linear é 0,88 (meia-vida ≈ 5 pregões); a 20
  pregões a correlação residual é $0{,}88^{20} \approx 0{,}08$. Sensibilidade com $L$ = 0, 10, 40
  na § 4.
- **Grade:** 25 pontos geométricos de $0{,}05$ a $5 \times \text{sd}(x)$, **mais $h = \infty$**.
  Incluir o infinito faz a reta disputar explicitamente com as curvas. É um teste informal de
  $H_0: g(x) = \alpha + \beta x$ (slide 29): quando o CV escolhe $\infty$, os dados da formação não
  sustentam a curva.
- Um $h$ em que algum ponto fica sem estimativa (massa insuficiente fora do bloco) é descartado.

### D8. $h$ escolhido uma vez na formação e fixo na negociação — [assumida, slide 33 passo 6]

O slide 33 põe a seleção do bandwidth na janela de formação. Reforço teórico: com regressor
I(1), a massa de dados perto de um ponto (o *tempo de permanência*) cresce como $\sqrt T$, e o
$h$ ótimo decresce muito devagar com $T$ — da ordem de $T^{-1/10}$ pelo balanço viés² $O(h^4)$ ×
variância $O(1/\sqrt T h)$ (derivação heurística minha, a conferir). Entre $T = 252$ e $T = 378$
isso muda o $h$ em ~4%. Wang & Phillips (2023) mostram que o $h$ ótimo é uma sequência
**aleatória**, dependente do tempo de permanência — o que motiva o veto de D12.

### D9. Curva re-estimada com dados até $t-1$ — [usuário: invadir a negociação; assumida: t−1]

- **Por que invadir é obrigatório, não opcional:** em **39,7%** dos dias de negociação dos pares
  lineares, $x_t$ está fora da faixa observada na formação (81% dos pares saem dela em algum
  momento). O kernel não tem informação fora do suporte, então a curva da formação não está
  definida ali.
- **Por que $t-1$ e não $t$:** com $h$ pequeno, a curva passa perto de cada ponto usado. Se $y_t$
  entrasse na curva do dia $t$, ela "explicaria" o próprio desvio que se quer operar
  (auto-absorção). Usar até $t-1$ é a curva **conhecida ontem, avaliada no preço de hoje**: sem
  look-ahead e sem auto-absorção.
- Amostra **expandida** (desde o início da formação), não móvel: coerente com a versão dinâmica
  (`JANELA_REESTIMACAO = None`) e maximiza o tempo de permanência em cada nível.

### D10. Gatilho = z não paramétrico diário — [usuário]

O spread monitorado é o próprio spread não paramétrico ($y_t - \hat g_{t-1}(x_t)$), e não o z da
linear com confirmação. O custo é baixo: uma avaliação do local linear por dia, vetorizada
(`kernel_np.monitoramento`).

### D11. $\mu$ e $\sigma$ do resíduo *leave-one-out* da formação — [assumida] · ⚠️ SUBSTITUÍDA em 19/10 pelo σ unilateral (§ 6.1)

- **Por que leave-one-out e não o resíduo dentro da amostra:** com $h$ pequeno, o resíduo dentro
  da amostra subestima a dispersão e inflaria o z. Com $h=\infty$ os dois praticamente
  coincidem com o resíduo do OLS.
- **Assimetria conhecida, a discutir:** o resíduo LOO da formação usa vizinhos dos **dois**
  lados no tempo; o spread monitorado usa só o passado. A dispersão real na negociação tende a
  ser maior, logo o z tende a ser inflado. O mesmo vale para a linear (o resíduo fora da amostra
  tem desvio ~1,6× o de dentro), então não distorce a comparação, mas afeta o nível de sinais.
- **Fixos** na negociação (não re-estimados), como na linear estática.
- **Medido depois (§ 4.3):** o desvio do spread monitorado é ~1,6–1,7σ em **todos** os regimes de
  h, inclusive na reta. Dentro da formação, o mesmo spread "um passo à frente" tem desvio ≈ 1,0σ.
  Ou seja, o σ está igualmente descalibrado para curva e reta. A inflação vem da mudança de
  regime formação → negociação, não do LOO, e não explica a diferença entre os métodos.

### D12. Veto por suporte: massa ≥ 10 vinda de dados com mais de 20 pregões — [assumida] · ⚠️ DESLIGADO em 22/10 (§ 7)

No dia do sinal, mede-se $\sum_{s < t-20} K\big((x_s - x_t)/h\big)$: quanto dado **antigo** existe
perto do preço atual. Abaixo de `MASSA_MIN = 10`, a curva em $x_t$ é determinada pelo próprio
movimento recente do preço, e o "equilíbrio" ali não está identificado → o trade não abre.

- **Fundamento:** é a estimativa empírica do tempo de permanência (local time) que governa a
  precisão do estimador com regressor I(1) (Wang & Phillips 2009a, 2023).
- **Análogo ao veto do dinâmico:** lá se veta quando a cointegração some; aqui, quando a curva
  não está identificada no ponto.
- Com $h = \infty$ a massa é o tamanho da amostra e o veto nunca dispara.
- `MASSA_MIN = 10` é um número redondo, sem calibração. Sensibilidade (0 e 30) na § 4.

### D13. Veto de $\hat\beta < 0{,}05$ — [herdada] · ⚠️ SUBSTITUÍDO em 22/10 por β ≥ 0,50 (§ 6.2 e § 7)

O dimensionamento $1/\beta$ de Rad (perna comprada de \$1 quando $z > +\delta$) não é definido
para $\beta \le 0$ e explode para $\beta \to 0$. Na linear isso filtra o par inteiro; aqui o $\beta$
só existe na entrada, então o veto é sinal a sinal.

### D14. Saída medida contra a **tangente** congelada — [assumida; **muda uma decisão do usuário**]

O usuário escolheu "curva congelada na entrada". A primeira rodada com essa escolha mostrou um
problema estrutural, e mudei o padrão para a tangente, mantendo a curva como opção
(`MODO_SAIDA`).

- **O problema:** o trade **mede** a convergência contra uma curva, mas **opera** uma reta
  ($Q_{dep} - \beta_e Q_{indep}$, $\beta_e$ fixo). Quando o par converge andando ao longo da curva,
  o hedge linear não acompanha. Decomposição trade a trade nos pares com $h \le 0{,}5\,\text{sd}$
  (1% de caudas fora): o spread contra a curva rendeu **+0,014** por trade (igual à reta, +0,013),
  e o descasamento do hedge custou **−0,014**, todo o ganho. Com $h = \infty$ o descasamento é
  exatamente 0, o que valida a medida. Havia ainda uma cauda esquerda pesada: a curva congelada,
  avaliada longe de onde foi estimada, extrapola mal.
- **A tangente:** referência $\hat g_e + \beta_e(Q_{indep} - x_e)$. A curva continua decidindo
  **quando** (nível local de equilíbrio) e **com quanto** (inclinação local). O spread contra a
  tangente é exatamente o valor da carteira hedgeada, então descasamento zero por construção e
  "z cruzou zero" significa "o lucro alvo foi realizado".
- **Opções mantidas:** `'curva'` (a escolha original) e `'curva_rebalanceada'` (β = inclinação da
  curva congelada no dia, a extensão do slide 19). Comparação na § 4.
- ⚠️ **O que a rodada completa mostrou:** a tangente **não** melhora o desempenho: 2,26% a.a. /
  Sharpe 0,49, contra 2,37% / 0,51 da curva congelada, empate dentro do ruído. O descasamento
  existe trade a trade, mas se compensa no agregado: sem aparar as caudas, a média dele era só
  −0,0025 por trade. **A perda dos pares com curva não vem do hedge** (ver § 4.3). Mantive a
  tangente como padrão pela coerência interna (o z do trade mede exatamente o P&L da carteira, e
  não há extrapolação da curva), não por desempenho. Voltar para `'curva'` é trocar uma linha;
  **é o primeiro item a discutir**.

### D15. Hedge ratio fixo da entrada ao fechamento — [usuário, slides 18–19]

Especificação principal dos slides. O rebalanceamento diário é a extensão, disponível como
`MODO_SAIDA = 'curva_rebalanceada'`. Sem custos de transação (D19), o turnover extra do
rebalanceamento **não é penalizado** — atenção ao comparar.

### D16. Retorno na convenção de Rad et al. (2016) — [herdada]

Perna comprada sempre de \$1: `pos = −1` → long \$1 em $Q_{dep}$ / short \$$\beta$ em $Q_{indep}$;
`pos = +1` → long \$1 em $Q_{indep}$ / short \$$1/\beta$ em $Q_{dep}$. Retorno diário
$-\text{pos}_{t-1} \cdot \text{escala} \cdot (\Delta Q_{dep} - \beta\,\Delta Q_{indep})$. Execução em
$t+1$. Portfólio com capital comprometido; REC e RCC mensais (eqs. 14–15 de Rad). Herda a
limitação de que o retorno não é excedente por identidade quando $\beta \ne 1$
(`validation/notas/retorno_excedente_cointegracao.md`).

### D17. Parâmetros de negociação iguais aos da linear — [herdada]

`DELTA = 2`, `SIGMA_MIN = 0,01`, `BETA_MIN = 0,05`, `COMMITTED_CAPITAL = True`,
`N_PARES_NOMINADOS = 20`, `PERIODO_FIM = '2015-12'` (o mesmo filtro com que a linear foi gravada).

⚠️ **`MAX_RETORNO_DIA = 0,90` é look-ahead** (olha o período de negociação inteiro). Na
distância já foi zerado; mantive aqui só porque a linear ainda o usa e a comparação é pareada.
Afeta 1 par em 5.768. Se for zerado na linear, zerar aqui também.

### D18. Sem teste formal de cointegração não paramétrica — [assumida, slides 21–22]

Os slides dizem que ADF/PP/KPSS sobre o resíduo não paramétrico são só diagnóstico: a
distribuição assintótica não é a convencional. A formação registra o ADF do resíduo LOO
(`adf_loo`) como diagnóstico, **sem** usá-lo como filtro, e não há re-teste na abertura (ao
contrário do dinâmico). O papel de "a relação ainda vale aqui?" fica com o veto de suporte (D12).

### D19. Sem custos de transação — [herdada]

Como nos outros métodos do projeto até aqui. O slide 31 lembra que isso pesa mais justamente
nas variantes com rebalanceamento.

---

## 3. Validação

| Teste | Resultado |
|---|---|
| `kernel_np.loclin` com $h=\infty$ contra `np.polyfit` | diferença máx. 8e-15 |
| `loclin` contra WLS explícito (`np.linalg.solve`) num ponto | 1,6e-15 |
| `monitoramento` (vetorizado) contra o loop dia a dia | 1,9e-15 (curva) / 7e-15 (massa) |
| CV de bloco numa relação simulada **quadrática** | escolhe h finito (0,73·sd), não a reta — detecta curva quando existe |
| **Motor de negociação:** NP com a curva trocada pela reta fixa da linear (mesmos α, β, μ, σ) contra `negociacao_pares_coint.csv` | **1.492 pares, diferença máx. 1,0e-15, trades idênticos em 100%** |
| Determinismo: rodada principal repetida do zero | 5.733 × 5.733 pares, diferença **0,0** por par e por dia |

Scripts dos testes e diagnósticos (pasta local, fora do git como o resto de `validation/`):
`src/validation/auditoria/nonparametric/`.

| Script | O que faz |
|---|---|
| `np_bandwidth_probe.py` | sonda inicial: LOO × blocos × Silverman em 247 pares, fração fora do suporte |
| `valida_motor_np.py` | motor do NP com a reta fixa contra `negociacao_pares_coint.csv` |
| `diag_trades_np.py` | decomposição trade a trade: P&L realizado × spread × descasamento |
| `diag_sigma_np.py` | calibração do σ por regime de h |
| `lin_completo.py` | linear estática 1991–2025 em memória (não grava nada na pasta da cointegração) |
| `lote_np.py` + `run_nb.py` | roda os notebooks fora do Jupyter com parâmetros sobrescritos (todas as rodadas da § 4) |
| `compara_rodadas.py` | gera as tabelas da § 4 (`tabelas_np.md`) |

O teste do motor é o mais importante: ele mostra que toda diferença de resultado entre o NP e a
linear vem do estimador (curva, h, re-estimação, vetos), não da mecânica de posições, lag,
escala $1/\beta$ ou agregação do portfólio.

---

## 4. Resultados

Todas as rodadas usam a mesma base (`base_unificada.csv`, com máscara de índice), os mesmos
5.768 pares da linear com negociação até 2015-12 e os mesmos parâmetros (D17), salvo o que a
linha indica. Sem custos de transação. Os CSVs de cada rodada estão em `output/resultados/` com
o sufixo indicado (`_curva`, `_rebal`, `_massa0`, `_massa30`, `_L0`, `_L10`, `_L40`, `_completo`).

### 4.1 Formação: quanto de não linearidade os dados sustentam

| Critério de h | reta venceu | h/sd mediano (finitos) | queda do erro de CV contra a reta (mediana, finitos) |
|---|---|---|---|
| LOO-CV (bloco L = 0) | 1,5% | 0,16 | 14,0% |
| bloco L = 10 | 45,9% | 0,73 | 5,6% |
| **bloco L = 20 (principal)** | **52,4%** | **0,89** | **6,1%** |
| bloco L = 40 | 50,1% | 0,89 | 6,7% |

- Assim que se controla a dependência temporal (L ≥ 10), **cerca de metade dos pares prefere a
  reta**, e nos demais a curva reduz o erro de previsão em só ~6%. O resultado é estável de
  L = 10 a L = 40; o salto está todo entre L = 0 e L = 10, o que confirma que o LOO capta
  dependência, não não linearidade.
- A fração linear varia entre 44% e 60% por ano de formação, sem tendência evidente.
- Nos pares com curva, o β local varia bastante dentro da faixa de preços (amplitude p90−p10
  mediana de 0,28), contra um β mediano de ~0,85.

### 4.2 Negociação, 1991–2015

| rodada | ret a.a. | vol | Sharpe | MDD | REC mensal | RCC mensal | trades | conv. | sinais vetados |
|---|---|---|---|---|---|---|---|---|---|
| **linear estática (referência)** | 3,71% | 3,98% | **0,94** | −15,4% | 0,37% | 0,31% | 10.927 | 55,3% | — |
| **NP tangente (principal)** | 2,26% | 4,85% | **0,49** | −22,6% | 0,26% | 0,20% | 10.580 | 54,4% | 21,9% |
| NP curva congelada (escolha original, D14) | 2,37% | 4,78% | 0,51 | −22,1% | 0,27% | 0,20% | 10.594 | 55,0% | 22,8% |
| NP curva rebalanceada (slide 19) | 1,29% | 5,52% | 0,26 | −26,9% | 0,16% | 0,12% | 10.594 | 55,0% | 22,8% |
| NP tangente, sem veto de suporte | 2,74% | 4,97% | 0,57 | −21,3% | 0,30% | 0,23% | 10.814 | 54,8% | 8,2% |
| NP tangente, `MASSA_MIN` = 30 | 2,70% | 4,49% | 0,62 | −21,1% | 0,30% | 0,23% | 10.180 | 54,2% | 45,4% |
| NP tangente, h por LOO-CV (L = 0) | −1,27% | 7,09% | −0,15 | −40,0% | −0,17% | −0,08% | 8.865 | 54,5% | 78,2% |
| NP tangente, bloco L = 10 | 2,23% | 5,15% | 0,45 | −23,0% | 0,25% | 0,19% | 10.507 | 54,6% | 30,0% |
| NP tangente, bloco L = 40 | 2,66% | 4,55% | 0,60 | −21,4% | 0,29% | 0,23% | 10.590 | 54,5% | 15,7% |

Referência externa, Rad et al. (2016), Tabela 3, cointegração antes de custos (CRSP 1962–2014):
REC 0,85% e RCC 0,68% ao mês.

### 4.3 Onde está a diferença: por regime de h (rodada principal, pareada com a linear)

| h escolhido | pares | retorno médio por par, NP | idem, linear | NP − linear | trades NP / linear |
|---|---|---|---|---|---|
| ∞ (reta reestimada até t−1) | 2.984 | +0,0207 | +0,0201 | **+0,0006** | 5.586 / 5.625 |
| > 2·sd | 302 | +0,0270 | +0,0185 | +0,0084 | 567 / 573 |
| 1–2·sd | 852 | +0,0221 | +0,0242 | −0,0021 | 1.623 / 1.654 |
| 0,5–1·sd | 828 | −0,0043 | +0,0125 | −0,0168 | 1.483 / 1.582 |
| ≤ 0,5·sd | 759 | −0,0202 | +0,0159 | **−0,0362** | 1.307 / 1.424 |

**Leitura:**

1. Nos pares em que o CV escolhe a reta, o NP **empata** com a linear. Reestimar a reta até t−1
   (em vez de congelá-la na formação) não ajuda nem atrapalha.
2. **Toda a perda está nos pares com curva, e cresce monotonicamente com a flexibilidade.** O
   número de trades e a convergência quase não mudam: o que cai é a qualidade de cada trade.
3. **Explicações testadas e descartadas:**
   - *Descasamento do hedge* (D14): a tangente zera o descasamento e o resultado não muda.
   - *σ descalibrado pelo LOO* (D11): a razão entre o desvio do spread monitorado e o σ é
     ~1,6–1,7 em todos os regimes, inclusive na reta.
   - *Auto-absorção pelo ponto t*: não há, porque o ponto t está fora da curva (D9).
4. **O que sobra é o diagnóstico do slide 27:** a curva melhor na formação (erro de CV ~6%
   menor) não identifica um equilíbrio melhor **fora** da amostra. Os pares com h pequeno até têm
   spread monitorado menos persistente (AR(1) 0,90 contra 0,94 na reta) e disparam menos
   (31% dos dias com |z| > 2, contra 44%), mas os desvios que sobram revertem pior. É sobreajuste
   no sentido econômico: "não linearidade estatística ≠ alpha econômico" (slide 29).
5. **O LOO-CV é desastroso como regra de bandwidth** (Sharpe −0,15, 78% dos sinais vetados por
   suporte). Isso valida empiricamente a escolha do bloco e o aviso do slide 24.
6. **O veto de suporte não tem efeito claro:** 0 → 2,74%; 10 → 2,26%; 30 → 2,70%. Não é
   monotônico; a diferença está dentro do ruído entre configurações. Escolher o `MASSA_MIN` pelo
   melhor backtest seria sobreajuste. Ver § 5.
7. **O rebalanceamento diário do β piora** (Sharpe 0,26), e isso ainda sem os custos do turnover
   extra (slide 31).

### 4.4 Período completo e subperíodos (NP tangente × linear estática)

A linear de 1991–2025 foi recalculada em memória, rodando o notebook dela com
`PERIODO_FIM = None` sem gravar nada (os CSVs dela seguem cobrindo só até 2015).

| período | método | ret a.a. | vol | Sharpe | MDD |
|---|---|---|---|---|---|
| 1991–2015 | linear | 3,80% | 3,96% | 0,96 | −15,7% |
| 1991–2015 | NP | 2,40% | 4,83% | 0,51 | −22,6% |
| 2016–2025 | linear | 0,04% | 4,69% | 0,03 | −12,1% |
| 2016–2025 | NP | 0,05% | 5,26% | 0,04 | −10,7% |
| 1991–2025 | linear | 2,70% | 4,18% | 0,66 | −15,7% |
| 1991–2025 | NP | 1,71% | 4,96% | 0,37 | −22,6% |

Depois de 2015 os dois métodos zeram, e o NP empata. A diferença inteira está no período do
orientador.

---

## 5. Para discutir

Em ordem de prioridade:

1. **Tangente ou curva congelada (D14)?** A tangente era para corrigir o descasamento do hedge;
   corrige, mas o desempenho não muda. Mantive pela coerência interna. Se a preferência for
   seguir os slides ao pé da letra (curva + β fixo), é `MODO_SAIDA = 'curva'`.
2. **Como apresentar o resultado principal.** Com os pares da linear, o método não paramétrico
   não supera a reta: metade dos pares nem sustenta uma curva, e onde a curva vence na formação
   ela perde fora da amostra. Isso responde à pergunta empírica dos slides 29–30 e pode ser o
   próprio resultado do capítulo. Antes de concluir, porém, vale o item 3.
3. **Seleção própria de pares (D2).** O teste atual é viesado a favor da reta, porque os pares
   foram escolhidos pela cointegração linear. Uma seleção própria (ex.: SSD top-100 → ajuste
   não paramétrico → ranking pelo erro de CV de bloco, com a reta como concorrente) daria ao
   método a chance de achar pares que a linear reprova. O lugar é `pairs_formation_np.ipynb`.
4. **Direção da regressão (D3):** testar as duas direções e escolher pela CV.
5. **Veto de suporte (D12):** não tem efeito claro. Sugiro **não** calibrar o `MASSA_MIN` pelo
   backtest. Ou se mantém 10 com justificativa teórica, ou se desliga (0) por parcimônia. Prefiro
   desligar se não houver argumento a priori melhor.
6. **Teste formal de linearidade** ($H_0: g = \alpha + \beta x$, slide 29). Hoje a "reta venceu
   no CV" funciona como teste informal. Um teste com distribuição conhecida exigiria a teoria de
   Wang & Phillips; vale ver se o orientador quer isso ou se o critério de CV basta.
7. **`MAX_RETORNO_DIA = 0,90` (look-ahead, D17):** zerar nos dois métodos de cointegração junto.
8. **Rendimento do caixa e custos (D16, D19):** valem para os três métodos; nada específico aqui.

### Como reproduzir

```
cointegration/pairs_formation_coint.ipynb   (gera os pares candidatos)
nonparametric/pairs_formation_np.ipynb      ~14 min (~6 min com CALCULAR_H_LOO = False)
nonparametric/pairs_trading_np.ipynb        ~1,5 min
```

As rodadas de sensibilidade trocam só os parâmetros do topo dos notebooks: `MODO_SAIDA`,
`MASSA_MIN`, `L_BLOCO` + `ARQUIVO_SAIDA`/`ARQUIVO_PARES`, `PERIODO_FIM`, e `SUFIXO` para não
sobrescrever a rodada principal.

---

## 6. Atualização de 2026-10-18 — CV unilateral e piso de β

### 6.1 CV unilateral (origem móvel) — [usuário: substituir a CV bilateral]

O usuário não aceitou que a CV de bloco use dados **futuros** ao dia previsto (bilateralidade),
já que na negociação a curva só conhece o passado. Implementado `kernel_np.cv_unilateral`:

$$\text{CV}_{\text{uni}}(h) = \tfrac{1}{T-t_{\min}}\textstyle\sum_{t=t_{\min}}^{T-1}\big[y_t - \hat g_{\{s\,\le\,t-g\}}(x_t)\big]^2$$

Na formação: `CRITERIO_H = 'unilateral'`, `GAP_UNILATERAL` (g), `T_MIN_UNILATERAL` (padrão 126) e
`SIGMA_MODO = 'unilateral'` (μ, σ do erro de previsão um passo à frente, a mesma natureza do
spread monitorado). Validado contra força bruta: diferença de 3e-15.

**Adotada como padrão em 2026-10-19 [usuário]:** `CRITERIO_H = 'unilateral'`, `GAP_UNILATERAL = 20`,
`T_MIN_UNILATERAL = 126`, `SIGMA_MODO = 'unilateral'`. Isso substitui a D7 (bloco) e a D11 (σ do LOO).
As saídas da CV de bloco foram preservadas com o sufixo `_bloco` (`pares_formados_np_bloco.csv`,
`*_np_bloco.csv`, `*_np_bloco_{repeticao,completo,beta025,beta050,curva}.csv`). Rodada completa com o
novo padrão: `validation/auditoria/nonparametric/lote_noturno.py` → `relatorio_noturno.md`.

| critério | reta vence | h/sd mediano | ret. a.a. | Sharpe | MDD | sinais vetados |
|---|---|---|---|---|---|---|
| linear estática | — | — | 3,71% | 0,94 | −15,4% | — |
| bloco L = 20 (bilateral) | 52,4% | 0,89 | 2,26% | 0,49 | −22,6% | 21,9% |
| unilateral g = 1 | 8,6% | 0,28 | 1,13% | 0,21 | −32,9% | 62,6% |
| unilateral g = 5 | 31,9% | 0,73 | 1,17% | 0,24 | −32,7% | 35,0% |
| **unilateral g = 20** | 45,5% | 0,89 | 2,57% | 0,54 | −27,6% | 22,8% |
| unilateral g = 40 | 44,3% | 0,89 | 2,47% | 0,52 | −22,8% | 21,0% |
| unilateral g = 20, t_min = 63 | 46,9% | 0,89 | 2,53% | 0,55 | −25,3% | 19,8% |
| **unilateral g = 20, σ unilateral** | 45,5% | 0,89 | 2,73% | **0,58** | −26,9% | 24,9% |

Leitura:

1. **g = 1 é a pior opção unilateral.** Ela minimiza exatamente o erro do monitoramento, e por
   isso premia a curva que acompanha o preço recente: h pequeno e 62,6% dos sinais vetados por
   suporte. Prever bem o preço de amanhã não é o mesmo que identificar um equilíbrio.
2. **Com g ≥ 20 a unilateral é ligeiramente melhor que o bloco** (Sharpe 0,54–0,58 contra 0,49) e
   estável em g e em t_min. A diferença é pequena e está dentro do ruído entre configurações,
   mas tem a mesma direção em todas as variantes.
3. **A escolha de h por par é instável.** Bloco L = 20 e unilateral g = 20 concordam na decisão
   reta × curva em só 73% dos pares, e a correlação de log(h) entre os dois, quando ambos
   escolhem curva, é 0,39. Critérios igualmente razoáveis escolhem bandwidths diferentes para o
   mesmo par.
4. A perda contra a linear continua concentrada nos pares com curva (−0,009 a −0,011 por par).

### 6.2 Piso de β na entrada — [assumida; achado novo]

A inclinação local é bem mais ruidosa que o β do OLS: na rodada principal, 293 trades abriram com
β < 0,3, e há aberturas com β = 0,08. Pela convenção de Rad (perna comprada de \$1), com z > 0
isso vende 1/β = 12 dólares contra 1 comprado — uma posição alavancada. 136 pares têm
|retorno| > 50% no semestre, concentrados nos pares com curva e β baixo. Na linear isso quase não
ocorre: o β do OLS tem p1 ≈ 0,49.

| piso de β (`BETA_MIN`) | ret. a.a. | vol. | Sharpe | MDD | sinais vetados por β | pares com \|ret\| > 0,5 |
|---|---|---|---|---|---|---|
| 0,05 (atual) | 2,26% | 4,85% | 0,49 | −22,6% | 7,1% | 136 |
| 0,25 | 2,75% | 4,23% | 0,66 | −18,3% | 15,0% | 85 |
| 0,50 | 3,06% | 3,90% | 0,79 | −15,8% | 40,6% | 57 |
| 0,50 + CV unilateral g = 20, σ unilateral | 3,17% | 3,89% | **0,82** | −14,1% | — | — |

- O piso melhora o resultado de forma monotônica e leva a volatilidade ao nível da linear. É o
  maior efeito encontrado até aqui.
- **Cuidado ao escolher o valor:** 0,50 não pode ser defendido por ser o que deu o melhor
  backtest. Um argumento a priori possível: 0,5 é aproximadamente o p1 do β do OLS nos mesmos
  pares, ou seja, a faixa de hedge ratio que a própria linear considera plausível.
- **Alternativa mais limpa a discutir:** em vez de vetar, limitar a alavancagem pela convenção de
  retorno — por exemplo, dimensionar as duas pernas de forma que a soma valha \$2 (dollar-neutral
  ajustado por β) em vez de fixar a perna comprada em \$1. Isso trata a causa (a escala 1/β), não
  o sintoma.
- Com piso 0,50 ainda vetam-se 40% dos sinais: o β local fica abaixo de 0,5 com frequência.

### 6.3 Exemplo visual da negociação

A seção 7 do artefato (*Negociação, dia a dia*) mostra o ciclo completo num par real,
MDLZ ~ g(LLY) no 1º semestre de 2012, incluindo uma abertura com β = 0,23 logo depois de cinco
vetos por β negativo. Fontes do artefato e dados do exemplo em
`src/validation/auditoria/nonparametric/artefato/` e `dados_negociacao_passo.py`.

### 6.4 Arquivos novos desta rodada

`output/pares/pares_formados_np_U{1,5,20,40,20t63,20s}.csv` e os respectivos
`output/resultados/*_np_U*.csv`; `*_np_beta025.csv`, `*_np_beta050.csv`, `*_np_U20s_beta050.csv`.
Scripts: `validation/auditoria/nonparametric/lote_unilateral.py`, `lote_beta.py`,
`compara_unilateral.py`.

### 6.5 Rodada com o novo padrão (2026-10-19)

Relatório completo: `validation/auditoria/nonparametric/relatorio_noturno.md`. Oito rodadas, nenhuma
com erro; a repetição e a rodada de 18/10 com a mesma configuração dão diferença **0,0** por par.

| 1991–2015 | ret. a.a. | vol. | Sharpe | MDD |
|---|---|---|---|---|
| linear estática | 3,71% | 3,98% | 0,94 | −15,4% |
| NP bloco (anterior) | 2,26% | 4,85% | 0,49 | −22,6% |
| **NP unilateral (padrão)** | 2,73% | 4,82% | **0,58** | −26,9% |
| NP unilateral, β ≥ 0,25 | 3,02% | 4,23% | 0,72 | −18,1% |
| NP unilateral, β ≥ 0,50 | 3,17% | 3,89% | 0,82 | −14,1% |
| NP unilateral, saída pela curva | 2,60% | 4,89% | 0,55 | −29,9% |

Período completo: 1991–2025, linear 0,66 × NP 0,43 × NP β ≥ 0,50 0,61. **De 2016 a 2025 o NP
supera a linear**, mas todos ficam perto de zero (Sharpe 0,03 linear, 0,06 NP, 0,11 NP β ≥ 0,50).
Por regime de h, a unilateral reduz a perda nos pares com curva flexível (≤ 0,5·sd: −0,024 contra
−0,036 no bloco) e empata ou ganha nos de curva suave (1–2·sd: +0,002).

---

## 7. Configuração v2 (2026-10-22) — veto de suporte desligado, piso de β 0,50

### 7.1 Veto de suporte — [usuário: testar veto 5 e sem veto] → DESLIGADO

O usuário questionou o veto: em mercado com tendência o preço passa muito tempo em níveis novos,
justamente onde não há dado antigo por perto. Testado com a CV unilateral (1991–2015, Sharpe):

| veto de suporte | β ≥ 0,05 | sinais vetados | β ≥ 0,50 | sinais vetados |
|---|---|---|---|---|
| mínimo 10 (antigo padrão) | 0,58 | 18,2% | 0,82 | 13,5% |
| mínimo 5 | 0,61 | 11,4% | 0,82 | 8,2% |
| idade mínima 5 pregões (mínimo 10) | 0,61 | 8,9% | 0,83 | 6,5% |
| **sem veto** | 0,57 | 0,0% | **0,85** | 0,0% |

Sem tendência clara; com β ≥ 0,50, desligar é o mais simples e o melhor. O piso de β já barra a
maior parte dos pontos onde a curva é mal identificada. `MASSA_MIN = 0` no notebook; o código
continua para sensibilidade.

### 7.2 Padrão dos notebooks desde 22/10 — [usuário: manter a melhor configuração]

| parâmetro | valor | onde |
|---|---|---|
| `CRITERIO_H` / `GAP_UNILATERAL` / `T_MIN_UNILATERAL` | `'unilateral'` / 20 / 126 | formação |
| `SIGMA_MODO` | `'unilateral'` | formação |
| `BETA_MIN` | **0,50** | negociação |
| `MASSA_MIN` | **0** (veto de suporte desligado) | negociação |
| `MODO_SAIDA` | `'tangente'` | negociação |

O piso de 0,50 continua **provisório**: foi escolhido depois de ver o resultado. Justificativa
proposta: ≈ percentil 1 do β do OLS nos mesmos pares. Alternativas na pauta: piso pela regra do
percentil calculada nos dados, ou mudar a convenção de dimensionamento das pernas.

**Achado sobre o β pequeno, refinado:** os dois lados importam. Com z > 0 a carteira vende 1/β
(β pequeno → alavancada); com z < 0 vende só β (β pequeno → quase sem hedge, aposta direcional).
Risco por par conforme o β médio dos trades (rodada sem piso): desvio-padrão do retorno do par
0,91 com β < 0,25 (34% dos pares com |retorno| > 50%), 0,33 com 0,25–0,5, contra 0,16 com
0,75–1 (0,9%).

### 7.3 Resultados da configuração v2

Rodada principal refeita com o padrão novo: reproduz a variante testada com diferença 0,0 por par
e é determinística (repetição 0,0).

| 1991–2015 | ret. a.a. | vol. | Sharpe | MDD |
|---|---|---|---|---|
| linear estática | 3,71% | 3,98% | 0,94 | −15,4% |
| NP v1 (bloco, β ≥ 0,05, veto 10) | 2,26% | 4,85% | 0,49 | −22,6% |
| + CV unilateral | 2,73% | 4,82% | 0,58 | −26,9% |
| + β ≥ 0,50 | 3,17% | 3,89% | 0,82 | −14,1% |
| **+ sem veto de suporte (v2)** | **3,37%** | **4,00%** | **0,85** | **−14,5%** |

Período completo (rodada `_completo`): linear 0,66 × NP v2 0,62 em 1991–2025; em 2016–2025,
0,03 × 0,09. Por regime de h (NP v2 − linear, por par): reta +0,001, > 2·sd +0,008, 1–2 −0,002,
0,5–1 −0,007, ≤ 0,5 −0,009 — a perda nas curvas flexíveis caiu a um quarto da v1 (−0,036).

### 7.4 Artefato explicativo

Reconstruído em 22/10 para refletir a configuração v2: https://claude.ai/artifact/EmAQP4n7QWKY6dgFUpNAcE.
Fontes e geradores em `src/validation/auditoria/nonparametric/artefato/` (`template_v2.html`,
`dados_artefato_v2.py`, `smoke_v2.js`) e `dados_negociacao_passo.py` (exemplo STT ~ g(OMC), 2002).
Saídas preservadas desta etapa: `*_np_massa5*`, `*_np_massa0*`, `*_np_lsup5*`,
`*_np_completo_b005_v10.csv` (completo com β 0,05 e veto 10).

### 7.5 μ e σ do z: fixos ou re-estimados até t−1? — [usuário: questionou; testado → FIXOS]

Se a curva é re-estimada todo dia, por que μ e σ não? Implementado `MU_SIGMA_MODO` no notebook
de negociação: `'formacao'` (padrão, fixos), `'expandido'` (erros um passo à frente da formação +
spreads de monitoramento até t−1, que têm a mesma natureza) e `'movel'` (últimos 126). Na abertura,
μ e σ do dia são congelados junto com a tangente. O padrão reproduz a rodada principal (Δ = 0,0).

| μ, σ | Sharpe | ret. a.a. | MDD | sinais | trades | ret./trade |
|---|---|---|---|---|---|---|
| **fixos da formação** | **0,85** | 3,37% | −14,5% | 19.055 | 10.694 | 0,0093 |
| expandido | 0,78 | 3,05% | −17,2% | 15.535 | 9.945 | 0,0091 |
| móvel 126 | 0,76 | 2,96% | −18,3% | 15.301 | 10.046 | 0,0087 |

Leitura: o spread na negociação tem desvio ~1,65× o σ da formação, então com σ fixo o "2σ" age
como ~1,2σ na escala real. Re-estimar σ o aumenta e corta ~3.500 sinais que, em média, rendiam
o mesmo por trade — o total cai. Além disso, σ cresce justo quando o par se afasta. Re-estimar,
portanto, mistura "consistência" com "limiar mais exigente"; comparar de forma justa exigiria
recalibrar δ (ajuste ao backtest). **Mantidos fixos**: melhor resultado e mesma convenção da linear
estática (Rad/Gatev), cujo z é inflado pelo mesmo fator — a comparação pareada é preservada.
Saídas: `*_np_ms_exp.csv`, `*_np_ms_mov.csv`.

---

## 8. Formação própria do método NP (iniciada em 2026-10-24) — [usuário: desenvolver seleção própria]

Até aqui os pares vinham da cointegração **linear**: o NP só redesenhava o equilíbrio de pares já
aprovados por um teste linear e não tinha teste de cointegração próprio (o ADF do resíduo era só
diagnóstico, slides 21–22). A formação própria seleciona os pares com o critério do NP.

### 8.1 Por que não há tabela para o teste, e por que simular — [assumida, discutida com o usuário]

- O ADF pode ser **calculado** sobre o erro de uma curva; o que não vale é o **valor crítico**. As
  tabelas mudam conforme o que gerou a série: −2,86 para um preço (Dickey–Fuller), −3,34 para o
  resíduo de uma reta por OLS (Engle–Granger; MacKinnon 1991, 2010). Para o erro de uma curva kernel
  com h escolhido por CV não existe tabela: a curva se adapta e "inventa" cointegração em pares
  independentes (regressão não paramétrica espúria, Phillips 2009).
- **Literatura de testes (verificada em 24/10):** Wang & Phillips (2012, *Annals of Statistics* 40(2))
  é um teste de **especificação** — H₀: g tem forma paramétrica (ex.: linear) — e supõe que a relação
  cointegrada existe; Duffy & Kasparis (2021) relatam mais poder que ele. Para a **existência** não há
  um teste kernel padrão; alternativas adjacentes: teste de postos de Breitung (2001, g monótona) e
  Choi & Saikkonen (2010, g paramétrica). (Detalhes destes dois a conferir antes de citar no TCC.)
- **Solução:** a mesma receita das tabelas de MacKinnon — simulação —, com o **nosso** procedimento
  no lugar do OLS. Notebook `valor_critico_np.ipynb`.

### 8.2 Wang & Phillips (2012) não ranqueia os pares — [usuário propôs; testado e descartado]

O usuário propôs ranquear pelos pares em que a curva mais acrescenta sobre a reta. Dois problemas:
(1) o teste supõe cointegração; num par sem ela o resíduo linear é I(1) e o teste rejeita "reta" com
força, premiando pares quebrados; (2) nos dados, o ganho da curva sobre a reta na formação (queda do
erro da CV unilateral) **não tem relação** com o resultado na negociação: correlação de postos −0,01
com a vantagem NP − linear por par; NP − linear é negativo em todas as faixas de ganho (−0,2 a −0,5
p.p.), positivo só onde a reta vence (+0,1 p.p.). Fica como **diagnóstico** possível (quantos pares
rejeitam a linearidade, slide 29), não como critério de seleção.

### 8.3 O teste — `kernel_np.teste_coint_np` (mesma função na simulação e na formação)

1. As duas direções (B ~ g(A) e A ~ g(B)); h pela CV unilateral (gap 20, t_min 126).
2. Direção de menor erro de CV **relativo** (÷ variância da dependente): as duas direções têm
   dependentes diferentes, o erro bruto não compara.
3. Erros **um passo à frente** (curva só com s ≤ t−1, t ≥ 126) no h escolhido — mesma natureza do
   spread monitorado na negociação, e fora da amostra para a curva não copiar o caminho.
4. ADF desses erros com **constante** (`regression='c'`: o erro fora da amostra não tem média zero por
   construção, ao contrário do resíduo do OLS) e lags por AIC (como a formação linear).

### 8.4 A hipótese nula a partir dos nossos dados — [assumida, pedido do usuário: usar nossos dados]

- **Principal — pares reais com os dias embaralhados:** pares sorteados entre os 300 candidatos de
  menor SSD de ~80 janelas (1 a cada 5, 1991–2025); os retornos diários das duas ações são
  embaralhados **mantendo juntos os dois retornos de cada dia**. Fica a correlação do mesmo dia, as
  caudas e a volatilidade reais; some o mecanismo de volta ao equilíbrio, que está na sequência dos
  dias. Usar os pares reais sem embaralhar é impossível: não se sabe quais são cointegrados (seria
  circular).
- **Conferência — gaussiana** com a média, a volatilidade e a correlação de cada par sorteado.
- **Poder:** pares cointegrados por construção, y = 1 + 0,9(x−1) + c(x−1)² + u, u AR(1) com φ ∈
  {0,80; 0,90; 0,95}, desvio 0,02; c = 0 (reta) e c = −1 (curva).
- Limitações: embaralhar apaga o agrupamento de volatilidade; o valor crítico controla o erro por par,
  não o da seleção dos 20 melhores entre centenas (testes múltiplos — o mesmo problema da linear).

### 8.5 A formação — `pairs_formation_np_propria.ipynb`

| passo | escolha | referência / motivo |
|---|---|---|
| universo, Q, SSD, mesmo emissor | idênticos à formação linear (`formacao_utils.py`) | comparação pareada |
| pré-filtro | 300 menores SSD (linear: 100) | Rad et al. (2016) § 4.2; N maior para relações curvas — **[assumida]** |
| teste | `teste_coint_np` < valor crítico simulado a 5% | § 8.1–8.4 |
| hedge | mediana do β local ≥ 0,50 | coerente com `BETA_MIN` da negociação — **[assumida]** |
| ranking | `'ssd'`: em ordem de SSD, para nos 20 primeiros aprovados | igual à linear (Rad et al. 2016); escolhido **antes** de ver resultados, para não ajustar ao backtest — **[assumida]** |
| saída | `pares_formados_np_propria.csv`, mesmas colunas | a negociação não muda |

### 8.6 Resultados da simulação do valor crítico (2026-10-24)

`output/valor_critico/valor_critico_np.json`; 3.000 pares reais embaralhados de 82 janelas e 2.000
gaussianos.

| nula | crítico 1% | **crítico 5%** | crítico 10% | aprovados por −3,34 | aprovados por −2,86 | reta escolhida |
|---|---|---|---|---|---|---|
| **real embaralhada (principal)** | −4,28 | **−3,52** | −3,18 | 7,6% | 16,5% | 33% |
| gaussiana (conferência) | −4,34 | −3,64 | −3,26 | 8,9% | 18,5% | 28% |

- As duas nulas concordam (diferença de 0,12): o valor crítico é robusto à forma da nula. Usamos o
  da real embaralhada, como planejado.
- A tabela de Engle–Granger erraria **pouco** aqui (7,6% de falsos positivos em vez de 5%): os erros
  **fora da amostra** já protegem contra a curva "copiar" o caminho. Com resíduos dentro da amostra o
  problema seria bem maior (não medido).

**Poder** (fração detectada pelo crítico simulado; 200 pares por cenário):

| equilíbrio | φ = 0,80 (meia-vida 3) | φ = 0,90 (7) | φ = 0,95 (14) |
|---|---|---|---|
| curvo (c = −1) | 64,5% | 27,0% | 13,0% |
| linear (c = 0) | 71,0% | 21,0% | 7,5% |

⚠️ **Limitação:** o poder é baixo para reversão lenta, porque o teste usa só 126 erros (um semestre,
t ≥ 126). Para os pares reais (AR(1) do spread ≈ 0,88, meia-vida ≈ 5 pregões) o poder fica perto de
30–50%: o teste rejeita muitos pares cointegrados. Alternativa a considerar: `T_MIN_UNILATERAL = 63`
(mais erros avaliados), que exige refazer a simulação, porque muda o procedimento.

**Teste da formação em 3 janelas:** 309 candidatos testados, 19,7% aprovados no teste, 98% destes
passam no filtro de β, todas as janelas com 20 pares, só 18% dos pares coincidem com os da linear.

### 8.7 Resultados da formação própria (rodada de 2026-10-24)

Relatório: `validation/auditoria/nonparametric/relatorio_propria.md`. A formação rodou completa
(44 min, 3 processos); a negociação travou com o computador suspenso e foi refeita às 17:51
(o processo travado foi encerrado; a formação não precisou ser refeita).

**Formação:** 409 janelas, 8.011 pares (19,6 por janela; 90% das janelas com 20); 73.926 candidatos
testados, **11,8% aprovados** no teste (92% destes passam no filtro de β); reta escolhida em 25%
dos selecionados; ADF mediano dos selecionados −3,90 (crítico −3,52); **só 23,7% dos pares coincidem
com os da formação linear**.

| 1991–2015 | ret. a.a. | vol. | Sharpe | MDD | trades | conv. |
|---|---|---|---|---|---|---|
| linear estática | 3,71% | 3,98% | 0,94 | −15,4% | 10.927 | 55,3% |
| NP, pares da linear (v2) | 3,37% | 4,00% | 0,85 | −14,5% | 10.694 | 56,2% |
| **NP, formação própria** | **3,92%** | 4,37% | **0,90** | **−13,4%** | 11.288 | **59,4%** |

| Sharpe | linear | NP pares da linear | **NP formação própria** |
|---|---|---|---|
| 1991–2015 (rodada completa) | 0,96 | 0,88 | 0,90 |
| 2016–2025 | 0,03 | 0,09 | **0,34** |
| **1991–2025** | 0,66 | 0,62 | **0,72** |

Leitura:
- É a primeira configuração do NP que **supera a linear no período completo** (0,72 × 0,66), com
  retorno maior (3,22% × 2,70% a.a.) e drawdown menor (−13,4% × −15,7%). Em 1991–2015 ainda fica
  pouco abaixo no Sharpe (0,90 × 0,94), com retorno maior e mais volatilidade.
- A convergência sobe para 59,4%, o nível da linear dinâmica: o teste próprio escolhe pares cuja
  curva de fato prevê fora da amostra.
- **Robustez do ganho em 2016–2025:** sem o 1% de melhores pares, o P&L do período segue positivo
  (+7,7) — com os pares da linear fica negativo (−4,9). Mas **2020 responde por 59%** do P&L do
  período (+10,8 de +18,3; crise e recuperação da COVID, alta volatilidade). Sem 2020 ainda positivo
  (~+7,5), mais modesto.
- Cuidado com seleção na amostra: N = 300 e o ranking `'ssd'` foram fixados antes de ver resultados,
  mas o conjunto do método (CV unilateral, piso de β, sem veto) foi calibrado olhando principalmente
  1991–2015. O período 2016–2025 é o mais próximo de "fora da amostra" que temos.

### 8.8 Formação própria adotada como padrão (2026-10-24) — [usuário]

- `pairs_trading_np.ipynb`: `ARQUIVO_PARES = 'output/pares/pares_formados_np_propria.csv'`. A rodada
  principal refeita com o padrão reproduz a rodada `_propria` com diferença 0,0 (1991–2015 e completo).
- Saídas da configuração anterior (pares da linear) preservadas como `*_np_pares_linear.csv` e
  `*_np_pares_linear_completo.csv`. A formação com os pares da linear (`pairs_formation_np.ipynb`)
  segue disponível.
- **Testes anteriores** (critério de h, vetos, saída, μ e σ, piso de β) foram feitos com os pares da
  linear, para a comparação ser par a par; o artefato indica isso em cada um.
- **Achado novo (teto de β):** com z < 0 a carteira vende β dólares da independente; houve abertura
  com β = 3,08 (WU ~ g(SBUX), janela 2014) — 3 dólares vendidos por 1 comprado. O piso só limita β
  pequeno; avaliar um teto (ex.: 2 = 1/0,50). Na pauta.
- Artefato v3 (abas "Método e decisões" e "Formação de pares"): fontes em
  `validation/auditoria/nonparametric/artefato/` — `monta_v3.py` monta a página a partir de
  `template_v2.html`, `aba_formacao.html`, `js_aba_formacao.js`, `dados_artefato_v3.py`,
  `dados_formacao_tab.py` e `../dados_negociacao_passo.py` (exemplo PG ~ g(ITW), 1998); teste com
  `smoke_v3.js`.

---

## 9. Rodada de 2026-11-02 — dimensionamento, significância, poder do teste e Wang & Phillips

Pedido do usuário (01/11): (1) corrigir o dimensionamento das pernas seguindo os slides e a linear,
"o mais simples e que faz mais sentido"; (2) testar se "supera a linear" é estatisticamente
significativo; (4) avaliar o teste a partir do dia 63; (6) diagnóstico de Wang & Phillips (2012).
Scripts e logs em `validation/auditoria/nonparametric/` (`patch_dimensionamento.py`, `lote_dim.py`,
`lin_variantes.py`, `lote_lin.py`, `teste_sharpe.py`, `compara_dim.py` → `relatorio_dim.md`,
`lote_t63.py` → `relatorio_t63.md`, `gera_nb_wp.py`).

### 9.1 Dimensionamento: maior perna = $1, 0,50 ≤ β ≤ 2 — [usuário: abordagem (b); assumida: faixa de β]

**O que dizem as referências:**
- **Slides 17–18:** "Short P1 + Long β̂ P2" e "Long P1 + Short β̂ P2 *ou a posição inversa*" — 1 unidade
  da dependente contra β da independente, a mesma razão nos dois sentidos. Não há 1/β.
- **Rad et al. (2016) § 4.2.2** (a convenção da linear e, até aqui, do NP): a perna **comprada** vale
  sempre $1; com z > 0 vende-se $1/β da dependente. Alavanca quando β < 1 (z > 0); com β > 1 e z < 0
  vende-se $β da independente — também alavancado (houve abertura com β = 3,08).
- **Gatev et al. (2006) / Rad § 5.1:** o retorno é medido sobre posições de $1.

**Escolha:** o hedge dos slides (1 : β nos dois sentidos) com a **maior perna normalizada em $1**:
retorno = −posição × Δspread ÷ max(1, β). Segue os slides no hedge e Gatev/Rad no capital, e não alavanca
nenhum lado por construção. Faixa 0,50 ≤ β ≤ 2: a perna menor vale ao menos metade da maior (regra
simétrica, fixada pelo princípio; o teto não muda o resultado com esta convenção).
`DIMENSIONAMENTO = 'maior_perna'`, `BETA_MAX = 2.0` em `pairs_trading_np.ipynb` (padrão; `'rad'` e
`'slides'` seguem como opção). O padrão reproduz a variante testada (Δ = 0,0); saídas Rad preservadas
como `*_np_dim_rad*.csv`.

| NP, formação própria | Sharpe 91–15 | vol 91–15 | MDD 91–15 | Sharpe 16–25 | Sharpe 91–25 | pares \|ret\| > 0,5 |
|---|---|---|---|---|---|---|
| Rad, β ≥ 0,50 (anterior) | 0,90 | 4,37% | −13,4% | 0,34 | 0,72 | 88 |
| Rad, 0,50 ≤ β ≤ 2 (opção a) | 0,95 | 4,22% | −14,2% | 0,31 | 0,74 | 78 |
| slides 1 : β, β ≥ 0,50 | 0,95 | 4,26% | −10,6% | 0,46 | 0,80 | 65 |
| maior perna, β ≥ 0,05 | 1,05 | 3,73% | −10,5% | 0,40 | 0,83 | 38 |
| maior perna, β ≥ 0,50 | 1,11 | 3,55% | −9,4% | 0,40 | 0,87 | 36 |
| **maior perna, 0,50 ≤ β ≤ 2 (padrão)** | **1,11** | **3,53%** | **−9,7%** | **0,38** | **0,87** | 36 |

**A linear com as mesmas convenções** (em memória, notebook atual, sem alterar o notebook nem as saídas):
Rad 0,93 / 0,66 (1991–2015 / 1991–2025); maior perna 1,02 / 0,71; slides 1,02 / 0,70. O problema era da
convenção de Rad, não do método: a linear também melhora. **Recomendação (decisão do usuário):** adotar
a mesma convenção na cointegração linear (estática e dinâmica), para a comparação entre métodos não
misturar dimensionamento com método.

⚠️ **Saídas gravadas da linear desatualizadas:** `cointegration/output/resultados/negociacao_*_coint.csv`
são de 14/09, antes da mudança de `SIGMA_MIN` (0,005 → 0,01, 22/09) no notebook. O notebook atual dá
Sharpe 0,934 em 1991–2015 (o arquivo, 0,937). As comparações desta seção usam as rodadas em memória do
notebook atual (`lin_<conv>_<período>_*.csv`). Regenerar as saídas da linear é recomendado.

### 9.2 Significância da diferença de Sharpe — [assumida: método]

`teste_sharpe.py`: bootstrap em blocos circulares (Politis & Romano 1992; espírito de Ledoit & Wolf
2008, versão básica) com blocos de 5, 21 e 63 pregões, 5.000 réplicas, e Jobson–Korkie com a correção de
Memmel (2003) como referência. Validado em séries simuladas de mesmo Sharpe: rejeita 6% a 5% (100 réplicas).

| NP × linear (mesma convenção maior perna) | dif. Sharpe | p (blocos 21) | IC 95% |
|---|---|---|---|
| 1991–2025 | +0,16 | 0,24 | [−0,10; +0,42] |
| 1991–2015 | +0,06 | 0,74 | [−0,28; +0,39] |
| 2016–2025 | +0,35 | 0,08 | [−0,05; +0,75] |

Contra a linear na convenção oficial dela (Rad): 1991–2025 +0,21 (p = 0,12); 2016–2025 +0,35 (p = 0,08).
**Nenhuma diferença é significativa a 5%.** Conclusão para o TCC: o NP é **comparável** à linear, com
indício (p ≈ 0,08) de vantagem depois de 2016 — período fortemente influenciado por 2020. Correlação
diária entre as duas estratégias ≈ 0,66: são estratégias parecidas, o que torna difícil separá-las.

### 9.3 Poder do teste: avaliar a partir do dia 63 — [usuário: rodar; resultado: manter 126]

Simulação refeita com `T_MIN_UNILATERAL = 63` (`output/valor_critico_t63/`) e formação própria
(`pares_formados_np_propria_t63.csv`). Mesmo procedimento; o notebook confere os parâmetros.

| | t_min 126 (padrão) | t_min 63 |
|---|---|---|
| valor crítico 5% (gaussiana) | −3,52 (−3,64) | −3,67 (−3,81) |
| falsos positivos com a tabela −3,34 | 7,6% | 10,1% |
| poder, meia-vida 3 / 7 / 14 pregões (curva) | 65% / 27% / 13% | 86% / 46% / 19% |
| candidatos aprovados no teste | 11,8% | 19,5% |
| janelas com 20 pares | 90% | 99,8% |
| pares em comum com a linear | 24% | 42% |
| Sharpe 1991–2015 / 2016–2025 / 1991–2025 | **1,11 / 0,38 / 0,87** | 1,04 / 0,21 / 0,77 |

**Mais poder não melhorou a negociação.** O teste mais poderoso aprova mais pares, mais parecidos com os
da linear (42% em comum), e o resultado converge para o da linear (dif. 1991–2025: +0,06, p = 0,57). O
teste com 126 erros funciona como filtro exigente: só passam pares com volta ao equilíbrio forte.
**Mantido t_min = 126** como padrão; t_min 63 fica documentado como sensibilidade. Ressalva: a diferença
entre as duas versões também não foi testada formalmente e pode ser ruído.

### 9.4 Diagnóstico de linearidade — Wang & Phillips (2012) — [usuário: rodar como diagnóstico]

Notebook `diagnostico_wang_phillips.ipynb`, módulo `especificacao_np.py`; saídas em `output/diagnostico/`.

**Implementação:** estatística do artigo (Seção 2, eq. 2: S_n = Σ_{s≠t} û_s û_t K((x_t−x_s)/h)) e
normalização do Teorema 3.1 (Z_n = S_n/(√2 V_n)), com û do OLS sob H0, kernel gaussiano, x na escala do
incremento diário e h = n^(−1/3) (meio da grade da Seção 4 do artigo). Leitura do artigo feita em 02/11
(ar5iv, arXiv 1206.0825): o artigo **supõe u_t diferença de martingal** (Assumption 2(i)) e diz que a
extensão a erros serialmente correlacionados não está provada. Nossos spreads têm AR(1) ≈ 0,89.
**Por isso o p-valor vem de bootstrap sob H0 com erro AR(1)** (199 réplicas, x fixo, OLS e Z_n refeitos)
— a mesma lógica do valor crítico simulado.

**Validação** (150 pares simulados por cenário; y = 1 + 0,9(x−1) + c(x−1)² + u):

| erro AR(1) | rejeita a reta verdadeira — N(0,1) do artigo | — bootstrap | detecta a curva (bootstrap) |
|---|---|---|---|
| 0 | 2,0% | 2,7% | 56,7% |
| 0,80 | 53,3% | 6,0% | 38,0% |
| 0,90 | 72,7% | 4,0% | 34,0% |
| 0,95 | 78,7% | 7,3% | 25,3% |

**Resultados:**
- Pares da formação própria (8.011): rejeitam a reta **18,3%** (bootstrap); pela N(0,1), 83,1% (inválido).
- Comparação com a CV: quando a CV escolhe a reta, W&P concorda em 96,6%; quando escolhe curva, **76,7%
  dessas curvas não são significativamente diferentes da reta**. A CV adota curvas bem mais do que um teste
  formal justifica.
- Pares da linear (8.139): rejeitam a reta 9,9%. **Onde W&P rejeita a reta, o NP perde da linear** (NP
  +1,30% × linear +2,50% por par; diferença −0,012), onde não rejeita, empatam (−0,0003). Correlação de
  postos entre Z_n e a vantagem NP − linear: −0,008.
- **Leitura:** não linearidade estatisticamente significativa na formação não vira vantagem na negociação
  — tende a ser o contrário (slide 29: "não linearidade estatística ≠ alpha econômico"). Hipótese: uma
  curva significativa na formação muitas vezes reflete uma mudança de regime dentro da janela, que não
  persiste. O ganho do NP vem do **teste de cointegração próprio** (seleção de pares com equilíbrio forte),
  não da forma curva em si.

### 9.5 Artefato v4 e relatório

- Página atualizada (versão 4, 02/11): seção 9 da aba Método passa a tratar do dimensionamento (tabelas
  NP e linear nas três convenções); seção 10 ganha o teste de significância; a aba Formação ganha a
  coluna de poder com t_min 63 (F4), a significância no resultado (F7) e a seção F8 (Wang & Phillips);
  o exemplo dia a dia (PG ~ g(ITW), 1998) foi refeito com a convenção nova. Fontes:
  `validation/auditoria/nonparametric/artefato/monta_v4.py` (+ `dados_artefato_v4.py`,
  `dados_formacao_tab_v4.py`, `smoke_v4.js`; `index_v4.html` é a página publicada).
- Relatório da rodada: `RELATORIO_2026-11-02.md`.
