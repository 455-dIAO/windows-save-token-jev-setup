# Windows save-token-jev setup

用于在 Windows 上安全安装、配置和验证用户级 Codex `save-token-jev` Hooks 的 Codex Skill。

上游项目：<https://github.com/IAmUnbounded/save-token-jev-clean>

## 安装 Skill

将本仓库克隆到 Codex Skills 目录：

```powershell
$skillsRoot = if ($env:CODEX_HOME) {
    Join-Path $env:CODEX_HOME 'skills'
} else {
    Join-Path $env:USERPROFILE '.codex\skills'
}

New-Item -ItemType Directory -Force -Path $skillsRoot | Out-Null
git clone https://github.com/455-dIAO/windows-save-token-jev-setup.git (Join-Path $skillsRoot 'windows-save-token-jev-setup')
```

完全重启 Codex 后输入：

```text
使用 $windows-save-token-jev-setup 帮我安装并配置用户级 save-token-jev。
```

## 安全边界

- API Key 只保存在 Windows 用户环境变量中，不写入仓库、Hook、项目或备份。
- 安装器不会自动信任 Hook，也不会绕过信任确认。
- `/compact` 必须由用户手动输入。
- 安装完成、Hook 已信任、合成测试成功和真实压缩验证会分别报告。
- 安装器会应用并验证旧 sidecar 防串回保护。

详细流程见 [SKILL.md](SKILL.md) 和 [信任与真实压缩验证](references/trust-and-e2e.md)。
