# 龙虾卫士官网与发布入口

本仓库仅承载龙虾卫士的公开官网、用户帮助和 GitHub Release 发布门禁。

- 公开仓库：<https://github.com/hammercui/ham-claw-site>
- GitHub Pages：<https://hammercui.github.io/ham-claw-site/>

## 当前阶段

- 官网与发布底座建设中。
- 首个公开版本尚未发布；页面会如实显示“准备中”。
- 首发平台：Windows 10/11 x64。

## 公开内容边界

本仓库只保存公开网站源码、公开帮助内容和用于验证已签名安装包的发布工具。以下内容不得提交：

- 签名私钥、证书、API Key、令牌和未脱敏日志；
- 非公开的研发管理资料；
- 本机路径、非公开服务地址、内部仓库名称或提交标识；
- 应用源码、构建输入和未经发布门禁确认的安装包。

## 本地运行

```powershell
npm install
npm run dev
```

提交前执行：

```powershell
npm run test:public-surface
npm run test:release-contract
npm run test:release-publisher
npm run build
```

`scripts/New-PublicReleaseBundle.ps1` 只接收已签名的候选产物，进行字节不变复制、公开元数据生成和完整性验证；本仓库不保存或使用签名私钥。

## GitHub Pages 配置

仓库 Variables：

- `SITE_URL`：站点 origin，GitHub Pages 默认值为 `https://hammercui.github.io`。
- `BASE_PATH`：项目 Pages 路径，当前为 `/ham-claw-site`。
- `PUBLIC_GITHUB_URL`：公开仓库地址；未配置时不显示 GitHub 入口。
- `PUBLIC_SUPPORT_EMAIL`：公开支持邮箱；未配置时不显示邮箱。

正式发布前，网站会保持“准备中”，Release 也只创建为 Draft。
