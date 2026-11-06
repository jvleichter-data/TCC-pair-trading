# -*- coding: utf-8 -*-
# Seleção de pares da formação PRÓPRIA do método NP — tradução de
# new_aproach/src/nonparametric/formacao_utils.py. Universo, normalização, SSD e exclusão de
# mesmo emissor vêm de funcoes/comum.R (idênticos aos da formação linear, para que a única
# diferença entre as duas seleções seja o teste de cointegração).
# Requer funcoes/comum.R, funcoes/adf.R e nonparametric/kernel_np.R.


# ── Formação própria: seleção numa janela ────────────────────────────────────────────
seleciona_pares_janela <- function(Q, p) {
  # Q : matriz de preços normalizados da janela (já filtrada e normalizada).
  # p : lista de parâmetros — n_pre_ssd, ssd_min, grade_rel, gap, t_min, autolag, crit,
  #     beta_med_min, top_k, ranking ('ssd' ou 'adf').
  # Para cada candidato do pré-filtro SSD (ordem crescente de SSD):
  #   teste_coint_np → aprovado se stat < crit (valor crítico SIMULADO);
  #   filtro de hedge: mediana do β local na formação ≥ beta_med_min.
  # ranking 'ssd' para ao reunir top_k aprovados (como a formação linear); 'adf' testa todos
  # e fica com as top_k estatísticas mais negativas.
  # Retorna list(sel = data.frame dos pares, log = contagens).
  cands <- candidatos_ssd(calcular_ssd(Q), p$n_pre_ssd, p$ssd_min)
  aprovados <- list(); n_test <- 0L; n_coint <- 0L
  for (k in seq_len(nrow(cands))) {
    a <- cands$ativo1[k]; b <- cands$ativo2[k]
    n_test <- n_test + 1L
    r <- teste_coint_np(Q[, a], Q[, b], p$grade_rel, p$gap, p$t_min, p$autolag)
    if (is.na(r$direcao) || !(r$stat < p$crit)) next
    n_coint <- n_coint + 1L
    if (r$direcao == "B~A") { x <- Q[, a]; y <- Q[, b] } else { x <- Q[, b]; y <- Q[, a] }
    b_loc <- loclin(x, x, y, r$h)$b
    beta_med <- stats::median(b_loc, na.rm = TRUE)
    if (!isTRUE(beta_med >= p$beta_med_min)) next
    aprovados[[length(aprovados) + 1]] <- data.frame(
      ativo1 = a, ativo2 = b, ssd = cands$ssd[k], r[c("direcao", "h", "h_rel", "h_linear",
      "cv_rel", "cv_rel_linear", "stat", "mu", "sigma", "n_erros")],
      beta_loc_med = beta_med,
      beta_loc_p10 = stats::quantile(b_loc, 0.10, na.rm = TRUE, names = FALSE),
      beta_loc_p90 = stats::quantile(b_loc, 0.90, na.rm = TRUE, names = FALSE),
      stringsAsFactors = FALSE)
    if (p$ranking == "ssd" && length(aprovados) >= p$top_k) break
  }
  sel <- if (length(aprovados)) do.call(rbind, aprovados) else NULL
  if (!is.null(sel) && p$ranking == "adf") sel <- sel[order(sel$stat), ]
  if (!is.null(sel)) sel <- head(sel, p$top_k)
  list(sel = sel, log = data.frame(n_candidatos = nrow(cands), n_testados = n_test,
                                   n_coint = n_coint, n_aprovados = length(aprovados),
                                   n_selecionados = if (is.null(sel)) 0L else nrow(sel)))
}


# ── Valor crítico salvo em JSON (valor_critico_np.R → pairs_formation_np_propria.R) ────────────────────────────────────────────
# Leitor mínimo para o formato que nonparametric/valor_critico_np.R e valor_critico_np.ipynb gravam;
# assim a formação aceita o valor crítico de qualquer um dos dois.
ler_valor_critico <- function(arq) {
  txt <- paste(readLines(arq, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  bloco <- function(nome) regmatches(txt, regexpr(paste0('"', nome, '"\\s*:\\s*\\{[^}]*\\}'), txt))
  valores <- function(b) {
    m <- regmatches(b, gregexpr('"[0-9]+%"\\s*:\\s*-?[0-9.eE+-]+', b))[[1]]
    stats::setNames(as.numeric(sub('.*:\\s*', "", m)), sub('"([0-9]+%)".*', "\\1", m))
  }
  campo <- function(nome) sub('^"[^"]*"\\s*:\\s*"?([^",}\n]*)"?.*$', "\\1",
                              regmatches(txt, regexpr(paste0('"', nome, '"\\s*:\\s*[^,}\n]+'), txt)))
  grade <- regmatches(txt, regexpr('"grade_h_rel"\\s*:\\s*\\[[^]]*\\]', txt))
  grade <- trimws(strsplit(sub('.*\\[([^]]*)\\].*', "\\1", grade), ",")[[1]])
  list(valor_critico = valores(bloco("valor_critico")),
       nula_principal = campo("nula_principal"), gerado_em = campo("gerado_em"),
       falso_positivo_com_EG_334 = as.numeric(campo("falso_positivo_com_EG_334")),
       grade_h_rel = ifelse(grade == "null", Inf, suppressWarnings(as.numeric(grade))),
       gap_unilateral = as.numeric(campo("gap_unilateral")),
       t_min_unilateral = as.numeric(campo("t_min_unilateral")),
       autolag_adf = campo("autolag_adf"))
}
