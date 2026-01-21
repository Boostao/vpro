##Might need to install packages first with install.packages("packageName")##

library(vegan)
library(vegclust)
library(ggplot2)
library(reshape2)
library(labdsv)

setwd("E:/Kiri's Storage/Veg Classification")

vegData <- read.csv("BEC10forR.csv") ##Import Data and clean
vegData <- vegData[!(vegData$Lifeform %in% c(1,2)),]
vegData$Cover <- rowSums(vegData[,-c(1:3,8)], na.rm = TRUE)
vegData$Species <- unlist(lapply(vegData$Species, toupper))
vegSub <- vegData[grep("SBS mc 2",vegData$SiteUnit),] ##Choose which subzone to group
SU <- vegSub[,1:2]
vegSub <- vegSub[,-2]
SU <- unique(SU)
vegSub <- vegSub[,-c(3:7)]

###Fuzzy clustering
vegMat <- matrify(vegSub)
vegDat.chord <- decostand(vegMat, "normalize")
veg.nc <- vegclust(vegDat.chord, mobileCenters = 6, m = 1.5, dnoise = 1, method = "NC", nstart = 20)
fuzzyMat <- round(t(veg.nc$memb), digits = 2)
groups <- as.data.frame(defuzzify(veg.nc)$cluster)

##MDS - currently doesn't converge
MDS <- metaMDS(vegMat, distance = "bray", k = 2, trymax = 100, noshare = 0.1)
MDS.df <- as.data.frame(scores(MDS, display = "sites"))
MDS.df <- cbind(groups$`defuzzify(veg.nc)$cluster`, MDS.df)
colnames(MDS.df)[1] <- "Group"

###Plot nMDS grouped by noise clustering
pdf(file = "TestnMDS.pdf")
ggplot(MDS.df)+
  geom_point(mapping = aes(x = NMDS1, y = NMDS2, colour = Group), size = 2.5, shape = 17)+
  coord_fixed()+
  theme_bw()
dev.off()

##Print fuzzy clustering matrix
write.csv(fuzzyMat, file = "FuzzyMembership.csv")
