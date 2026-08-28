# 这不得瘦死 · iOS / iPadOS / macOS

这是原微信小程序的原生 SwiftUI 重写版，最低支持 iOS 26、iPadOS 26 和 macOS 26。

## 打开

用 Xcode 打开 `ZheBuDeShouSi.xcodeproj`，选择 iPhone/iPad 模拟器、真机或 Mac 后运行。第一次真机运行需要在 Xcode 的 Signing & Capabilities 中选择自己的 Apple Developer Team。

## TestFlight

本次版本的中文测试说明位于 `TestFlight/WhatToTest.zh-Hans.txt`。Xcode Cloud 上传 TestFlight 构建时会读取这个与 `ZheBuDeShouSi.xcodeproj` 同级的文件，并自动填写简体中文“测试内容”；它采用静态维护方式，每次正式构建前更新并提交即可。如果使用本机 Organizer 上传，也可以在上传页面的 “What to Test” 中直接粘贴文件内容。

macOS 的 App Store Connect 导出配置位于 `Distribution/ExportOptions-mac-app-store.plist`，命令行导出时使用该路径。

## 已包含

- 首页、趋势、习惯、我的四页底部导航
- 首页轻盈进度、当前体重、目标体重和体重历史
- 体重原生双列 Wheel Picker，整数和小数分别滑动
- 居中的记录弹窗，饮食、饮水、运动和体重记录
- 趋势折线图、周期切换、统计和历史记录
- 体围记录：腰围、臀围、左右上臂围、左右大腿围、左右小腿围及独立趋势图
- 习惯清单：饮食、运动、睡眠、喝水、排便、吃药、生理期
- Apple 健康连接：授权后导入最近 90 天体重、腰围、饮食热量、饮水、运动、睡眠和生理期，并按 HealthKit 样本 ID 去重
- UserDefaults 本地保存体重、饮水、活动和趋势历史

## Apple 健康

在 iPhone 上进入“我的” -> “Apple 健康” -> “连接”，在系统弹窗中允许读取需要的项目。导入只读，不会修改 Apple 健康；本地手动记录仍然保留。臀围、上臂、大腿、小腿、排便和吃药没有稳定的通用 HealthKit 数值，继续在应用内手动记录。

macOS 版本使用原生 SwiftUI 窗口运行，输入框会自动使用 macOS 的文本输入行为；iOS/iPadOS 版本保留数字键盘和滚轮选择器交互。iPadOS 和 macOS 会将主要内容限制在居中的宽度内，便于宽屏阅读。

## 目录

- `ZheBuDeShouSi/App`：App 入口、Info.plist 和签名 entitlements
- `ZheBuDeShouSi/Shared`：跨平台模型与 SwiftUI 界面
- `ZheBuDeShouSi/Features`：健康数据和 Apple 健康功能
- `ZheBuDeShouSi/Resources`：AppIcon 和其他资源
- `Distribution`：归档导出配置
- `TestFlight`：TestFlight 测试说明
