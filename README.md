# flutter-demo

CaoIM 客户端。覆盖 Android、iOS、macOS、Windows 和 Web，桌面端是三栏布局，手机端是底部三个 Tab。登录和上传走 app-server，消息和通话信令走 im-server，长连接由 `im-sdk-flutter` 维护。音视频媒体使用 `flutter_webrtc`，只做一对一。

## 仓库一览

| 仓库 | 作用 |
|------|------|
| im-server | 消息与长连接。好友、群、历史、已读、离线同步和一对一通话信令。端口 8080，库 `cao_im_db` |
| app-server | 客户端注册、登录、个人资料和文件上传。端口 8081，库 `cao_im_app_server` |
| im-admin | 运营后台：用户启停、群、消息检索、敏感词、系统配置、角色和审计。API 端口 8082，页面开发端口 5173，库 `cao_im_admin` |
| im-sdk-flutter | Flutter SDK。负责 WebSocket、本地消息库、会话、群和通话信令，不包含界面 |
| flutter-demo | 本仓库。同一套客户端运行在 Windows、macOS、Android、iOS 和 Web |

## 界面

### Windows

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/windows/01-conversation-list.png" alt="会话列表" width="420" /><br/><b>会话列表</b></td>
    <td align="center"><img src="docs/screenshots/windows/02-private-chat.png" alt="私聊" width="420" /><br/><b>私聊</b></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/windows/03-group-info.png" alt="群资料" width="420" /><br/><b>群资料</b></td>
    <td align="center"><img src="docs/screenshots/windows/04-contacts.png" alt="通讯录" width="420" /><br/><b>通讯录</b></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/windows/05-contact-profile.png" alt="联系人资料" width="420" /><br/><b>联系人资料</b></td>
    <td align="center"><img src="docs/screenshots/windows/06-voice-call.png" alt="语音呼叫" width="420" /><br/><b>语音呼叫</b></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><img src="docs/screenshots/windows/07-video-call.jpg" alt="视频通话" width="420" /><br/><b>视频通话</b></td>
  </tr>
</table>

### App

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/app/01-messages.png" alt="消息" width="180" /><br/><b>消息</b></td>
    <td align="center"><img src="docs/screenshots/app/02-chat.png" alt="私聊" width="180" /><br/><b>私聊</b></td>
    <td align="center"><img src="docs/screenshots/app/08-contacts.png" alt="通讯录" width="180" /><br/><b>通讯录</b></td>
    <td align="center"><img src="docs/screenshots/app/03-profile.png" alt="个人资料" width="180" /><br/><b>个人资料</b></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/app/06-emoji.png" alt="表情" width="180" /><br/><b>表情</b></td>
    <td align="center"><img src="docs/screenshots/app/07-attach.png" alt="图片视频文件" width="180" /><br/><b>图片、视频、文件</b></td>
    <td align="center"><img src="docs/screenshots/app/04-voice-call.png" alt="语音呼叫" width="180" /><br/><b>语音呼叫</b></td>
    <td align="center"><img src="docs/screenshots/app/05-video-call.jpg" alt="视频通话" width="180" /><br/><b>视频通话</b></td>
  </tr>
</table>

### Web

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/web/01-group-chat.png" alt="群聊" width="420" /><br/><b>群聊</b></td>
    <td align="center"><img src="docs/screenshots/web/02-group-info.png" alt="群资料" width="420" /><br/><b>群资料</b></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/web/03-contacts.png" alt="通讯录" width="420" /><br/><b>通讯录</b></td>
    <td align="center"><img src="docs/screenshots/web/04-voice-call.png" alt="语音呼叫" width="420" /><br/><b>语音呼叫</b></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><img src="docs/screenshots/web/05-video-incoming.png" alt="视频来电" width="420" /><br/><b>视频来电</b></td>
  </tr>
</table>

## 功能

- 注册、登录，Token 本地保存，启动时恢复会话
- 会话列表：最后一条消息、未读、置顶、免打扰、下拉刷新。当前打开的会话不再增加未读
- 私聊和群聊：文本、表情、图片、拍照、语音消息、文件、短视频
- 引用、转发、撤回、已读和群已读人数
- 本地记录与服务端消息搜索，消息收藏
- 好友申请、备注、黑名单、个人资料、二维码加好友和扫码入群
- 建群、成员拼接头像、改群名、公告、管理员、禁言、入群验证、群昵称。桌面端群资料从右侧抽屉打开
- 一对一语音、视频通话：等待铃声、接听后建立媒体、视频本地预览和切换摄像头
- 深色模式，后台新消息本地通知
- 应用图标使用产品 logo

群通话还没有做。一对一媒体只配置了公共 STUN（`stun:stun.l.google.com:19302`），同一局域网可以通。放到公网后，信令仍可用，对称 NAT 下经常没有声音和画面，需要另外部署 TURN 并把地址写进 `lib/providers/call_provider.dart` 的 `iceServers`。

## 环境

| 环境 | 版本 |
|------|------|
| Flutter | 3.x |
| Dart | 3.11 及以上 |

依赖本机的 `../im-sdk-flutter`。运行前 app-server（8081）和 im-server（8080）都要已启动。

## 服务器地址

默认地址在 `lib/config/server_config.dart`，当前写的是一台开发机的局域网 IP。换机器或上线时改这个文件，或在启动时覆盖：

```bash
flutter run --dart-define=APP_SERVER_URL=http://192.168.0.10:8081/api --dart-define=IM_SERVER_URL=http://192.168.0.10:8080/api --dart-define=IM_WS_URL=ws://192.168.0.10:8080/api/ws
```

- 真机和桌面端填写电脑的局域网 IP，或服务器域名。`localhost` 指的是手机自己
- Android 模拟器访问宿主机时，主机名用 `10.0.2.2`
- app-server 的 `file.domain` 也要改成同一台机器的可访问地址，否则发出去的图片和文件打不开
- 修改 SDK、原生库或服务器地址后做一次完整运行。热重载不会重建 Dio、长连接监听和原生库

WebSocket 使用登录返回的 `imToken`。

## 运行

```bash
cd flutter-demo
flutter pub get
flutter run
```

指定设备：

```bash
flutter devices
flutter run -d windows
flutter run -d chrome
flutter run -d <android-device-id>
```

Android 需要麦克风、摄像头和网络权限，这些已经写在 `AndroidManifest.xml`。安装包内带有 `libsqlite3.so`（`android/app/src/main/jniLibs`），因为 Android 上 Drift 加载不到系统 SQLite。`pubspec.yaml` 里 `sqlite3` 使用 `source: system`，Windows 走系统 `winsqlite3`，避免和 Android 的 so 打出两份。

iOS、macOS 的麦克风和摄像头用途说明在各自的 `Info.plist`，macOS 还在 entitlements 里打开了摄像头和音频输入。

## 打包

```bash
flutter build apk
flutter build ios
flutter build macos
flutter build windows
flutter build web
```

把 `--dart-define` 加到对应的 `flutter build` 上，安装包才会指向生产服务器。Windows 的 exe 图标在完整构建后才会换成 logo，调试热重载不会更新 exe 图标。

Web 构建产物在 `build/web`，由任意静态服务器托管。浏览器里的音视频还受页面是否 HTTPS、以及设备是否允许麦克风和摄像头影响。

## 目录

```
lib/
├── main.dart / app.dart
├── config/server_config.dart
├── theme/app_theme.dart          # 浅色与深色
├── providers/                    # 登录、会话、联系人、通话
├── services/                     # HTTP、本地通知、通话铃声
├── pages/                        # 登录、会话、聊天、群、资料、通话、桌面主页
└── widgets/
```

通话界面是盖在 `MaterialApp` 上的全局层。私聊右上角有语音和视频按钮，群聊没有。

## 联系与支持

有新功能、定制开发或合作意向，欢迎扫码加微信私信。

独立开发不易。如果这个项目对你有帮助，也可以通过微信或支付宝支持一下，你的认可是我继续更新的动力。

<table>
  <tr>
    <td align="center"><img src="docs/contact/wechat.jpg" alt="微信" width="220" /><br/><b>微信</b><br/>定制与合作</td>
    <td align="center"><img src="docs/contact/wechat-pay.jpg" alt="微信支付" width="220" /><br/><b>微信支付</b></td>
    <td align="center"><img src="docs/contact/alipay.jpg" alt="支付宝" width="220" /><br/><b>支付宝</b></td>
  </tr>
</table>

## License

MIT License
