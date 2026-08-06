# docker-images

CYL-Logan-Lab 各个项目的计算环境配方。**一个 project 一个目录，目录里一个 Dockerfile。**
目录名跟这个 project 的仓库名对齐，一眼能看出对应关系。

镜像由 GitHub Actions 构建、推到 GHCR（public，拉取不需要登录）：

```
ghcr.io/cyl-logan-lab/<目录名>
```

| 目录 | 用于 | 内容 |
|---|---|---|
| [`t2d-sc-lipid/`](t2d-sc-lipid/Dockerfile) | [CYL-Logan-Lab/t2d-sc-lipid](https://github.com/CYL-Logan-Lab/t2d-sc-lipid) | R 4.5.2 / Seurat 5.5.1 / Bioconductor 3.22 + scDblFinder |

## 下游项目怎么引用

**按 digest，不要按标签。** 标签是可变引用 —— 同名标签被重推之后，你拿到的是另一个
镜像，而且没有任何提示；digest 是内容寻址的，不可变。`:latest` 只用来给人看「哪个是
最新的」，不用来固定环境。

digest 在每次发布构建的任务摘要里（Actions → 那次 run → Summary），也可以直接查：

```bash
docker buildx imagetools inspect ghcr.io/cyl-logan-lab/t2d-sc-lipid:latest
```

拉取：

```bash
docker pull ghcr.io/cyl-logan-lab/t2d-sc-lipid@sha256:<digest>

# 没有 docker 权限的机器上用 Singularity/Apptainer（GHCR 是 public，无需登录）
singularity pull env.sif docker://ghcr.io/cyl-logan-lab/t2d-sc-lipid@sha256:<digest>
```

然后把这个 digest 写进下游项目自己的环境脚本里，由那边做校验。

## 可复现性的边界（先说清楚）

**可复现的单位是产出的镜像，不是「重跑一次 build 得到同样的东西」。** 下游按 digest
引用，所以「那次分析用的环境到底是什么」永远有确切答案。配方的职责是让镜像能被建出来，
并且建出来的东西**符合它自己的声明**。

具体说：直接依赖的版本被逐个断言，对不上就 build 失败；但 Bioconductor 拖进来的
**传递依赖**没有被钉住，它们的补丁版本漂移不会让 build 失败，只会体现在镜像里的
`/opt/Renv-manifest.tsv`。所以同一份配方隔半年重建，**可能**得到一个略有差异的环境 ——
这正是为什么下游必须按 digest 引用，而不是「照配方自己建一个」。

## 三层 pin

每个 Dockerfile 都要能独立回答「这个环境是什么」。做不到三层 pin 的配方，等于只是
「大概装了这些包」：

1. **基础镜像按 digest 取**，不按标签；并在装包脚本开头**断言** R / Seurat 版本 ——
   顶部注释里用文字声明的东西，应该是可执行的。
2. **CRAN 走按日期冻结的快照**（Posit Package Manager），不用滚动镜像。
3. **Bioconductor 没有按日期的快照服务**，版本由 release 分支的 URL 钉死，但分支内部
   仍会滚出补丁版本 —— 所以对直接依赖**逐个断言版本号**，对不上就让 build 失败。
   断言炸了是在提醒「上游动了」：把新版本号写进配方重新 build，**不要**删断言。

另外两条约定：

- **冒烟测试放在 Dockerfile 之外**，由 CI 在 build 之后 `docker run` 本次真正产出的
  镜像。写成镜像里的一层是没用的：层命中缓存就整层跳过，这次 build 其实一个 R 进程
  都没跑过，却看起来「验证过了」。发布构建按 digest 把镜像拉回来跑，连推上去的东西
  本身一起验。
- **把包清单烧进镜像**（`/opt/Renv-manifest.tsv`），记整个库而不只是点名的那几个 ——
  断言覆盖不到的传递依赖，至少能事后查出「那次用的是哪个版本」。

## 加一个新环境

1. 新建目录，名字用下游 project 的仓库名（只允许小写字母、数字，以及 `.` `_` `-`
   作分隔 —— CI 会卡这个格式，GHCR 的仓库路径必须小写）。
2. 写 `<目录>/Dockerfile`，照着 `t2d-sc-lipid/Dockerfile` 的三层 pin 来。
3. 在上面的表格里加一行。
4. 开 PR —— CI 会 build 并跑冒烟测试，但不 push。合进 `main` 之后才推 GHCR。

只想手动重建某一个：Actions → build → Run workflow，填目录名（留空则全建）。
**手动触发不会发布**，只验证配方 —— 否则在功能分支上点一下就能把未合并的东西推上
GHCR 并覆盖 `:latest`。

## CI 什么时候会 build

- 改了某个镜像目录里的任何文件 → 只 build 那个目录。
- 改了 `.github/` 下的东西 → 全部重建（构建方式变了，等于所有镜像都受影响）。
- 分支首次 push 或拿不到可比较的基线 → 全部重建（宁可全建，也不要静默漏建）。

发布（推 GHCR）**只发生在 push 到 `main`**。PR 和手动触发都只 build 不 push。
