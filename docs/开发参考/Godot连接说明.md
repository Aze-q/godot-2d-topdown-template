# Codex + Godot 开发环境

配置日期：2026-09-11。适用于本机和当前项目。

## 已安装

- Godot **4.7.2 stable** 标准版：`/Applications/Godot.app`。
- 命令行入口：`/opt/homebrew/bin/godot`。
- Godot MCP：`@coding-solo/godot-mcp@0.1.1`，安装于 `/Users/ze/.local/share/godot-mcp`，使用现有 Node.js 24.16.0。
- Codex 全局配置中已添加 `godot` 服务。原配置备份：`/Users/ze/.codex/config.toml.before-godot-20260911-031107.bak`。

项目使用 GDScript，标准版包含编辑器和调试功能，无需 .NET SDK。MCPClientToolset、ModelContextProtocol、Terminal 是 Unreal Engine 接入说明中的插件，不需要为本项目安装。

## 让 Codex 加载连接

1. 打开 Codex 设置 → **MCP servers**，找到 `godot` 并选择 **Restart**；也可以完全退出并重新打开 Codex。
2. 回到当前项目，输入 `/mcp` 查看服务状态。
3. 对 Codex 说：

   > 使用 Godot MCP 检查引擎版本和当前项目，然后运行游戏、读取调试日志。

本次安装已经完成独立 MCP 握手和工具调用测试。当前对话的工具列表不会因写入配置立即改变；桌面控制工具也禁止操作 Codex 自己的界面，因此最后的重新加载需要手动完成。

配置写在 `/Users/ze/.codex/config.toml`：

```toml
[mcp_servers.godot]
command = "/Users/ze/.nvm/versions/node/v24.16.0/bin/node"
args = ["/Users/ze/.local/share/godot-mcp/node_modules/@coding-solo/godot-mcp/build/index.js"]

[mcp_servers.godot.env]
GODOT_PATH = "/Applications/Godot.app/Contents/MacOS/Godot"
```

该连接使用本机标准输入/输出，无需端口、API key 或手动常驻终端。以后若移除当前 Node 版本，需要更新上面的 Node 路径。

## 日常开发

在 Codex 中描述需要的功能，Codex 编辑脚本和场景，再通过 MCP 运行项目并读取日志。在 Godot 编辑器中可查看场景和资源，按 **F6** 运行当前场景，按 **F5** 运行整个项目，按 **F8** 停止编辑器启动的游戏。

MCP 工具调用中的 `projectPath` 使用当前项目绝对路径：

```text
/Users/ze/godot-project/godot-2d-topdown-template
```

MCP 启动的游戏使用 `get_debug_output` 读取日志、`stop_project` 停止。读取日志应在游戏仍运行时进行；该 MCP 同时只管理一个游戏进程，不能停止从编辑器另行启动的游戏。

这是通过 Godot 命令行工作的轻量连接，支持 14 个工具，包括版本、项目信息、运行、日志和基础场景操作。它没有读取当前编辑器选中节点、运行时截图或自动操作游戏的工具。

首次克隆项目后先导入资源：

```sh
godot --headless --path /Users/ze/godot-project/godot-2d-topdown-template --editor --import
```

导入会建立 `.godot/` 和资源缓存。需要打包发布游戏时，再安装与引擎版本匹配的 Export Templates。

## 本次验证与修复

- Godot 的严格签名检查和 Gatekeeper 公证检查通过；下载包 SHA-256 与 Homebrew 发布记录一致。
- MCP 握手、14 个工具的发现、版本读取、项目信息读取均通过。
- 通过 MCP 分别启动标题页和 `playground_01.tscn`，各运行约 6 秒，再读取日志并停止：标题页无错误或警告；关卡无错误，有 7 条资源 UID 回退警告。
- 修复 Dialogue Manager 读取旧版编辑器字体设置名的问题，并保留旧 Godot 版本回退逻辑。
- 将失效的项目图标 UID 改为 `res://icon.png`。
- 第二次导入不再出现字体脚本错误。仍有资源 UID 回退警告，以及 headless 编辑器退出时的对象/资源未释放提示；本次没有扩展为模板整体排错，也未验证全部玩法。

包版本为 0.1.1，但 MCP 握手中的服务版本仍显示 0.1.0，这是上游包的版本标识不一致。

## 来源

- [Godot 官方 macOS 稳定版下载](https://godotengine.org/download/macos/)
- [Godot MCP 项目及能力说明](https://github.com/Coding-Solo/godot-mcp)
- [Codex 官方 MCP 配置说明](https://developers.openai.com/codex/mcp/)
- [Godot 最新编辑器字体设置](https://docs.godotengine.org/en/latest/classes/class_editorsettings.html#class-editorsettings-property-interface-editor-fonts-code-font-size)
- [Godot 4.4 编辑器字体设置](https://docs.godotengine.org/en/4.4/classes/class_editorsettings.html#class-editorsettings-property-interface-editor-code-font-size)
- [Unreal Engine MCP 设置说明](https://dev.epicgames.com/documentation/unreal-engine/unreal-mcp-in-unreal-editor)
