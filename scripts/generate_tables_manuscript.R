#' -----------------------------------------------------------------------------
#' Generate tables we show in the manuscript
#'
#' @author Johann Hawe <johann.hawe@helmholtz-muenchen.de>
#'
#' @date Wed Nov 20 13:11:37 2019
#' -----------------------------------------------------------------------------

# ------------------------------------------------------------------------------
print("Load libraries and source scripts")
# ------------------------------------------------------------------------------
library(tidyverse)
library(igraph)
library(graph)
library(Rgraphviz)
library(BDgraph)
source("scripts/lib.R")

# ------------------------------------------------------------------------------
print("Table comparing our graphs to the ones reported in the meQTL study")
# ------------------------------------------------------------------------------
loci <- c("rs9859077", "rs7783715", "rs730775")

# get a graphNEL object from a dot file
parse_dot <- function(dot_file) {
  ag <- agread(dot_file)
  print(ag)
  enames <- Rgraphviz::edgeNames(ag)
  e1 <- unlist(lapply(strsplit(enames, "~"), "[[", 1))
  e2 <- unlist(lapply(strsplit(enames, "~"), "[[", 2))
  
  nodes <- unique(c(e1,e2))
  
  g <- graphNEL(nodes)
  g <- addEdge(e1,e2,g)
  g
}

# load our graphs
g1 <- sapply(loci, function(l) {
  readRDS(paste0("results/current/biogrid_stringent/graph_plots_tfa/_rerun/",
                   l,
                   "_meqtl/glasso_combined.rds"))
})

# load the ones from the meQTL paper
g2 <- sapply(loci, function(l) {
  parse_dot(paste0("../meQTLs/results/current/rw_ggm_integration/",
                   l,
                   "/graph-final.dot"))
})

parse_edge_data <- function(graph) {
    chip_seq <- edgeData(graph, attr = "isChipSeq") %>% as_tibble()
    ppi <- edgeData(graph, attr = "isPPI") %>% as_tibble() 
    
    d <- data.frame(bind_rows(chip_seq, ppi) %>% t())
    edges <- rownames(d)
    colnames(d) <- c("isChipSeq", "isPPI")
    d <- d %>%
      as_tibble() %>%
      mutate(edge = edges) %>%
      dplyr::select(edge, everything())
    
    d <- mutate(d,
                isGeneGene = !grepl("^rs|\\|rs|^cg|\\|cg", edge, ignore.case = FALSE))
    
    d <- dplyr::filter(d, isChipSeq | isPPI | isGeneGene)
    
    return(d)
}

# compare graphs
tab <- lapply(loci, function(l) {
  g2m <- as(g2[[l]], "matrix")
  g1m <- as(g1[[l]], "matrix")
  
  # NOTE: edges will occur twice(!) (once for each possible 'direction') when
  # using graph::edgeData(). So we devide by 2 to get proper counts
  
  edge_data <- parse_edge_data(g1[[l]])
  total_chip <- filter(edge_data, isChipSeq) %>% tally() %>% pull(n) / 2
  total_ppi <- filter(edge_data, isPPI) %>% tally() %>% pull(n) / 2
  total_gg <- filter(edge_data, isGeneGene) %>% tally() %>% pull(n) / 2
  
  edge_names_g1 <- names(edgeData(g1[[l]]))
  edge_names_g2 <- names(edgeData(g2[[l]]))
  
  edge_overlap <- intersect(edge_names_g1, edge_names_g2)
  total_overlap <- length(edge_overlap) / 2
  
  edge_overlap_chip <- edge_overlap[edge_overlap %in% 
                                      (dplyr::filter(edge_data, isChipSeq) %>% pull(edge))]
  total_edge_overlap_chip <- length(edge_overlap_chip) / 2
  
  edge_overlap_ppi <- edge_overlap[edge_overlap %in% 
                                      (dplyr::filter(edge_data, isPPI) %>% pull(edge))]
  total_edge_overlap_ppi <- length(edge_overlap_ppi) / 2
  
  edge_overlap_gg <- edge_overlap[edge_overlap %in% 
                                     (dplyr::filter(edge_data, isGeneGene) %>% pull(edge))]
  total_edge_overlap_gg <- length(edge_overlap_gg) / 2
  
  fraction_overlap_chip <- total_edge_overlap_chip / total_overlap
  fraction_overlap_ppi <- total_edge_overlap_ppi / total_overlap
  fraction_overlap_gg <- total_edge_overlap_gg / total_overlap
  
  nodes_g2 <- colnames(g2m)
  nodes_g1 <- colnames(g1m)
  total_edges_g2 <- graph::numEdges(g2[[l]])
  total_edges_g1 <- graph::numEdges(g1[[l]])
  total_nodes_g1_in_g2 <- sum(nodes_g1 %in% nodes_g2)
  total_nodes_g2_in_g1 <- sum(nodes_g2 %in% nodes_g1)
  node_intersection <- intersect(nodes_g2, nodes_g1)
  
  g2m <- g2m[node_intersection, node_intersection]
  g1m <- g1m[node_intersection, node_intersection]
  
  # gets MCC and edge overlap (as true positives)
  comp <- BDgraph::compare(g2m, g1m)
  
  # selected SNP gene in referene
  snp_genes_in_ref <- unlist(adj(g2[[l]], l))
  snp_genes_in_est <- unlist(adj(g1[[l]], l))
  snp_genes_recovered <- intersect(snp_genes_in_ref, snp_genes_in_est)
  
  # return some stats
  rbind(c(locus=l,
    nodes_in_reference=length(nodes_g2),
    nodes_in_estimate=length(nodes_g1),
    edges_in_reference=total_edges_g2,
    edges_in_estimate=total_edges_g1,
    node_overlap=total_nodes_g2_in_g1,
    edge_overlap=comp["true positive", "estimate1"],
    snp_genes_reference=length(snp_genes_in_ref),
    snp_genes_estimate=length(snp_genes_in_est),
    snp_genes_recovered=length(snp_genes_recovered),
    total_chip = total_chip,
    total_ppi = total_ppi,
    total_gg = total_gg,
    total_edge_overlap_chip = total_edge_overlap_chip,
    total_edge_overlap_ppi = total_edge_overlap_ppi,
    total_edge_overlap_gg = total_edge_overlap_gg,
    fraction_overlap_chip = fraction_overlap_chip,
    fraction_overlap_ppi = fraction_overlap_ppi,
    fraction_overlap_gg = fraction_overlap_gg,
    MCC=comp["MCC", "estimate1"])) %>%
    as_tibble() %>%
    mutate(
      nodes = paste0(nodes_in_estimate, " (", nodes_in_reference, ")"),
      edges = paste0(edges_in_estimate, " (", edges_in_reference, ")"),
      common_edges = edge_overlap,
      overlap_chip = paste0(total_edge_overlap_chip, " (", round(as.numeric(fraction_overlap_chip) * 100, 2), "%)"),
      overlap_ppi = paste0(total_edge_overlap_ppi, " (", round(as.numeric(fraction_overlap_ppi) * 100, 2), "%)"),
      overlap_gg = paste0(total_edge_overlap_gg, " (", round(as.numeric(fraction_overlap_gg) * 100, 2), "%)")
    )
}) %>% bind_rows()

tab %>%
  dplyr::select(locus, nodes, edges, overlap_edges = common_edges, 
         total_chip, overlap_chip, 
         total_ppi, overlap_ppi,
         total_gg, overlap_gg, 
         MCC) %>%
  xtable::xtable(
    label = "stab:network_comparison",
    align = c("l", rep("|c", 11)),
    caption = "Comparison of the networks inferred in this study to the networks extracted from \\citep{HaweMEQTL2020}. Numbers in brackets indicate statistics for the networks from the original publication.")

# ------------------------------------------------------------------------------
# Generate the supplementary tables
# ------------------------------------------------------------------------------
RESULT_PATH <- "results/current/biogrid_stringent/"

# generate the supplementary performance tables
finput <- paste0(RESULT_PATH, "simulation_rerun/validation-subsetall.txt")

# create data-matrix
print("Reading simulation validation results...")
tab <- read_tsv(finput) %>%
  mutate(R = paste0("R=", rdegree)) %>%
  mutate(comparison = gsub("bdgraph$", "bdgraph (priors)", comparison),
         comparison = gsub("glasso$", "glasso (priors)", comparison),
         comparison = gsub("bdgraph_no_priors$", "bdgraph (empty)", comparison),
         comparison = gsub("bdgraph_no_priors_full$", "bdgraph (full)", comparison),
         comparison = gsub("glasso_no_priors","glasso", comparison)) %>%
  dplyr::rename(method=comparison)

# MCC table
tab %>% 
  #filter(subset == "all") %>% 
  group_by(method, R) %>% 
  summarise(n=mean(MCC)) %>% 
  spread(R, n) %>% 
  arrange(desc(`R=0`)) %>%
  xtable(caption="Table showing an overview over the performance (mean MCC) in the simulation study for each method for all prior noise scenarios, sorted by first column. Highest mean MCC for each scenario is indicated in bold.", 
         label="stab:method_performance_simulation_mcc")

# F1 score table
tab %>% 
  #filter(subset == "all") %>% 
  group_by(method, R) %>% 
  summarise(n=mean(`F1-score`)) %>% 
  spread(R, n) %>% 
  arrange(desc(`R=0`)) %>%
  xtable(caption="Same as ST~\\ref{stab:method_performance_simulation_mcc}, but showing mean F1 scores instead of MCC. Highest mean F1 for each scenario is indicated in bold.",
         label="stab:method_performance_simulation_f1")

# Sensitivity table
tab %>% 
  #filter(subset == "all") %>% 
  group_by(method, R) %>% 
  summarise(n=mean(`sensitivity`)) %>% 
  spread(R, n) %>% 
  arrange(desc(`R=0`)) %>%
  xtable(caption="Same as ST~\\ref{stab:method_performance_simulation_mcc}, but showing mean sensitivity instead of MCC. Highest mean sensitivity for each scenario is indicated in bold.",
         label="stab:method_performance_simulation_sens")

# Specificity table
tab %>% 
  #filter(subset == "all") %>% 
  group_by(method, R) %>% 
  summarise(n=mean(`specificity`)) %>% 
  spread(R, n) %>% 
  arrange(desc(`R=0`)) %>%
  xtable(caption="Same as ST~\\ref{stab:method_performance_simulation_mcc}, but showing mean specificity scores instead of MCC. Highest mean specificity for each scenario is indicated in bold.",
         label="stab:method_performance_simulation_spec")

# also create tables for the sample size simulation
finput <- file.path(RESULT_PATH, "simulation_rerun/validation-subsets.tsv")

tab <- read_tsv(finput) %>% 
  mutate(comparison = gsub("bdgraph$", "bdgraph (priors)", comparison),
         comparison = gsub("glasso$", "glasso (priors)", comparison),
         comparison = gsub("bdgraph_no_priors$", "bdgraph (empty)", comparison),
         comparison = gsub("bdgraph_no_priors_full$", "bdgraph (full)", comparison),
         comparison = gsub("glasso_no_priors","glasso", comparison)) %>%
  dplyr::rename(method=comparison) %>%
  mutate(subset = factor(subset, level=c(seq(50,600,by=50)), ordered = T))

# MCC
tab %>% 
  group_by(method, subset) %>% 
  summarise(n=mean(MCC)) %>% 
  spread(subset, n, sep=" ") %>% 
  arrange(desc(`subset 50`)) %>%
  xtable(caption="Table showing an overview over the performance (mean MCC) in the simulation study for each method for different sub samplings of simulated data (increasing from left to right), sorted by first column. Highest mean MCC for each scenario is indicated in bold.", 
         label="stab:method_performance_simulation_subsample_mcc")

# F1
tab %>% 
  group_by(method, subset) %>% 
  summarise(n=mean(`F1-score`)) %>% 
  spread(subset, n, sep=" ") %>% 
  arrange(desc(`subset 50`)) %>%
  xtable(caption="Table showing an overview over the performance (mean F1) in the simulation study for each method for different sub samplings of simulated data (increasing from left to right), sorted by first column. Highest mean F1 for each scenario is indicated in bold.", 
         label="stab:method_performance_simulation_subsample_f1")

# Sensitivity table
tab %>% 
  group_by(method, subset) %>% 
  summarise(n=mean(`sensitivity`)) %>% 
  spread(subset, n, sep=" ") %>% 
  arrange(desc(`subset 50`)) %>%
  xtable(caption="Table showing an overview over the performance (mean sensitivity) in the simulation study for each method for different sub samplings of simulated data (increasing from left to right), sorted by first column. Highest mean sensitivity for each scenario is indicated in bold.", 
         label="stab:method_performance_simulation_subsample_sens")

# Specificity table
tab %>% 
  group_by(method, subset) %>% 
  summarise(n=mean(`specificity`)) %>% 
  spread(subset, n, sep=" ") %>% 
  arrange(desc(`subset 50`)) %>%
  xtable(caption="Table showing an overview over the performance (mean specificity) in the simulation study for each method for different sub samplings of simulated data (increasing from left to right), sorted by first column. Highest mean specificity for each scenario is indicated in bold.", 
         label="stab:method_performance_simulation_subsample_spec")

# ------------------------------------------------------------------------------
# Overview table on cohort results
# TODO adjust to use "rerun" results
# ------------------------------------------------------------------------------
# read the validation results for meqtls and eqtls and combine them
meqtl_expr <- read_tsv(paste0(RESULT_PATH, "validation_expr/_rerun/validation_all_meqtl.txt"))
meqtl_tfa <- read_tsv(paste0(RESULT_PATH, "validation_tfa/_rerun/validation_all_meqtl.txt"))
meqtl <- bind_rows(meqtl_expr,meqtl_tfa) %>%
  mutate(type=c(rep("Expression", nrow(meqtl_expr)), rep("TF activities", nrow(meqtl_tfa))),
         qtl_type="meQTL")

eqtl_expr <- read_tsv(paste0(RESULT_PATH, "validation_expr/_rerun/validation_all_eqtlgen.txt"))
eqtl_tfa <- read_tsv(paste0(RESULT_PATH, "validation_tfa/_rerun/validation_all_eqtlgen.txt"))
eqtl <- bind_rows(eqtl_expr,eqtl_tfa) %>%
  mutate(type=c(rep("Expression", nrow(eqtl_expr)), rep("TF activities", nrow(eqtl_tfa))),
         qtl_type="eQTL")

data <- bind_rows(meqtl, eqtl)

data <- data %>% 
  mutate(graph_type = gsub("bdgraph$", "bdgraph (priors)", graph_type),
         graph_type = gsub("glasso$", "glasso (priors)", graph_type),
         graph_type = gsub("bdgraph_no_priors$", "bdgraph (empty)", graph_type),
         graph_type = gsub("bdgraph_no_priors_full$", "bdgraph (full)", graph_type),
         graph_type = gsub("glasso_no_priors","glasso", graph_type)) %>%
  dplyr::select(graph_type, type, graph_score, cross_cohort_mcc)

data %>% 
  #filter(subset == "all") %>% 
  dplyr::rename(method=graph_type) %>%
  group_by(method, type) %>% 
  summarise(n=mean(cross_cohort_mcc), sd=sd(cross_cohort_mcc)) %>% 
  pivot_wider(names_from = type, values_from = c(n,sd)) %>% 
  arrange(desc(`n_TF activities`)) %>%
  mutate(n_Expression = paste0(round(n_Expression, digits=2), " (", round(sd_Expression, digits=2), ")")) %>%
  mutate(`n_TF activities` = paste0(round(`n_TF activities`, digits=2), " (", round(`sd_TF activities`, digits=2), ")")) %>%
  dplyr::select(method, Expression = n_Expression, `TF activities` = `n_TF activities`) %>%
  xtable(caption="Table shows the mean cross cohort replication MCC for expression and TF activity based analyses for each method and standard deviations in parentheses. Highest mean MCC per method is indicated in bold.",
         label="stab:method_performance_cross_cohort_mcc")

# the supplementary table containing the validation results; add GWAS info
gwas <- read_tsv("data/current/gwas/gwas_catalog_v1.0.2-associations_e96_r2019-07-12.tsv", 
                 col_types = cols(.default="c")) %>%
  as_tibble(.name_repair="universal") %>%
  separate_rows(SNPS)
snps <- unique(data$sentinel)

# get gwas traits for all SNPs
traits_per_snp <- mclapply(snps, function(s) {
  return(get_gwas_traits(s, gwas))
}, mc.cores=6)
names(traits_per_snp) <- snps

data$gwas_disease_trait <- NA
data$gwas_disease_trait <- unlist(traits_per_snp[match(data$sentinel,
                                                      names(traits_per_snp))])

tab <- data %>%
  mutate(has_gwas_hit = !is.na(gwas_disease_trait)) %>%
  dplyr::select(sentinel, cohort, seed=qtl_type, graph_type, number_nodes, 
                number_edges, has_gwas_hit, 
                graph_score, cross_cohort_mcc, data_type = type)
  
# ------------------------------------------------------------------------------
# Generate the ST with info on all graphs
# ------------------------------------------------------------------------------
meqtl_hotspots <- read_tsv("results/current/hotspots/meqtl_thres5/hotspots.tsv")
eqtl_hotspots <- read_tsv("results/current/hotspots/eqtlgen_thres5/hotspots.tsv")

# save a version for the Supp Table
write_tsv(meqtl_hotspots %>% dplyr::select(snp = sentinel.snp,
                                           snp.chr = chr.snp,
                                           snp.pos = pos.snp,
                                           A1, A2,
                                           cpg,
                                           cpg.chr = chr.cpg,
                                           cpg.pos = pos.cpg,
                                           ntrans), 
          "results/current/supplement/meqtl_hotspots.tsv")
write_tsv(eqtl_hotspots %>% dplyr::select(snp = sentinel,
                                          snp.chr = SNPChr,
                                          snp.pos = SNPPos,
                                          A1 = AssessedAllele, 
                                          A2 = OtherAllele,
                                          gene = Gene,
                                          gene.symbol = GeneSymbol,
                                          gene.chr = GeneChr,
                                          gene.pos = GenePos,
                                          ntrans), 
          "results/current/supplement/eqtl_hotspots.tsv")
meqtl_sentinels <- pull(meqtl_hotspots, sentinel.snp) %>% unique
eqtl_sentinels <- pull(eqtl_hotspots, sentinel) %>% unique

# generate table for bdgraph and glasso results
gtypes <- c("glasso", "bdgraph")

tab <- lapply(meqtl_sentinels, function(s) {
  print(s)
  
  if(!file.exists(paste0("results/current/biogrid_stringent/fits_tfa/_rerun/kora/",
                         s, "_meqtl.rds"))) {
    warning(paste0("Results for sentinel ", s, " do not exist."))
    return(NULL)
  }
  fits_kora <- readRDS(paste0("results/current/biogrid_stringent/fits_tfa/_rerun/kora/",
                              s, "_meqtl.rds"))
                       
  fits_lolipop <- readRDS(paste0("results/current/biogrid_stringent/fits_tfa/_rerun/lolipop/",
                                 s, "_meqtl.rds"))
  
  lapply(gtypes, function(gt) {
    gk <- fits_kora[[gt]]
    gl <- fits_lolipop[[gt]]
    
    gc <- combine_graphs(gk,gl)
    
    graph2table(gc) %>% mutate(graph_type = gt)
    
  }) %>% bind_rows() %>% mutate(sentinel = s)
}) %>% bind_rows() %>% mutate(seed = "meQTL")

tab2 <- lapply(eqtl_sentinels, function(s) {
  
  if(!file.exists(paste0("results/current/biogrid_stringent/fits_tfa/_rerun/kora/",
                         s, "_eqtlgen.rds"))) {
    warning(paste0("Results for sentinel ", s, " do not exist."))
    return(NULL)
  }
  
  fits_kora <- readRDS(paste0("results/current/biogrid_stringent/fits_tfa/_rerun/kora/",
                              s, "_eqtlgen.rds"))
  
  fits_lolipop <- readRDS(paste0("results/current/biogrid_stringent/fits_tfa/_rerun/lolipop/",
                                 s, "_eqtlgen.rds"))
  
  lapply(gtypes, function(gt) {
    gk <- fits_kora[[gt]]
    gl <- fits_lolipop[[gt]]
    
    gc <- combine_graphs(gk,gl)
    
    graph2table(gc) %>% mutate(graph_type = gt)
    
  }) %>% bind_rows() %>% mutate(sentinel = s)
}) %>% bind_rows() %>% mutate(seed = "eQTL")

data <- bind_rows(tab,tab2) %>% 
  dplyr::select(sentinel, seed, graph_type, everything())

write_tsv(path="results/current/revisions/supplement/all_graphs.tsv", data)

# ----------------------------------------------------------------------------
print("SessionInfo:")
# ------------------------------------------------------------------------------
sessionInfo()
