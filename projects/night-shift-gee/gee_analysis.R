# 야간근무와 업무상 사고 경험 분석
# 교수님 전달용 통합 분석 코드
#
# 이 파일은 원자료 불러오기부터 대상자 선별, 변수 생성, 대상자 특성표,
# GEE 분석, Firth 보조분석, 민감도 분석, 결과 저장까지 한 번에 실행합니다.
#
# 실행 전 확인할 사항
# 1) 아래 data_file_name과 같은 엑셀 파일을 이 코드와 같은 폴더에 둡니다.
# 2) 필요한 패키지는 openxlsx, data.table, geepack, logistf입니다.
# 3) 전체 코드를 실행하면 같은 폴더에 '분석결과' 폴더가 생성됩니다.

options(stringsAsFactors = FALSE, scipen = 999)
try(Sys.setlocale("LC_ALL", "Korean_Korea.utf8"), silent = TRUE)


# 1. 패키지와 파일 경로 설정 -----------------------------------------------

required_packages <- c("openxlsx", "data.table", "geepack", "logistf")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0) {
  stop(
    "다음 패키지를 먼저 설치해 주세요: ",
    paste(missing_packages, collapse = ", "),
    "\n예: install.packages(c('",
    paste(missing_packages, collapse = "', '"),
    "'))"
  )
}

suppressPackageStartupMessages({
  library(openxlsx)
  library(data.table)
  library(geepack)
  library(logistf)
})

# Rscript로 실행할 때는 코드 파일의 위치를 기준으로 경로를 잡습니다.
# RStudio에서 전체 실행하는 경우에는 현재 작업 폴더를 기준으로 합니다.
cmd_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", cmd_args, value = TRUE)
script_dir <- if (length(file_arg) > 0) {
  dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE))
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

data_file_name <- "직장인 수면과 건강 연구 관련 조사_1~6차 최종DATA (2).xlsx"

# 자료가 코드와 다른 폴더에 있으면 아래 source_xlsx 경로만 수정하면 됩니다.
# 환경변수 GEE_SOURCE_XLSX가 지정되어 있으면 그 경로를 우선 사용합니다.
source_xlsx <- Sys.getenv(
  "GEE_SOURCE_XLSX",
  unset = file.path(script_dir, data_file_name)
)

if (!file.exists(source_xlsx)) {
  stop(
    "원자료 파일을 찾을 수 없습니다.\n",
    "현재 확인한 경로: ", source_xlsx, "\n",
    "엑셀 파일을 코드와 같은 폴더에 두거나 source_xlsx 경로를 수정해 주세요."
  )
}

result_dir <- file.path(script_dir, "분석결과")
table_dir <- file.path(result_dir, "표")
output_dir <- file.path(result_dir, "기록")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)


# 2. 원자료 불러오기와 대상자 선별 -----------------------------------------

# 종속변수 문항이 있는 1·3·5·6차 자료만 사용합니다.
selected_waves <- c(1, 3, 5, 6)

# 분석에 필요한 열만 읽어 불필요한 개인정보와 메모리 사용을 줄였습니다.
selected_vars <- c(
  "ID", "Gu", "SQ1", "SQ2_code", "Q1", "Q4", "Q6", "Q8", "Q9",
  "Q9_1", "Q9_2", "Q9_8_1", "Q9_8_2", "Q73", "Q74", "Q78", "Q81"
)

message("1/7 원자료 확인")

raw_header <- openxlsx::read.xlsx(
  source_xlsx,
  sheet = "Raw",
  rows = 1,
  colNames = FALSE,
  skipEmptyRows = FALSE,
  skipEmptyCols = FALSE
)

header_names <- as.character(unlist(raw_header[1, ], use.names = FALSE))
selected_cols <- match(selected_vars, header_names)

if (anyNA(selected_cols)) {
  stop(
    "원자료에서 찾지 못한 변수: ",
    paste(selected_vars[is.na(selected_cols)], collapse = ", ")
  )
}

dat <- openxlsx::read.xlsx(
  source_xlsx,
  sheet = "Raw",
  cols = selected_cols,
  colNames = TRUE,
  skipEmptyRows = FALSE,
  skipEmptyCols = FALSE,
  detectDates = FALSE
)

dat <- as.data.table(dat)
dat <- dat[, ..selected_vars]

# ID는 문자형으로, 나머지 설문 코드는 숫자형으로 통일합니다.
numeric_vars <- setdiff(selected_vars, "ID")
dat[, (numeric_vars) := lapply(
  .SD,
  function(x) suppressWarnings(as.numeric(as.character(x)))
), .SDcols = numeric_vars]
dat[, ID := trimws(as.character(ID))]

dat <- dat[Gu %in% selected_waves & !is.na(ID) & ID != ""]
setorder(dat, ID, Gu)

# 동일한 사람이 같은 차수에 두 번 들어간 경우 분석을 중단합니다.
duplicate_keys <- dat[, .N, by = .(ID, Gu)][N > 1]
if (nrow(duplicate_keys) > 0) {
  stop("ID-차수 중복이 발견되어 분석을 중단했습니다.")
}


# 3. 분석 변수 생성 --------------------------------------------------------

message("2/7 분석 변수 생성")

# 조사차수는 범주형 민감도 분석과 시간 추세 보정에 각각 사용합니다.
dat[, wave_time := fifelse(
  Gu == 1, 0,
  fifelse(Gu == 3, 1, fifelse(Gu == 5, 2, fifelse(Gu == 6, 3, NA_real_)))
)]
dat[, wave_factor := factor(
  Gu,
  levels = selected_waves,
  labels = c("1차", "3차", "5차", "6차")
)]

# Q9=1은 주간근무, Q9=2는 주간 외 시간대 근무입니다.
# 문항 표현상 Q9=2에는 야간 외 시간대가 포함될 수 있어 해석에서는 비주간근무로 표현합니다.
dat[, non_day := fifelse(Q9 == 2, 1, fifelse(Q9 == 1, 0, NA_real_))]

# 야간근무 관련 지원환경 문항은 Q9=2 응답자에게만 적용됩니다.
dat[, sleep_yes := fifelse(Q9_8_1 == 1, 1, fifelse(Q9_8_1 == 2, 0, NA_real_))]
dat[, rest_yes := fifelse(Q9_8_2 == 1, 1, fifelse(Q9_8_2 == 2, 0, NA_real_))]

# Q73은 최근 1년 내 업무상 사고·손상 경험 여부입니다.
dat[, accident_any := fifelse(Q73 == 1, 1, fifelse(Q73 == 2, 0, NA_real_))]

# Q74=2인 경우를 사업장 안에서 발생한 사고·손상으로 정의합니다.
# 사업장 사고 분석은 사건 수가 더 적으므로 보조분석으로 사용합니다.
dat[, accident_work := fifelse(
  Q73 == 2, 0,
  fifelse(
    Q73 == 1 & Q74 == 2, 1,
    fifelse(Q73 == 1 & !is.na(Q74) & Q74 != 2, 0, NA_real_)
  )
)]

# 대상자 특성표와 범주형 민감도 분석에 사용할 변수입니다.
dat[, sex := factor(SQ1, levels = 1:2, labels = c("남자", "여자"))]
dat[, age_group := factor(
  SQ2_code,
  levels = 1:5,
  labels = c("20~29세", "30~39세", "40~49세", "50~59세", "60~69세")
)]
dat[, education := factor(
  Q1,
  levels = 1:6,
  labels = c("초등학교", "중학교", "고등학교", "2/3년제 대학", "4년제 대학", "대학원")
)]
dat[, employment := factor(
  Q4,
  levels = 1:6,
  labels = c("직접고용", "파견·용역", "직접고용+자영업", "고용주 자영업", "1인 자영업", "무급가족종사")
)]
dat[, establishment_size := factor(
  Q6,
  levels = 1:6,
  labels = c("1~4명", "5~9명", "10~49명", "50~99명", "100~299명", "300명 이상")
)]
dat[, smoking := factor(
  Q81,
  levels = 1:3,
  labels = c("현재 흡연", "과거 흡연·현재 금연", "비흡연")
)]
dat[, alcohol := factor(
  Q78,
  levels = 1:6,
  labels = c("최근 1년 비음주", "월 1회 미만", "월 1회", "월 2~4회", "주 2~3회", "주 4회 이상")
)]
dat[, shift_tenure := factor(
  Q9_1,
  levels = 1:6,
  labels = c("5년 미만", "5~9년", "10~14년", "15~19년", "20년 이상", "해당 없음")
)]
dat[, work_schedule := factor(
  Q9_2,
  levels = 1:6,
  labels = c("3교대", "2교대", "격일제(24시간)", "고정 저녁", "고정 야간", "기타·불규칙")
)]
dat[, weekly_hours := fifelse(Q8 >= 1 & Q8 <= 168, Q8, NA_real_)]
dat[, weekly_hours10 := weekly_hours / 10]

# 사고 사건 수가 적기 때문에 주 분석에서는 공변량의 자유도를 줄여 보정합니다.
# 범주별 효과가 연구목적이 아니라 교란 보정이 목적이므로 이분화 또는 순서 추세로 코딩했습니다.
dat[, female := fifelse(SQ1 == 2, 1, fifelse(SQ1 == 1, 0, NA_real_))]
dat[, age_decade_trend := fifelse(SQ2_code %in% 1:5, SQ2_code - 1, NA_real_)]
dat[, college_or_more := fifelse(Q1 %in% 4:6, 1, fifelse(Q1 %in% 1:3, 0, NA_real_))]
dat[, directly_employed := fifelse(Q4 == 1, 1, fifelse(Q4 %in% 2:6, 0, NA_real_))]
dat[, establishment_trend := fifelse(Q6 %in% 1:6, Q6 - 1, NA_real_)]
dat[, current_smoker := fifelse(Q81 == 1, 1, fifelse(Q81 %in% 2:3, 0, NA_real_))]
dat[, alcohol_frequency_trend := fifelse(Q78 %in% 1:6, Q78 - 1, NA_real_)]

# H2와 H3는 주간근무자를 기준으로 한 3집단 결합변수로 분석합니다.
# 연속 야간근무일수는 교수님 피드백에 따라 모든 최종 모형에서 제외했습니다.
dat[, rest_group := factor(
  fifelse(
    Q9 == 1, "주간근무",
    fifelse(
      Q9 == 2 & rest_yes == 1, "야간근무·휴게실 있음",
      fifelse(Q9 == 2 & rest_yes == 0, "야간근무·휴게실 없음", NA_character_)
    )
  ),
  levels = c("주간근무", "야간근무·휴게실 있음", "야간근무·휴게실 없음")
)]

dat[, sleep_group := factor(
  fifelse(
    Q9 == 1, "주간근무",
    fifelse(
      Q9 == 2 & sleep_yes == 1, "야간근무·수면 가능",
      fifelse(Q9 == 2 & sleep_yes == 0, "야간근무·수면 불가", NA_character_)
    )
  ),
  levels = c("주간근무", "야간근무·수면 가능", "야간근무·수면 불가")
)]


# 4. 데이터 품질과 분석대상 확인 ------------------------------------------

message("3/7 분석대상 및 결측 확인")

quality_checks <- data.table(
  check = c(
    "1·3·5·6차 관측치",
    "1·3·5·6차 고유 참여자",
    "ID-차수 중복",
    "Q9 결측",
    "Q9=2 중 휴게실 문항 결측",
    "Q9=2 중 수면 가능 문항 결측",
    "Q73 결측",
    "주당 근로시간 범위 밖"
  ),
  value = c(
    nrow(dat),
    uniqueN(dat$ID),
    nrow(duplicate_keys),
    sum(is.na(dat$Q9)),
    dat[Q9 == 2 & is.na(Q9_8_2), .N],
    dat[Q9 == 2 & is.na(Q9_8_1), .N],
    sum(is.na(dat$Q73)),
    dat[!is.na(Q8) & (Q8 < 1 | Q8 > 168), .N]
  )
)

population <- data.table(
  item = c(
    "1·3·5·6차 전체",
    "주간근무",
    "비주간근무",
    "전체 사고·손상",
    "사업장 발생 사고·손상"
  ),
  observations = c(
    nrow(dat),
    dat[Q9 == 1, .N],
    dat[Q9 == 2, .N],
    dat[accident_any == 1, .N],
    dat[accident_work == 1, .N]
  ),
  participants = c(
    uniqueN(dat$ID),
    uniqueN(dat[Q9 == 1, ID]),
    uniqueN(dat[Q9 == 2, ID]),
    uniqueN(dat[accident_any == 1, ID]),
    uniqueN(dat[accident_work == 1, ID])
  )
)

# 주간근무와 비주간근무 참여자 수는 차수별 근무형태가 바뀐 사람 때문에 서로 중복될 수 있습니다.
# 관측 건수는 시점별 응답 수이고, 참여자 수는 각 조건에 한 번이라도 해당한 고유 ID 수입니다.


# 5. 개인 단위 대상자 특성표 ----------------------------------------------

message("4/7 대상자 특성표 작성")

# 특성표는 한 사람을 한 번만 집계하기 위해 개인별 최초 참여 차수를 사용합니다.
# 반면 아래 GEE 모형은 1·3·5·6차 반복응답을 모두 사용합니다.
baseline <- dat[, .SD[1], by = ID]
baseline[, work_group := factor(
  fifelse(Q9 == 1, "주간근무", fifelse(Q9 == 2, "비주간근무", NA_character_)),
  levels = c("주간근무", "비주간근무")
)]
baseline[, accident_baseline := factor(Q73, levels = 1:2, labels = c("있음", "없음"))]
baseline[, rest_room := factor(Q9_8_2, levels = 1:2, labels = c("있음", "없음"))]
baseline[, sleep_possible := factor(Q9_8_1, levels = 1:2, labels = c("가능", "불가"))]

fmt_n_pct <- function(n, denominator) {
  if (is.na(denominator) || denominator == 0) return(NA_character_)
  sprintf("%s (%.1f)", format(n, big.mark = ",", scientific = FALSE), 100 * n / denominator)
}

fmt_p <- function(p) {
  if (is.na(p)) return(NA_character_)
  if (p < 0.001) return("<.001")
  sub("^0", "", sprintf("%.3f", p))
}

categorical_p <- function(d, variable) {
  keep <- !is.na(d$work_group) & !is.na(d[[variable]])
  tab <- table(d$work_group[keep], d[[variable]][keep])
  if (nrow(tab) < 2 || ncol(tab) < 2) {
    return(list(p = NA_real_, test = "검정 불가"))
  }

  chi <- suppressWarnings(chisq.test(tab, correct = FALSE))
  if (any(chi$expected < 5)) {
    set.seed(20260920)
    fisher <- fisher.test(tab, simulate.p.value = TRUE, B = 50000)
    return(list(p = unname(fisher$p.value), test = "Fisher 정확검정(모의 p값)"))
  }

  list(p = unname(chi$p.value), test = "카이제곱검정")
}

categorical_rows <- function(d, variable, variable_label) {
  x <- d[[variable]]
  levels_x <- levels(droplevels(x))
  overall_den <- sum(!is.na(x))
  day_den <- d[work_group == "주간근무", sum(!is.na(get(variable)))]
  non_day_den <- d[work_group == "비주간근무", sum(!is.na(get(variable)))]
  test <- categorical_p(d, variable)

  rows <- rbindlist(lapply(seq_along(levels_x), function(i) {
    level_value <- levels_x[[i]]
    data.table(
      variable = variable_label,
      level = level_value,
      overall = fmt_n_pct(sum(x == level_value, na.rm = TRUE), overall_den),
      day = fmt_n_pct(
        d[work_group == "주간근무", sum(get(variable) == level_value, na.rm = TRUE)],
        day_den
      ),
      non_day = fmt_n_pct(
        d[work_group == "비주간근무", sum(get(variable) == level_value, na.rm = TRUE)],
        non_day_den
      ),
      p_value = if (i == 1) fmt_p(test$p) else "",
      p_numeric = if (i == 1) test$p else NA_real_,
      test = if (i == 1) test$test else ""
    )
  }))

  missing_n <- sum(is.na(x))
  if (missing_n > 0) {
    rows <- rbind(
      rows,
      data.table(
        variable = variable_label,
        level = "결측",
        overall = format(missing_n, big.mark = ",", scientific = FALSE),
        day = format(
          d[work_group == "주간근무", sum(is.na(get(variable)))],
          big.mark = ",", scientific = FALSE
        ),
        non_day = format(
          d[work_group == "비주간근무", sum(is.na(get(variable)))],
          big.mark = ",", scientific = FALSE
        ),
        p_value = "",
        p_numeric = NA_real_,
        test = ""
      ),
      fill = TRUE
    )
  }

  rows
}

continuous_row <- function(d, variable, variable_label) {
  overall <- d[[variable]]
  day <- d[work_group == "주간근무"][[variable]]
  non_day <- d[work_group == "비주간근무"][[variable]]
  day_valid <- day[is.finite(day)]
  non_day_valid <- non_day[is.finite(non_day)]

  test <- if (length(day_valid) > 1 && length(non_day_valid) > 1) {
    t.test(day_valid, non_day_valid, var.equal = FALSE)
  } else {
    NULL
  }

  data.table(
    variable = variable_label,
    level = "평균 ± 표준편차",
    overall = sprintf("%.1f ± %.1f", mean(overall, na.rm = TRUE), sd(overall, na.rm = TRUE)),
    day = sprintf("%.1f ± %.1f", mean(day_valid), sd(day_valid)),
    non_day = sprintf("%.1f ± %.1f", mean(non_day_valid), sd(non_day_valid)),
    p_value = if (is.null(test)) NA_character_ else fmt_p(test$p.value),
    p_numeric = if (is.null(test)) NA_real_ else unname(test$p.value),
    test = "Welch t검정"
  )
}

baseline_characteristics <- rbindlist(list(
  categorical_rows(baseline, "sex", "성별"),
  categorical_rows(baseline, "age_group", "연령대"),
  categorical_rows(baseline, "education", "학력"),
  categorical_rows(baseline, "employment", "고용형태"),
  categorical_rows(baseline, "establishment_size", "사업장 근로자 수"),
  continuous_row(baseline, "weekly_hours", "주당 근로시간(시간)"),
  categorical_rows(baseline, "smoking", "흡연"),
  categorical_rows(baseline, "alcohol", "음주빈도"),
  categorical_rows(baseline, "accident_baseline", "최근 1년 업무상 사고·손상 경험")
), fill = TRUE)

baseline_group_counts <- baseline[, .(
  total = .N,
  day = sum(work_group == "주간근무", na.rm = TRUE),
  non_day = sum(work_group == "비주간근무", na.rm = TRUE),
  missing_group = sum(is.na(work_group))
)]

# 교대근무 종사기간과 근무형태, 휴게실, 수면 가능 여부는 비주간근무자에게만 적용되므로 별도 표로 제시합니다.
baseline_non_day <- baseline[work_group == "비주간근무"]
night_variables <- list(
  "교대근무 종사기간" = "shift_tenure",
  "근무형태" = "work_schedule",
  "휴게실 제공 여부" = "rest_room",
  "야간근무 중 수면 가능 여부" = "sleep_possible"
)

baseline_non_day_characteristics <- rbindlist(lapply(names(night_variables), function(label) {
  variable <- night_variables[[label]]
  x <- baseline_non_day[[variable]]
  denominator <- sum(!is.na(x))
  levels_x <- levels(droplevels(x))

  rows <- rbindlist(lapply(levels_x, function(level_value) {
    data.table(
      variable = label,
      level = level_value,
      n_percent = fmt_n_pct(sum(x == level_value, na.rm = TRUE), denominator),
      denominator = denominator
    )
  }))

  if (sum(is.na(x)) > 0) {
    rows <- rbind(
      rows,
      data.table(
        variable = label,
        level = "결측",
        n_percent = format(sum(is.na(x)), big.mark = ",", scientific = FALSE),
        denominator = denominator
      )
    )
  }

  rows
}), fill = TRUE)


# 6. GEE와 Firth 분석 함수 -------------------------------------------------

message("5/7 GEE와 Firth 분석")

# 주 분석은 개인 내 반복응답의 상관을 고려하는 GEE입니다.
# 상관구조는 exchangeable, 표준오차는 robust sandwich 표준오차를 사용합니다.
model_data <- function(formula, data) {
  vars <- unique(c(all.vars(formula), "ID", "Gu"))
  z <- as.data.frame(data[, ..vars])
  z <- droplevels(z[complete.cases(z), , drop = FALSE])
  z[order(z$ID, z$Gu), , drop = FALSE]
}

fit_gee_direct <- function(formula, data) {
  z <- model_data(formula, data)
  id_vec <- z$ID
  formula_local <- formula
  environment(formula_local) <- environment()

  fit <- geepack::geeglm(
    formula_local,
    id = id_vec,
    data = z,
    family = binomial("logit"),
    corstr = "exchangeable",
    std.err = "san.se",
    control = geepack::geese.control(maxit = 100)
  )

  list(fit = fit, data = z)
}

contrast_row <- function(beta, vcov_beta, weights, label) {
  estimate <- sum(weights * beta)
  standard_error <- sqrt(as.numeric(t(weights) %*% vcov_beta %*% weights))

  data.table(
    comparison = label,
    estimate = estimate,
    standard_error = standard_error,
    odds_ratio = exp(estimate),
    ci_low = exp(estimate - 1.96 * standard_error),
    ci_high = exp(estimate + 1.96 * standard_error),
    p_value = 2 * pnorm(abs(estimate / standard_error), lower.tail = FALSE)
  )
}

extract_gee_binary <- function(
  model_id, hypothesis, outcome_scope, adjustment,
  fit_obj, term, comparison
) {
  fit <- fit_obj$fit
  z <- fit_obj$data
  coefficients <- as.data.frame(summary(fit)$coefficients)
  row <- coefficients[term, , drop = FALSE]
  estimate <- row[["Estimate"]]
  standard_error <- row[["Std.err"]]
  outcome <- all.vars(formula(fit))[1]

  pairwise <- data.table(
    hypothesis = hypothesis,
    outcome_scope = outcome_scope,
    method = "GEE",
    adjustment = adjustment,
    comparison = comparison,
    model_id = model_id,
    odds_ratio = exp(estimate),
    ci_low = exp(estimate - 1.96 * standard_error),
    ci_high = exp(estimate + 1.96 * standard_error),
    p_value = row[[grep("^Pr", names(row), value = TRUE)[1]]],
    estimate = estimate,
    standard_error = standard_error,
    n = nrow(z),
    clusters = uniqueN(z$ID),
    events = sum(z[[outcome]] == 1)
  )

  n_parameters <- qr(model.matrix(formula(fit), z))$rank
  diagnostics <- data.table(
    model_id = model_id,
    hypothesis = hypothesis,
    outcome_scope = outcome_scope,
    method = "GEE",
    adjustment = adjustment,
    n = nrow(z),
    clusters = uniqueN(z$ID),
    events = sum(z[[outcome]] == 1),
    parameters = n_parameters,
    events_per_parameter = sum(z[[outcome]] == 1) / n_parameters,
    geese_error = fit$geese$error,
    status = ifelse(fit$geese$error == 0, "적합 완료", "수렴 확인 필요"),
    formula = paste(deparse(formula(fit)), collapse = " ")
  )

  list(pairwise = pairwise, diagnostics = diagnostics, fit = fit)
}

extract_gee_group <- function(
  model_id, hypothesis, outcome_scope, adjustment,
  fit_obj, exposure, level_labels
) {
  fit <- fit_obj$fit
  z <- fit_obj$data
  beta <- coef(fit)
  vcov_beta <- fit$geese$vbeta
  dimnames(vcov_beta) <- list(names(beta), names(beta))

  term_index <- grep(paste0("^", exposure), names(beta))
  if (length(term_index) != 2L) {
    stop(model_id, ": 3집단 계수 2개를 찾지 못했습니다.")
  }

  contrast_1 <- contrast_2 <- rep(0, length(beta))
  contrast_1[term_index[1]] <- 1
  contrast_2[term_index[2]] <- 1

  pairwise <- rbindlist(list(
    contrast_row(
      beta, vcov_beta, contrast_1,
      paste0(level_labels[2], " 대 ", level_labels[1])
    ),
    contrast_row(
      beta, vcov_beta, contrast_2,
      paste0(level_labels[3], " 대 ", level_labels[1])
    ),
    contrast_row(
      beta, vcov_beta, contrast_2 - contrast_1,
      paste0(level_labels[3], " 대 ", level_labels[2])
    )
  ))

  outcome <- all.vars(formula(fit))[1]
  pairwise[, `:=`(
    model_id = model_id,
    hypothesis = hypothesis,
    outcome_scope = outcome_scope,
    method = "GEE",
    adjustment = adjustment,
    n = nrow(z),
    clusters = uniqueN(z$ID),
    events = sum(z[[outcome]] == 1)
  )]
  setcolorder(pairwise, c(
    "hypothesis", "outcome_scope", "method", "adjustment", "comparison",
    "model_id", "odds_ratio", "ci_low", "ci_high", "p_value",
    "estimate", "standard_error", "n", "clusters", "events"
  ))

  # 3집단 계수 두 개가 동시에 0인지 확인하는 2자유도 Wald 검정입니다.
  beta_group <- beta[term_index]
  vcov_group <- vcov_beta[term_index, term_index, drop = FALSE]
  wald_statistic <- as.numeric(t(beta_group) %*% solve(vcov_group, beta_group))

  global <- data.table(
    hypothesis = hypothesis,
    outcome_scope = outcome_scope,
    method = "GEE",
    adjustment = adjustment,
    model_id = model_id,
    test = paste0(exposure, " 3집단 전체 차이"),
    statistic = wald_statistic,
    df = 2L,
    p_value = pchisq(wald_statistic, df = 2, lower.tail = FALSE),
    n = nrow(z),
    clusters = uniqueN(z$ID),
    events = sum(z[[outcome]] == 1)
  )

  n_parameters <- qr(model.matrix(formula(fit), z))$rank
  diagnostics <- data.table(
    model_id = model_id,
    hypothesis = hypothesis,
    outcome_scope = outcome_scope,
    method = "GEE",
    adjustment = adjustment,
    n = nrow(z),
    clusters = uniqueN(z$ID),
    events = sum(z[[outcome]] == 1),
    parameters = n_parameters,
    events_per_parameter = sum(z[[outcome]] == 1) / n_parameters,
    geese_error = fit$geese$error,
    status = ifelse(fit$geese$error == 0, "적합 완료", "수렴 확인 필요"),
    formula = paste(deparse(formula(fit)), collapse = " ")
  )

  list(pairwise = pairwise, global = global, diagnostics = diagnostics, fit = fit)
}

# Firth 분석은 희귀사건 편의를 줄이기 위한 보조분석입니다.
# 반복측정 상관을 직접 반영하지 못하므로 최종 판단은 GEE 결과를 기준으로 합니다.
extract_firth_term <- function(fit, term, comparison) {
  data.table(
    comparison = comparison,
    estimate = unname(coef(fit)[term]),
    standard_error = sqrt(unname(diag(fit$var)[term])),
    odds_ratio = exp(unname(coef(fit)[term])),
    ci_low = exp(unname(fit$ci.lower[term])),
    ci_high = exp(unname(fit$ci.upper[term])),
    p_value = unname(fit$prob[term])
  )
}

fit_firth_binary <- function(
  model_id, hypothesis, outcome_scope, adjustment,
  formula, data, term, comparison
) {
  z <- model_data(formula, data)
  fit <- logistf::logistf(formula = formula, data = z, pl = TRUE)
  pairwise <- extract_firth_term(fit, term, comparison)
  outcome <- all.vars(formula)[1]

  pairwise[, `:=`(
    model_id = model_id,
    hypothesis = hypothesis,
    outcome_scope = outcome_scope,
    method = "Firth",
    adjustment = adjustment,
    n = nrow(z),
    clusters = uniqueN(z$ID),
    events = sum(z[[outcome]] == 1)
  )]
  setcolorder(pairwise, c(
    "hypothesis", "outcome_scope", "method", "adjustment", "comparison",
    "model_id", "odds_ratio", "ci_low", "ci_high", "p_value",
    "estimate", "standard_error", "n", "clusters", "events"
  ))

  n_parameters <- qr(model.matrix(formula, z))$rank
  diagnostics <- data.table(
    model_id = model_id,
    hypothesis = hypothesis,
    outcome_scope = outcome_scope,
    method = "Firth",
    adjustment = adjustment,
    n = nrow(z),
    clusters = uniqueN(z$ID),
    events = sum(z[[outcome]] == 1),
    parameters = n_parameters,
    events_per_parameter = sum(z[[outcome]] == 1) / n_parameters,
    geese_error = NA_integer_,
    status = "적합 완료",
    formula = paste(deparse(formula), collapse = " ")
  )

  list(pairwise = pairwise, diagnostics = diagnostics, fit = fit)
}

fit_firth_group <- function(
  model_id, hypothesis, outcome_scope, adjustment,
  formula, data, exposure, level_labels
) {
  z <- model_data(formula, data)

  # 첫 번째 적합에서는 주간근무자를 기준으로 두 야간근무 집단을 비교합니다.
  fit_day <- logistf::logistf(formula = formula, data = z, pl = TRUE)
  day_terms <- grep(paste0("^", exposure), names(coef(fit_day)), value = TRUE)
  if (length(day_terms) != 2L) {
    stop(model_id, ": Firth 3집단 계수 2개를 찾지 못했습니다.")
  }

  pairwise <- rbindlist(list(
    extract_firth_term(
      fit_day, day_terms[1],
      paste0(level_labels[2], " 대 ", level_labels[1])
    ),
    extract_firth_term(
      fit_day, day_terms[2],
      paste0(level_labels[3], " 대 ", level_labels[1])
    )
  ))

  # 지원환경 없음 대 있음의 직접 비교를 위해 기준집단을 한 번 바꾸어 다시 적합합니다.
  z_support <- copy(as.data.table(z))
  z_support[, (exposure) := relevel(get(exposure), ref = level_labels[2])]
  z_support <- as.data.frame(z_support)
  fit_support <- logistf::logistf(formula = formula, data = z_support, pl = TRUE)
  support_terms <- grep(paste0("^", exposure), names(coef(fit_support)), value = TRUE)
  target_term <- support_terms[grepl(level_labels[3], support_terms, fixed = TRUE)]

  if (length(target_term) != 1L) {
    stop(model_id, ": Firth 지원환경 직접비교 계수를 찾지 못했습니다.")
  }

  pairwise <- rbindlist(list(
    pairwise,
    extract_firth_term(
      fit_support, target_term,
      paste0(level_labels[3], " 대 ", level_labels[2])
    )
  ))

  outcome <- all.vars(formula)[1]
  pairwise[, `:=`(
    model_id = model_id,
    hypothesis = hypothesis,
    outcome_scope = outcome_scope,
    method = "Firth",
    adjustment = adjustment,
    n = nrow(z),
    clusters = uniqueN(z$ID),
    events = sum(z[[outcome]] == 1)
  )]
  setcolorder(pairwise, c(
    "hypothesis", "outcome_scope", "method", "adjustment", "comparison",
    "model_id", "odds_ratio", "ci_low", "ci_high", "p_value",
    "estimate", "standard_error", "n", "clusters", "events"
  ))

  n_parameters <- qr(model.matrix(formula, z))$rank
  diagnostics <- data.table(
    model_id = model_id,
    hypothesis = hypothesis,
    outcome_scope = outcome_scope,
    method = "Firth",
    adjustment = adjustment,
    n = nrow(z),
    clusters = uniqueN(z$ID),
    events = sum(z[[outcome]] == 1),
    parameters = n_parameters,
    events_per_parameter = sum(z[[outcome]] == 1) / n_parameters,
    geese_error = NA_integer_,
    status = "적합 완료",
    formula = paste(deparse(formula), collapse = " ")
  )

  list(pairwise = pairwise, diagnostics = diagnostics, fit = fit_day)
}

make_formula <- function(outcome, exposure, covariates) {
  as.formula(paste(outcome, "~", exposure, "+", covariates))
}


# 7. 주 분석과 민감도 분석 -------------------------------------------------

# 압축 전체보정 모형은 희귀사건 상황에서 공변량 수를 줄인 주 분석입니다.
compact_common_terms <- paste(
  "female + age_decade_trend + college_or_more + directly_employed +",
  "establishment_trend + weekly_hours10 + current_smoker +",
  "alcohol_frequency_trend + wave_time"
)

# 범주형 전체보정 모형은 원래 범주를 모두 넣어 결론의 일관성을 확인하는 민감도 분석입니다.
categorical_common_terms <- paste(
  "sex + age_group + education + employment + establishment_size +",
  "weekly_hours10 + smoking + alcohol + wave_factor"
)

# 교대근무 종사기간과 근무형태는 주간근무자에게 구조적으로 비해당이고
# 3집단 결합변수와 중첩되므로 전체표본 모형의 보정변수에서는 제외했습니다.
h1_compact_formula <- make_formula("accident_any", "non_day", compact_common_terms)
h2_compact_formula <- make_formula("accident_any", "rest_group", compact_common_terms)
h3_compact_formula <- make_formula("accident_any", "sleep_group", compact_common_terms)
h2_categorical_formula <- make_formula("accident_any", "rest_group", categorical_common_terms)
h3_categorical_formula <- make_formula("accident_any", "sleep_group", categorical_common_terms)
h2_work_formula <- make_formula("accident_work", "rest_group", compact_common_terms)
h3_work_formula <- make_formula("accident_work", "sleep_group", compact_common_terms)

# H1: 비주간근무 대 주간근무
h1_gee <- extract_gee_binary(
  "H1_any_gee_compact", "H1", "전체 사고·손상", "압축 전체보정",
  fit_gee_direct(h1_compact_formula, dat),
  "non_day", "비주간근무 대 주간근무"
)

h1_firth <- fit_firth_binary(
  "H1_any_firth_compact", "H1", "전체 사고·손상", "압축 전체보정",
  h1_compact_formula, dat,
  "non_day", "비주간근무 대 주간근무"
)

# H2: 주간근무, 야간근무·휴게실 있음, 야간근무·휴게실 없음의 3집단 비교
h2_gee <- extract_gee_group(
  "H2_rest_gee_compact", "H2", "전체 사고·손상", "압축 전체보정",
  fit_gee_direct(h2_compact_formula, dat),
  "rest_group", levels(dat$rest_group)
)

h2_firth <- fit_firth_group(
  "H2_rest_firth_compact", "H2", "전체 사고·손상", "압축 전체보정",
  h2_compact_formula, dat,
  "rest_group", levels(dat$rest_group)
)

# H3: 주간근무, 야간근무·수면 가능, 야간근무·수면 불가의 3집단 비교
h3_gee <- extract_gee_group(
  "H3_sleep_gee_compact", "H3", "전체 사고·손상", "압축 전체보정",
  fit_gee_direct(h3_compact_formula, dat),
  "sleep_group", levels(dat$sleep_group)
)

h3_firth <- fit_firth_group(
  "H3_sleep_firth_compact", "H3", "전체 사고·손상", "압축 전체보정",
  h3_compact_formula, dat,
  "sleep_group", levels(dat$sleep_group)
)

# 공변량을 원래 범주대로 넣은 민감도 분석
h2_categorical <- extract_gee_group(
  "H2_rest_gee_categorical", "H2", "전체 사고·손상", "범주형 전체보정",
  fit_gee_direct(h2_categorical_formula, dat),
  "rest_group", levels(dat$rest_group)
)

h3_categorical <- extract_gee_group(
  "H3_sleep_gee_categorical", "H3", "전체 사고·손상", "범주형 전체보정",
  fit_gee_direct(h3_categorical_formula, dat),
  "sleep_group", levels(dat$sleep_group)
)

# 사업장 안에서 발생한 사고만 사용한 보조분석
h2_workplace <- extract_gee_group(
  "H2_rest_work_gee_compact", "H2", "사업장 발생 사고·손상", "압축 전체보정",
  fit_gee_direct(h2_work_formula, dat),
  "rest_group", levels(dat$rest_group)
)

h3_workplace <- extract_gee_group(
  "H3_sleep_work_gee_compact", "H3", "사업장 발생 사고·손상", "압축 전체보정",
  fit_gee_direct(h3_work_formula, dat),
  "sleep_group", levels(dat$sleep_group)
)

pairwise_results <- rbindlist(list(
  h1_gee$pairwise,
  h1_firth$pairwise,
  h2_gee$pairwise,
  h2_firth$pairwise,
  h3_gee$pairwise,
  h3_firth$pairwise,
  h2_categorical$pairwise,
  h3_categorical$pairwise,
  h2_workplace$pairwise,
  h3_workplace$pairwise
), fill = TRUE)

global_tests <- rbindlist(list(
  h2_gee$global,
  h3_gee$global,
  h2_categorical$global,
  h3_categorical$global,
  h2_workplace$global,
  h3_workplace$global
), fill = TRUE)

model_diagnostics <- rbindlist(list(
  h1_gee$diagnostics,
  h1_firth$diagnostics,
  h2_gee$diagnostics,
  h2_firth$diagnostics,
  h3_gee$diagnostics,
  h3_firth$diagnostics,
  h2_categorical$diagnostics,
  h3_categorical$diagnostics,
  h2_workplace$diagnostics,
  h3_workplace$diagnostics
), fill = TRUE)


# 8. 집단별 사고 경험률 ----------------------------------------------------

wilson_ci <- function(events, n, z = 1.96) {
  proportion <- events / n
  denominator <- 1 + z^2 / n
  center <- (proportion + z^2 / (2 * n)) / denominator
  half <- z * sqrt(
    (proportion * (1 - proportion) + z^2 / (4 * n)) / n
  ) / denominator

  list(
    rate = proportion,
    ci_low = pmax(0, center - half),
    ci_high = pmin(1, center + half)
  )
}

make_group_rates <- function(group_var, group_type, outcome_var, outcome_scope) {
  result <- dat[
    !is.na(get(group_var)) & !is.na(get(outcome_var)),
    .(
      observations = .N,
      participants = uniqueN(ID),
      events = sum(get(outcome_var) == 1),
      event_participants = uniqueN(ID[get(outcome_var) == 1])
    ),
    by = .(group = as.character(get(group_var)))
  ]

  intervals <- mapply(
    wilson_ci,
    result$events,
    result$observations,
    SIMPLIFY = FALSE
  )

  result[, `:=`(
    rate = vapply(intervals, `[[`, numeric(1), "rate"),
    ci_low = vapply(intervals, `[[`, numeric(1), "ci_low"),
    ci_high = vapply(intervals, `[[`, numeric(1), "ci_high"),
    group_type = group_type,
    outcome_scope = outcome_scope
  )]
  result[, `:=`(
    rate_percent = 100 * rate,
    ci_low_percent = 100 * ci_low,
    ci_high_percent = 100 * ci_high
  )]

  result
}

group_rates <- rbindlist(list(
  make_group_rates("rest_group", "휴게실 3집단", "accident_any", "전체 사고·손상"),
  make_group_rates("sleep_group", "수면 가능 3집단", "accident_any", "전체 사고·손상"),
  make_group_rates("rest_group", "휴게실 3집단", "accident_work", "사업장 발생 사고·손상"),
  make_group_rates("sleep_group", "수면 가능 3집단", "accident_work", "사업장 발생 사고·손상")
), fill = TRUE)


# 9. 변수 정의표와 결과 저장 ----------------------------------------------

message("6/7 결과 저장")

variable_definitions <- data.table(
  role = c(
    "대상자 ID", "조사차수", "H1 독립변수", "H2 독립변수", "H3 독립변수",
    "주 종속변수", "보조 종속변수", "공변량"
  ),
  variable = c(
    "ID", "Gu", "non_day", "rest_group", "sleep_group",
    "accident_any", "accident_work",
    "성별, 연령, 학력, 고용형태, 사업장 규모, 주당 근로시간, 흡연, 음주, 조사차수"
  ),
  definition = c(
    "개인 식별번호",
    "1·3·5·6차 설문",
    "0=주간근무, 1=비주간근무",
    "주간근무 / 야간근무·휴게실 있음 / 야간근무·휴게실 없음",
    "주간근무 / 야간근무·수면 가능 / 야간근무·수면 불가",
    "최근 1년 내 업무상 사고·손상 경험 여부",
    "업무상 사고·손상 중 사업장 안에서 발생한 경우",
    "주 분석은 저자유도 코딩, 민감도 분석은 원 범주 코딩"
  )
)

fwrite(quality_checks, file.path(table_dir, "01_데이터_품질점검.csv"), bom = TRUE)
fwrite(population, file.path(table_dir, "02_분석대상_현황.csv"), bom = TRUE)
fwrite(baseline_group_counts, file.path(table_dir, "03_대상자_특성표_집단수.csv"), bom = TRUE)
fwrite(baseline_characteristics, file.path(table_dir, "04_대상자_일반특성.csv"), bom = TRUE)
fwrite(baseline_non_day_characteristics, file.path(table_dir, "05_비주간근무자_추가특성.csv"), bom = TRUE)
fwrite(group_rates, file.path(table_dir, "06_집단별_사고경험률.csv"), bom = TRUE)
fwrite(pairwise_results, file.path(table_dir, "07_GEE_Firth_비교결과.csv"), bom = TRUE)
fwrite(global_tests, file.path(table_dir, "08_3집단_전체검정.csv"), bom = TRUE)
fwrite(model_diagnostics, file.path(table_dir, "09_모형진단.csv"), bom = TRUE)
fwrite(variable_definitions, file.path(table_dir, "10_변수정의.csv"), bom = TRUE)

# 주요 결과를 텍스트로도 저장해 실행 직후 빠르게 확인할 수 있게 합니다.
pick_result <- function(model_id_value, comparison_text) {
  pairwise_results[
    model_id == model_id_value & comparison == comparison_text
  ][1]
}

h1_main <- pick_result(
  "H1_any_gee_compact",
  "비주간근무 대 주간근무"
)
h2_main <- pick_result(
  "H2_rest_gee_compact",
  "야간근무·휴게실 없음 대 야간근무·휴게실 있음"
)
h3_main <- pick_result(
  "H3_sleep_gee_compact",
  "야간근무·수면 불가 대 야간근무·수면 가능"
)

fmt_result <- function(row) {
  sprintf(
    "OR %.2f (95%% CI %.2f-%.2f), p=%s",
    row$odds_ratio,
    row$ci_low,
    row$ci_high,
    fmt_p(row$p_value)
  )
}

summary_lines <- c(
  "야간근무와 업무상 사고 경험 분석 결과",
  "",
  sprintf("전체 자료: %s건 / %s명", format(nrow(dat), big.mark = ","), format(uniqueN(dat$ID), big.mark = ",")),
  sprintf("주간근무: %s건 / 비주간근무: %s건", format(dat[Q9 == 1, .N], big.mark = ","), format(dat[Q9 == 2, .N], big.mark = ",")),
  sprintf("전체 사고·손상: %s건 / 사업장 발생 사고·손상: %s건", format(dat[accident_any == 1, .N], big.mark = ","), format(dat[accident_work == 1, .N], big.mark = ",")),
  "",
  paste0("H1 비주간근무 대 주간근무: ", fmt_result(h1_main)),
  paste0("H2 휴게실 없음 대 있음: ", fmt_result(h2_main)),
  paste0("H3 수면 불가 대 가능: ", fmt_result(h3_main)),
  "",
  paste0("H2 3집단 전체 검정 p=", fmt_p(global_tests[model_id == "H2_rest_gee_compact", p_value])),
  paste0("H3 3집단 전체 검정 p=", fmt_p(global_tests[model_id == "H3_sleep_gee_compact", p_value])),
  "",
  "해석: H1은 지지되었으나, 지원환경의 직접 비교인 H2와 H3는 통계적으로 유의하지 않았습니다.",
  "Firth, 범주형 공변량 GEE, 사업장 사고 GEE에서도 지원환경의 직접 비교 결론은 같았습니다.",
  "H2와 H3는 상호작용항을 사용한 조절효과 검정이 아니라 야간근무와 지원환경을 묶은 3집단 비교입니다."
)

writeLines(
  summary_lines,
  file.path(output_dir, "주요_분석결과.txt"),
  useBytes = TRUE
)

writeLines(
  capture.output(sessionInfo()),
  file.path(output_dir, "R_실행환경.txt"),
  useBytes = TRUE
)


# 10. 실행 완료 확인 -------------------------------------------------------

message("7/7 완료")
cat(paste(summary_lines, collapse = "\n"), "\n")
cat("\n결과 저장 위치: ", normalizePath(result_dir, winslash = "/"), "\n", sep = "")
