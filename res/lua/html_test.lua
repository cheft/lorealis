-- html_test_view.lua
local html_test_view = {}

local html_content = [[
<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">


<body style="margin:0;padding:0;background-color:#f4f7f9">
  <center style="width:100%;table-layout:fixed;background-color:#f4f7f9">
    <div style="max-width:600px;margin:0 auto;background-color:#fff;box-shadow:0 4px 6px rgba(0,0,0,0.05)">
      <table role="presentation" width="100%" style="background-color:#fff">
        <tr>
          <td align="center" style="padding:30px 0;border-bottom:3px solid #34a671">
            <img src="https://loflog.com/logo.png" height="28"
              style="display:inline-block;vertical-align:middle;margin-right:12px">
            <span
              style="color:#294686;font-size:18px;letter-spacing:3px;text-transform:uppercase;font-weight:700;vertical-align:middle">Lofeng
              International Logistics</span>
          </td>
        </tr>
        <tr>
          <td style="background-color:#004494;text-align:center;padding:0">
            <img src="https://loflog.com/email-header.png" alt="Global Logistics" width="600"
              style="width:100%;max-width:600px;height:auto;display:block">
          </td>
        </tr>
        <tr>
          <td class="padding-mobile" style="padding:40px 40px 20px 40px;text-align:left">
            <h1 style="margin:0 0 20px 0;font-size:24px;line-height:1.3;color:#294686;font-weight:700">
              Import from China with <span style="color:#34a671">Zero-Risk, US-Backed Confidence</span>.
            </h1>
            <p style="margin:0 0 20px 0;font-size:16px;line-height:1.6;color:#555">Dear Friend,</p>
            <p style="margin:0 0 20px 0;font-size:16px;line-height:1.6;color:#555">China’s factories offer
              unmatched <strong>product diversity</strong> and <strong>cost-performance</strong>—but only
              if you know exactly whom to trust. We do. Hundreds of U.S. companies already rely on
              <strong>Lofeng International Logistics (Loflog)</strong>.
            </p>
            <p style="margin:0 0 20px 0;font-size:16px;line-height:1.6;color:#555">Our teams in Anaheim, CA
              and China coordinate everything while your cargo—and your cash—stay protected. No delays, no
              hidden fees.</p>
          </td>
        </tr>
        <tr>
          <td class="padding-mobile" style="padding:40px 40px 20px 40px;text-align:center">
            <h2 style="margin:0 0 20px 0;font-size:20px;color:#294686">Trusted by American Manufacturers
            </h2>
            <p style="margin:0 0 30px 0;font-size:15px;line-height:1.6;color:#555">We help businesses reduce
              costs and improve reliability. Need <strong>Air Freight</strong> or <strong>Ocean
                Freight</strong>? We have the network.</p>
            <div><a
                href="mailto:services@loflog.com?subject=Logistics Quote Request&body=Hi Loflog,%0D%0A%0D%0APlease send me a free quote.%0D%0A%0D%0AThank you!"
                style="background-color:#64748b;color:#fff;padding:15px 35px;text-decoration:none;border-radius:50px;font-weight:700;font-size:16px;display:inline-block">Reply
                Now for Free Quote</a></div>
          </td>
        </tr>
        <tr>
          <td style="padding:0 40px">
            <div style="border-top:1px solid #e6e6e6;margin:20px 0"></div>
          </td>
        </tr>
        <tr>
          <td style="padding:20px 40px 40px 40px;text-align:center;color:#888;font-size:12px">
            <p style="margin:0 0 10px 0"><strong>Lofeng International Logistics</strong></p>
            <p style="margin:0"><a href="https://loflog.com"
                style="color:#34a671;text-decoration:underline">loflog.com</a> | <a href="mailto:services@loflog.com"
                style="color:#34a671;text-decoration:underline">services@loflog.com</a></p>
            <p style="margin:20px 0 0 0">© 2025 Loflog. All rights reserved. <a href="#"
                style="color:#888;text-decoration:underline">Unsubscribe</a></p>
          </td>
        </tr>
      </table>
    </div>
  </center>
</body>

</html>
]]


local md_content = [[
# Borealis 渲染器测试 Demo（一级标题）
> 测试场景：Switch 平台 Markdown/HTML 渲染验证（块引用）测试场景：Switch 平台 Markdown/HTML 渲染验证（块引用）测试场景：Switch 平台 Markdown/HTML 渲染验证（块引用）
测试场景：Switch 平台 Markdown/HTML 渲染验证（块引用）测试场景：Switch 平台 Markdown/HTML 渲染验证（块引用）测试场景：Switch 平台 Markdown/HTML 渲染验证（块引用）测试场景：Switch 平台 Markdown/HTML 渲染验证（块引用）测试场景：Switch 平台 Markdown/HTML 渲染验证（块引用）测试场景：Switch 平台 Markdown/HTML 渲染验证（块引用）测试场景：Switch 平台 Markdown/HTML 渲染验证（块引用）

## 1. 基础文本样式（二级标题）
- 粗体文本：**Switch 手柄导航测试**
- 斜体文本：*触控缩放适配测试*
- 粗斜体文本：***Borealis 样式复用***
- 删除线：~~废弃功能测试~~
- 行内代码：`html_render.render_file("test.html")`

## 2. 列表测试
### 无序列表
- 新闻分类 1
  - 子分类 1-1
  - 子分类 1-2
- 新闻分类 2
  - 子分类 2-1

### 有序列表
1. RSS 加载步骤
2. XML 解析步骤
3. HTML 转换步骤
4. Borealis 渲染步骤

## 3. 表格测试（邮件/报告常用）
| 功能模块        | 支持状态 | 备注                 |
|----------------|---------|----------------------|
| HTML 标题      | 支持     | h1-h6 全适配         |
| 图片渲染       | 支持     | 本地/SD 卡路径        |
| 表格渲染       | 支持     | 极简样式适配          |
| JavaScript    | 不支持    | 仅静态渲染           |

## 4. 链接与图片测试（Switch 场景）
### 链接
- 本地文档链接：[配置页](sdmc:/switch/borealis/config.html)
- 外部链接（仅展示，无跳转）：[阮一峰 RSS 示例](http://www.ruanyifeng.com)

![Switch 图标](E:/Works/Projects/ns-chat/resources/img/demo_icon.jpg)
> 备注：图片尺寸适配 Borealis 窗口大小

## 5. 代码块测试（Lua 脚本示例）
```lua
-- Switch 上的 Lua 调用示例
local html_render = require("html_render")
-- 渲染 Markdown 转换后的 HTML
local ok, res = html_render.render_file("test_render.html")
if ok then
    print("渲染成功：Switch 界面显示内容")
else
    print("渲染失败：", res)
end
```

]]

function html_test_view.init(main_view)
    print("Rendering Markdown via MarkdownRenderer...")
    local content = brls.ScrollingFrame.new()


    -- local renderer = brls.HtmlRenderer.new()
    -- renderer:renderString(html_content)

    local renderer = brls.MarkdownRenderer.new()
    renderer:renderMarkdown(md_content)

    content:setContentView(renderer)
    return content
end

return html_test_view