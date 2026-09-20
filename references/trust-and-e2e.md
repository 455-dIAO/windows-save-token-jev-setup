# 信任与真实压缩验证

安装脚本不会创建信任记录，也不会执行 `/compact`。以下步骤必须由用户本人完成。

## 1. 完全重启

1. 完全退出 Codex 桌面版，不只是关闭当前任务。
2. 关闭所有正在运行的 `codex` CLI。
3. 重新打开 Windows Terminal。
4. 运行 `codex`。

这一步确保新进程读取 Windows 用户环境变量和同一份用户级 Codex 配置。

## 2. 逐项信任

在 Codex CLI 交互界面输入：

```text
/hooks
```

选择 `Review hooks`，不要选择一键全部信任，也不要使用绕过信任参数。

逐项核对并信任：

- `PreCompact`
  - matcher：`manual|auto`
  - timeout：`120s`
- `SessionStart`
  - matcher：`compact`
  - timeout：`10s`
  - context limit：`200000`

两项命令都必须是：

```text
node "<实际安装目录>/dist/cli.js" hook codex
```

不应残留 `${PLUGIN_ROOT}`。最终总览必须显示：

```text
PreCompact    Installed 1    Active 1
SessionStart  Installed 1    Active 1
```

如果 Hook 显示 `New` 或 `Changed`，说明内容需要重新审查；不要把“已配置”当成“已信任”。

## 3. 全新 CLI 隔离测试

使用新的空目录和新的 Codex CLI 任务。不要在已有长对话中测试，否则旧标记本来就在历史里，无法判断是否发生串回。

```powershell
$testRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Codex\jev-e2e-test'
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
Set-Location $testRoot
codex
```

在 CLI 内输入一段不含私人内容的唯一标记，例如：

```text
这是全新的 Jev 隔离测试。唯一标记：JEV-E2E-CURRENT-PURPLE。最终颜色是紫色。
请用终端执行：Write-Output "tool-record:JEV-E2E-CURRENT-PURPLE"
然后只回复“已记录”。
```

工具执行完成后，由用户在同一个 CLI 中手动输入：

```text
/compact
```

不要让自动化脚本代替用户输入该命令。

## 4. 判定证据

只有同时满足以下条件，才能写“真实运行已验证”：

1. Codex 产生原生 compaction 事件，而不是把 `/compact` 当普通聊天消息。
2. `%TEMP%\save-token-jev\codex\history.jsonl` 出现本次运行的新记录。
3. 本次会话对应的 sidecar 创建时间晚于测试开始时间。
4. 压缩后的下一次模型请求收到 `<save-token-jev-context>`。
5. 恢复内容包含当前唯一标记和对应工具输出。
6. 新任务不包含之前测试任务的旧标记。

如果只有第 1 项，明确写“只执行了 Codex 原生压缩”。

桌面版输入 `/compact` 如果作为普通消息发送，不能算测试。此时使用 CLI TUI 重新测试。桌面版和 CLI 是否共享配置，应通过有效 `CODEX_HOME` 和实际用户配置目录核对，不能仅凭 CLI 成功推断桌面版成功。

## 5. 结果措辞

分别报告：

- 安装：文件是否存在、构建是否通过。
- 配置：JSON、两个 Hook、环境变量是否正确。
- 信任：两项是否在 `/hooks` 中显示 Trusted 和 Active。
- 合成验证：旧 sidecar 回归测试是否通过。
- 真实验证：是否出现真实 PreCompact、原生 compaction、SessionStart 恢复和跨任务隔离证据。

无法确认的项目直接写“无法确认”，不要用 CLI 已成功代替桌面版结论。
