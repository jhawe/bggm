#' -----------------------------------------------------------------------------
#' Extract eQTLgen hotspots from the eQTLgen trans eQTL file
#'
#' @author Johann Hawe <johann.hawe@helmholtz-muenchen.de>
#'
#' @date Fri Dec 21 21:40:48 2018
#' -----------------------------------------------------------------------------

# ------------------------------------------------------------------------------
print("Load libraries and source scripts")
# ------------------------------------------------------------------------------
suppressPackageStartupMessages(library(GenomicRanges))
suppressPackageStartupMessages(library(ggplot2))
library(data.table)
source("scripts/lib.R")

# ------------------------------------------------------------------------------
print("Get snakemake params")
# ------------------------------------------------------------------------------
# input
fmeqtl <- snakemake@input[[1]]
fkora_data <- snakemake@input$kora_data
flolipop_data <- snakemake@input$lolipop_data

# output
fout_plot <- snakemake@output$plot
dout_loci <- snakemake@output$loci_dir

# params
threads <- snakemake@threads

# minimum number of trans loci
hots_thres <- as.numeric(snakemake@wildcards$hots_thres)

# ------------------------------------------------------------------------------
print("Loading and processing data.")
# ------------------------------------------------------------------------------
load(fkora_data)
available_snps <- colnames(geno)
load(flolipop_data)
available_snps <- intersect(available_snps, colnames(geno))

rm(geno,expr,meth,covars)
gc()

meqtl <- fread(fmeqtl)

# check the number of trans sentinel cpg for each sentinel
trans_cpgs_by_snp <- tapply(meqtl$sentinel.cpg, meqtl$sentinel.snp, function(x){
  if(length(unique(x)) >= hots_thres) {
    return(unique(x))
  } else {
    return(NULL)
  }
})

# remove NULLs
trans_cpgs_by_snp <- trans_cpgs_by_snp[!unlist(lapply(trans_cpgs_by_snp,
                                                      is.null))]

# extract dataframe
hotspots <- cbind.data.frame(sentinel=names(trans_cpgs_by_snp),
                             ntrans=unlist(lapply(trans_cpgs_by_snp, length)),
                             stringsAsFactors=F)
hotspots <- hotspots[hotspots$sentinel %in% available_snps,,drop=F]

print("Total number of hotspots:")
print(nrow(hotspots))

# ------------------------------------------------------------------------------
print("Saving and plotting results.")
# ------------------------------------------------------------------------------
# create dummy files (more convenient for snakemake) for each sentinel
for(i in 1:nrow(hotspots)) {
  file.create(paste0(dout_loci, hotspots[i,"sentinel"], ".dmy"))
}

# plot a simple histogram for now
theme_set(theme_bw())

pdf(fout_plot)
ggplot(aes(x=ntrans), data=hotspots) + geom_histogram() +
  ggtitle(paste0("Overview on number of trans CpGs for ", nrow(hotspots), " hotspots.")) +
  xlab("number of trans associations")
dev.off()

# ------------------------------------------------------------------------------
print("SessionInfo:")
# ------------------------------------------------------------------------------
sessionInfo()