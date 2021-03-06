library(raster)
library(stringr)
library(glcm)
library(ff)
  library(dplyr)
library(randomForest)
  library(parallel)
    library(doParallel)

band.for.texture.appendage = "_ratio.nir"
window <- list(c(3,3), c(5,5), c(7,7))
statistics = list("homogeneity", "contrast", "correlation", "entropy")
shift = list(c(0,1),c(1,0),c(1,1),c(-1,1))
texture.params <- expand.grid(band.appendage = band.for.texture.appendage,window = window, statistics = statistics, shift = shift, stringsAsFactors = F)

save_each_band <- function(tile.path, band.names) {
    tile <- stack(tile.path)
    names(tile) <- band.names
    tile.name <- str_sub(basename(tile.path),1,-5)
    writeRaster(tile, filename = paste0(dirname(tile.path),"/",tile.name,"_",names(tile), ".tif"), bylayer = T, format = "GTiff", overwrite = T)
}

named.glcm <- function(tile.dir, tile.basename, band.appendage, window, statistics, shift, na_opt, na_val,...) {

    tile.path <- paste0(tile.dir, "/", tile.basename,band.appendage,".tif")
    x <- raster(tile.path)

    mnx <- NULL
    mxx <- NULL
    if(band.appendage == "_ratio.nir") {
        mnx <- 27
        mxx <-97
    }

    if (band.appendage == "_ratio.red") {
        mnx <- 27
        mxx <-97
    }


    if (statistics == "correlation") {
        texture <- glcm(x, window = window, statistics = statistics, shift = shift, na_opt = na_opt, na_val = na_val, min_x =mnx, max_x = mxx)
        texture[texture == -Inf] <- -1
        texture[texture == Inf] <- 1
        texture[is.na(texture)] <- 1
    } else {
        texture <- glcm(x, window = window, statistics = statistics, shift = shift, na_opt = na_opt, na_val = na_val, min_x = mnx, max_x =mxx)
    }
    win.size <- paste0("window.",window[1])
    shift.dir <- paste0("angle.",atan(shift[1]/shift[2])*180/pi) # calc shift angle

    tile.dir <- dirname(tile.path)
    tile.name <- str_sub(basename(tile.path),1,-5)
    fn = paste0(tile.dir,"/", tile.basename,band.appendage, "_stat.", statistics, "_", win.size,"_",shift.dir,".tif")
    writeRaster(texture, fn, overwrite = T)
    }

        calc.texture <- function(texture.params.df,
                                 tile.dir,
                                 tile.basename) {

            texture <- mapply(named.glcm,
                              tile.dir = tile.dir,
                              tile.basename = tile.basename,
                              band.appendage = texture.params.df$band.appendage,
                              window = texture.params.df$window,
                              statistics = texture.params.df$statistics,
                              shift = texture.params.df$shift,
                              na_opt = "ignore",
                              na_val = NA)
        }

calc_ratios <- function(tile.path, band.names, ratio.bands, scale200 = T) {
    tile <- stack(tile.path)
    names(tile) <- band.names

    ratios <- tile[[ratio.bands,drop = F]] / sum(tile)

    if (scale200 == T) {
        ratios <- ratios * 200
    }

    tile.name <- str_sub(basename(tile.path),1,-5)
    names(ratios) <- paste0(tile.name,"_ratio.",ratio.bands)
    writeRaster(ratios, filename= paste0(dirname(tile.path),"/",names(ratios),".tif"),
                bylayer = T, format= "GTiff", overwrite = T,
                datatype = 'INT1U')
}

calc_ndvi <- function(tile.path, band.names, ndvi_appendage = "_ndvi", scale200 = T) {

    tile <- stack(tile.path)
    names(tile) <- band.names

    ndvi <- (tile[["nir"]] - tile[["red"]]) /  (tile[["nir"]] + tile[["red"]])

    ndvi [ndvi < 0] <- 0

    if (scale200 == T) {
        ndvi <- ndvi * 200
    }

    tile.dir <- dirname(tile.path)
    tile.name <- str_sub(basename(tile.path),1,-5)
    writeRaster(ndvi, filename=paste0(tile.dir,"/",tile.name,ndvi_appendage,".tif"), bylayer=TRUE,format="GTiff", overwrite = T,datatype = 'INT1U')
    return(ndvi)
}

## raster.dir <- "../WholeState_DD/QualitativeAccuracy/NAIP"
## raster.name <- c("mad1_blue")
## fun <- c("mean")
## window.diameter <- c(1,2,4,8)
## feature.pattern = "_(blue|green|red|nir|ratio.blue|ratio.green|ratio.red|ratio.nir|ndvi|ratio.nir_stat\\.\\w+_window\\.3_angle\\..?\\d+|ratio.red_stat\\.\\w+_window\\.3_angle\\..?\\d+|ratio.nir_stat\\.\\w+_window\\.5_angle\\..?\\d+).tif$"

## feature.pattern = "_(ndvi).tif$"


## raster.name <- remove.tif.ext(list.files(raster.dir, feature.pattern))

## focal.param.df <- expand.grid(raster.dir = raster.dir,
##                               raster.name = raster.name,
##                               fun = fun,
##                               window.diameter = window.diameter,
##                               stringsAsFactors = F)


## make.focal.features(focal.param.df)

make.focal.features <- function(focal.param.df) {
    mapply(focal.name.and.writeRaster, focal.param.df$raster.dir, focal.param.df$raster.name, fun = focal.param.df$fun, window.diameter = focal.param.df$window.diameter)
}


circular.weight <- function(rs, d) {
        nx <- 1 + 2 * floor(d/rs[1])
        ny <- 1 + 2 * floor(d/rs[2])
        m <- matrix(ncol=nx, nrow=ny)
        m[ceiling(ny/2), ceiling(nx/2)] <- 1
        if (nx == 1 & ny == 1) {
                return(m)
        } else {
                x <- raster(m, xmn=0, xmx=nx*rs[1], ymn=0, ymx=ny*rs[2], crs="+proj=utm +zone=1 +datum=WGS84")
                d <- as.matrix(distance(x)) <= d
                d / sum(d)
        }
}


myfocalWeight <- function(x, d, type=c('circle', 'Gauss', 'rectangle')) {
        type <- match.arg(type)
        x <- res(x)
        x <- round(x)
        if (type == 'circle') {
                circular.weight(x, d[1])
        } else if (type == 'Gauss') {
                if (!length(d) %in% 1:2) {
                        stop("If type=Gauss, d should be a vector of length 1 or 2")
                }
                .Gauss.weight(x, d)
        } else {
                .rectangle.weight(x, d)
        }
}



focal.name.and.writeRaster <- function(raster.dir,raster.name, fun, window.diameter, window.shape = "circle") {
    raster.path <- str_c(raster.dir,"/",raster.name,".tif")
    r <- raster(raster.path)
    extent(r) <- round(extent(r),digits = 5)
    rs <- round(res(r))
    res(r) <- rs
    fw <- myfocalWeight(r, window.diameter, type = window.shape)
    if(fun == "min")    fw[fw==0] <- NA  # if fun is min and fw has 0's in it, the raster becomes 0's
    out <- focal(r, match.fun(fun), w = fw, na.rm = T, pad = T) * sum(fw != 0, na.rm = T)
    names(out) <- paste0(names(r), "_window",window.shape,"-",window.diameter,"_fun-",fun)
    writeRaster(out, file = str_c(raster.dir,"/",names(out),".tif"), overwrite = T, datatype = 'INT1U')
    return(out)
}

save.pixel.feature.df <- function(tile.dir,
                                  tile.name,
                                  feature.pattern,
                                  feature.df.append = feature.df.appendage ) {
    s <- stack(list.files(tile.dir, pattern = paste0(tile.name,feature.pattern), full.names = T))
    names(s) <- sub(x = names(s), pattern = paste0("(",tile.name,"_)"), replacement = "")
    s.df <- as.data.frame(s, xy = T)
    saveRDS(s.df, file = paste0(tile.dir, "/", tile.name, "_Pixel",feature.df.append, ".rds"))
}


## this function replaced with make.focal.features and then save.pixel.feature.df
##   save.pixel.feature.wWindows.df <- function(tile.dir,
##                                     tile.name,
##                                     feature.pattern,
##                                     feature.df.append = feature.df.appendage,
##                                     window.sizes = c(3,5,9),
##                                     sample.size = "none") {

##       s <- stack(list.files(tile.dir, pattern = paste0(tile.name,feature.pattern), full.names = T))

##       names(s) <- sub(x = names(s), pattern = paste0("(",tile.name,"_)"), replacement = "")

##      out <- lapply(s@layers, function(ras) {
##         lapply(window.sizes, function(w.s) {
##           mean <- focal(ras, fun = mean, w = matrix(1, nrow = w.s, ncol = w.s), na.rm = T, pad = T)
##           names(mean) <- paste0(names(ras),"_windowSize-",w.s,"_fun-mean")

##           max <- focal(ras, fun = max, w = matrix(1, nrow = w.s, ncol = w.s), na.rm = T, pad = T)
##           names(max) <- paste0(names(ras),"_windowSize-",w.s,"_fun-max")

##           min <- focal(ras, fun = min, w = matrix(1, nrow = w.s, ncol = w.s), na.rm = T, pad = T)
##           names(min) <- paste0(names(ras),"_windowSize-",w.s,"_fun-min")

## #          sd <- focal(ras, fun = sd, w = matrix(1, nrow = w.s, ncol = w.s), na.rm = T, pad = T)
## #         names(sd) <- paste0(names(ras),"_windowSize-",w.s,"_fun-sd")

##           out <- stack(mean, max, min, sd)
##         })
##       })

##       s.focal <- do.call("stack",unlist(out))
##       s <- stack(s,s.focal)
##       s.df <- as.data.frame(s, xy = T)

## if (sample.size != "none"){
##       s.df <- s.df[sample(1:nrow(s.df), size = max(c(sample.size,nrow(s.df)))),]
## }
##       saveRDS(s.df, file = paste0(tile.dir, "/", tile.name, "_Pixel",feature.df.append, ".rds"))
##   }

pca.transformation <- function(tile.dir,
                               image.name,
                               tile.name,
                               loc,
                               feature.pattern = "_(blue|green|red|nir|ratio.blue|ratio.green|ratio.red|ratio.nir|ndvi).tif",
                               pca.append = pca.appendage,
                               out.image.appendage = pca.appendage,
                               comps.to.use = c(1,2,3),
                               pca.dir = dd.pca.dir) {

    s <- stack(list.files(tile.dir, pattern = paste0(tile.name,feature.pattern), full.names = T))
    names(s) <- sub(x = names(s), pattern = ".*_", replacement = "")

    pca.model <- readRDS(str_c(pca.dir,"/",loc,image.name,pca.append,".rds"))

    r <- predict(s, pca.model, index = comps.to.use)

    min.r <- getRasterMin(r)
    max.r <- getRasterMax(r)
    rescaled.r <- rescale.0.254(r, min.r, max.r)

    out.path <- str_c(tile.dir, "/", tile.name, out.image.appendage, ".tif")
    writeRaster(rescaled.r, filename = out.path, overwrite=TRUE, datatype = 'INT1U', bylayer = F)
}


getRasterMin <- function(t) {
    return(min(cellStats(t, stat = "min")))
}

getRasterMax <- function(t) {
    return(max(cellStats(t, stat = "max")))
}

rescale.0.254 <- function(raster,
                          min,
                          max) {
                              (raster - min)/(max-min) * 254
}

rescale.0.b <- function(raster, b, each.band = T) {
    if (each.band == T) {
        min <- cellStats(raster, stat = "min")
        max <- cellStats(raster, stat = "max")
    } else {
        min <- getRasterMin(raster)
        max <- getRasterMax(raster)
    }
    (raster - min)/(max-min) * b
}


## image.pca <- function(image.name,
##                       pca.model.name.append = pca.model.name.appendage,
##                       tile.dir,
##                       tile.name,
##                       in.image.appendage = ratio.tile.name.append,
##                       out.image.appendage = pca.tile.name.append,
##                       band.names = c("blue","green","red","nir","b_ratio","g_ratio","r_ratio","n_ratio","ndvi"),
##                       comps.to.use = c(1,2,3),
##                       pca.dir = dd.pca.dir) {


##     out.path <- str_c(tile.dir, "/", tile.name, out.image.appendage, ".tif")

##     s <- stack(str_c(tile.dir, "/", tile.name, in.image.appendage,".tif"))
##     names(s) <- band.names

##     pca.model <- readRDS(str_c(pca.dir,"/",image.name,pca.model.name.append))

##     r <- predict(s, pca.model, index = comps.to.use)

##     min.r <- getRasterMin(r)
##     max.r <- getRasterMax(r)
##     rescaled.r <- rescale.0.255(r, min.r, max.r)
##     writeRaster(rescaled.r, filename = out.path, overwrite=TRUE, datatype = 'INT1U')
## }


make.and.save.pca.transformation <- function(image.dir,
                                             image.name,
                                             location,
                                             pca.append = pca.appendage,
                                             max.sample.size = 10000,
                                             core.num = cores,
                                             feature.pattern = ".*_(blue|green|red|nir|ratio.blue|ratio.green|ratio.red|ratio.nir|ndvi).tif",
                                             ratio.appendage = ratio.tile.name.append) {

    tile.paths <- list.files(image.dir, pattern = paste0(feature.pattern), full.names = T)

    tile.names <- str_match(tile.paths,"(.*\\.[0-9]+)_.*")[,2] %>%  unique() # get the image names of pca regions

    cl <- makeCluster(cores)
    registerDoParallel(cl)

    sr <- foreach (tile.name = tile.names, .packages = c("stringr","raster"), .combine ="rbind") %dopar% {
        t.names <- str_extract(tile.paths, paste0(".*",tile.name,".*")) %>% na.omit()
        tile <- stack(t.names)
        names(tile) <- sub(x = names(tile), pattern = ".*_", replacement = "")
        samp <- sampleRandom(tile, ifelse(ncell(tile) > max.sample.size ,max.sample.size, ncell(tile)))
        colnames(samp) <- names(tile)
        samp
    }
    closeAllConnections()

                                        # Perform PCA on sample
    pca <- prcomp(sr, scale = T)
    saveRDS(pca,paste0(image.dir,"/",location,image.name,pca.append,".rds"))
    return(pca)
}



make.and.save.pca.transformation.wholestate <- function(image.dir,
                                                        image.name,
                                                        location,
                                                        pca.append = pca.appendage,
                                                        max.sample.size = 10000,
                                                        core.num = cores,
                                                        feature.pattern = ".*_(blue|green|red|nir|ratio.blue|ratio.green|ratio.red|ratio.nir|ndvi).tif",
                                                        Recurs = F) {
                                        #                                               ratio.append = ratio.appendage) {

    tile.paths <- list.files(image.dir, pattern = feature.pattern, full.names = T, recursive = Recurs)

    tile.names <- str_match(tile.paths,"(.*)_.*")[,2] %>%  unique() # get the image names of pca regions

    cl <- makeCluster(cores)
    registerDoParallel(cl)

    sr <- foreach (tile.name = tile.names, .packages = c("stringr","raster"), .combine ="rbind") %dopar% {
        t.names <- str_extract(tile.paths, paste0(".*",tile.name,"_.*")) %>% na.omit()
        tile <- stack(t.names)
        names(tile) <- sub(x = names(tile), pattern = ".*_", replacement = "")
        samp <- sampleRandom(tile, ifelse(ncell(tile) > max.sample.size ,max.sample.size, ncell(tile)))
        colnames(samp) <- names(tile)
        samp
    }
    closeAllConnections()

                                        # Perform PCA on sample
    pca <- prcomp(sr, scale = T)
    saveRDS(pca,paste0(image.dir,"/",location,image.name,pca.append,".rds"))
    return(pca)
}


## make.and.save.pca.transformation <- function(image.dir,
##                                              image.name,
##                                              pca.model.name.append = "_pca.rds",
##                                              max.sample.size = 10000,
##                                              core.num = cores,
##                                              band.names = c("blue","green","red","nir","b_ratio","g_ratio","r_ratio","n_ratio","ndvi"),
##                                              ratio.appendage = ratio.tile.name.append) {
##     tile.paths <- list.files(str_c(image.dir), pattern = paste0("*",ratio.appendage), full.names = T)

##     tile.names <- basename(tile.paths)

##     cl <- makeCluster(core.num)
##     registerDoParallel(cl)

##     sr <- foreach (i = seq_along(tile.names), .packages = c("raster"), .combine ="rbind") %dopar% {
##         tile <- stack(tile.paths[i])
##         s <- sampleRandom(tile, ifelse(ncell(tile) > max.sample.size ,max.sample.size, ncell(tile)))
##     }

##     colnames(sr) <- band.names

##                                         # Perform PCA on sample
##     pca <- prcomp(sr, scale = T)
##     saveRDS(pca,paste0(image.dir,"/",image.name,pca.model.name.append))

##     return(pca)
## }


image.pca.forWholeState <- function(pca.model.name.append = pca.model.name.appendage,
                                    tile.dir,
                                    tile.name,
                                    in.image.appendage = ratio.tile.name.append,
                                    out.image.appendage = pca.tile.name.append,
                                    band.names = c("blue","green","red","nir","b_ratio","g_ratio","r_ratio","n_ratio","ndvi"),
                                    comps.to.use = c(1,2,3),
                                    pca.transform) {


    out.path <- str_c(tile.dir, "/", tile.name, out.image.appendage, ".tif")

    s <- stack(str_c(tile.dir, "/", tile.name, in.image.appendage,".tif"))
    names(s) <- band.names

    r <- predict(s, pca.transform, index = comps.to.use)

    min.r <- getRasterMin(r)
    max.r <- getRasterMax(r)
    rescaled.r <- rescale.0.254(r, min.r, max.r)
    writeRaster(rescaled.r, filename = out.path, overwrite=TRUE, datatype = 'INT1U')
}



## image.dir <- image.cropped.to.training.dir
## image.name <- 9
##                         in.image.appendage = ratio.tile.name.append
##                         out.image.appendage = pca.tile.name.append
##                         band.names = c("blue","green","red","nir","b_ratio","g_ratio","r_ratio","n_ratio","ndvi")
##                         max.sample.size = 10000
##                         comps.to.use = c(1,2,3)

##       out.path <- str_c(image.dir, "/", image.name, out.image.appendage, ".tif")

##       s <- stack(str_c(image.dir, "/", image.name, in.image.appendage,".tif"))
##       names(s) <- band.names

##       sr <- sampleRandom(s, ifelse(ncell(s) > max.sample.size, max.sample.size, ncell(s)))
##       pca <- prcomp(sr, scale = T)

##       r <- predict(s, pca, index = comps.to.use)

##       min.r <- getRasterMin(r)
##       max.r <- getRasterMax(r)
##       rescaled.r <- rescale.0.255(r, min.r, max.r)
##       writeRaster(rescaled.r, filename = out.path, overwrite=TRUE, datatype = 'INT1U')









                                        # Function takes raster stack, samples data, performs pca and returns stack of first n_pcomp bands
## predict_pca_wSampling_parallel <- function(stack, sampleNumber, n_pcomp, nCores = detectCores()-1) {
##     sr <- sampleRandom(stack,sampleNumber)
##     pca <- prcomp(sr, scale=T)
##     beginCluster()
##     r <- clusterR(stack, predict, args = list(pca, index = 1:n_pcomp))
##     endCluster()
##     return(r)
## }

segment.multiple <- function(tile.dir,
                             tile.name,
                             image.name,
                             segment.params.df,
                             krusty  = T) {
    segments <- mapply(segment,
                       tile.dir = tile.dir,
                       image.name = image.name,
                       tile.name = tile.name,
                       compactness = segment.params.df$compactness,
                       segment.size = segment.params.df$segment.size,
                       krusty = krusty)
}

segment  <- function(tile.dir,
                     image.name,
                     tile.name,
                     compactness,
                     segment.size,
                     krusty = T) {
    pixel_size <- ifelse(image.name == "NAIP", 1, 1.5)
    compactness <- if(image.name == "NAIP") compactness else round(2/3*compactness)
    if (krusty == T) {
        system(paste("/home/erker/.conda/envs/utc/bin/python","fia_segment_cmdArgs.py",pixel_size,segment.size,compactness,tile.name,tile.dir))
    } else {
        system(paste("python","fia_segment_cmdArgs.py",pixel_size,segment.size,compactness,tile.name,tile.dir))
    }
}

add.features <- function(tile.dir,
                         tile.name,
                         band.names,
                         ndvi = T,
                         ratio.bands,
                         texture = T,
                         texture.params.df) {

    til.path <- paste0(tile.dir,"/",tile.name,".tif")
    til <- stack(til.path)
    names(til) <- band.names

    save_each_band(tile.path = til.path,
                   band.names = band.names)

    if (ndvi == T) {
        calc_ndvi(tile.path = til.path,
                  band.names = band.names)
    }

    if (length(ratio.bands > 0)) {
        calc_ratios(tile.path = til.path,
                    band.names = band.names,
                    ratio.bands = ratio.bands)
    }

    if (texture == T) {
        calc.texture(texture.params.df = texture.params.df,
                     tile.dir = tile.dir,
                     tile.basename = tile.name)
    }
}

make.segment.feature.df.foreach.segmentation <- function(tile.dir,
                                                         tile.name,
                                                         feature.pattern,
                                                         segmentation.pattern = "_N-[0-9]+_C-[0-9]+.*") {

    segmentation.files <-  list.files(tile.dir, pattern = paste0(tile.name,segmentation.pattern))
    segmentation.param.appendages <- str_match(segmentation.files,paste0(tile.name,"(_.*).tif"))[,2] %>% na.omit()


    out <- lapply(X = segmentation.param.appendages, FUN = function(segmentation.param.appendage) {
        make.segment.feature.df(tile.dir = tile.dir,
                                tile.name = tile.name,
                                segmentation.param.appendage = segmentation.param.appendage,
                                fea.pattern = feature.pattern)
    })

}


make.segment.feature.df <- function(tile.dir,
                                    tile.name,
                                    segmentation.param.appendage,
                                    fea.pattern,
                                    feature.df.append = feature.df.appendage) {

    fea <- stack(list.files(tile.dir, pattern = paste0(tile.name,fea.pattern), full.names = T))
                                        #      names(fea) <- sub(x = names(fea), pattern = "(madisonNAIP|madisonPanshpSPOT|urbanExtent|wausauNAIP).*?_", replacement = "")
    names(fea) <- sub(x = names(fea), pattern = "(.*?)_", replacement = "")
    seg.path <- paste0(tile.dir,"/",tile.name,segmentation.param.appendage, ".tif")
    seg <- raster(seg.path)

                                        # Create a data_frame where mean and variances are calculated by zone
    x <- as.data.frame(fea, xy = T)
    s <- as.data.frame(seg)
    colnames(s) <- "segment"
    r <- bind_cols(x,s)
    r2 <- r %>%
        group_by(segment)

    mean.max.min.and.sd <- r2 %>%
        summarize_each(funs(mean(.,na.rm = T), sd(., na.rm = T), max(., na.rm = T), min(., na.rm = T))) %>%
        select(-x_mean, -x_sd, -y_mean, -y_sd, -x_max, -x_min, -y_max, -y_min)

    tile.name.df = data.frame(tile.name = rep(tile.name, nrow(mean.max.min.and.sd)))

    out <- bind_cols(mean.max.min.and.sd, tile.name.df)


    names <- colnames(out)
    names <- str_replace(names, "\\(",".")
    names <- str_replace(names, "\\)",".")
    names <- str_replace(names, "\\:",".")
    colnames(out) <- names
    saveRDS(out, file = paste0(tile.dir,"/",tile.name,segmentation.param.appendage,feature.df.append,".rds"))
    out
}



                                        #  make.segment.feature.df(dd.training.dir, "madisonNAIP.1", segmentation.param.appendage = "_N-100_C-10", feature.pattern = feature.pattern)

make.feature.df <- function(tile.dir,
                            image.name,
                            tile.name,
                            band.names,
                            ndvi = T,
                            ratio.bands,
                            texture = T,
                            texture.params.df,
                            feature.pattern = "_(blue.*|green.*|red.*|nir.*|ratio.blue.*|ratio.green.*|ratio.red.*|ratio.nir.*|ndvi.*|ratio.red_stat\\.\\w+_window\\.\\d+_angle\\..?\\d+|ratio.nir_stat\\.\\w+_window\\.\\d+_angle\\..?\\d+).tif",
                            focal.features = T,
                            focal.params.df,
                            pixel.df,
                                        #                              pca.features = c("blue","green","red","nir","ndvi","ratio.blue","ratio.green","ratio.red","ratio.nir"),
                            pca.features = c("red","green","blue","nir"),
                            pca.location,
                            pca.directory = dd.pca.dir,
                            segmentation = T,
                            segment.params.df,
                            using.krusty = T) {

    add.features(tile.dir,
                 tile.name,
                 band.names,
                 ndvi = T,
                 ratio.bands,
                 texture = T,
                 texture.params.df)

    if (focal.features == T) {
        make.focal.features(focal.params.df)
    }


    message ( tile.name,"features added")

    if (pixel.df ==T) {

        save.pixel.feature.df(tile.dir = tile.dir,
                              tile.name = tile.name,
                              feature.pattern)}

    message("pixel feature df saved")

    if (segmentation == T) {

        pca.transformation(tile.dir = tile.dir,
                           tile.name = tile.name,
                           image.name = image.name,
                           loc = pca.location,
                           pca.dir = pca.directory)

        message("pca done")

        segment.multiple(tile.dir = tile.dir,
                         tile.name = tile.name,
                         image.name = image.name,
                         segment.params.df = segment.params.df,
                         krusty = using.krusty)

        message("segmentation done")

        make.segment.feature.df.foreach.segmentation(tile.dir = tile.dir,
                                                     tile.name = tile.name,
                                                     feature.pattern = feature.pattern)}



}

remove.tif.ext <- function(x) {
    str_match(x, "(.*).tif")[,2]
}

r <- stack("data/image/m_4409047_ne_15_1_20130701.tif")

s <- shapefile("data/training/Sandhill_training_data_new.shp")
s <- spTransform(s, proj4string(r))

rc <- crop(r, extent(s))
writeRaster(rc, "data/image/train/m_4409047_ne_15_1_20130701_train.tif", overwrite = T)

plotRGB(rc, 1,2,3)
plot(s, add = T)

add.features(tile.dir = "data/image/train/",
             tile.name = "m_4409047_ne_15_1_20130701_train",
             band.names = c("red","green","blue","nir"),
             ratio.bands = c("red","green","blue","nir"),
             texture = F,
             texture.params.df = texture.params)

library(parallel)
  library(doParallel)
cores <- detectCores() - 1

  cl <- makeCluster(cores)
  registerDoParallel(cl)

  focal.feature.pattern = "_(blue|green|red|nir|ratio.blue|ratio.green|ratio.red|ratio.nir|ndvi).tif$"
  focal.fun <- c("mean","max","min")
  focal.window.diameter <- c(1,2,4,8,11)

  tile.names <- remove.tif.ext(list.files("data/image/train", focal.feature.pattern))

  focal.param.df <- expand.grid(raster.dir = "data/image/train/",
                                raster.name = tile.names,
                                fun = focal.fun,
                                window.diameter = focal.window.diameter,
                                stringsAsFactors = F)

      features <- foreach (i = 1:nrow(focal.param.df),
                           .packages = c("raster","stringr")) %dopar% {
                               make.focal.features(focal.param.df[i,])
                           }

train.stack <- stack(list.files("data/image/train", full.names = T, pattern = ".*train_.*.tif$"))

snag <- raster("data/training/snags.png")
other <- raster("data/training/other.png")
livetree <- raster("data/training/livetree.png")
liveveg <- raster("data/training/liveveg.png")

snag.cells <- which(getValues(snag == 255))
  snag.df <- data.frame(cell = snag.cells, Class = "snag")

  liveveg.cells <- sample(which(getValues(liveveg == 255)),20000)
  liveveg.df <- data.frame(cell = liveveg.cells, Class = "liveveg")

  livetree.cells <- sample(which(getValues(livetree == 255)),20000)
  livetree.df <- data.frame(cell = livetree.cells, Class = "livetree")

  other.cells <- sample(which(getValues(other == 255)),17000)
  other.df <- data.frame(cell = other.cells, Class = "other")

ext_ID <- do.call("bind", list(snag.df, liveveg.df, livetree.df, other.df))

mat <- ff(vmode="integer",dim=c(ncell(train.stack),nlayers(train.stack)),filename="data/image/train/trainstack.ffdata")

for(i in 1:nlayers(train.stack)){
    mat[,i] <- train.stack[[i]][]
}

save(mat,file="data/image/train/train_stack_mat.RData")

extracted.values <- mat[ext_ID$cell,]

df <- data.frame(extracted.values)
colnames(df) <- paste0("X",str_match(names(train.stack), "train(.*)")[,2])

df$Class <- factor(ext_ID$Class)

saveRDS(df, "data/training/model_building_df.rds")

df <- readRDS("data/training/model_building_df.rds")

df <- df[,!grepl(".*stat.*",colnames(df))]

df <- df %>% na.omit()

mod_all <- randomForest(y = factor(df$Class), x= df[,1:(dim(df)[2]-1)])

top <- arrange(data.frame(importance(mod_all), name = row.names(importance(mod_all))), -MeanDecreaseGini) %>% head(60)
top

mod <- randomForest(y = factor(df$Class), x= df[,c(as.character(top$name), "X_ratio.red","X_blue", "X_red")])

names(train.stack.int) <- paste0("X",str_match(names(train.stack.int), "train(.*)")[,2])
pred.r <- raster::predict(train.stack.int, mod)

writeRaster(pred.r, "data/image/prediction/prediction.tif",overwrite = T)

plot(pred.r)

plot(s)
e2 <- drawExtent()

dput(e2)

r.test <- crop(r, e2)

plotRGB(r.test,1,2,3)

writeRaster(r.test, "data/image/test/test.tif")

add.features(tile.dir = "data/image/test/",
             tile.name = "test",
             band.names = c("red","green","blue","nir"),
             ratio.bands = c("red","green","blue","nir"),
             texture = T,
             texture.params.df = texture.params)

cores <- detectCores() - 1

  cl <- makeCluster(cores)
  registerDoParallel(cl)

  focal.feature.pattern = "_(blue|green|red|nir|ratio.blue|ratio.green|ratio.red|ratio.nir|ndvi).tif$"
  focal.fun <- c("mean","max","min")
  focal.window.diameter <- c(1,2,4,8,11)

  tile.names <- remove.tif.ext(list.files("data/image/test", focal.feature.pattern))

  focal.param.df <- expand.grid(raster.dir = "data/image/test/",
                                raster.name = tile.names,
                                fun = focal.fun,
                                window.diameter = focal.window.diameter,
                                stringsAsFactors = F)

      features <- foreach (i = 1:nrow(focal.param.df),
                           .packages = c("raster","stringr")) %dopar% {
                               make.focal.features(focal.param.df[i,])
                           }

test.stack <- stack(list.files("data/image/test", full.names = T, pattern = "test_.*.tif$"))
names(test.stack) <- str_match(names(test.stack), "test(.*)")[,2]

dir.create("data/image/test/int/")
stretch.vals <- read.csv("data/training/stretchvals.csv")

  test.stack.int <- lapply(1:nlayers(test.stack), function(i) {
      nm <- names(test.stack[[i]])
      j <- which(stretch.vals[,"nms"] == nm)
      mn <- stretch.vals[j,1]
      mx <- stretch.vals[j,2]
      if (cellStats(test.stack[[i]], "min") < mn) {
          test.stack[[i]][test.stack[[i]] < mn] <- mn
      }
      if (cellStats(test.stack[[i]], "max") > mx) {
          test.stack[[i]][test.stack[[i]] > mx] <- mx
      }


      calc(test.stack[[i]], fun=function(x){((x - mn) * 254)/(mx- mn) + 0},
           filename = paste0("data/image/test/int/",names(test.stack[[i]]),".tif"), datatype='INT1U', overwrite = T)
  })

test.stack.int <- stack(list.files("data/image/test/int", full.names = T, pattern = ".*.tif$"))

pred.test <- predict(test.stack.int, mod)

plot(pred.test)

writeRaster(pred.test, "data/image/test/prediction.tif", overwrite = T, dataType = "INT1U")

library(readxl)
    library(sp)
    library(rgeos)
    library(maptools)
    library(dplyr)
    library(raster)
    d <- read_excel("data/NAIPImages/MYSE_captures_2014.xlsx")
    coordinates(d) <- ~long + lat
    proj4string(d) <- CRS("+init=epsg:4326")

    utms <- c("15","16")
    bufs <- lapply(utms, function(utm) {
        p <- spTransform(d, CRS(paste0("+init=epsg:269",utm)))
        buf <- gBuffer(p, width = 2000, byid = T)
        buf <- gUnion(buf, buf)
        buf <- disaggregate(buf)
        buf
})
names(bufs) <- c("utm15","utm16")
shapefile(bufs$utm15, "data/NAIPImages/MYSE_captures_2014_utm15.shp", overwrite = T)
shapefile(bufs$utm16, "data/NAIPImages/MYSE_captures_2014_utm16.shp", overwrite = T)

image.files <- list.files("data/NAIPImages", recursive = T, full.names = T, pattern = ".*[0-9].tif$")

    images <- lapply(image.files, function(image.file) stack(image.file))

    extents <- lapply(images, function(i) extent(i))
    poly.extents <- lapply(extents, function(extent) as(extent, "SpatialPolygons"))
    poly.extents.merged <- do.call("bind", poly.extents)
shapefile(poly.extents.merged, "data/NAIPImages/extents.shp", overwrite = T)
    projs <- sapply(images, function(i) proj4string(i))

    cropped.images <- lapply(1:length(projs), function(i) {
        out.path <- paste0(tools::file_path_sans_ext(image.files[i]),"_cropped.tif")
        if(grepl(".*zone=15.*", projs[i])) {
         mask(images[[i]], bufs$utm15, out.path, overwrite = T)
        }
        if(grepl(".*zone=16.*", projs[i])) {
          mask(images[[i]], bufs$utm16, out.path, overwrite = T)
        }
    })

tile.dirs <- list.dirs("data/NAIPImages/")[-1]

  lapply(tile.dirs, function(tile.dir) {
      tile.names <- tools::file_path_sans_ext(list.files(tile.dir, pattern = ".*_cropped.tif$"))
    lapply(tile.names, function(tile.name) {

        add.features(tile.dir = tile.dir,
                     tile.name = tile.name,
                     band.names = c("red","green","blue","nir"),
                     ratio.bands = c("red","green","blue","nir"),
                     texture = F,
                     texture.params.df = texture.params)
})
})

cores <- 2

  tile.dirs <- list.dirs("data/NAIPImages/")[-1]

  lapply(tile.dirs, function(tile.dir) {
      tile.names <- tools::file_path_sans_ext(list.files(tile.dir, pattern = ".*_cropped.tif$"))
      lapply(tile.names, function(tile.name) {
#          cl <- makeCluster(cores)
 #         registerDoParallel(cl)
          focal.feature.pattern = "_(blue|green|red|nir|ratio.blue|ratio.green|ratio.red|ratio.nir|ndvi).tif$"
          focal.fun <- c("mean","max","min")
          focal.window.diameter <- c(1,2,4,8,11)
          names <- remove.tif.ext(list.files(tile.dir, paste0(tile.name,focal.feature.pattern)))
          focal.param.df <- expand.grid(raster.dir = tile.dir,
                                        raster.name = names,
                                        fun = focal.fun,
                                        window.diameter = focal.window.diameter,
                                        stringsAsFactors = F)
          features <- foreach (i = 56:nrow(focal.param.df),   ################## FIX THE 56...
                               .packages = c("raster","stringr"),
                               .export = c('make.focal.features','focal.name.and.writeRaster','myfocalWeight','circular.weight')) %do% {
                                   make.focal.features(focal.param.df[i,])
                               }
      })
  })
