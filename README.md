# CaoIM - 即时通讯 Flutter Demo 客户端

## 项目简介

CaoIM 是一个基于 Flutter 开发的即时通讯（IM）应用 Demo 客户端，采用现代化的 UI 设计和 Material Design 规范。该项目完整实现了 IM 应用的核心功能模块，包括用户认证、单聊/群聊、会话管理、联系人管理等。

## 功能特性

### ✅ 已实现功能

- **用户认证系统**
  - 用户注册与登录
  - JWT Token 持久化存储
  - 自动登录状态检测

- **即时消息功能**
  - 单聊消息收发
  - 群组聊天
  - 文本消息发送
  - 图片选择与发送（支持相册和拍照）
  - 消息气泡 UI（自己靠右蓝色，对方靠左白色）
  - 消息时间戳显示
  - 发送状态指示

- **会话管理**
  - 会话列表展示
  - 最后消息预览
  - 未读消息计数
  - 下拉刷新
  - 会话时间格式化显示

- **通讯录功能**
  - 好友列表展示
  - 新朋友入口
  - 群组管理
  - 创建群组（选择成员）

- **个人中心**
  - 用户信息展示
  - 设置项列表
  - 退出登录
  - 关于我们

### 🎨 UI 特性

- Material Design 3 规范
- 蓝色主色调 (#2196F3)
- 支持深色模式基础配置
- 流畅的动画过渡效果
- 响应式布局设计
- 圆角卡片式界面

## 技术架构

### 技术栈

| 技术 | 用途 |
|------|------|
| **Flutter** | 跨平台 UI 框架 |
| **Provider** | 状态管理 |
| **Dio** | HTTP 网络请求 |
| **SharedPreferences** | 本地数据持久化 |
| **ImagePicker** | 图片选择器 |
| **CachedNetworkImage** | 网络图片缓存 |
| **Intl** | 国际化日期格式化 |

### 项目结构

```
lib/
├── main.dart                 # 应用入口，配置 Provider
├── app.dart                  # MaterialApp 配置
├── theme/
│   └── app_theme.dart        # 主题样式（亮色/暗色模式）
├── router/
│   └── app_router.dart       # 路由配置
├── models/
│   ├── user_model.dart       # 用户信息模型
│   ├── chat_model.dart       # 聊天状态模型
│   └── message_model.dart    # 消息模型
├── providers/
│   ├── auth_provider.dart    # 认证状态管理
│   ├── chat_provider.dart    # 聊天状态管理
│   └── contact_provider.dart # 联系人管理
├── services/
│   ├── api_service.dart      # HTTP API 服务
│   ├── im_service.dart       # WebSocket IM 服务
│   └── storage_service.dart  # 本地存储服务
├── pages/
│   ├── splash_page.dart      # 启动页
│   ├── login_page.dart       # 登录页
│   ├── register_page.dart    # 注册页
│   ├── home_page.dart        # 主页（底部导航）
│   ├── conversation_list_page.dart  # 会话列表
│   ├── chat_page.dart        # 聊天页面
│   ├── contacts_page.dart    # 通讯录
│   ├── group_create_page.dart # 创建群组
│   ├── group_chat_page.dart  # 群聊页面
│   └── profile_page.dart     # 个人中心
└── widgets/
    ├── message_bubble.dart   # 消息气泡组件
    ├── conversation_item.dart # 会话列表项
    └── avatar_widget.dart    # 头像组件
```

## 运行步骤

### 前置要求

- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Android Studio / VS Code
- Android SDK / Xcode（iOS）

### 安装依赖

```bash
cd flutter-demo
flutter pub get
```

### 运行项目

**Android:**
```bash
flutter run
```

**iOS:**
```bash
flutter run ios
```

**Web（实验性）:**
```bash
flutter run chrome
```

## API 对接说明

### 后端接口配置

项目已配置好与后端对接的接口地址：

#### App Server (HTTP API)
- **Base URL**: `http://localhost:8080/api`
- **登录**: `POST /auth/login`
- **注册**: `POST /auth/register`
- **获取用户信息**: `GET /users/{id}`
- **会话列表**: `GET /conversations`
- **创建会话**: `POST /conversations`
- **消息列表**: `GET /conversations/{id}/messages`
- **发送消息**: `POST /conversations/{id}/messages`
- **联系人列表**: `GET /contacts`

#### IM Server (WebSocket)
- **WebSocket URL**: `ws://localhost:8081/api/ws`
- 用于实时消息推送

### 对接 im-sdk 说明

当前版本使用 HTTP API + WebSocket 实现消息通信。如需对接专业的 IM SDK：

1. **替换 IMService**:
   ```dart
   // 在 lib/services/im_service.dart 中
   // 替换为实际 IM SDK 的初始化和连接逻辑
   ```

2. **修改 ChatProvider**:
   - 使用 IM SDK 的消息监听替代 HTTP 轮询
   - 实现 SDK 的消息发送方法

3. **Token 认证**:
   - 登录后获取的 JWT Token 可用于 IM SDK 的身份验证

## 页面截图说明

### 主要页面流程

1. **启动页** → 显示品牌 Logo 和动画，自动检测登录状态
2. **登录页** → 用户名+密码表单，跳转注册或进入主页
3. **注册页** → 用户名、昵称、密码、确认密码
4. **主页** → 底部三个 Tab（消息、通讯录、我的）
5. **会话列表** → 显示所有聊天会话，支持下拉刷新
6. **聊天页** → 气泡式消息 UI，支持文本和图片
7. **通讯录** → 好友列表，新朋友/群组入口
8. **创建群组** → 输入群名，多选成员
9. **个人中心** → 用户信息、设置项、退出登录

## 注意事项

### 开发环境

1. 确保 Flutter 环境正确配置：
   ```bash
   flutter doctor
   ```

2. iOS 需要配置权限（相机、相册访问）

3. 需要启动后端服务才能正常使用完整功能：
   - App Server: `localhost:8080`
   - IM Server: `localhost:8081`

### 已知限制

- 当前为 Demo 版本，部分功能使用 Mock 数据
- 图片上传需配合后端文件存储服务
- 群聊功能为基础实现
- 未实现消息撤回、转发等高级功能

### 性能优化建议

- 使用 ListView.builder 进行长列表渲染
- 图片使用 CachedNetworkImage 缓存
- Provider 精细化更新，避免不必要的 rebuild
- WebSocket 连接管理优化

## 版本信息

- **Version**: 1.0.0
- **Build**: 1
- **Last Update**: 2025-05-21

## License

MIT License

## 联系方式

如有问题或建议，欢迎提交 Issue 或 Pull Request。
