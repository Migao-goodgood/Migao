# 这不得瘦死 · iOS / iPadOS / macOS

这是原微信小程序的原生 SwiftUI 重写版，最低支持 iOS 26、iPadOS 26 和 macOS 26。

## 打开

用 Xcode 打开 `ZheBuDeShouSi.xcodeproj`，选择 iPhone/iPad 模拟器、真机或 Mac 后运行。第一次真机运行需要在 Xcode 的 Signing & Capabilities 中选择自己的 Apple Developer Team。

## 已包含

- 首页、趋势、我的三页底部导航
- 当前体重、目标进度、饮水和运动概览
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
