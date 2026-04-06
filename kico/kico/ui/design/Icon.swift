//
//  Icon.swift
//  ios
//
//  Created by TAO DAI on 2025/7/29.
//

import SwiftUI

// MARK: - 图标定义
/// 应用程序的图标常量集合，定义了应用中使用的各种图标
struct AppIcon {
    // MARK: - Tab Bar Icons
    /// 首页图标
    static let home = "house.fill"
    /// 个人资料图标
    static let profile = "person.fill"
    /// 欢迎页面图标
    static let welcome = "hand.wave.fill"
    
    // MARK: - Navigation Icons
    /// 返回图标
    static let back = "chevron.left"
    /// 前进图标
    static let forward = "chevron.right"
    /// 关闭图标
    static let close = "xmark"
    /// 更多选项图标
    static let more = "ellipsis"
    
    // MARK: - Action Icons
    /// 添加图标
    static let add = "plus"
    /// 删除图标
    static let delete = "trash"
    /// 编辑图标
    static let edit = "pencil"
    /// 保存图标
    static let save = "square.and.arrow.down"
    /// 分享图标
    static let share = "square.and.arrow.up"
    
    // MARK: - Status Icons
    /// 成功图标
    static let success = "checkmark.circle"
    /// 错误图标
    static let error = "xmark.circle"
    /// 警告图标
    static let warning = "exclamationmark.triangle"
    /// 信息图标
    static let info = "info.circle"
    
    // MARK: - Media Icons
    /// 播放图标
    static let play = "play.fill"
    /// 暂停图标
    static let pause = "pause.fill"
    /// 停止图标
    static let stop = "stop.fill"
    /// 上一首图标
    static let previous = "backward.fill"
    /// 下一首图标
    static let next = "forward.fill"
}
