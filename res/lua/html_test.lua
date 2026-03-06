-- html_test_view.lua
local html_test_view = {}

local html_content = [[
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <title>Email Render Test Template</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f7f9fc; font-family: Arial, Helvetica, sans-serif; font-size: 14px; line-height: 1.6; color: #333333;">
    <table width="100%" border="0" cellpadding="0" cellspacing="0" style="background-color: #f7f9fc;">
        <tr>
            <td align="center" valign="top" style="padding: 20px 0;">
                <!-- 主容器 -->
                <table width="600" border="0" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.05); overflow: hidden;">
                    <!-- 头部 -->
                    <tr>
                        <td align="center" valign="middle" style="padding: 25px 20px; background-color: #4285f4; color: #ffffff;">
                            <h1 style="margin: 0; font-size: 24px; font-weight: 600; line-height: 1.2;">Email 渲染测试模板 | Test Template</h1>
                            <p style="margin: 10px 0 0; font-size: 16px; opacity: 0.9;">行内样式全场景验证 | Inline Style Full Test</p>
                        </td>
                    </tr>
                    <!-- 内容区 -->
                    <tr>
                        <td style="padding: 30px 25px;">
                            <!-- 文本测试 -->
                            <div style="margin-bottom: 25px;">
                                <h2 style="margin: 0 0 15px; font-size: 20px; color: #202124; font-weight: 600;">1. 文本格式测试 | Text Formatting</h2>
                                <p style="margin: 0 0 10px;">普通文本：这是一封测试邮件，包含中英文混合内容，用于验证邮件客户端对行内样式的渲染效果。</p>
                                <p style="margin: 0 0 10px;"><strong>粗体文本 | Bold Text</strong>：LÖVE2D 框架适配测试，Sol2 绑定性能验证。</p>
                                <p style="margin: 0 0 10px;"><em>斜体文本 | Italic Text</em>：水浒卡牌游戏开发进度更新，108好汉牌型设计完成。</p>
                                <p style="margin: 0 0 10px;"><span style="text-decoration: line-through; color: #70757a;">删除线 | Strikethrough</span>：已废弃的渲染方案，改用行内样式实现。</p>
                                <p style="margin: 0; color: #1a73e8; font-weight: 500;">链接色文本 | Link Color：<a href="https://love2d.org" style="color: #1a73e8; text-decoration: none; border-bottom: 1px solid #1a73e8;">LÖVE2D 官网</a></p>
                            </div>
                            <!-- 列表测试 -->
                            <div style="margin-bottom: 25px;">
                                <h2 style="margin: 0 0 15px; font-size: 20px; color: #202124; font-weight: 600;">2. 列表测试 | List Test</h2>
                                <ul style="margin: 0 0 15px; padding-left: 20px; list-style: disc;">
                                    <li style="margin: 0 0 8px;">无序列表项 1：修复图片拉伸问题（Image Stretch Fix）</li>
                                    <li style="margin: 0 0 8px;">无序列表项 2：实现剪贴板复制功能（Clipboard Copy）</li>
                                    <li style="margin: 0;">嵌套列表：
                                        <ul style="margin: 5px 0 0; padding-left: 20px; list-style: circle;">
                                            <li style="margin: 0;">子项 1：Emoji 单色渲染验证</li>
                                            <li style="margin: 0;">子项 2：Markdown 链接空格恢复</li>
                                        </ul>
                                    </li>
                                </ul>
                                <ol style="margin: 0; padding-left: 20px; list-style: decimal;">
                                    <li style="margin: 0 0 8px;">有序列表项 1：测试行内样式优先级</li>
                                    <li style="margin: 0;">有序列表项 2：验证跨客户端兼容性（Outlook/Gmail/QQ邮箱）</li>
                                </ol>
                            </div>
                            <!-- 按钮测试 -->
                            <div style="margin-bottom: 25px; text-align: center;">
                                <h2 style="margin: 0 0 15px; font-size: 20px; color: #202124; font-weight: 600;">3. 按钮测试 | Button Test</h2>
                                <a href="https://example.com/test" style="display: inline-block; padding: 12px 24px; background-color: #4285f4; color: #ffffff; text-decoration: none; border-radius: 4px; font-weight: 500; font-size: 16px; line-height: 1; mso-padding-alt: 0; text-transform: none;">
                                    测试按钮 | Test Button
                                </a>
                                <a href="https://example.com/secondary" style="display: inline-block; margin-left: 10px; padding: 12px 24px; background-color: #ffffff; color: #4285f4; border: 1px solid #4285f4; text-decoration: none; border-radius: 4px; font-weight: 500; font-size: 16px; line-height: 1; mso-padding-alt: 0;">
                                    次要按钮 | Secondary Button
                                </a>
                            </div>
                            <!-- 图片测试 -->
                            <div style="margin-bottom: 25px; text-align: center;">
                                <h2 style="margin: 0 0 15px; font-size: 20px; color: #202124; font-weight: 600;">4. 图片测试 | Image Test</h2>
                                <img src="https://picsum.photos/500/200?random=1" alt="Test Image" style="width: 100%; max-width: 550px; height: auto; border-radius: 4px; display: block; margin: 0 auto; border: 0;" />
                                <p style="margin: 10px 0 0; color: #70757a; font-size: 13px;">图片说明：测试自适应宽度与圆角样式 | Image Caption: Responsive & Border Radius</p>
                            </div>
                            <!-- 表格测试 -->
                            <div style="margin-bottom: 25px;">
                                <h2 style="margin: 0 0 15px; font-size: 20px; color: #202124; font-weight: 600;">5. 表格测试 | Table Test</h2>
                                <table width="100%" border="0" cellpadding="8" cellspacing="0" style="border-collapse: collapse;">
                                    <tr style="background-color: #f8f9fa;">
                                        <th style="text-align: left; font-weight: 600; color: #202124; border-bottom: 2px solid #dadce0;">功能模块 | Module</th>
                                        <th style="text-align: center; font-weight: 600; color: #202124; border-bottom: 2px solid #dadce0;">状态 | Status</th>
                                        <th style="text-align: right; font-weight: 600; color: #202124; border-bottom: 2px solid #dadce0;">进度 | Progress</th>
                                    </tr>
                                    <tr>
                                        <td style="border-bottom: 1px solid #dadce0; color: #333;">文本渲染 | Text Render</td>
                                        <td style="text-align: center; border-bottom: 1px solid #dadce0; color: #333;">完成 | Done</td>
                                        <td style="text-align: right; border-bottom: 1px solid #dadce0; color: #333;">100%</td>
                                    </tr>
                                    <tr style="background-color: #f8f9fa;">
                                        <td style="border-bottom: 1px solid #dadce0; color: #333;">图片适配 | Image Adapt</td>
                                        <td style="text-align: center; border-bottom: 1px solid #dadce0; color: #333;">完成 | Done</td>
                                        <td style="text-align: right; border-bottom: 1px solid #dadce0; color: #333;">100%</td>
                                    </tr>
                                    <tr>
                                        <td style="color: #333;">Emoji 渲染 | Emoji Render</td>
                                        <td style="text-align: center; color: #333;">进行中 | Ongoing</td>
                                        <td style="text-align: right; color: #333;">80%</td>
                                    </tr>
                                </table>
                            </div>
                            <!-- 代码行测试 -->
                            <div style="margin-bottom: 0;">
                                <h2 style="margin: 0 0 15px; font-size: 20px; color: #202124; font-weight: 600;">6. 代码行测试 | Code Line Test</h2>
                                <div style="padding: 15px; background-color: #f8f9fa; border-radius: 4px; font-family: 'Courier New', monospace; font-size: 13px; color: #202124; line-height: 1.5;">
                                    <code style="color: #d73a4a;">local emojiFont = love.graphics.newFont("C:\\Windows\\Fonts\\seguiemj.ttf", 24)</code><br/>
                                    <code style="color: #005cc5;">function love.draw() love.graphics.print("🎴 水浒卡牌 🃏", 100, 100) end</code>
                                </div>
                            </div>
                        </td>
                    </tr>
                    <!-- 页脚 -->
                    <tr>
                        <td align="center" valign="middle" style="padding: 20px 25px; background-color: #f8f9fa; border-top: 1px solid #dadce0;">
                            <p style="margin: 0 0 8px; color: #70757a; font-size: 13px;">© 2026 测试团队 | Test Team - 行内样式仅用于邮件渲染测试</p>
                            <p style="margin: 0; color: #9aa0a6; font-size: 12px;">如果无法正常查看，请切换至网页版 | View in browser if display is abnormal</p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
]]


local md_content = [[
# Electrobun
<p align="center">
  <a href="https://electrobun.dev"><img src="https://github.com/blackboardsh/electrobun/assets/75102186/8799b522-0507-45e9-86e3-c3cfded1aa7c" alt="Logo" height=170></a>
</p>

<h1 align="center">Electrobun</h1>

<div align="center">
  Get started with a template <br />
  <code><strong>npx electrobun init</strong></code>   
</div>



## What is Electrobun?

Electrobun aims to be a complete **solution-in-a-box** for building, updating, and shipping ultra fast, tiny, and cross-platform desktop applications written in Typescript.
Under the hood it uses <a href="https://bun.sh">bun</a> to execute the main process and to bundle webview typescript, and has native bindings written in <a href="https://ziglang.org/">zig</a>.

Visit <a href="https://blackboard.sh/electrobun/">https://blackboard.sh/electrobun/</a> to see api documentation, guides, and more.

**Project Goals**

- Write typescript for the main process and webviews without having to think about it.
- Isolation between main and webview processes with fast, typed, easy to implement RPC between them.
- Small self-extracting app bundles ~12MB (when using system webview, most of this is the bun runtime)
- Even smaller app updates as small as 14KB (using bsdiff it only downloads tiny patches between versions)
- Provide everything you need in one tightly integrated workflow to start writing code in 5 minutes and distribute in 10.

## Apps Built with Electrobun
- [Audio TTS](https://github.com/blackboardsh/audio-tts) - desktop text-to-speech app using Qwen3-TTS for voice design, cloning, and generation
- [Co(lab)](https://blackboard.sh/colab/) - a hybrid web browser + code editor for deep work
- [DOOM](https://github.com/blackboardsh/electrobun-doom) - DOOM implemented in 2 ways: bun -> (c doom -> bundled wgpu) and (full ts port bun -> bundled wgpu)

# Video Demos

[![Audio TTS Demo](https://img.youtube.com/vi/Z4dNK1d6l6E/maxresdefault.jpg)](https://www.youtube.com/watch?v=Z4dNK1d6l6E)

[![Co(lab) Demo](https://img.youtube.com/vi/WWTCqGmE86w/maxresdefault.jpg)](https://www.youtube.com/watch?v=WWTCqGmE86w)

[![DOOM Demo](https://github.com/user-attachments/assets/6cc5f04a-6d97-4010-b65f-3f282d32590c)](https://x.com/YoavCodes/status/2028499038148903239?s=20)

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=blackboardsh/electrobun&type=date&legend=top-left&cache=2)](https://www.star-history.com/#blackboardsh/electrobun&type=date&legend=top-left)

## Contributing
Ways to get involved:

- Follow us on X for updates <a href="https://twitter.com/BlackboardTech">@BlackboardTech</a> or <a href="https://bsky.app/profile/yoav.codes">@yoav.codes</a>
- Join the conversation on <a href="https://discord.gg/ueKE4tjaCE">Discord</a>
- Create and participate in Github issues and discussions
- Let me know what you're building with Electrobun

## Development Setup
Building apps with Electrobun is as easy as updating your package.json dependencies with `npm add electrobun` or try one of our templates via `npx electrobun init`.

**This section is for building Electrobun from source locally in order to contribute fixes to it.**

### Prerequisites

**macOS:**
- Xcode command line tools
- cmake (install via homebrew: `brew install cmake`)

**Windows:**
- Visual Studio Build Tools or Visual Studio with C++ development tools
- cmake

**Linux:**
- build-essential package
- cmake
- webkit2gtk and GTK development packages

On Ubuntu/Debian based distros: `sudo apt install build-essential cmake pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev`

### First-time Setup

```bash
git clone --recurse-submodules https://github.com/blackboardsh/electrobun.git
cd electrobun/package
bun install
bun dev:clean
```

### Development Workflow

```bash
# All commands are run from the /package directory
cd electrobun/package

# After making changes to source code
bun dev

# If you only changed kitchen sink code (not electrobun source)
bun dev:rerun

# If you need a completely fresh start
bun dev:clean
```

### Additional Commands

All commands are run from the `/package` directory:

- `bun dev:canary` - Build and run kitchen sink in canary mode
- `bun build:dev` - Build electrobun in development mode
- `bun build:release` - Build electrobun in release mode

### Debugging

**macOS:** Use `lldb <path-to-bundle>/Contents/MacOS/launcher` and then `run` to debug release builds

## Platform Support

| OS | Status |
|---|---|
| macOS 14+ | Official |
| Windows 11+ | Official |
| Ubuntu 22.04+ | Official |
| Other Linux distros (gtk3, webkit2gtk-4.1) | Community |

]]

function html_test_view.markdown(main_view)
    local content = brls.ScrollingFrame.new()
    local renderer = brls.MarkdownRenderer.new()
    renderer:renderMarkdown(md_content)
    renderer:setPadding(64)
    content:setContentView(renderer)
    return content
end

function html_test_view.html(main_view)
    local content = brls.ScrollingFrame.new()
    local renderer = brls.HtmlRenderer.new()
    renderer:renderString(html_content)
    renderer:setPadding(4)

    content:setContentView(renderer)
    return content
end


return html_test_view