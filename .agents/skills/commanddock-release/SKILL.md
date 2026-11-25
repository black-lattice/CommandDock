---
name: commanddock-release
description: 在 CommandDock 项目中说“发布新版”“发个版本”或指定发布版本时使用。自动更新版本与发布说明、推送 main 和标签，跟进 GitHub Actions 直到正式 Release 和 Sparkle 更新源可用。
---

# 发布 CommandDock

从仓库根目录执行。用户要求“发布新版”即授权完成本次发版；默认发下一个稳定补丁版，用户指定的版本优先。打包、签名和发布交给 GitHub Actions，本机安装按用户单独要求执行。

1. **确定本次范围。** 检查工作区、分支、远端及上游；获取 `origin/main`、远端版本标签和最新正式 Release。以同步后的发布分支 `main` 为基线，查看上一正式版至今的提交和本次待发布修改；仅纳入本次发布内容。保留无关改动。若是继续此前未完成的发布，先核对已有发版提交、目标标签、Release 和运行状态，按原有标签和 SHA 接着执行第 4、5 步。若该提交已正式发布且没有新的待发改动，直接验收已有版本并结束。若只准备了版本文件或本地提交，沿用该版本完成剩余步骤。
2. **定版并写记录。** 未指定版本时，按稳定版本号递增 patch，确认新标签未被占用；既有标签指向另一提交时不得覆盖。把 `scripts/build.sh` 中的 `VERSION` 默认值和 `.github/workflows/build.yml` 中非标签打包的 `VERSION` 默认值同步为新版本。标签构建实际从 `vX.Y.Z` 取版本；`CFBundleVersion` 由 CI 的 `github.run_number` 生成，无需手填。新增 `.github/release-notes/vX.Y.Z.md`，用中文按用户可见变化写具体更新；该文件同时用于 GitHub Release 和 Sparkle 内嵌说明。
3. **提交与推送。** 核对两处版本、说明、暂存文件和 `git diff --cached --check`。使用中文提交并创建带说明的 `vX.Y.Z` 标签，首次推送用 `git push --atomic origin main "refs/tags/$tag"`（`tag` 为实际版本标签）。如本地忽略规则隐藏新建的发布说明，仅对该文件定向添加。恢复发布时复用已匹配的提交和标签；推送失败后先核对远端状态，不强推或移动远端标签。
4. **跟进标签 CI。** 推送后核对远端标签解引用后的 SHA。用 `gh run list --workflow build.yml --event push --commit "$sha" --json databaseId,headBranch,headSha,status,conclusion` 查找同时匹配标签名和 SHA 的 run；同一提交的 main run 也会打包，但不会发布。新 run 尚未出现时稍后再查。用 `gh run watch "$run_id" --exit-status` 跟进至结束。若网络中断则重连同一 run；失败时读失败 job 日志，临时性错误可重跑失败 job，签名密钥等缺失时报告阻塞。若需要修改已打标签的代码，保留原标签，修复后选未占用的新版本继续。避免重复创建 Release。
5. **验收实际发布。** 确认双架构测试、Universal 打包和发布 job 均成功；通过 `gh release view "$tag" --json url,tagName,isDraft,isPrerelease,assets` 确认正式版可见且四份附件均已上传、非空：`CommandDock-X.Y.Z-universal.dmg`、`CommandDock-X.Y.Z-universal.zip`、`SHA256SUMS.txt`、`appcast.xml`。检查 latest Release 指向本次标签，实际访问 `releases/latest/download/appcast.xml`，核对清单中的显示版本、构建号及指向本次通用 ZIP 的下载地址。签名验证由标签工作流的 `scripts/generate-appcast.py` 执行；保留现有密钥与公钥。汇报版本、提交 SHA、CI 与 Release 链接及验收结果。
