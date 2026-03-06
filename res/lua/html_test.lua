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
# ❤️ ✨ Welcome to Markdown Viewer

## ✨ Key Features
- **Live Preview** with GitHub styling
- **Smart Import/Export** (MD, HTML, PDF)
- **Mermaid Diagrams** for visual documentation
- **LaTeX Math Support** for scientific notation
- **Emoji Support** 😄 👍 🎉

## 💻 Code with Syntax Highlighting
```javascript
  function renderMarkdown() {
    const markdown = markdownEditor.value;
    const html = marked.parse(markdown);
    const sanitizedHtml = DOMPurify.sanitize(html);
    markdownPreview.innerHTML = sanitizedHtml;
    
    // Apply syntax highlighting to code blocks
    markdownPreview.querySelectorAll('pre code').forEach((block) => {
        hljs.highlightElement(block);
    });
  }
```

## 🧮 Mathematical Expressions
Write complex formulas with LaTeX syntax:

Inline equation: $$E = mc^2$$

Display equations:
$$\frac{\partial f}{\partial x} = \lim_{h \to 0} \frac{f(x+h) - f(x)}{h}$$

$$\sum_{i=1}^{n} i^2 = \frac{n(n+1)(2n+1)}{6}$$

## 📊 Mermaid Diagrams
Create powerful visualizations directly in markdown:

```mermaid
flowchart LR
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Great!]
    B -->|No| D[Debug]
    C --> E[Deploy]
    D --> B
```

### Sequence Diagram Example
```mermaid
sequenceDiagram
    User->>Editor: Type markdown
    Editor->>Preview: Render content
    User->>Editor: Make changes
    Editor->>Preview: Update rendering
    User->>Export: Save as PDF
```

## 📋 Task Management
- [ ] Create responsive layout
- [x] Implement live preview with GitHub styling
- [x] Add syntax highlighting for code blocks
- [x] Support math expressions with LaTeX
- [ ] Enable mermaid diagrams

## 🆚 Feature Comparison

| Feature                  | Markdown Viewer (Ours) | Other Markdown Editors  |
|:-------------------------|:----------------------:|:-----------------------:|
| Live Preview             | ✅ GitHub-Styled       | ✅                     |
| Sync Scrolling           | ✅ Two-way             | 🔄 Partial/None        |
| Mermaid Support          | ✅                     | ❌/Limited             |
| LaTeX Math Rendering     | ✅                     | ❌/Limited             |

### 📝 Multi-row Headers Support

<table>
  <thead>
    <tr>
      <th rowspan="2">Document Type</th>
      <th colspan="2">Support</th>
    </tr>
    <tr>
      <th>Markdown Viewer (Ours)</th>
      <th>Other Markdown Editors</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Technical Docs</td>
      <td>Full + Diagrams</td>
      <td>Limited/Basic</td>
    </tr>
    <tr>
      <td>Research Notes</td>
      <td>Full + Math</td>
      <td>Partial</td>
    </tr>
    <tr>
      <td>Developer Guides</td>
      <td>Full + Export Options</td>
      <td>Basic</td>
    </tr>
  </tbody>
</table>

## 📝 Text Formatting Examples

### Text Formatting

Text can be formatted in various ways for ~~strikethrough~~, **bold**, *italic*, or ***bold italic***.

For highlighting important information, use <mark>highlighted text</mark> or add <u>underlines</u> where appropriate.

### Superscript and Subscript

Chemical formulas: H<sub>2</sub>O, CO<sub>2</sub>  
Mathematical notation: x<sup>2</sup>, e<sup>iπ</sup>

### Keyboard Keys

Press <kbd>Ctrl</kbd> + <kbd>B</kbd> for bold text.

### Abbreviations

<abbr title="Graphical User Interface">GUI</abbr>  
<abbr title="Application Programming Interface">API</abbr>

### Text Alignment

<div style="text-align: center">
Centered text for headings or important notices
</div>

<div style="text-align: right">
Right-aligned text (for dates, signatures, etc.)
</div>

### **Lists**

Create bullet points:
* Item 1
* Item 2
  * Nested item
    * Nested further

### **Links and Images**

Add a  [link](https://github.com/ThisIs-Developer/Markdown-Viewer) to important resources.

Embed an image:
![Markdown Logo](https://godotengine.org/assets/download/download-background-4.x.webp)

### **Blockquotes**

Quote someone famous:
> "The best way to predict the future is to invent it." - Alan Kay

---

## 🛡️ Security Note

This is a fully client-side application. Your content never leaves your browser and stays secure on your device.

]]

function html_test_view.markdown(main_view)
    local content = brls.ScrollingFrame.new()
    local renderer = brls.MarkdownRenderer.new()
    renderer:renderMarkdown(md_content)
    renderer:setPadding(0)
    content:setContentView(renderer)
    return content
end

function html_test_view.html(main_view)
    local content = brls.ScrollingFrame.new()
    local renderer = brls.HtmlRenderer.new()
    renderer:renderString(html_content)
    renderer:setPadding(0)

    content:setContentView(renderer)
    return content
end


return html_test_view