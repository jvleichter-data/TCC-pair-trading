# -*- coding: utf-8 -*-
# Funções compartilhadas pelos métodos da distância e da cointegração.
#
# Equivalem às funções que se repetem nos notebooks de new_aproach/src/distance e
# new_aproach/src/cointegration (carga da base, janelas em meses calendário, filtros de
# universo, SSD, exclusão de mesmo emissor, contagem de trades, portfólio e métricas
# simples). Cada script faz source() deste arquivo com local = TRUE.

source("config.R", local = TRUE)

META_COLS <- c("year", "semester", "period", "day_in_semester", "total_days_sem")

# Pastas de saída do método do script: PASTA_PARES, PASTA_RESULTADOS e PASTA_IMAGENS
# (<método>/output/pares etc.), definidas no ambiente de quem chama.
usar_pastas <- function(metodo, ambiente = parent.frame()) {
  for (tipo in c("pares", "resultados", "imagens"))
    assign(paste0("PASTA_", toupper(tipo)), pasta_saida(metodo, tipo), envir = ambiente)
}


# ── Base de preços ───────────────────────────────────────────────────────────────────
# Mês calendário como inteiro (ano·12 + mês − 1): comparações de período ficam baratas e
# a ordem é a mesma de 'YYYY-MM'.
mes_num   <- function(ym) as.integer(substr(ym, 1, 4)) * 12L + as.integer(substr(ym, 6, 7)) - 1L
num_mes   <- function(n) sprintf("%04d-%02d", n %/% 12L, n %% 12L + 1L)

carregar_base <- function(caminho = ARQ_BASE) {
  # A base é guardada em .GlobalEnv: rodar_tudo.R lê o CSV (~55 MB) uma vez só.
  if (exists(".BASE_PRECOS", envir = .GlobalEnv)) {
    b <- get(".BASE_PRECOS", envir = .GlobalEnv)
    if (identical(attr(b, "caminho"), normalizePath(caminho, mustWork = FALSE))) return(b)
  }
  if (!file.exists(caminho))
    stop("Base não encontrada em '", caminho, "'. Ajuste ARQ_BASE em config.R.")

  if (requireNamespace("data.table", quietly = TRUE)) {
    dt <- data.table::fread(caminho, data.table = FALSE, showProgress = FALSE)
  } else {
    dt <- utils::read.csv(caminho, check.names = FALSE, stringsAsFactors = FALSE)
  }
  datas <- as.Date(dt[["date"]])
  cols  <- setdiff(names(dt), c("date", META_COLS))
  P <- matrix(unlist(lapply(dt[cols], as.numeric), use.names = FALSE),
              nrow = nrow(dt), dimnames = list(NULL, cols))
  rm(dt)

  base <- list(P = P, datas = datas, mes = mes_num(format(datas, "%Y-%m")))
  attr(base, "caminho") <- normalizePath(caminho, mustWork = FALSE)
  assign(".BASE_PRECOS", base, envir = .GlobalEnv)
  base
}


# ── Janelas rolantes em meses calendário ─────────────────────────────────────────────
janelas_formacao <- function(meses_unicos, meses_formacao, meses_negociacao, passo) {
  fim <- length(meses_unicos) - meses_formacao - meses_negociacao + 1
  if (fim < 1) return(list())
  lapply(seq(1, fim, by = passo), function(i) list(
    form = meses_unicos[i:(i + meses_formacao - 1)],
    neg  = meses_unicos[(i + meses_formacao):(i + meses_formacao + meses_negociacao - 1)]))
}

# Linhas da base dentro de [mes_ini, mes_fim] ('YYYY-MM').
linhas_periodo <- function(base, mes_ini, mes_fim) {
  which(base$mes >= mes_num(mes_ini) & base$mes <= mes_num(mes_fim))
}

# Recorte de um par num período, só com os dias em que os dois têm preço (= dropna()).
recortar_par <- function(base, a1, a2, mes_ini, mes_fim) {
  todas <- linhas_periodo(base, mes_ini, mes_fim)
  X  <- base$P[todas, c(a1, a2), drop = FALSE]
  ok <- !is.na(X[, 1]) & !is.na(X[, 2])
  list(P = X[ok, , drop = FALSE], linhas = todas[ok], todas = todas)
}


# ── Funções do método (formação) ─────────────────────────────────────────────────────
filtrar_ativos_completos <- function(precos) {
  precos[, colSums(is.na(precos)) == 0, drop = FALSE]
}

normalizar_precos <- function(precos) {
  # Q_i(t) = P_i(t) / P_i(0): todos os ativos partem de 1.
  sweep(precos, 2, precos[1, ], "/")
}

calcular_ssd <- function(Q) {
  # D(i,j) = Σ_t (Q_i(t) − Q_j(t))² = ||q_i||² + ||q_j||² − 2·<q_i, q_j>
  G <- crossprod(Q)
  n <- diag(G)
  outer(n, n, "+") - 2 * G
}

# Pares de mesmo emissor — lista explícita, não heurística.
# Ver o comentário completo em new_aproach/src/distance/pairs_formation.ipynb.
MESMO_EMISSOR <- list(
  # classes duais — permanentemente a mesma empresa
  c("GOOGL", "GOOG"), c("FOXA", "FOX"), c("NWSA", "NWS"), c("DISCA", "DISCK"),
  c("CMCSA", "CMCSK"), c("UA", "UAA"), c("BRK_A", "BRK_B"), c("BF_A", "BF_B"),
  c("RTN", "RTN_B"), c("TAP", "TAP_B"), c("VIAB", "VIAC"), c("LEN", "LEN_B"),
  # códigos Bloomberg mortos e renomeações sem reaproveitamento de ticker
  c("TKR", "1288453D", "291784Q"), c("JCI", "1436513D"), c("LSI", "1431816D"),
  c("DTV", "1448062D"), c("BF_B", "1958Q"), c("MHFI", "SPGI")
)
# Dois tickers são o mesmo emissor se aparecem juntos em algum grupo (BF_B está em dois).
.PARES_EMISSOR <- unlist(lapply(MESMO_EMISSOR, function(g) {
  e <- expand.grid(a = g, b = g, stringsAsFactors = FALSE)
  e <- e[e$a != e$b, ]
  paste(e$a, e$b, sep = "|")
}))
mesmo_emissor <- function(t1, t2) paste(t1, t2, sep = "|") %in% .PARES_EMISSOR

candidatos_ssd <- function(ssd, n = NULL, ssd_min = 0.01) {
  # Pares (ativo1, ativo2, ssd) em ordem crescente de SSD, cada par uma vez (ativo1 é a
  # coluna de menor índice, como np.triu_indices). Exclui SSD < ssd_min (ghost tickers)
  # e pares de mesmo emissor. n = NULL devolve todos os pares válidos.
  tick <- colnames(ssd)
  idx  <- which(upper.tri(ssd))
  v    <- ssd[idx]
  ok   <- v >= ssd_min
  idx  <- idx[ok]; v <- v[ok]
  o    <- order(v)
  # O filtro de emissor só precisa olhar os primeiros n + |lista| pares.
  if (!is.null(n)) o <- o[seq_len(min(length(o), n + length(.PARES_EMISSOR)))]
  idx <- idx[o]; v <- v[o]
  i <- (idx - 1L) %% nrow(ssd) + 1L
  j <- (idx - 1L) %/% nrow(ssd) + 1L
  out <- data.frame(ativo1 = tick[i], ativo2 = tick[j], ssd = v, stringsAsFactors = FALSE)
  out <- out[!mesmo_emissor(out$ativo1, out$ativo2), , drop = FALSE]
  if (!is.null(n)) out <- out[seq_len(min(nrow(out), n)), , drop = FALSE]
  rownames(out) <- NULL
  out
}


# ── Negociação: utilitários ──────────────────────────────────────────────────────────
ler_pares <- function(caminho) {
  # Tickers sempre como texto: há ações chamadas T e F, que o R leria como lógicos.
  d <- utils::read.csv(caminho, stringsAsFactors = FALSE, na.strings = "",
                       colClasses = c(ativo1 = "character", ativo2 = "character",
                                      formacao_inicio = "character", formacao_fim = "character",
                                      negociacao_inicio = "character", negociacao_fim = "character"))
  # CSVs gravados pelo Python: True/False e inf (o R não converte sozinho)
  texto <- c("ativo1", "ativo2", "formacao_inicio", "formacao_fim", "negociacao_inicio", "negociacao_fim")
  for (col in setdiff(names(d), texto)) if (is.character(d[[col]])) {
    v <- d[[col]][!is.na(d[[col]])]
    if (length(v) && all(v %in% c("True", "False", "TRUE", "FALSE"))) d[[col]] <- toupper(d[[col]]) == "TRUE"
    else if (length(v) && all(grepl("^-?([0-9.eE+-]+|inf|Inf|nan|NaN)$", v))) d[[col]] <- as.numeric(d[[col]])
  }
  d
}

filtrar_periodo <- function(pares, inicio = NULL, fim = NULL) {
  if (!is.null(inicio)) pares <- pares[pares$negociacao_inicio >= inicio, , drop = FALSE]
  if (!is.null(fim))    pares <- pares[pares$negociacao_fim    <= fim, , drop = FALSE]
  pares
}

imprimir_cabecalho_pares <- function(pares_raw, pares, base, inicio, fim) {
  cat(sprintf("Pares disponíveis : %s (%d janelas)\n",
              milhar(nrow(pares_raw)), length(unique(pares_raw$janela))))
  if (!is.null(inicio) || !is.null(fim)) {
    ini <- if (is.null(inicio)) min(pares_raw$negociacao_inicio) else inicio
    fi  <- if (is.null(fim)) max(pares_raw$negociacao_fim) else fim
    cat(sprintf("Período filtrado  : %s → %s  (%s pares, %d janelas)\n",
                ini, fi, milhar(nrow(pares)), length(unique(pares$janela))))
  } else {
    cat("Período filtrado  : todo o histórico\n")
  }
  cat(sprintf("Base de preços    : %s dias × %s tickers\n",
              milhar(nrow(base$P)), milhar(ncol(base$P))))
}

# Maior retorno diário (pct_change) entre as duas colunas — o filtro MAX_RETORNO_DIA.
maior_retorno_dia <- function(P) {
  if (nrow(P) < 2) return(-Inf)
  max(P[-1, ] / P[-nrow(P), ] - 1)
}

retornos_simples <- function(p) c(0, p[-1] / p[-length(p)] - 1)   # pct_change().fillna(0)

# Posição do dia anterior (a decisão de t é executada em t+1).
defasar <- function(x) c(0, x[-length(x)])

contar_trades <- function(pos) {
  # (n_abertos, n_fechados_normal, n_forcados), sobre o sinal SEM lag.
  n <- length(pos)
  entradas <- sum(pos[-1] != 0 & pos[-n] == 0) + (pos[1] != 0)
  saidas   <- sum(pos[-n] != 0 & pos[-1] == 0)
  c(abertos = as.integer(entradas), fechados = as.integer(saidas),
    forcados = as.integer(pos[n] != 0))
}

duracoes_trades <- function(pos) {
  # Duração (em pregões) de cada posição aberta, inclusive a fechada à força no fim.
  dur <- integer(0); ini <- NA
  for (t in seq_along(pos)) {
    if (pos[t] != 0 && is.na(ini)) {
      ini <- t
    } else if (pos[t] == 0 && !is.na(ini)) {
      dur <- c(dur, t - ini); ini <- NA
    }
  }
  if (!is.na(ini)) dur <- c(dur, length(pos) - ini)
  dur
}

aberturas_idx <- function(pos) {
  # Dias em que uma posição foi aberta (transição 0 → ±1).
  c(pos[1] != 0, pos[-1] != 0 & pos[-length(pos)] == 0)
}


# ── Portfólio diário ─────────────────────────────────────────────────────────────────
# Soma e contagem por dia da base; o retorno do portfólio é soma / contagem.
novo_acumulador <- function(base) list(soma = numeric(length(base$datas)),
                                       cont = integer(length(base$datas)))

acumular_par <- function(acc, recorte_neg, retorno, position_lag, committed_capital) {
  if (committed_capital) {
    # O par entra no denominador em TODOS os pregões do período — inclusive dias sem
    # preço (delisting), em que contribui 0.
    r <- numeric(length(recorte_neg$todas))
    r[match(recorte_neg$linhas, recorte_neg$todas)] <- retorno
    acc$soma[recorte_neg$todas] <- acc$soma[recorte_neg$todas] + r
    acc$cont[recorte_neg$todas] <- acc$cont[recorte_neg$todas] + 1L
  } else {
    ativo <- position_lag != 0
    l <- recorte_neg$linhas[ativo]
    acc$soma[l] <- acc$soma[l] + retorno[ativo]
    acc$cont[l] <- acc$cont[l] + 1L
  }
  acc
}

serie_portfolio <- function(acc, base) {
  ok <- acc$cont > 0
  data.frame(date = base$datas[ok], retorno_diario = acc$soma[ok] / acc$cont[ok])
}

retorno_composto <- function(r, grupo) {
  v <- tapply(r, grupo, function(x) prod(1 + x) - 1)
  data.frame(grupo = names(v), retorno = as.numeric(v), stringsAsFactors = FALSE)
}

metricas_performance <- function(r) {
  # Métricas anualizadas de uma série de retornos diários.
  eq <- cumprod(1 + r)
  mx <- cummax(eq)
  n_anos <- length(r) / 252
  c("Retorno acumulado"    = eq[length(eq)] - 1,
    "Retorno anualizado"   = eq[length(eq)]^(1 / n_anos) - 1,
    "Média diária × 252"   = mean(r) * 252,
    "Volatilidade anual"   = sd(r) * sqrt(252),
    "Sharpe ratio"         = mean(r) / sd(r) * sqrt(252),
    "Drawdown máximo"      = min((eq - mx) / mx),
    "Dias com retorno > 0" = mean(r > 0))
}

imprimir_metricas_simples <- function(r) {
  m <- metricas_performance(r)
  cat(strrep("=", 40), "\n     MÉTRICAS DE PERFORMANCE\n", strrep("=", 40), "\n", sep = "")
  cat(sprintf("Retorno acumulado      : %s\n", pct(m[["Retorno acumulado"]], sinal = TRUE)))
  cat(sprintf("Retorno anualizado     : %s\n", pct(m[["Retorno anualizado"]], sinal = TRUE)))
  cat(sprintf("Volatilidade anual     : %s\n", pct(m[["Volatilidade anual"]])))
  cat(sprintf("Sharpe ratio           : %+.2f\n", m[["Sharpe ratio"]]))
  cat(sprintf("Drawdown máximo        : %s\n", pct(m[["Drawdown máximo"]], sinal = TRUE)))
  cat(sprintf("Dias com retorno > 0   : %s\n", pct(m[["Dias com retorno > 0"]], 1)))
  cat(strrep("=", 40), "\n", sep = "")
}

carregar_rf <- function(datas, caminho = ARQ_RF) {
  rf_df <- utils::read.csv(caminho, stringsAsFactors = FALSE)
  rf <- rf_df$rf[match(datas, as.Date(rf_df$date))]
  if (anyNA(rf)) {
    cat(sprintf("⚠ %d dia(s) do portfólio sem taxa — preenchidos com o último valor disponível.\n\n",
                sum(is.na(rf))))
    # ffill e depois bfill
    for (i in seq_along(rf)[-1]) if (is.na(rf[i])) rf[i] <- rf[i - 1]
    for (i in rev(seq_along(rf))[-1]) if (is.na(rf[i])) rf[i] <- rf[i + 1]
  }
  rf
}

imprimir_bruto_liquido <- function(port) {
  # Retorno bruto × líquido de renda fixa. O número comparável com o artigo do orientador
  # é o BRUTO: a posição long-short já é retorno excedente (ver notebooks).
  rf <- carregar_rf(port$date)
  bruto   <- metricas_performance(port$retorno_diario)
  liquido <- metricas_performance(port$retorno_diario - rf)
  cat(sprintf("Renda fixa no período : %s a.a. (média diária de %.6f)\n",
              pct((1 + mean(rf))^252 - 1), mean(rf)))
  cat(sprintf("Período               : %s → %s  (%s dias)\n\n",
              port$date[1], port$date[nrow(port)], milhar(nrow(port))))
  cat(strrep("=", 66), "\n   MÉTRICAS DE PERFORMANCE — bruto × líquido de renda fixa\n",
      strrep("=", 66), "\n", sep = "")
  cat(esq("", 24), drt("bruto", 13), drt("líquido", 13), drt("diferença", 14), "\n", sep = "")
  cat(strrep("-", 66), "\n", sep = "")
  for (nome in names(bruto)) {
    b <- bruto[[nome]]; l <- liquido[[nome]]; d <- l - b
    if (nome == "Sharpe ratio") {
      cat(esq(nome, 24), sprintf("%13.2f%13.2f%+14.2f", b, l, d), "\n", sep = "")
    } else if (nome %in% c("Volatilidade anual", "Dias com retorno > 0")) {
      cat(esq(nome, 24), drt(pct(b), 13), drt(pct(l), 13), drt(pct(d, sinal = TRUE), 14), "\n", sep = "")
    } else {
      cat(esq(nome, 24), drt(pct(b, sinal = TRUE), 13), drt(pct(l, sinal = TRUE), 13),
          drt(pct(d, sinal = TRUE), 14), "\n", sep = "")
    }
  }
  cat(strrep("=", 66), "\n", sep = "")
  invisible(list(bruto = bruto, liquido = liquido))
}

imprimir_estatisticas_trades <- function(res) {
  cat("=== Estatísticas de trades ===\n")
  cat(sprintf("Pares que abriram ≥ 1 trade    : %s de %s\n",
              milhar(sum(res$n_trades > 0)), milhar(nrow(res))))
  cat(sprintf("Total de trades abertos        : %s\n", milhar(sum(res$n_trades))))
  cat(sprintf("Trades fechados normalmente    : %s\n", milhar(sum(res$n_fechados))))
  cat(sprintf("Trades forçados (fim período)  : %s\n", milhar(sum(res$n_forcados))))
  if (sum(res$n_trades) > 0)
    cat(sprintf("\nTaxa de convergência           : %s\n",
                pct(sum(res$n_fechados) / sum(res$n_trades), 1)))
  cat("\n=== Retorno por par (todos os pares) ===\n")
  x <- res$retorno_total
  q <- stats::quantile(x, c(.25, .5, .75), names = FALSE)
  cat(sprintf("%-6s %12s\n", c("count", "mean", "std", "min", "25%", "50%", "75%", "max"),
              format(c(length(x), mean(x), sd(x), min(x), q, max(x)), digits = 6)), sep = "")
}

imprimir_top_bottom <- function(res, colunas) {
  o <- order(res$retorno_total, decreasing = TRUE)
  cat("Top 10 pares por retorno total:\n")
  print(res[head(o, 10), colunas], row.names = FALSE)
  cat("\nBottom 10 pares por retorno total:\n")
  print(res[head(rev(o), 10), colunas], row.names = FALSE)
}

imprimir_resumo_portfolio <- function(port) {
  eq <- cumprod(1 + port$retorno_diario)
  cat(sprintf("Período do portfólio: %s → %s\n", port$date[1], port$date[nrow(port)]))
  cat(sprintf("Dias de negociação  : %s\n", milhar(nrow(port))))
  cat(sprintf("Retorno diário médio: %s\n", pct(mean(port$retorno_diario), 4)))
  cat(sprintf("Retorno acumulado   : %s\n", pct(eq[length(eq)] - 1)))
}

imprimir_meses_positivos <- function(port) {
  m <- retorno_composto(port$retorno_diario, format(port$date, "%Y-%m"))
  cat(sprintf("Meses positivos: %d de %d  (%s)\n", sum(m$retorno > 0), nrow(m),
              pct(mean(m$retorno > 0), 0)))
  invisible(m)
}

# ── Estatísticas no padrão do pandas ─────────────────────────────────────────────────
# pandas.Series.skew() e .kurtosis() usam os estimadores ajustados pelo tamanho de
# amostra (G1 e G2); kurtosis() é a EXCEDENTE.
assimetria <- function(x) {
  x <- x[!is.na(x)]; n <- length(x)
  m2 <- mean((x - mean(x))^2); m3 <- mean((x - mean(x))^3)
  sqrt(n * (n - 1)) / (n - 2) * m3 / m2^1.5
}
curtose_excedente <- function(x) {
  x <- x[!is.na(x)]; n <- length(x)
  m2 <- mean((x - mean(x))^2); m4 <- mean((x - mean(x))^4)
  ((n + 1) * (m4 / m2^2 - 3) + 6) * (n - 1) / ((n - 2) * (n - 3))
}

# Corte em faixas de mesma largura, como pandas.cut(x, bins = k).
cortar_faixas <- function(x, k = 5) {
  mn <- min(x); mx <- max(x)
  br <- seq(mn, mx, length.out = k + 1)
  br[1] <- br[1] - (mx - mn) * 0.001
  cut(x, br, right = TRUE, dig.lab = 6)
}


# ── Formatação ───────────────────────────────────────────────────────────────────────
pct <- function(x, d = 2, sinal = FALSE) {
  ifelse(is.na(x), "—",
         sprintf(paste0("%", if (sinal) "+" else "", ".", d, "f%%"), 100 * x))
}
milhar <- function(x) formatC(x, format = "d", big.mark = ",")

# Alinhamento de texto por CARACTERES. O sprintf("%-26s") do R conta bytes, e cada letra
# acentuada ocupa dois em UTF-8 — as tabelas sairiam desalinhadas.
esq <- function(x, w) vapply(as.character(x), function(s) format(s, width = w), character(1), USE.NAMES = FALSE)
drt <- function(x, w) vapply(as.character(x), function(s) format(s, width = w, justify = "right"), character(1), USE.NAMES = FALSE)


# ── Gráficos (PNG em output/imagens) ─────────────────────────────────────────────────
abrir_png <- function(nome, largura = 14, altura = 7, pasta = PASTA_IMAGENS) {
  arq <- file.path(pasta, nome)
  grDevices::png(arq, width = largura, height = altura, units = "in", res = 110)
  arq
}
fechar_png <- function(arq) {
  grDevices::dev.off()
  cat("Gráfico salvo em:", arq, "\n")
}

plot_equity <- function(port, titulo, nome) {
  arq <- abrir_png(nome)
  eq <- cumprod(1 + port$retorno_diario)
  graphics::layout(matrix(1:2), heights = c(3, 1))
  graphics::par(mar = c(1, 5, 3, 1), oma = c(2, 0, 0, 0))
  plot(port$date, eq, type = "l", col = "#1565C0", lwd = 1.5, xlab = "",
       ylab = "Valor da carteira (base 1)", main = titulo, xaxt = "n")
  graphics::abline(h = 1, col = "gray", lty = 2); graphics::grid()
  graphics::par(mar = c(3, 5, 0.5, 1))
  r <- port$retorno_diario * 100
  plot(port$date, r, type = "h", col = ifelse(r < 0, "#ef5350", "#43A047"),
       xlab = "", ylab = "Retorno diário (%)")
  graphics::abline(h = 0)
  fechar_png(arq)
}

plot_pares_por_janela <- function(res, top_k, titulo, nome) {
  cont <- table(res$neg_inicio)
  arq <- abrir_png(nome, 16, 3.5)
  graphics::par(mar = c(5, 4, 3, 1))
  graphics::barplot(as.numeric(cont), names.arg = names(cont), las = 2, cex.names = 0.45,
                    col = ifelse(as.numeric(cont) >= 10, "#1565C0", "#ef5350"),
                    border = NA, main = titulo, ylab = "N pares")
  graphics::abline(h = top_k, col = "gray", lty = 2)
  fechar_png(arq)
  cat(sprintf("Janelas com 0 pares simulados : %d\n", sum(cont == 0)))
  cat(sprintf("Média de pares por janela     : %.1f\n", mean(cont)))
  cat(sprintf("Mínimo / Máximo               : %d / %d\n", min(cont), max(cont)))
}

plot_retorno_anual <- function(port, titulo, nome) {
  a <- retorno_composto(port$retorno_diario, format(port$date, "%Y"))
  arq <- abrir_png(nome, 14, 4)
  graphics::par(mar = c(4, 4, 3, 1))
  graphics::barplot(a$retorno * 100, names.arg = a$grupo, las = 2, cex.names = 0.7,
                    col = ifelse(a$retorno > 0, "#43A047", "#ef5350"), border = NA,
                    main = titulo, ylab = "Retorno (%)")
  graphics::abline(h = 0)
  fechar_png(arq)
}

# Estático × dinâmico, nas datas em comum (seção final dos notebooks dinâmicos).
comparar_estatico_dinamico <- function(port_din, res_din, arq_port_est, arq_par_est, titulo, nome) {
  if (!file.exists(arq_port_est)) {
    cat("Baseline estático não encontrado em", arq_port_est, "\n")
    cat("Rode o script estático correspondente primeiro para gerar a comparação.\n")
    return(invisible(NULL))
  }
  base_port <- utils::read.csv(arq_port_est, stringsAsFactors = FALSE)
  base_port$date <- as.Date(base_port$date)
  base_par <- utils::read.csv(arq_par_est, stringsAsFactors = FALSE)

  idx <- intersect(port_din$date, base_port$date)
  est <- base_port$retorno_diario[match(idx, base_port$date)]
  din <- port_din$retorno_diario[match(idx, port_din$date)]
  if (length(idx) < nrow(port_din) || length(idx) < nrow(base_port))
    cat(sprintf("⚠️  Períodos diferem: dinâmico %s dias, estático %s dias → comparando %s dias em comum.\n\n",
                milhar(nrow(port_din)), milhar(nrow(base_port)), milhar(length(idx))))

  metricas <- function(s) {
    eq <- cumprod(1 + s); dd <- (eq - cummax(eq)) / cummax(eq)
    c("Retorno acumulado" = eq[length(eq)] - 1,
      "Retorno anualizado" = eq[length(eq)]^(252 / length(s)) - 1,
      "Volatilidade anual" = sd(s) * sqrt(252),
      "Sharpe ratio" = mean(s) / sd(s) * sqrt(252),
      "Drawdown máximo" = min(dd),
      "Dias positivos" = mean(s > 0))
  }
  m_est <- metricas(est); m_din <- metricas(din)
  cat(strrep("=", 74), "\n   PORTFÓLIO — ESTÁTICO × DINÂMICO   (mesmas datas, sem custos)\n",
      strrep("=", 74), "\n", sep = "")
  cat(esq("", 22), drt("estático", 16), drt("dinâmico", 16), drt("diferença", 16), "\n", sep = "")
  cat(strrep("-", 74), "\n", sep = "")
  for (k in names(m_est)) {
    a <- m_est[[k]]; b <- m_din[[k]]
    if (k == "Sharpe ratio") cat(esq(k, 22), sprintf("%16.2f%16.2f%+16.2f", a, b, b - a), "\n", sep = "")
    else cat(esq(k, 22), drt(pct(a), 16), drt(pct(b), 16), drt(pct(b - a, sinal = TRUE), 16), "\n", sep = "")
  }
  cat(strrep("=", 74), "\n", sep = "")

  conv <- function(d) if (sum(d$n_trades)) sum(d$n_fechados) / sum(d$n_trades) else NA
  linha <- function(rot, a, b) cat(esq(rot, 28), drt(a, 14), drt(b, 14), "\n", sep = "")
  cat("\n"); linha("", "estático", "dinâmico")
  cat(strrep("-", 56), "\n", sep = "")
  linha("Trades abertos", milhar(sum(base_par$n_trades)), milhar(sum(res_din$n_trades)))
  linha("Fechados por reversão", milhar(sum(base_par$n_fechados)), milhar(sum(res_din$n_fechados)))
  linha("Forçados (fim do período)", milhar(sum(base_par$n_forcados)), milhar(sum(res_din$n_forcados)))
  linha("Taxa de convergência", pct(conv(base_par), 1), pct(conv(res_din), 1))
  linha("Retorno médio por par", pct(mean(base_par$retorno_total)), pct(mean(res_din$retorno_total)))
  linha("Sinais avaliados", "—", milhar(sum(res_din$n_sinais)))
  cat("\nNota: 'sinais avaliados' não tem contrapartida no estático — lá todo sinal vira\n")
  cat("trade. As duas contagens não são pareáveis: um sinal vetado devolve o par ao\n")
  cat("monitoramento, e ele volta a cruzar a banda mais adiante.\n")

  datas <- as.Date(idx, origin = "1970-01-01")
  eq_est <- cumprod(1 + est); eq_din <- cumprod(1 + din)
  dd_est <- (eq_est - cummax(eq_est)) / cummax(eq_est)
  dd_din <- (eq_din - cummax(eq_din)) / cummax(eq_din)
  arq <- abrir_png(nome)
  graphics::layout(matrix(1:2), heights = c(3, 1))
  graphics::par(mar = c(1, 5, 3, 1))
  plot(datas, eq_est, type = "l", log = "y", col = "#90A4AE", lwd = 1.4, xaxt = "n",
       xlab = "", ylab = "Equity (base 1)", main = titulo, ylim = range(c(eq_est, eq_din)))
  graphics::lines(datas, eq_din, col = "#1565C0", lwd = 1.6)
  graphics::legend("topleft", c("estático", "dinâmico"), col = c("#90A4AE", "#1565C0"), lwd = 2, bty = "n")
  graphics::grid()
  graphics::par(mar = c(3, 5, 0.5, 1))
  plot(datas, dd_est, type = "n", ylim = range(c(dd_est, dd_din, 0)), xlab = "", ylab = "Drawdown")
  graphics::polygon(c(datas, rev(datas)), c(dd_est, rep(0, length(datas))),
                    col = grDevices::adjustcolor("#90A4AE", 0.6), border = NA)
  graphics::polygon(c(datas, rev(datas)), c(dd_din, rep(0, length(datas))),
                    col = grDevices::adjustcolor("#1565C0", 0.5), border = NA)
  fechar_png(arq)
  invisible(list(estatico = m_est, dinamico = m_din))
}


# ── Cointegração (linear e NP): orientação do par e retorno mensal REC/RCC ─────────────
# Variável dependente e independente do OLS conforme a direção salva na formação.
orientar <- function(a1, a2, direcao) {
  if (identical(direcao, "A~B")) c(dep = a1, indep = a2) else c(dep = a2, indep = a1)
}


# ── Retorno mensal REC/RCC (Rad et al., §4.5, eq. 14 e 15) ───────────────────────────
mensal_do_par <- function(datas, retorno, position_lag, janela, a1, a2) {
  # r_mes = soma dos P&L diários do par no mês; negociou = teve posição em algum dia.
  mes <- format(datas, "%Y-%m")
  r   <- tapply(retorno, mes, sum)
  neg <- tapply(position_lag != 0, mes, any)
  data.frame(mes = names(r), r_mes = as.numeric(r), negociou = as.logical(neg[names(r)]),
             janela = janela, ativo1 = a1, ativo2 = a2, stringsAsFactors = FALSE)
}

calcular_rec_rcc <- function(mensal_df, n_pares_nominados) {
  # Primeiro por portfólio (janela), depois média equiponderada dos sobrepostos no mês.
  chave <- paste(mensal_df$janela, mensal_df$mes, sep = "\r")
  grupos <- unique(mensal_df[, c("janela", "mes")])
  grupos <- grupos[order(grupos$janela, grupos$mes), ]
  ch <- paste(grupos$janela, grupos$mes, sep = "\r")
  n_pares <- as.integer(table(chave)[ch])
  neg <- mensal_df$negociou
  soma_r <- tapply(mensal_df$r_mes[neg], chave[neg], sum)[ch]
  n_neg  <- as.integer(table(factor(chave[neg], levels = ch)))
  soma_r[is.na(soma_r)] <- 0
  port_mes <- data.frame(janela = grupos$janela, mes = grupos$mes, n_pares = n_pares,
                         n_negociaram = n_neg, soma_r = as.numeric(soma_r),
                         REC = ifelse(n_neg > 0, as.numeric(soma_r) / n_neg, NA),
                         RCC = as.numeric(soma_r) / n_pares_nominados,
                         stringsAsFactors = FALSE)
  rownames(port_mes) <- NULL
  media_na <- function(v) if (all(is.na(v))) NA else mean(v, na.rm = TRUE)
  rec <- tapply(port_mes$REC, port_mes$mes, media_na)
  rcc <- tapply(port_mes$RCC, port_mes$mes, mean)
  list(port_mes = port_mes,
       mensal = data.frame(mes = names(rec), REC = as.numeric(rec), RCC = as.numeric(rcc[names(rec)]),
                           stringsAsFactors = FALSE))
}

imprimir_rec_rcc <- function(rr, n_pares_nominados) {
  pm <- rr$port_mes; rec <- rr$mensal$REC
  n_por_mes <- table(pm$mes)
  cat(sprintf("Portfólios (janelas)             : %s\n", milhar(length(unique(pm$janela)))))
  cat(sprintf("Observações portfólio-mês        : %s\n", milhar(nrow(pm))))
  cat(sprintf("Meses de calendário              : %s (%s → %s)\n",
              milhar(length(unique(pm$mes))), min(pm$mes), max(pm$mes)))
  cat(sprintf("Portfólios sobrepostos por mês   : média %.2f | máx %d\n", mean(n_por_mes), max(n_por_mes)))
  cat(sprintf("Portfólio-mês sem nenhum trade   : %s (%s)  → REC indefinido, RCC = 0\n",
              milhar(sum(pm$n_negociaram == 0)), pct(mean(pm$n_negociaram == 0), 1)))
  cat(sprintf("Pares que negociaram por mês     : média %.1f de %d nominados (pares simulados por portfólio: média %.1f)\n",
              mean(pm$n_negociaram), n_pares_nominados, mean(pm$n_pares)))
  cat(sprintf("Meses sem REC (nenhum portfólio negociou): %s\n", milhar(sum(is.na(rec)))))

  estat <- function(s) {
    s <- s[!is.na(s)]; n <- length(s); m <- mean(s); dp <- sd(s)
    c("N meses" = n, "Média" = m, "t-stat" = m / (dp / sqrt(n)), "Desvio-padrão" = dp,
      "Sharpe (mensal)" = m / dp, "Assimetria" = assimetria(s), "Curtose" = curtose_excedente(s) + 3)
  }
  tab <- rbind("REC — capital empregado" = estat(rr$mensal$REC),
               "RCC — capital comprometido" = estat(rr$mensal$RCC),
               # Rad et al. (2016), Tabela 3, cointegração, ANTES de custos, CRSP 1962–2014.
               "REC — Rad et al. (antes de custos)" = c(630, 0.0085, 7.3268, 0.0111, 0.7703, 0.8130, 7.3561),
               "RCC — Rad et al. (antes de custos)" = c(630, 0.0068, 7.0365, 0.0097, 0.6969, 1.3934, 10.8547))
  cat("\n", strrep("=", 78), "\n  RETORNO MENSAL — média dos portfólios sobrepostos (Rad et al., eq. 14 e 15)\n", sep = "")
  cat(sprintf("  %s → %s  |  SEM custos de transação\n", min(rr$mensal$mes), max(rr$mensal$mes)))
  cat(strrep("=", 78), "\n", sep = "")
  f <- tab; f[, 1] <- round(f[, 1]); f[, -1] <- round(f[, -1], 4)
  print(f)
  cat(sprintf("\nREC — média mensal: %s | meses positivos: %s\n",
              pct(tab[1, "Média"]), pct(mean(rr$mensal$REC[!is.na(rr$mensal$REC)] > 0), 1)))
  cat(sprintf("RCC — média mensal: %s | meses positivos: %s\n",
              pct(tab[2, "Média"]), pct(mean(rr$mensal$RCC > 0), 1)))
  invisible(tab)
}
