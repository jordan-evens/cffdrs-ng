source("test_hFWI.r")
source("NG_FWI.r")
source("old_cffdrs.r")
source("load_data.r")

rmse  <- function(x, y) {
  return(sqrt(mean((x - y) ^ 2)))
}

rrmse <- function(x, y) {
  return(sqrt(mean((x - y) ^ 2) / sum(x ^ 2)))
}

df_rmse <- NULL
df_fwi_all <- NULL
for (yr in sort(unique(df_wx$YR))) {
  df_yr <- df_wx[YR == yr, ]
  for (timezone in unique(df_yr$TIMEZONE)) {
    df_tz <- df_yr[TIMEZONE == timezone, -c("SOLRAD", "SUNRISE", "SUNSET", "SUNLIGHT_HOURS")]
    for (stn in unique(df_tz$ID)) {
      df_stn <- df_tz[ID == stn, ]
      # don't run if already have results
      if (is.null(df_rmse) || (0 == nrow(df_rmse[(ID == stn) & (YR == yr) & (TIMEZONE == timezone)]))) {
        df_fwi <- test_hfwi(df_stn, timezone, filename = NULL)
        df_daily <- df_fwi[hour(TIMESTAMP) == 16,]
        df_rmse <- rbind(
          df_rmse,
          df_daily[, list(ID=stn,
                          TIMEZONE=timezone,
                          YR=yr,
                          RMSE_FFMC=rmse(DFFMC, FFMC),
                          RMSE_DMC=rmse(DDMC, DMC),
                          RMSE_DC=rmse(DDC, DC),
                          RRMSE_FFMC=rrmse(DFFMC, FFMC),
                          RRMSE_DMC=rrmse(DDMC, DMC),
                          RRMSE_DC=rrmse(DDC, DC))])
        df_fwi_all <- rbind(df_fwi_all, df_fwi)
      }
    }
  }
}
df_fwi_all[, HR := hour(TIMESTAMP)]
cols_id <- c("ID", "LAT", "LONG", "TIMEZONE", "YR", "MON", "DAY", "HR")
cols_ordered <- c(cols_id, setdiff(names(df_fwi_all), cols_id))
df_fwi_all <- df_fwi_all[, ..cols_ordered]
df_fwi_all <- df_fwi_all[, -c("TIMESTAMP")]
write.csv(df_fwi_all, "fwi_ON_cmp_full.csv", row.names=FALSE, quote=FALSE)

# HACK: just use known column names for now
cols <- names(df_fwi_all)[9:26]
# cols <- setdiff(names(df_fwi_all), cols_id)
df_fwi_all[, 9:26 := round(.SD, digits=1), .SDcols = cols]
write.csv(df_fwi_all, "fwi_ON_cmp.csv", row.names=FALSE, quote=FALSE)

df_stns <- unique(df_fwi_all[, list(ID, LAT, LONG, TIMEZONE, YR)])
write.csv(df_stns, "fwi_ON_cmp_stns.csv", row.names=FALSE, quote=FALSE)
df_fwi_data <- df_fwi_all[, -c("LAT", "LONG", "TIMEZONE")]
write.csv(df_fwi_data, "fwi_ON_cmp_data.csv", row.names=FALSE, quote=FALSE)

df_fwi_daily <- df_fwi_data[16 == HR, -c("HR", "TEMP", "WS", "RH", "PREC", "FFMC", "DMC", "DC", "ISI", "BUI", "FWI", "DSR")]
write.csv(df_fwi_daily, "fwi_ON_cmp_daily.csv", row.names=FALSE, quote=FALSE)
df_fwi_hourly <- df_fwi_data[, -c("DFFMC", "DDMC", "DDC", "DISI", "DBUI", "DFWI", "DDSR")]
write.csv(df_fwi_hourly, "fwi_ON_cmp_hourly.csv", row.names=FALSE, quote=FALSE)

df_fwi_int <- copy(df_fwi_all)
# not sure how to do this propery but this works for now
cols_int <- c("RH", "DMC", "DC", "BUI", "DDMC", "DDC", "DBUI")
for (col in cols_int) {
  i <- match(col, names(df_fwi_int))
  # df_fwi_int[, `:=`(list(eval(col)=as.integer(round(.SD, digits=0)))), .SDcols = c(col)]
  df_fwi_int[, i:i] <- lapply(df_fwi_int[, ..i], function (x) { as.integer(round(x, 0)) })
}
write.csv(df_fwi_int, "fwi_ON_cmp_int.csv", row.names=FALSE, quote=FALSE)

# comparing every row doesn't make sense since only one of them should match the daily value
df_fwi_int[, list(RMSE_FFMC=rmse(DFFMC, FFMC),
                  RMSE_DMC=rmse(DDMC, DMC),
                  RMSE_DC=rmse(DDC, DC),
                  RRMSE_FFMC=rrmse(DFFMC, FFMC),
                  RRMSE_DMC=rrmse(DDMC, DMC),
                  RRMSE_DC=rrmse(DDC, DC)),
           by = c("HR")]

write.csv(df_fwi_int[16 == HR, ], "fwi_ON_cmp_int_1600.csv", row.names=FALSE, quote=FALSE)
