# GitHub 插件

当前 Agent 已迁移为 Swift 原生运行时，Asky 不再随包分发 Node / Pi。插件清单、安装配置、启停、工具命名和确认策略保持兼容。API v2 可执行文件由 Swift ToolService 直接启动；旧 API v1 JavaScript 插件使用本机 Node.js 22+，缺少 Node 时仅该插件调用不可用，不影响 Agent 与原生工具。

## API v2 原生插件

清单沿用下文全部配置、tools、commands 和指导字段，将 `apiVersion` 改为 `2`，`entry` 指向插件目录内有执行权限的程序。建议分发签名的 macOS arm64 Swift 可执行文件；Git 必须保留入口的可执行位。安装时验证文件与权限，不在用户设备编译、不安装 npm 依赖。示例源码与清单见 [native-echo](../examples/plugins/native-echo/main.swift)，作者在发布仓库前执行 `xcrun swiftc -O main.swift -o native-echo`，提交编译产物和清单；应用不内置或自动安装这个示例。

每次工具执行或回读启动一个进程，通过 stdin / stdout 交换单行 JSON。stdin 第一行包含 `tool`、`arguments`、`requestID`、`configuration`、`state`、`inputSchema`、`readback`、`output`；`entry` 是宿主已校验的入口路径。宿主在执行前校验 JSON Schema。工具逻辑必须根据 `readback` 区分执行与核实，不重放写入。

```json
{"type":"result","value":{"text":"完成后的实际结果"}}
```

失败返回 `{"type":"result","error":"原因","errorCode":"invalidArguments"}`（其他错误为 adapterFailure）。stdout 仅承载协议，诊断写 stderr，由宿主限量保存到 execution.log。

插件可以请求宿主保存状态或以 argv 执行 CLI，等待 stdin 中同一 id 的响应：

```json
{"type":"rpc","id":1,"method":"state","value":{"checkpoint":"attempting"}}
{"type":"rpc","id":2,"method":"exec","executable":"/path/to/cli","arguments":["status","--json"],"timeoutSeconds":20}
```

宿主响应为 `{"id":1,"value":true}` 或 `{"id":2,"value":{"stdout":"...","stderr":"...","exitCode":0}}`，失败为 `{"id":2,"error":"原因"}`。id 在调用内唯一。状态与 CLI 仍经 ToolService，模型 Key 不进入环境。API v2 复用 API v1 的超时、取消、输出上限、版本租约、回读和未知结果策略。可信插件仍不是沙箱；其自身代码拥有当前用户权限。

Orca / 飞书插件已提供 API v2 Swift 原生入口，插件执行器不再需要 Node / npm。CLI 本身的安装、登录与运行环境仍由用户准备。插件 ID、工具名、配置字段与持久化状态保持兼容，旧安装可通过插件更新迁移；旧 API v1 版本仍可回退并通过本机 Node 兼容入口运行。独立仓库是否已发布，以其默认分支清单为准。

Asky 插件是用户主动安装的可信本机代码。主应用携带插件宿主，不携带官方插件实现；官方与自行安装的插件使用同一套安装和执行接口。官方插件各自拥有独立仓库，包括 [Orca](https://github.com/Niall-Young/asky-plugin-orca) 与 [飞书 / Lark](https://github.com/Niall-Young/asky-plugin-lark)。不提供系统沙箱，也不宣称能力声明能限制插件自行执行的代码。

插件可以同时提供启动器功能和 Agent 工具，也可以只提供其中一种。启动器命令无需模型配置、不启动 AI 会话；既有只声明 `tools` 的插件继续兼容。已有 Orca / 飞书插件不会自动获得启动器入口，需要插件作者声明 `commands`。

## 启动器功能扩展

`tools` 与 `commands` 共用 API v2 原生入口及权限生命周期：Agent 通过工具名调用，聚焦搜索通过命令引用调用，不启动模型。纯功能插件将工具的 `agentVisible` 设为 false；混合插件可同时声明两类入口。动态输入仍由宿主防抖、取消和丢弃过期结果，原生插件无需实现 UI。

安装并启用后，在普通搜索中按命令标题、插件名称或触发词查找入口，回车进入。唯一且未与已有内置指令、网页指令或别名冲突的触发词可用 `触发词 空格` 直接进入。重名触发词不抢占已有路由，仍可按标题选择入口。Esc 返回普通搜索并保留输入，空输入退格退出；隐藏窗口取消当前调用并清理临时结果，不撤销已完成的外部操作。

清单增加可选的 `commands` 数组，每个插件最多 64 项；每项引用同一清单中的一个工具：

```json
{
  "commands": [
    {"name": "text", "title": "Text Tools", "keyword": "text", "tool": "transform", "mode": "search", "queryArgument": "text"},
    {"name": "uuid", "title": "Generate UUID", "keyword": "uuid", "tool": "uuid", "mode": "action"}
  ]
}
```

- `name`：插件内唯一标识，沿用工具名的字符规则；`title` 为入口名称，可选 `subtitle` 为描述。
- `keyword`：可选触发词，沿用工具名的字符规则，不覆盖内置或用户已有触发词。
- `tool`：引用工具名称；执行仍经 ToolService 的权限、确认、超时、取消、状态与回读流程。
- `mode: "search"`：进入后按输入动态查询，150 ms 防抖，取消旧查询并丢弃过期结果；引用的工具必须为 `read`，空输入也会查询。最多显示前 200 项。
- `mode: "action"`：无 `queryArgument` 时，选择入口立即执行；有该字段时，进入输入模式，编辑参数后回车执行，不随输入自动执行。
- `queryArgument`：可选，指定接收输入文本的字符串属性。不声明时传入 `{}`；声明时传入例如 `{"text":"用户输入"}`。工具不能要求宿主未提供的其他必填参数，确认保留字段不能作为输入属性。

工具新增可选的 `agentVisible`（默认 true）。设为 false 时，不向 Agent 发布该工具，Agent 也不能直接调用它；引用它的启动器命令仍可使用。因此纯功能插件可以将其所有工具设为 false，不要求提供 Agent 指导文件。所有插件仍需声明 `tools`，命令直接复用这些实现。

工具通过既有 `execute(args, context)` 返回原生展示数据：

```js
return {
  items: [
    { id: 'encoded', title: 'hello%20world', subtitle: 'URL Encode', copy: 'hello%20world' },
    { id: 'site', title: 'Example', url: 'https://example.com' }
  ]
};
// 单个文本结果：return { text: 'value' };
```

列表项 `id` 在本次结果中唯一，`title` 非空，`subtitle` 可选。`copy` 添加复制动作，`url` 添加 HTTP/HTTPS 打开动作；同时声明时复制为主动作，打开位于 `⌘K` 菜单。无动作的项目只展示。`text` 生成可复制的单条结果，`items: []` 显示无匹配状态。宿主不会执行返回内容中的 HTML、脚本、Shell 或工具调用。写命令只有执行完成并通过原有回读流程后才展示成功结果；未知结果显示待核实，不自动重放。

可运行的 API v2 [Text Tools 示例](../examples/plugins/text-tools/asky-plugin.json) 提供 URL 编解码、Base64 编码和 UUID 生成，是不向 Agent 暴露工具的纯聚焦搜索插件。原生 `text-tools` 可执行文件随示例分发，用户无需 Node、npm 或编译器。作者修改 Swift 源码后先运行 `./examples/plugins/text-tools/build.sh`，再将该目录内容放到公开 GitHub 仓库根目录，即可沿用设置中的 GitHub 安装流程；应用不会自动安装示例，也不修改用户现有插件配置。本版使用原生结果列表，不提供插件自定义 HTML 或任意窗口视图接口。

## 安装与生命周期

设置 › 插件沿用指令页的搜索框与分段 Tab，按「AI 插件」「功能插件」分别查看。提供可见 Agent 工具或操作指导的插件归入 AI 类；声明启动器 commands 的插件归入功能类；两者兼有时在两个分类显示，共用同一份安装、配置与启用状态。旧版未声明 commands 的插件保留在 AI 类。

搜索框跨分类匹配插件名称、仓库链接、工具名称/说明及启动器命令名称、说明和触发词；搜索时按类别展示结果，清除搜索恢复当前 Tab。每个分类只有一张插件展示列表：官方插件无论是否安装都直接列出并带「官方」标签，未安装时显示安装按钮，安装后原地变为启用开关和更多菜单；自行安装的插件标注来源。安装成功后切到相应分类；混合插件优先显示功能类。当前未安装的官方 Orca/飞书插件属于 AI 类，不在功能类提供安装入口。

顶部「添加」按钮打开窗口内对话框，填写公开 GitHub HTTPS 仓库根目录链接即可安装，对话框同时说明插件会在本机执行代码。清单必须位于默认分支根目录。首版不支持私有仓库认证、子目录安装或 Pi 扩展直接兼容。

安装需要 Git。插件存放在现有应用数据根目录的 `plugins/<id>/`；配置、来源、commit、启用状态和运行状态保存在 LocalStore。安装时一次说明本机代码执行能力；安装完成默认停用，需要用户手动开启；更新或回退保留用户选择的启用状态，缺少必填配置时不提供工具。不会自动安装任何插件。

API v1 插件提供可直接运行的 JS/ESM 入口；不执行构建命令。有运行依赖时要求 package-lock.json 和本机 npm，执行 `npm ci --omit=dev --ignore-scripts --no-audit --no-fund`。不支持需要安装脚本的依赖。旧版 Orca 无 npm 依赖，使用用户本机 Node；不再使用随包 Node。

下载、清单检查和依赖安装在临时目录完成后切换。更新由用户触发，失败保留旧版本，成功后保留一个旧版供回退。执行期间固定版本与配置，更新/卸载等待该插件的调用和回读结束。停用立即阻止后续调用；工具与指导在下一次 AI 请求刷新，不取消其他会话。

卸载删除安装和配置，保留历史执行记录与交接状态，不删除外部工作区或终止外部 Agent。重新安装相同 ID 可继续查询旧交接。

官方身份由应用的精确来源清单判定，不信任插件自行声明。加入官方清单需要主项目变更；插件自身更新不要求更新 Asky。

## API v1

仓库包含 `asky-plugin.json`、JS/ESM 入口和可选操作指导。参考最小结构：

清单可选 `icon` 字段指定插件目录内的本地图片相对路径，例如 `"icon": "assets/icon.png"`。推荐透明边缘的方形 PNG；宿主读取上限为 2 MiB，不加载远程 URL、绝对路径或目录外文件。安装与回退后使用该版本的图片；缺失、不可读或无法解码时，官方 Orca / 飞书插件使用本机对应应用的图标，其他情况使用内置蓝色玻璃拼图占位图标。未指定 `icon` 的旧版清单继续兼容。

```json
{
  "id": "example",
  "name": "Example",
  "version": "0.1.0",
  "apiVersion": 1,
  "entry": "index.mjs",
  "instructions": "SKILL.md",
  "configuration": [
    {"key": "cli_path", "label": "CLI", "type": "path", "defaultValue": "example"}
  ],
  "tools": [{
    "name": "status",
    "description": "查询 Example 状态",
    "effect": "read",
    "confirmation": "never",
    "timeoutSeconds": 20,
    "inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}
  }]
}
```

ID、工具名、配置 key 使用小写字母开头、字母/数字/下划线/短横线，最长 64 字符。配置支持 text、path、boolean、enum，字段可声明 required、defaultValue 和 options。工具名对模型显示为 `plugin_<id>__<tool>`，不能覆盖内置工具。

工具参数支持 JSON Schema 的基本 type、required、properties、additionalProperties、enum、minLength 和数组 items 检查，不提供完整 JSON Schema 方言实现。入口与指导必须为插件目录内的普通文件；清单最多 128 KiB，指导最多 64 KiB。

工具 effect 为 read 或 write。read 使用 never；write 使用 always、createDirectOtherwiseConfirm 或 explicitDirectOtherwiseConfirm。最后一种允许用户明确要求的插件任务直接执行，AI 自行推断的写操作仍只作为建议。首版写工具按 handoff 分类，所以 createDirectOtherwiseConfirm 会要求确认。

```js
export default {
  tools: {
    status: {
      async execute(args, context) {
        return await context.exec(context.configuration.cli_path, ['status', '--json']);
      }
    }
  }
};
```

宿主上下文：

- `configuration`：本次调用固定的配置对象。
- `signal`：本次调用的 AbortSignal；取消会终止宿主管理的执行进程。
- `requestID`：原生稳定请求 ID。使用它记录检查点，避免重复产生外部操作。
- `state`：该插件的持久化 JSON 状态快照。
- `await saveState(value)`：通过宿主更新状态；同一插件调用串行执行。
- `await exec(executable, argv, {cwd?, timeoutSeconds?})`：经 ToolService 执行 CLI，返回 stdout、stderr 和 exitCode。以数组传参，不通过 Shell 拼接。默认 20 秒，单次 CLI 上限 120 秒。

写工具同时实现 `async readback(args, context, output)`。output 是执行返回值，超时后可能为 null。回读返回真实已核实结果；无法核实时返回 null，宿主标记 pendingVerification。回读不应重放创建或发送。插件状态落盘与外部操作并非原子事务，必须保存“尝试前”检查点并核实未知结果。

工具调用总超时默认 20 秒，可声明 1–240 秒。CLI 每个输出流和插件协议帧上限 512 KiB；console 输出进入安装目录的 execution.log，调用间将超过 1 MiB 的旧日志清空。取消终止本次插件进程和 CLI 客户端，不撤销已完成操作，也不自动终止外部 Agent。

插件执行进程继承用户 HOME 与常见程序 PATH，不继承模型 API Key。可信代码仍有本机用户权限；独立进程不构成安全隔离。插件工具不向外部 MCP 暴露。

## Orca

Orca 插件 0.2 的本地实现（尚未发布）使用 skill 指导 Agent 操作本机 CLI：`cli_query` 读取当前版本 `skills get orca-cli`、命令帮助和已打开项目，`cli_execute` 按 argv 执行用户要求的命令。通过 `repo list` 按名称发现 repo ID，已打开项目无需用户提供绝对路径；新项目添加才需要目录。歧义时展示候选，命令参数以当前 CLI 文档为准，不再限定三个固定交接工具。

交接默认使用项目默认 base 的独立 worktree，原目录未提交修改不会复制；Agent、工作区和其他选项遵循用户要求。回报真实 worktree ID、终端 handle 与接收阶段，提交后不默认监控完成。通用写操作先保存 requestID 检查点，未知结果不重放；原生 readback 返回 null，保留 pendingVerification，由 Agent 使用 `cli_query` 按具体命令核实目标。旧版交接 ID 仍可用 query_handoff / send_message。

CLI 支持的能力通过实时文档发现，插件不自动合并或发布。0.2 的检查与当前安装边界见[验证记录](validation/2026-10-12-orca-cli-skill.md)；旧版真实交接验收见[插件验证](validation/2026-10-11-plugins.md)。

## 飞书 / Lark

飞书插件复用用户已安装、授权的 `lark-cli`，无 npm 运行依赖，不进入应用包。配置 CLI 路径和 user/bot 身份；默认 user。此为 Asky 官方集成，非飞书官方出品。

通过 `help` 浏览命令、`query` 读取内置 skills / schema 与业务资源、`execute` 执行确认后的写操作。业务查询前读取实时 CLI Risk；无法分类时拒绝执行。所有写入使用 always 确认，CLI exit 10 需用户进一步明确同意，不能自动加 --yes。

写入先保存 requestID 检查点，未知结果不重放。通用写入口无法自动验证任意外部资源，readback 返回 null；模型随后用 query 回读真实对象。查询不自动清除历史 pendingVerification。首版不提供 raw api、登录、凭证或 CLI 更新管理。实际验证见 [飞书插件验证](validation/2026-10-11-lark-plugin.md)。
