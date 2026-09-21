# TypeSafe：Jev   Jev决策模型安装调用使用  Windows save-token-jev setup

这是一个面向 Windows Codex 的安装与验证 Skill，用来安全部署用户级
[`save-token-jev`](https://github.com/IAmUnbounded/save-token-jev-clean) Hooks。

它帮助 Codex 完成以下流程：

1. 在手动或自动压缩前，由 `PreCompact` Hook 调用 Jev，从当前会话中筛选值得保留的工具记录。
2. Codex 继续执行自己的原生上下文压缩。
3. 压缩后的 `SessionStart(compact)` Hook 把本次选中的内容补入后续模型请求。
4. 独立检查旧 sidecar，避免准备失败时错误恢复上一次会话的旧内容。

> [!IMPORTANT]
> `npx` 或 `git clone` **只安装这个 Codex Skill**。它们不会直接安装或配置
> `save-token-jev`，不会写入 `hooks.json`，不会设置 API Key，不会信任 Hook，也不会执行
> `/compact`。安装 Skill 后，还要重启 Codex，再明确调用 Skill 完成配置。

## 前置条件

- Windows 10/11。
- Codex 桌面版或 Codex CLI。
- Node.js 20 或更高版本，包含 `npm` 和 `npx`。
- Git。
- 一个可用的 OpenRouter API Key；不要把 Key 发到聊天、命令参数或仓库中。

### 使用 winget 安装 Node.js LTS 和 Git

在 PowerShell 中运行：

```powershell
winget install --id OpenJS.NodeJS.LTS -e --source winget
winget install --id Git.Git -e --source winget
```

安装后关闭并重新打开 Windows Terminal，再验证：

```powershell
node --version
npm --version
npx --version
git --version
```

`node --version` 应显示 `v20` 或更高版本；其他命令都应正常显示版本号。如果 `node`
可用但 `npm`/`npx` 报找不到模块，通常是 Node.js 安装不完整或旧 PATH 冲突。先完全重启
Terminal；仍失败时，通过“设置 → 应用 → 已安装的应用”修复或卸载 Node.js，再用上面的
winget 命令重装 LTS 版本。

## 推荐：一条 npx 命令安装或更新 Skill

```powershell
npx --yes github:455-dIAO/windows-save-token-jev-setup
```

安装器按以下顺序确定目标位置：

- 当前进程设置了 `CODEX_HOME`：安装到
  `$env:CODEX_HOME\skills\windows-save-token-jev-setup`；
- 未设置 `CODEX_HOME`：安装到
  `%USERPROFILE%\.codex\skills\windows-save-token-jev-setup`。

重复执行同一命令会更新 Skill 管理的文件。它使用固定白名单，不复制 `.git`、
`node_modules`、备份、日志、`.env`、密钥或其他无关内容；也不会删除目标目录中不属于本
Skill 的文件。

检查安装结果：

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$skillPath = Join-Path $codexHome 'skills\windows-save-token-jev-setup'
Test-Path (Join-Path $skillPath 'SKILL.md')
Get-ChildItem -LiteralPath $skillPath
```

`Test-Path` 应返回 `True`。

## 备选：使用 Git clone 安装

首次安装：

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$skillsRoot = Join-Path $codexHome 'skills'
$skillPath = Join-Path $skillsRoot 'windows-save-token-jev-setup'

New-Item -ItemType Directory -Force -Path $skillsRoot | Out-Null
git clone https://github.com/455-dIAO/windows-save-token-jev-setup.git $skillPath
```

如果该目录是用 Git clone 创建的，以后可更新：

```powershell
git -C $skillPath pull --ff-only
```

如果目录之前由 `npx` 安装，没有 `.git`，请继续用 `npx` 更新，不要在非空目录上运行
`git clone`。

## 调用 Skill 完成 save-token-jev 配置

1. 完全退出 Codex 桌面版，并关闭所有正在运行的 Codex CLI。
2. 重新打开 Codex。
3. 在新任务中输入：

```text
使用 $windows-save-token-jev-setup 帮我安装并配置用户级 save-token-jev。
```

Skill 会先说明数据传输边界并征得同意，然后检查实际 `CODEX_HOME`、Node.js、npm、Git、
OpenRouter 用户环境变量和现有配置。它会备份相关设置、构建上游项目、幂等合并两个 Hook，
并运行不触发真实压缩的配置检查。

### OpenRouter Key

不要在聊天里粘贴 Key。Skill 会在需要时引导你从本 Skill 目录运行交互式脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-OpenRouterKey.ps1
```

脚本只把 Key 写入 Windows 当前用户环境变量 `OPENROUTER_API_KEY`。后续配置会从该用户变量
复制到 `TYPESAFE_API_KEY`，不会把明文写进 `hooks.json`、`AGENTS.md`、项目、源码或备份。

## Hook 配置和信任

配置完成后，必须完全退出并重新打开 Codex，确保新进程读取用户环境变量。然后在 Codex CLI
交互界面输入：

```text
/hooks
```

逐项查看并信任，不能绕过确认：

- `PreCompact`：matcher 为 `manual|auto`，timeout 为 `120s`；
- `SessionStart`：matcher 为 `compact`，timeout 为 `10s`，context limit 为 `200000`。

两项命令都应类似：

```text
node "<实际安装目录>/dist/cli.js" hook codex
```

命令中不能残留 `${PLUGIN_ROOT}`。只有详情页显示 `Trusted`，总览显示 `Installed 1 / Active 1`，
才能说 Hook 已信任。`hooks.json` 中存在配置不代表已经信任。

完整操作见 [信任与真实压缩验证](references/trust-and-e2e.md)。

## 真实运行测试

配置检查通过不等于真实运行成功。请在新的空目录、新的 Codex CLI 会话里，用不含私人内容的
唯一标记完成一次测试；工具记录产生后，由你本人手动输入：

```text
/compact
```

检查必须覆盖：

- `PreCompact` 确实产生本次新的 Jev history/sidecar 记录；
- Codex 执行的是原生压缩，而不是把 `/compact` 当成普通聊天消息；
- 压缩后的请求收到本次 `<save-token-jev-context>`；
- 恢复内容包含本次标记和对应工具输出；
- 另一个全新任务没有收到上一次的旧标记。

如果只有 Codex 原生压缩证据，必须明确报告“只执行了 Codex 原生压缩”；不能把 CLI 成功直接
当成桌面版也已生效。

## 状态应该分别判断

| 状态 | 最低证据 |
| --- | --- |
| Skill 已安装 | 目标 Skills 目录存在有效 `SKILL.md` |
| save-token-jev 已安装 | 上游构建产物 `dist/cli.js` 存在且程序可执行 |
| 已配置 | `hooks.json`、两个 Hook 和用户环境变量检查通过 |
| 已信任 | `/hooks` 中两项均显示 `Trusted` 和 `Active` |
| 合成回归通过 | 旧 sidecar 防串回测试通过 |
| 真实运行已验证 | 本次筛选、原生压缩、恢复和跨任务隔离证据全部齐全 |

不能确认的状态应直接写“无法确认”。

## 常见问题

### `npx` 或 `npm` 无法运行

重新打开 Terminal 后再次检查 `node --version`、`npm --version`、`npx --version`。若仍失败，
修复或重装 Node.js LTS，并确认 PATH 中没有抢在新版 Node.js 前面的旧 `npm`/`npx`。

### npx 安装到了意外目录

在运行 npx 的同一个 PowerShell 中检查：

```powershell
$env:CODEX_HOME
[Environment]::GetEnvironmentVariable('CODEX_HOME', 'User')
```

npx 使用当前进程的 `CODEX_HOME`；如果它与桌面版启动时继承的用户变量不同，先统一配置并
完全重启 Codex。不能仅凭 CLI 中看到 Skill 就认定桌面版使用同一份配置。

### `/hooks` 中显示 `New`、`Changed` 或需要 review

这是正常的安全确认。进入每一项查看命令、matcher 和 timeout，确认无误后再手动信任。更新
导致命令变化时应重新审查，不要一键绕过。

### 输入 `/compact` 后只显示普通消息

这不能算真实压缩测试。请在 Codex CLI TUI 中重新测试，并检查当前版本是否支持该命令。

### Jev 准备失败或没有恢复内容

检查 Hook 是否 Active/Trusted、当前进程是否读到用户环境变量、OpenRouter 是否可访问，以及
Jev history/sidecar 是否为本次新记录。准备失败时不得恢复旧 sidecar；若证据不足，只能报告
Codex 原生压缩是否执行。

## 安全边界

- `PreCompact` 会把待筛选的会话/工具记录发送给配置的 Jev/OpenRouter 端点；安装前必须知情同意。
- API Key 只存 Windows 用户环境变量，不写入仓库、Hook、项目或备份。
- Skill 安装器和 save-token-jev 安装器都不会自动建立 Hook 信任记录。
- `/compact` 只能由用户手动输入。
- 保留现有 `AGENTS.md`、JevRouter 技能、其他 Hook 和无关配置。
- “配置完成”“已信任”“合成验证通过”“真实压缩验证成功”必须分开报告。

## 卸载 Skill

只删除这个 Skill 目录不会自动删除已配置的 save-token-jev 或 Hook。先确认目标路径，再手动处理：

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$skillPath = Join-Path $codexHome 'skills\windows-save-token-jev-setup'
$skillPath
```

不要把删除 Skill 误认为已经撤销 Hook 或环境变量；这些是不同状态，应另行审查和处理。
