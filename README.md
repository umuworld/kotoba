# Kotoba · 日语伴学

把日语留在身边。一个原生 macOS 悬浮字幕与 AI 学习工具。

Native Japanese-learning companion for macOS: floating live captions, grammar explanations, vocabulary, and contextual AI questions. Built with Swift, AppKit and SwiftUI, without third-party runtime dependencies.

**视频留在原来的浏览器里。** 把 Kotoba 拖到 B 站选集栏、网页旁边或任意位置，看剧时字幕逐句出现；点击一句，才打开翻译、语法、生词与追问面板。它不是内嵌播放器，也不修改视频网站。

> 早期版本：需要 Apple Silicon 与 macOS 26+。目前推荐从源码构建；没有已公证的通用安装包。识别与 AI 输出可能有误，请作为学习辅助使用。

## 功能

- **独立悬窗**：字幕窗和解析窗可分别拖动、调整长宽，支持置顶并记住位置。
- **稳定磨砂**：背景色彩透入，但材质不随点击或输入切换；支持底色浓淡调节及系统“减少透明度”。
- **声音字幕**：采集 Chrome、Safari、Edge 或系统声音；默认在设备端用 Apple SpeechAnalyzer / SpeechTranscriber 识别。
- **点击学习**：中文翻译、语法解释、活用、生词与 JLPT 参考等级。按住 Shift 连选多句。
- **连续追问**：围绕当前句子保留问答上下文；切换句子会重置上下文。
- **多 AI 服务商**：DeepSeek、OpenAI、Claude、Gemini、通义千问、Kimi、OpenRouter、Ollama 和自定义接口。
- **本地学习记录**：字幕导入、粘贴、朗读、收藏、SRT 导出及 Markdown 笔记导出。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| 系统 | macOS 26 或更新版本 |
| 处理器 | Apple Silicon（arm64）；暂不提供 Intel 构建 |
| 工具链 | Xcode 26+ 或带有 macOS SDK 26+ 的 Command Line Tools |
| 测试工具 | Python 3、curl（仅本机接口测试使用） |
| AI | 云服务 API Key，或已运行并准备好模型的本机 Ollama |

首次设备端识别可能需要从 Apple 下载语言模型。AI 平台的聊天会员不等于 API 额度；模型是否可用取决于账户、地域及服务商，预设模型名可编辑。

## 从源码运行

```sh
git clone https://github.com/umuworld/kotoba.git
cd kotoba
bash build.sh
open dist/Kotoba.app
```

构建产物只写入仓库内的 `.build/` 与 `dist/`，不会覆盖「应用程序」中的版本。应用图标由 `Tools/generate_icon.swift` 本地生成。

默认使用临时签名，适合自行构建。若已有合法安装的稳定签名身份，可使用：

```sh
KOTOBA_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" bash build.sh
```

签名不等于公证。面向其他用户分发可下载的应用，需要单独配置合适的开发者签名与 Apple 公证；不要关闭 Gatekeeper 或降低系统安全设置来运行。

## 第一次使用

1. 将字幕悬窗放到浏览器右侧，拖动顶部空白区域移动，拖边缘或右下角调整大小。
2. 在设置中选择声音来源与识别语言；看日语内容选日语，中文讲解选中文，当前一次识别一种语言。
3. 点击「开始聆听」，完成 macOS 的屏幕与系统音频录制授权；如使用 Apple 在线识别，还需语音识别权限。
4. 播放视频，等待字幕。点击句子打开解析；首次分析前，在设置里填写自己的 AI 服务配置。
5. 也可以先点「先看看示例」。示例不会启动采集或访问 AI 服务。

关闭字幕窗只是隐藏并暂停采集；从顶部菜单栏的字幕图标可以重新显示。真正退出请使用菜单里的「退出 Kotoba」。

### AI 接口

| 服务 | 默认接口格式 |
| --- | --- |
| OpenAI | Responses |
| Claude / Anthropic | Messages |
| DeepSeek、Gemini、通义千问、Kimi、OpenRouter、Ollama | Chat Completions 兼容接口 |
| 自定义 | 上述三种格式任选，必须与服务实际支持的格式一致 |

每个服务商分别记住地址、模型和接口格式。API Key 按完整端点保存在 macOS 钥匙串；切换地址或协议不会自动携带另一接口的密钥。留空保留已有密钥，使用删除按钮可在保存时删除。取消设置不会保存密钥改动。

OpenRouter 需填完整模型 ID；Ollama 需自行启动、下载模型并填写模型名称，本机接口可不填 Key。通义千问的预设地址为中国内地地域，其他地域需按账户修改。测试连接也会发送请求，可能产生 API 费用。

## 隐私与数据

- 不保存录音、视频，不注册视频帧输出；ScreenCaptureKit 权限名称中仍会出现“屏幕录制”。
- 默认设备端识别，音频不上传到 AI 服务。关闭“仅设备端识别”后允许 Apple 在线语音识别。
- 点击分析、发送追问时，会把所选字幕及相关对话发给你配置的 AI 服务；测试连接发送一条简短测试消息。
- OpenAI Responses 请求设置 `store: false`；这不代表其他服务商没有自己的保留策略，请查看所用平台政策。
- 最近 2,000 句字幕、设置与收藏保存在 `~/Library/Application Support/Kotoba/`；API Key 不写入该目录，使用系统钥匙串。
- 仓库不包含个人字幕历史、账户密钥、浏览器截图、剧集片段或用户录音。示例为短小的学习用句子。

## 常见问题

### 权限开关是蓝色，仍提示无法采集

先真正退出再打开应用。临时签名在重新构建后可能改变应用身份，旧授权可能不再对应新版。固定安装位置，避免同时运行多个版本，并在需要时重新授权。

如果确认要清除旧授权，可以在退出 Kotoba 后手动执行：

```sh
tccutil reset ScreenCapture local.kotoba.learning
```

它只重置 Kotoba 的屏幕录制授权，不删除字幕、收藏或 Key；重新打开并点击「开始聆听」后需再次授权。不要重置所有应用的权限。开发阶段建议使用稳定签名身份，正式分发需要签名与公证。

当前“未能取得声音采集权限”提示也可能涵盖其他 ScreenCaptureKit 初始化错误，不能仅凭提示确定权限被关闭。报告问题时请说明系统版本、应用版本、声音来源及是否刚重新构建，但不要公开密钥或私人字幕。

### 没有字幕、识别不准确

确认浏览器正在播放且声音来源选对；浏览器进程重启后暂停再开始，或尝试“所有系统声音”。第一次使用等待 Apple 语言资源准备完成。音乐、人声重叠、语速快、中日混讲都会影响结果。

### 导入的字幕能和视频自动同步吗？

不能。SRT / VTT / TXT 导入生成可点击的学习列表，不控制浏览器播放进度。实时声音识别也会有延迟，不是逐帧同步字幕。

### JLPT 等级一定准确吗？

不是。翻译、语法与词汇来自模型，JLPT 等级仅供参考；语音误识别也可能影响解释。

## 测试

```sh
bash build.sh
bash Tests/run.sh
```

脚本运行无界面的核心测试和三种 AI 协议的本机 HTTP 测试。只监听 `127.0.0.1:18765`，不连接真实 AI 服务、不消耗账户额度、不申请录音权限，退出时停止测试服务。该端口需空闲。

扩展状态与磨砂视图检查需要可访问 macOS 窗口服务的本地会话：

```sh
dist/Kotoba.app/Contents/MacOS/Kotoba --self-test
```

预览界面：

```sh
open dist/Kotoba.app --args --preview --analysis
```

CI 使用 `macos-26` 运行构建和本机接口测试，不自动采集用户声音，不验证真实云端模型可用性。实时采集、权限弹窗和听写准确度仍需真机手动验证。

## 项目结构

```text
Sources/       原生窗口、字幕状态、声音识别、AI 协议与测试入口
Tests/         本机 HTTP 模拟服务与测试脚本
Resources/     示例字幕
Tools/         项目图标生成器
Info.plist     应用标识与权限说明
build.sh       无第三方依赖的构建脚本
```

欢迎提交 Issue 或 Pull Request，参见 [贡献指南](CONTRIBUTING.md)。安全问题请先阅读 [安全说明](SECURITY.md)。

## 名字与许可证

Kotoba 来自日语「ことば／言葉」，意思是语言、话语。本项目与 Apple、Bilibili 及各 AI 服务商无隶属或背书关系。

[MIT License](LICENSE) · Copyright (c) 2026 Namitoko。
