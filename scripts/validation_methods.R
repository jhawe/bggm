#' Library script providing the main functions for validating a ggm.fit based
#' on the identified links between entities
#'
#' @author Johann Hawe
#'
#' @version 20170803
#'


#' Validates the given ggm fit based on the found SNP~Gene links
#'
#' @param graph The graph extracted from the ggm fit
#' @param data The original data with which the ggm was fitted
#' @param ranges The original list of granges related to the entities in the
#' fitted data matrix
#'
#' @return
#'
#' @author Johann Hawe
#'
validate.snps <- function(graph, data, ranges){

}

#' Validates the given ggm fit based on the found CpG~Gene links
#'
#' @param ggm.fit The ggm.fit which is to be validated
#' @param ranges The original list of granges related to the entities in the
#' fitted data matrix
#'
#' @return
#'
#' @author Johann Hawe
#'
validate.cpgs <- function(ggm.fit, ranges){
  # (1) Epigenetic annotation chromHMM
  # (2) trans-eQTL in other dataset (Cpg~Gene)
  # (3) CpG in TFBS in independent CLs
}

#' Validates cpg genes based on a set of eqtm-genes
#'
#' Rather naive approach for validating our identified cpg genes.
#' Checks which of the selected and not selected cpg genes were identified
#' as having an eQTM (given by a list of eqtm.genes) and creates from this
#' a confusion table. In the end the fisher.test pvalue of this table is
#' reported
#'
#' @param eqtm.genes A list of eqtm genes which should be checked against
#' @param cg The list of cpg-genes in our network
#' @param cg.selected The list of cpg-genes in out network selected by the
#' GGM
#'
#' @author Johann Hawe
#'
#' @return The fisher.test()-pvalue for the calculated confusion table
#'
validate_cpggenes <- function(eqtm.genes, cg, cg.selected){

  # create the individual values for our confusion matrix
  v1 <- sum(setdiff(cg, cg.selected) %in% eqtm.genes)
  v2 <- sum(!setdiff(cg, cg.selected) %in% eqtm.genes)
  v3 <- sum(cg.selected %in% eqtm.genes)
  v4 <- sum(!cg.selected %in% eqtm.genes)

  # build the confusion matrix

  print("Confusion matrix for cpg-genes:")
  cont <- matrix(0, nrow=2, ncol=2)
  cont[1,1] <- v3
  cont[1,2] <- v1
  cont[2,1] <- v4
  cont[2,2] <- v2

  rownames(cont) <- c("has_eQTM", "has_no_eQTM")
  colnames(cont) <- c("ggm_selected", "not_gmm_selected")

  # report fisher test
  return(c(bonder_cis_eQTM=fisher.test(cont)$p.value))
}

#' Validates the given ggm fit based on the found Gene~Gene links
#'
#' @param expr.data A list containing expression datasets (matrices) which
#' should be checked against
#' @param g The GGM graph for which to check the genes
#' @param all.genes The list of genes intitially gone into the GGM analysis
#'
#' @author Johann Hawe
#'
#' @return For each of the expression datasets a single (fisher) pvalues for the
#' respective set
#'
validate_gene2gene <- function(expr.data, g, all.genes){

  require(BDgraph)

  # the complete set of nodes in the ggm graph
  gnodes <- nodes(g)

  # get adjacency matrices
  model_adj <- as(g, "matrix")

  # we create a adjacency matrix for each of the expression sets
  # TODO: for the external datasets, check whether we could normalize for age/sex
  results <- lapply(names(expr.data), function(ds) {
    # get the data set
    dset <- expr.data[[ds]]
    dset <- dset[,colnames(dset) %in% gnodes,drop=F]
    if(ncol(dset) < 2) {
      return(NA)
    }
    # create adj_matrix
    m <- matrix(nrow=ncol(dset), ncol=ncol(dset))
    rownames(m) <- colnames(m) <- colnames(dset)
    diag(m) <- 0

    # calculate correlations
    res <- c()
    cnames <- colnames(dset)
    for(i in 1:ncol(dset)) {
      for(j in i:ncol(dset)) {
      	if(j==i) next
        corr <- cor.test(dset[,i], dset[,j])
        res <- rbind(res, c(cnames[i], cnames[j], corr$p.value, corr$estimate))
      }
    }
    pvs <- as.data.frame(matrix(res, ncol=4, byrow = F), stringsAsFactors=F)
    colnames(pvs) <- c("n1", "n2", "pval", "cor")
    pvs$pval <- as.numeric(pvs$pval)
    pvs$cor <- as.numeric(pvs$cor)

    # get qvalue
    if(nrow(pvs)>10) {

      pvs <- cbind(pvs, qval=qvalue(pvs$pval,
  				  lambda=seq(min(pvs$pval), max(pvs$pval)))$qvalues)
    } else {
      pvs <- cbind(pvs, qval=p.adjust(pvs$pval, "BH"))
    }
    use <- pvs$qval<0.05 & abs(pvs$cor)>0.3
    # fill matrix
    for(i in 1:nrow(pvs)) {
     r <- pvs[i,,drop=F]
     if(use[i]) {
       m[r$n1, r$n2] <- m[r$n2, r$n1] <- 1
     } else {
       m[r$n1, r$n2] <- m[r$n2, r$n1] <- 0
     }
    }
    n <- intersect(colnames(m), colnames(model_adj))
    m <- m[n,n]
    model_adj <- model_adj[n,n]
    res <- BDgraph::compare(model_adj, m)
    res["MCC","estimate1"]
  })
  names(results) <- names(expr.data)
  # report MCC for each dataset
  return(unlist(results))
}

#' -----------------------------------------------------------------------------
#' Validate the genes in the GGM by performing a
#' GO enrichment on them
#'
#' @param genes Genes selected via the respective model for the network
#'
#' @author Johann Hawe
#'
#' @return A vector containing enriched GOIDs, terms, their pvalues and
#' qvalues or instead only containing NAs if no enrichments was found
#'
#' -----------------------------------------------------------------------------
validate_geneenrichment <- function(genes) {

  require(illuminaHumanv3.db)

  # define background set
  # for now all possible symbols from the array annotation
  # are used. We might want to think about only using those genes which were
  # initially collected for the respective locus
  annot <- illuminaHumanv3SYMBOLREANNOTATED
  bgset <- unique(unlist(as.list(annot)))

  if(length(genes)>2 & length(genes)<length(bgset)){
    go_tab <- go.enrichment(genes, bgset, gsc)
    go_tab <- go_tab[go_tab$q<0.01,,drop=F]
    if(nrow(go_tab)>0){
      r <- c(paste0(go_tab$GOID, collapse=","),
               paste0(go_tab$Term, collapse=","),
               paste0(go_tab$Pvalue, collapse=","),
               paste0(go_tab$q, collapse=","))
      return(r)
    }
  }
  r <- c(NA, NA, NA, NA)
  return(r)
}

#' Validates all trans genes (tfs and cpg-genes) by using a set of
#' previously identified trans eqtls
#'
#' @param teqtl The set of related trans eqtls
#' @param cgenes The CpG-genes to be checked
#' @param cgenes.selected THe CpG-genes selected in the GGM
#' @param tfs The TFs to be checked
#' @param tfs.selected The TFs selected in the GGM
#'
#' @author Johann Hawe
#'
#' @return Fisher pvalues for the two contingency table tests
#'
validate_trans_genes <- function(teqtl, trans_genes, tfs,
                                 trans_genes.selected, tfs.selected) {

  # analyze the cpggenes, total and selected
  teqtl.tgenes <- trans_genes[trans_genes %in%
                                unlist(strsplit(teqtl$Transcript_GeneSymbol, "\\|"))]
  teqtl.tgenes.selected <- intersect(teqtl.tgenes, trans_genes.selected)

  # analyze the tfs, total and selected
  teqtl.tfs <- tfs[tfs %in% unlist(strsplit(teqtl$Transcript_GeneSymbol, "\\|"))]
  teqtl.tfs.selected <- intersect(teqtl.tfs, tfs.selected)

  cat("Trans genes: ", trans_genes, "\n")
  cat("Trans genes with trans-eQTL: ", teqtl.tgenes, "\n")
  cat("selected CpG genes with trans-eQTL: ", teqtl.tgenes.selected, "\n")

  cat("TFs: ", tfs, "\n")
  cat("TFs with trans-eQTL: ", teqtl.tfs, "\n")
  cat("selected TFs with trans-eQTL: ", teqtl.tfs.selected, "\n")

  # create matrix for fisher test
  cont <- matrix(c(length(teqtl.tgenes),length(teqtl.tgenes.selected),
                   length(trans_genes),length(trans_genes.selected)),
                 nrow=2,ncol=2, byrow = T)
  cat("confusion matrix for trans genes:\n")
  rownames(cont) <- c("teqtl", "no teqtl")
  colnames(cont) <- c("not selected", "selected")
  f1 <- fisher.test(cont)$p.value

  # create matrix for fisher test
  cont <- matrix(c(length(teqtl.tfs),length(teqtl.tfs.selected),
                   length(tfs),length(tfs.selected)),
                 nrow=2,ncol=2, byrow = T)
  cat("confusion matrix for TFs:\n")
  rownames(cont) <- c("teqtl", "no teqtl")
  colnames(cont) <- c("not selected", "selected")
  f2 <- fisher.test(cont)$p.value

  # report fisher test results
  return(c(transEqtl_tgenes=f1,transEqtl_tfs=f2))
}

#' -----------------------------------------------------------------------------
#' Plot the Rho progression for an individual glasso model
#'
#' @param gl_model the glasso model containing the loglikelihood progression
#' as 'll_progression'
#' -----------------------------------------------------------------------------
plot_glasso_progression <- function(gl_model) {
  require(ggplot2)
  require(reshape2)

  toplot <- melt(gl_model$rho_progression)
  toplot$measure <- unlist(lapply(strsplit(as.character(toplot$X2), "_"), "[[", 1))
  toplot$rho <- unlist(lapply(strsplit(as.character(toplot$X2), "_"), "[[", 2))

  ggplot(toplot) +
    geom_boxplot(aes(x=rho, y=value), outlier.shape=NA) +
    facet_wrap(measure ~ ., nrow=3, scales="free_y") +
    scale_x_discrete(breaks=colnames(loglikes)[seq(1,length(rholist), by=10)]) +
    theme(axis.text.x = element_text(angle=-90, vjust=0.5)) +
    labs(title=paste0("Rho screening evaluation. (best rho=",
                      gl_model$rho_best,
                      ")"),
         y="value",
         x="rho")
}

#' -----------------------------------------------------------------------------
#' Plot the parameter progression for a genie3 fitted model
#'
#' @param model the GENIE3 model containing the loglikelihood progression
#' as 'logLiks' and the KS-pvalue progression as 'KS_ps' (both named by weights)
#'
#' -----------------------------------------------------------------------------
plot_genie_progression <- function(model) {

  require(ggplot2)
  require(reshape2)
  require(cowplot)

  toplot <- melt(model$fit$pl_fits, id.vars = "weight")
  ggplot(toplot, aes(x=weight, y=value)) +
    facet_wrap(~variable, ncol=2, scales="free_y") +
    geom_line() +
    geom_vline(xintercept = model$fit$best_weight, color="red")
}

# ------------------------------------------------------------------------------
#' Gets MCC and F1 between two graph objects (e.g. for comparing replication)
#'
#' @param comparison_graph The graph of interest which to compare to a
#' reference graph
#' @param reference_graph The reference graph to which to compare the graph of
#' interest
#'
#' @author Johann Hawe
#'
# ------------------------------------------------------------------------------
get_graph_replication_f1_mcc <- function(comparison_graph, reference_graph) {
  
  # get adjacency matrices
  g_comparison_adj <- as(comparison_graph, "matrix")
  g_reference_adj <- as(reference_graph, "matrix")
  
  # ensure that we have the same nodes only in all graphs.
  # this might somewhat change results, but otherwise we
  # cant compute the MCC properly.
  use <- intersect(colnames(g_comparison_adj), colnames(g_reference_adj))
  if (length(use) > 1) {
    g_comparison_adj <- g_comparison_adj[use, use]
    g_reference_adj <- g_reference_adj[use, use]
    
    # calculate performance using the DBgraph method compare()
    comp <- BDgraph::compare(g_comparison_adj, g_reference_adj)
    f1 <- comp["F1-score", "estimate1"]
    mcc <- comp["MCC", "estimate1"]
    
    return(list(MCC = mcc, F1 = f1, number_common_nodes = length(use)))
  } else {
    warning("No node overlap between graphs, can't get replication matrics.")
    return(NULL)
  }
}