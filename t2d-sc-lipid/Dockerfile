# syntax=docker/dockerfile:1.7
# ============================================================================
# t2d-sc-lipid 的 R 运行环境（snRNA-seq 注释流水线，Seurat v5）。
# 对应项目：https://github.com/CYL-Logan-Lab/t2d-sc-lipid
#
# ── 可复现性的单位是**产出的镜像**，不是"重跑 build 得到同样的东西" ─────────
# 下游项目按 digest 引用镜像，digest 是内容寻址的，所以「这次分析用的环境是什么」
# 永远有确切答案。这份 Dockerfile 的职责是：让镜像**能被建出来**，并且建出来的
# 东西**符合它自己的声明**（版本对不上就 build 失败）。它不承诺半年后重跑一遍
# 会得到逐字节相同的镜像 —— 见下面第 3 层的说明。
#
# ── 三层 pin ────────────────────────────────────────────────────────────────
#   1. 基础镜像按 **OCI manifest digest** 取，不按 :5.5.1 标签。标签是可变引用 ——
#      维护者重推同名标签，拿到的就是另一个镜像，且不会有任何提示；digest 不可变。
#      R 4.5.2 / Seurat 5.5.1 由这一层决定，装包脚本开头会**断言**这两个版本：
#      基础镜像若被换掉，build 当场失败，而不是悄悄产出一个别的环境。
#   2. CRAN 走 Posit 的**按日期冻结**快照（Ubuntu noble 二进制包）。换成
#      cloud.r-project.org 这类滚动镜像的话，同一份 Dockerfile 今天和半年后
#      装到的不是同一份代码。
#   3. Bioconductor 没有按日期的快照服务，只有按 release 分支（3.22）的仓库 ——
#      Bioc 版本由下面那个 URL 钉死，但 release 分支**内部**仍会滚出补丁版本。
#      所以对直接依赖**逐个断言版本号**，对不上就让 build 失败。
#      要说清楚这一层的边界：断言只覆盖点名的那些包，Bioc 拖进来的**传递依赖**
#      没有被钉住，它们的补丁版本漂移不会让 build 失败，只会体现在镜像里的
#      /opt/Renv-manifest.tsv 上。所以"同一份配方重建两次得到同一个环境"这句话
#      对本文件**不成立**；成立的是"下游按 digest 用到的一直是同一个环境"。
#      断言炸了是在提醒「上游动了」：把新版本号写进 PKG_PINNED 重新 build，
#      **不要**删掉断言。
#
# ── 为什么要往 satijalab/seurat 上加东西 ────────────────────────────────────
# 项目要做核级双细胞打分（scDblFinder）。基础镜像里没有它，也没有它依赖的
# scran / scuttle / scater / bluster / edgeR / BiocNeighbors / BiocSingular /
# metapod / ScaledMatrix，以及 CRAN 的 xgboost。
#
# ── 冒烟测试不在这里 ────────────────────────────────────────────────────────
# 下面的装包层里会 library() 一遍，但那只在**该层真正被构建时**才跑：层命中缓存
# 时整层跳过，写成单独一个 RUN 也一样跳过（缓存是沿父层顺序匹配的）。要"每次 CI
# 都真的验证一遍"，就必须在 Dockerfile 之外跑 —— 见 .github/workflows/build.yml
# 的冒烟测试步骤，它 docker run 本次真正产出的那个镜像。
# ============================================================================
FROM satijalab/seurat@sha256:048d965487afc2961c450879692281a73e24f6de47360ed2f11b31112ebd844e

LABEL org.opencontainers.image.source="https://github.com/CYL-Logan-Lab/docker-images"
LABEL org.opencontainers.image.description="R env for CYL-Logan-Lab/t2d-sc-lipid: Seurat 5.5.1 + scDblFinder"
LABEL org.opencontainers.image.base.name="satijalab/seurat@sha256:048d965487afc2961c450879692281a73e24f6de47360ed2f11b31112ebd844e"

ENV LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

# 安装脚本以文件形式落进镜像（而不是 RUN 的 stdin 堆文档）：Rscript 不从标准输入
# 读脚本，必须给它一个文件路径。顺带的好处是这份配方连同镜像一起留存，事后在容器里
# 就能查「这个环境是怎么装出来的」。
COPY <<'EOF' /opt/install-Rpkgs.R
# ── 第 1 层 pin 的断言：基础镜像必须还是那个基础镜像 ──────────────────────────
# FROM 写的是 digest，正常情况下不会变；但这份文件顶部**用文字声明了** R 4.5.2 /
# Seurat 5.5.1，声明就应该可执行。哪天有人把 digest 换成新的却忘了改文字说明，
# 这里会当场炸掉。
stopifnot(
  getRversion() == "4.5.2",
  utils::packageVersion("Seurat") == "5.5.1"
)

# 用 install.packages 而不是 BiocManager::install：两个仓库直接挂在 repos 上，
# Bioc 包的 CRAN 依赖也就跟着落进冻结快照，来源在一处说清楚。
# （BiocManager::install(ask = FALSE, update = FALSE) 也能做到不交互、不升级，
# 这里只是不想为一件事引入第二套解析逻辑。）
# Bioc 版本由这个 URL 钉死，不依赖镜像里 BiocManager 的默认值。
options(repos = c(BIOC = "https://bioconductor.org/packages/3.22/bioc",
                  CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/2026-08-06"),
        Ncpus = 4)

# 按依赖顺序列出只是给人看的，真正的顺序由 install.packages 自己解析依赖决定。
PKG_PINNED <- c(
  xgboost       = "3.2.1.1",   # CRAN 快照
  BiocNeighbors = "2.4.0",
  BiocSingular  = "1.26.1",
  ScaledMatrix  = "1.18.0",
  metapod       = "1.18.0",
  edgeR         = "4.8.2",
  scuttle       = "1.20.0",
  bluster       = "1.20.0",
  scran         = "1.38.1",
  scater        = "1.38.1",
  scDblFinder   = "1.24.10"
)

install.packages(names(PKG_PINNED))

# ── 断言：装上的必须就是 Dockerfile 写的那几个版本 ────────────────────────────
# 这一段不能省：install.packages() 装不上时**只发警告、照样退出 0**，没有断言的话
# build 会一路成功、镜像正常出厂，直到几个月后跑分析才发现包根本不在。
# 下面既查「装没装上」，也查「是不是那个版本」。
got <- vapply(names(PKG_PINNED), function(p)
  tryCatch(as.character(utils::packageVersion(p)),
           error = function(e) NA_character_), character(1))
bad <- is.na(got) | got != PKG_PINNED
if (any(bad)) {
  stop("包版本与 Dockerfile 不符：\n",
       paste(sprintf("  %-14s 期望 %-10s 实得 %s",
                     names(PKG_PINNED)[bad], PKG_PINNED[bad],
                     ifelse(is.na(got[bad]), "<未装上>", got[bad])),
             collapse = "\n"),
       "\n上游动过了。把新版本号写进 PKG_PINNED 重新 build，不要删掉这段断言。")
}

# 能装上 ≠ 能加载：C 层依赖缺失时装是装上了，library() 才炸。
# 注意这只在**这一层真正被构建时**执行；层命中缓存时不会跑。每次 CI 都要验证的
# 那一遍在 workflow 里，见文件顶部说明。
invisible(lapply(names(PKG_PINNED), function(p)
  library(p, character.only = TRUE, quietly = TRUE)))

# ── 清单烧进镜像 ────────────────────────────────────────────────────────────
# 记的是**整个库**而不只是上面点名的那几个：Bioc 会拖进一串传递依赖，而那些依赖
# 恰恰是断言没覆盖到的部分 —— 清单管不住它们，但至少能事后回答「那次用的到底是
# 哪个版本」。出问题时要查的往往正是这些没人点名的包。
bioc <- tryCatch(as.character(BiocManager::version()),
                 error = function(e) "(BiocManager 不在镜像里)")
ip <- utils::installed.packages()[, c("Package", "Version", "LibPath"), drop = FALSE]
ip <- ip[order(ip[, "Package"]), , drop = FALSE]
dir.create("/opt", showWarnings = FALSE)
writeLines(c("# 本镜像的 R 包清单，build 时由 /opt/install-Rpkgs.R 生成",
             paste0("# R: ", R.version.string),
             paste0("# BiocManager: ", bioc),
             paste0("# CRAN: ", getOption("repos")[["CRAN"]]),
             paste0("# Bioc repo: ", getOption("repos")[["BIOC"]]),
             "package\tversion\tlibpath",
             apply(ip, 1, paste, collapse = "\t")),
           "/opt/Renv-manifest.tsv")
cat("清单写入 /opt/Renv-manifest.tsv，共", nrow(ip), "个包\n")
EOF

RUN Rscript --vanilla /opt/install-Rpkgs.R \
 && chmod 0444 /opt/Renv-manifest.tsv /opt/install-Rpkgs.R
