# ------------------------------------------------------------------------------
print("get snakemake params.")
# ------------------------------------------------------------------------------
fcosmo <- snakemake@input$cosmo
fout <- snakemake@output$snps

# ------------------------------------------------------------------------------
print("Loading data")
# ------------------------------------------------------------------------------
load(fcosmo)

# ------------------------------------------------------------------------------
print("Extracting SNPs.")
# ------------------------------------------------------------------------------
snps <-cbind(snp=as.character(unique(cosmo$snp)))

# ------------------------------------------------------------------------------
print("Finishing up.")
# ------------------------------------------------------------------------------
write.table(snps, file=fout, col.names=F, row.names=F, quote=F)

sessionInfo()
