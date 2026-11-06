# -*- coding: utf-8 -*-
# ── Execução em paralelo ─────────────────────────────────────────────────────────────
# O kernel é caro (a formação própria testa ~74 mil pares). Os scripts NP dividem o
# trabalho entre processos do pacote `parallel` (vem com o R). Cada processo carrega as
# funções e, se pedido, a base de preços uma vez só.
iniciar_processos <- function(n, com_base = FALSE, funcoes = list()) {
  # funcoes: funções do script a disponibilizar nos processos, ex. list(ajustar_par = ajustar_par).
  # Toda função enviada aos processos tem o ambiente trocado pelo global: senão o R serializa
  # junto o ambiente do script — inclusive a base de preços inteira.
  if (n <= 1) return(NULL)
  cl <- parallel::makeCluster(n)
  prepara <- function(dir, com_base, funcoes) {
    setwd(dir)
    for (f in c("funcoes/comum.R", "funcoes/adf.R", "funcoes/paralelo.R", "nonparametric/kernel_np.R",
                "nonparametric/formacao_utils.R", "nonparametric/negociacao_utils.R",
                "nonparametric/especificacao_np.R"))
      source(f, encoding = "UTF-8")
    if (com_base) assign("base", carregar_base(), envir = globalenv())
    for (nome in names(funcoes)) assign(nome, funcoes[[nome]], envir = globalenv())
    NULL
  }
  environment(prepara) <- globalenv()
  funcoes <- lapply(funcoes, function(f) { environment(f) <- globalenv(); f })
  parallel::clusterCall(cl, prepara, getwd(), com_base, funcoes)
  cl
}

encerrar_processos <- function(cl) if (!is.null(cl)) parallel::stopCluster(cl)

aplicar <- function(cl, itens, f, ..., lote = NULL, rotulo = "itens") {
  # lapply (cl = NULL) ou parLapplyLB. Com `lote`, processa em blocos e imprime o progresso.
  # f roda nos processos com as funções carregadas por iniciar_processos (e `base`, se
  # com_base = TRUE); por isso o ambiente dela é trocado pelo global antes do envio.
  if (!is.null(cl)) environment(f) <- globalenv()
  roda <- function(x) if (is.null(cl)) lapply(x, f, ...) else parallel::parLapplyLB(cl, x, f, ...)
  if (is.null(lote)) return(roda(itens))
  out <- vector("list", length(itens)); t0 <- Sys.time()
  for (ini in seq(1, length(itens), by = lote)) {
    idx <- ini:min(ini + lote - 1, length(itens))
    out[idx] <- roda(itens[idx])
    cat(sprintf("  %5d / %d %s  (%4.0f s)\n", max(idx), length(itens), rotulo,
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    utils::flush.console()
  }
  out
}
