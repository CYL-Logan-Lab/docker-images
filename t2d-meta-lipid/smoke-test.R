options(warn = 2)
suppressPackageStartupMessages({
  library(coloc)
  library(digest)
  library(jsonlite)
})

stopifnot(
  getRversion() == "4.5.2",
  utils::packageVersion("coloc") == "6.0.1",
  utils::packageVersion("digest") == "0.6.39",
  utils::packageVersion("jsonlite") == "2.0.0",
  file.exists("/opt/Renv-manifest.tsv"),
  file.exists("/opt/system-manifest.tsv"),
  file.exists("/opt/build-manifest.tsv"),
  identical(Sys.getenv("R0_COLOC_SOURCE_COMMIT"),
            "50fe5291fea7f8ab49823bd86747385d6e56870f")
)

json_fixture <- '{"release":"26.06","rows":[{"id":"ENSG00000185619","count":1}],"ok":true}'
parsed_json <- jsonlite::fromJSON(json_fixture, simplifyVector = TRUE)
round_trip_json <- jsonlite::fromJSON(jsonlite::toJSON(parsed_json, auto_unbox = TRUE),
                                      simplifyVector = TRUE)
stopifnot(
  identical(parsed_json$release, "26.06"),
  identical(parsed_json$rows$id, "ENSG00000185619"),
  identical(parsed_json$rows$count, 1L),
  isTRUE(parsed_json$ok),
  identical(parsed_json, round_trip_json)
)

bf1 <- c(v1 = -0.8, v2 = 0.3, v3 = 1.1)
bf2 <- c(v1 = 0.6, v2 = -0.2, v3 = 0.9)
w1 <- c(v1 = 1, v2 = 2, v3 = 4)
w2 <- c(v1 = 3, v2 = 2, v3 = 1)
p1 <- 1e-4
p2 <- 1e-4
p12 <- 5e-6

observed <- coloc::coloc.bf_bf(
  bf1 = bf1,
  bf2 = bf2,
  p1 = p1,
  p2 = p2,
  p12 = p12,
  overlap.min = 0.90,
  trim_by_posterior = FALSE,
  prior_weights1 = w1,
  prior_weights2 = w2
)$summary[1, paste0("PP.H", 0:4, ".abf")]
observed <- as.numeric(observed)

logsumexp <- function(x) {
  anchor <- max(x)
  anchor + log(sum(exp(x - anchor)))
}
logdiffexp <- function(x, y) {
  stopifnot(x > y)
  x + log1p(-exp(y - x))
}

q <- length(bf1)
p1v <- q * p1 * w1 / sum(w1)
p2v <- q * p2 * w2 / sum(w2)
p12v <- p1v * p2v * p12 / (p1 * p2)
joint <- bf1 + bf2
log_h <- c(
  0,
  logsumexp(log(p1v) + bf1),
  logsumexp(log(p2v) + bf2),
  logdiffexp(
    logsumexp(log(p1v) + bf1) + logsumexp(log(p2v) + bf2),
    logsumexp(log(p1v) + log(p2v) + joint)
  ),
  logsumexp(log(p12v) + joint)
)
expected <- exp(log_h - logsumexp(log_h))

stopifnot(
  all(is.finite(observed)),
  abs(sum(observed) - 1) <= 1e-10,
  max(abs(observed - expected)) <= 1e-10,
  all(bf1[c("v1")] < 0),
  all(p1v > 0), all(p2v > 0), all(p12v > 0)
)

cat(
  "smoke ok:", R.version.string,
  "/ coloc", as.character(utils::packageVersion("coloc")),
  "/ jsonlite", as.character(utils::packageVersion("jsonlite")),
  "/ weighted H0-H4 max abs diff", format(max(abs(observed - expected)), digits = 17),
  "/ Python intentionally absent\n"
)
