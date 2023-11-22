source("test_dc_k.r")
source("NG_FWI.r")
source("test_hFWI.r")



do_test <- function(fit_temp, fit_daylight, offset_temp=2.8, timezone = -6, offset_sunrise=2.5, offset_sunset=0.5) {
  FIT_TEMP <<- fit_temp
  FIT_DAYLIGHT <<- fit_daylight
  OFFSET_SUNRISE <<- offset_sunrise
  OFFSET_SUNSET <<- offset_sunset
  hour_split <- HOUR_PEAK
  df_hourly <- copy(df_wx)
  df_hourly <- df_hourly[TIMEZONE == timezone,]
  df_hourly[, DATE := as.Date(TIMESTAMP)]
  df_hourly[, FOR_DATE := fifelse(HR <= hour_split, DATE, DATE + 1)]
  df_hours <- df_hourly[, list(num_hours=.N), by=list(ID, FOR_DATE)]
  # remove any hours with TEMP <= -2.8
  df_hourly <- df_hourly[TEMP > -2.8, ]
  # remove partial days
  df_hours <- df_hours[num_hours == 24, ]
  df_hourly <- merge(df_hours, df_hourly)
  df_hourly[, PREC24 := sum(PREC), by=list(ID, YR, FOR_DATE)]
  df_hourly[, HAD_RAIN := ifelse(PREC24 > 0, "T", "F")]
  df_hourly[, SUNRISE := round(SUNRISE + offset_sunrise)]
  df_hourly[, SUNSET := round(SUNSET + offset_sunset)]
  df_hourly[, IS_DAYLIGHT := ifelse((HR >= SUNRISE) & (HR < SUNSET), "T", "F")]
  df_hourly[, SUNLIGHT_HOURS := SUNSET - SUNRISE]
  df_hourly <- df_hourly["F" == HAD_RAIN,]
  df_noon <- df_hourly[12 == HR, ]
  df_noon[, PE_DAILY := dc_drying_daily(TEMP, MON)]
  df_noon <- df_noon[, list(ID, FOR_DATE, PE_DAILY)]
  df_hourly <- df_hourly[, list(ID, FOR_DATE, HR, IS_DAYLIGHT, TEMP)]
  cmp_df <- function(x) {
    k <- x[[1]]
    if (fit_temp) {
      offset_temp <- x[[2]]
    }
    df <- copy(df_hourly)
    # if (fit_daylight) {
    #   df <- df["T" == IS_DAYLIGHT,]
    # }
    # K <- 0.0914 * 3.937 / 24.0 * k
    K <- k
    df[, DC_DRY_HOURLY := (K * pmax(0.0, TEMP + offset_temp))]
    df[, DC_DRY_HOURLY := ifelse(fit_daylight & ("F" == IS_DAYLIGHT), 0.0, 1.0) * DC_DRY_HOURLY]
    df_pe <- df[, list(PE_SUM=sum(DC_DRY_HOURLY)), by=list(ID, FOR_DATE)]
    df <- merge(df_noon[, c("ID", "FOR_DATE", "PE_DAILY")], df_pe, by=c("ID", "FOR_DATE"))
    return(sqrt(mean(df[, PE_DAILY - PE_SUM] ^ 2)))
  }
  r <- ifelse(fit_temp,
              optim(list(k=1.0, offset_temp=offset_temp), cmp_df),
              optim(list(k=1.0), cmp_df, method="Brent", lower=1E-6, upper=10))
  r <- as.list(unlist(r))
  # DC_K_HOURLY <<- r$k
  DC_K_HOURLY <<- r[[1]]
  if (fit_temp) {
    # OFFSET_TEMP <<- r$offset_temp
    OFFSET_TEMP <<- r[[2]]
  } else {
    OFFSET_TEMP <<- offset_temp
  }
  title_daylight <- ifelse(fit_daylight,
                           sprintf("Daylight hours from round(sunrise + %0.1f) to round(sunset + %0.1f)", OFFSET_SUNRISE, OFFSET_SUNSET),
                           "24 hours")
  # title <- sprintf("TIMEZONE=%d\n%s\nK <- 0.0914 * 3.937 / 24.0 * F\npe <- K * (temp + %f)\nF <- %f", timezone, title_daylight, OFFSET_TEMP, DC_K_HOURLY)
  title <- sprintf("TIMEZONE=%d\n%s\npe <- K_HOURLY * temp\nK_HOURLY <- %f", timezone, title_daylight, DC_K_HOURLY)
  print(sprintf("Fit is:\n%s", title))
  df_test <- fread("./data/wx_hourly.csv")
  df_test$prec <- 0.0
  df_fwi <- test_hfwi(df_test, timezone, FLAG_NO_MONTH_FACTOR = FALSE)
  score <- sqrt(mean(df_fwi[hour(TIMESTAMP) == 16, (DC - DDC)] ^ 2))
  title <- sprintf("RMSE: %0.3f\n%s", score, title)
  print(ggplot(df_fwi) +
          # ggtitle(sprintf("Equation %dx%dx%d", eqn_k, eqn, eqn_j)) +
          ggtitle(title) +
          geom_line(aes(TIMESTAMP, DC), colour="red") +
          geom_point(aes(TIMESTAMP, DDC), data = df_fwi[hour(TIMESTAMP) == 16]))
  # df_fwi_all <- test_hfwi(df_all[TIMEZONE == timezone,], timezone)
  # score_all <- sqrt(mean(df_fwi_all[hour(TIMESTAMP) == 16, (DC - DDC)] ^ 2))
  return(data.table(list(offset_sunrise=ifelse(fit_daylight, offset_sunrise, NA),
              offset_sunset=ifelse(fit_daylight, offset_sunset, NA),
              fit_temp=fit_temp,
              fit_daylight=fit_daylight,
              timezone=timezone,
              offset_temp=OFFSET_TEMP,
              k=DC_K_HOURLY,
              score=score)))
}

df_all <- df_wx[, -c("SOLRAD", "SUNRISE", "SUNSET", "SUNLIGHT_HOURS")]
df_all$PREC <- 0.0

results <- NULL

offsets <- list(c(0.0, 0.0), c(3.0, 0.0), c(2.5, 0.5), c(2.0, 1.0), c(1.5, 1.5), c(1.0, 2.0), c(0.5, 2.5), c(0.0, 3.0))
for (k in 1:length(offsets)) {
  offset_sunrise=offsets[[k]][[1]]
  offset_sunset=offsets[[k]][[2]]
  for (fit_daylight in c(FALSE, TRUE)) {
    if (fit_daylight || (1 == k)) {
      for (timezone in -6:-5) {
        for (fit_temp in c(TRUE, FALSE)) {
          if (fit_temp) {
            results <- rbind(results, do_test(fit_temp=fit_temp, fit_daylight=fit_daylight, timezone=timezone, offset_sunrise=offset_sunrise, offset_sunset=offset_sunset))
          } else {
            for (offset_temp in c(2.8, 0.0)) {
              results <- rbind(results, do_test(fit_temp=fit_temp, fit_daylight=fit_daylight, offset_temp=offset_temp, timezone=timezone, offset_sunrise=offset_sunrise, offset_sunset=offset_sunset))
            }
          }
        }
      }
    }
  }
}




setorder(results, score)
# FIT_TEMP <<- TRUE
# r <- optim(list(k=1.0, offset_temp=2.8), cmp_df)
# DC_K_HOURLY <<- r$par[1]
# OFFSET_TEMP <<- r$par[2]
# df_results[[1]] <- plot_test(df)
#
# FIT_TEMP <<- FALSE
# OFFSET_TEMP <<- 2.8
# r2 <- optim(list(k=1.0), cmp_df)
# DC_K_HOURLY <<- r2$par[1]
# plot_test(df)
#
# FIT_TEMP <<- FALSE
# OFFSET_TEMP <<- 0.0
# r3 <- optim(list(k=1.0), cmp_df)
# DC_K_HOURLY <<- r3$par[1]
# plot_test(df)
#
#



do_apply <- function(v) {
  FIT_TEMP <<- v$fit_temp
  FIT_DAYLIGHT <<- v$fit_daylight
  # OFFSET_SUNRISE <<- v$offset_sunrise
  # OFFSET_SUNSET <<- v$offset_sunset
  hour_split <- HOUR_PEAK
  DC_K_HOURLY <<- v$k
  OFFSET_TEMP <<- v$offset_temp
  timezone <<- v$timezone
  calc_fit <- function(df_test) {
    names(df_test) <- toupper(names(df_test))
    df_fwi <- test_hfwi(df_test, timezone, FLAG_NO_MONTH_FACTOR = FALSE)
    score <- sqrt(mean(df_fwi[hour(TIMESTAMP) == 16, (DC - DDC)] ^ 2))
    return(list(df_fwi=df_fwi, score=score))
  }
  plot_fit <- function(df_test) {
    title_daylight <- ifelse(FIT_DAYLIGHT,
                             sprintf("Daylight hours from round(sunrise + %0.1f) to round(sunset + %0.1f)", OFFSET_SUNRISE, OFFSET_SUNSET),
                             "24 hours")
    # title <- sprintf("TIMEZONE=%d\n%s\nK <- 0.0914 * 3.937 / 24.0 * F\npe <- K * (temp + %f)\nF <- %f", timezone, title_daylight, OFFSET_TEMP, DC_K_HOURLY)
    title <- sprintf("TIMEZONE=%d\n%s\npe <- K * temp\nK <- %f", timezone, title_daylight, DC_K_HOURLY)
    print(sprintf("Fit is:\n%s", title))
    x <- calc_fit(df_test)
    df_fwi <- x$df_fwi
    score <- x$score
    title <- sprintf("RMSE: %0.3f\n%s", score, title)
    print(ggplot(df_fwi) +
            # ggtitle(sprintf("Equation %dx%dx%d", eqn_k, eqn, eqn_j)) +
            ggtitle(title) +
            geom_line(aes(TIMESTAMP, DC), colour="red") +
            geom_point(aes(TIMESTAMP, DDC), data = df_fwi[hour(TIMESTAMP) == 16]))
  }
  df_test <- fread("./data/wx_hourly.csv")
  plot_fit(df_test)
  df_test$prec <- 0.0
  plot_fit(df_test)
  # df_test_all <- df_all[TIMEZONE == timezone,]
  # df_test_all <- df_test_all[ID == "SAU",]
  # PREC already 0
  # results_all <- calc_fit(df_test_all)
  # df_fwi_all <- results_all$df_fwi
  # score_all <- results_all$score
  # df_score_all <- df_fwi_all[hour(TIMESTAMP) == 16, list(score=(DC - DDC)^2), by=list(DATE=date(TIMESTAMP))]
  # boxplot(score ~ year(DATE), df_score_all)
  # score_all <- sqrt(mean(df_fwi_all[hour(TIMESTAMP) == 16, (DC - DDC)] ^ 2))
  # return(list(offset_sunrise=ifelse(fit_daylight, offset_sunrise, NA),
  #             offset_sunset=ifelse(fit_daylight, offset_sunset, NA),
  #             fit_temp=fit_temp,
  #             fit_daylight=fit_daylight,
  #             timezone=timezone,
  #             offset_temp=OFFSET_TEMP,
  #             k=DC_K_HOURLY,
  #             score=score))
  # rely on this being done in test_dmc_k_simple.r
  boxplot(estimate ~ YR, df_results, ylim=c(0.01, 0.03))
  boxplot(estimate ~ MON, df_results, ylim=c(0.01, 0.03))
  df_yr <- df_results[, list(estimate=mean(estimate)), by=list(YR)]
  df_mon <- df_results[, list(estimate=mean(estimate)), by=list(MON)]
  for (i in 1:nrow(df_mon)) {
    k <- df_mon$estimate[i]
    DC_K_HOURLY <<- k
    df_test <- fread("./data/wx_hourly.csv")
    plot_fit(df_test)
    df_test$prec <- 0.0
    plot_fit(df_test)
  }
}

df_test <- fread("./data/wx_hourly.csv")
df_fwi <- calc_fit(df_test)$df_fwi
print(ggplot(df_fwi) +
        ggtitle("DMC for k = 2.1") +
        geom_line(aes(TIMESTAMP, DMC), colour="red") +
        geom_point(aes(TIMESTAMP, DDMC), data = df_fwi[hour(TIMESTAMP) == 16]))
df_test$prec <- 0.0
df_fwi <- calc_fit(df_test)$df_fwi
print(ggplot(df_fwi) +
        ggtitle("DMC for k = 2.1") +
        geom_line(aes(TIMESTAMP, DMC), colour="red") +
        geom_point(aes(TIMESTAMP, DDMC), data = df_fwi[hour(TIMESTAMP) == 16]))
