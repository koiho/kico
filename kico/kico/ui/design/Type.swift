//
//  Type.swift
//  ios
//
//  Created by TAO DAI on 2025/7/27.
//

import SwiftUI

// MARK: - 字体排版定义
/// 应用程序的字体排版常量集合，定义了不同级别的字体样式
struct AppTypography {
    // MARK: - Display (显示字体)
    /// 大号显示字体 - 用于最大标题
    static let displayLarge = TypographyStyle(
        size: 57,
        weight: .regular,
        lineHeight: 64
    )
    
    /// 中号显示字体 - 用于较大标题
    static let displayMedium = TypographyStyle(
        size: 45,
        weight: .regular,
        lineHeight: 52
    )
    
    /// 小号显示字体 - 用于中等标题
    static let displaySmall = TypographyStyle(
        size: 36,
        weight: .regular,
        lineHeight: 44
    )
    
    // MARK: - Headline (标题字体)
    /// 大号标题字体 - 用于页面标题
    static let headlineLarge = TypographyStyle(
        size: 32,
        weight: .regular,
        lineHeight: 40
    )
    
    /// 中号标题字体 - 用于章节标题
    static let headlineMedium = TypographyStyle(
        size: 28,
        weight: .regular,
        lineHeight: 36
    )
    
    /// 小号标题字体 - 用于小节标题
    static let headlineSmall = TypographyStyle(
        size: 24,
        weight: .regular,
        lineHeight: 32
    )
    
    // MARK: - Title (标题字体)
    /// 大号标题字体 - 用于卡片标题
    static let titleLarge = TypographyStyle(
        size: 22,
        weight: .bold,
        lineHeight: 28
    )
    
    /// 中号标题字体 - 用于列表项标题
    static let titleMedium = TypographyStyle(
        size: 16,
        weight: .bold,
        lineHeight: 24
    )
    
    /// 小号标题字体 - 用于辅助标题
    static let titleSmall = TypographyStyle(
        size: 14,
        weight: .bold,
        lineHeight: 20
    )
    
    // MARK: - Body (正文字体)
    /// 大号正文字体 - 用于主要文本内容
    static let bodyLarge = TypographyStyle(
        size: 16,
        weight: .regular,
        lineHeight: 24
    )
    
    /// 中号正文字体 - 用于次要文本内容
    static let bodyMedium = TypographyStyle(
        size: 14,
        weight: .regular,
        lineHeight: 20
    )
    
    /// 小号正文字体 - 用于辅助文本内容
    static let bodySmall = TypographyStyle(
        size: 12,
        weight: .regular,
        lineHeight: 16
    )
    
    // MARK: - Label (标签字体)
    /// 大号标签字体 - 用于按钮和重要标签
    static let labelLarge = TypographyStyle(
        size: 14,
        weight: .medium,
        lineHeight: 20
    )
    
    /// 中号标签字体 - 用于普通标签
    static let labelMedium = TypographyStyle(
        size: 12,
        weight: .medium,
        lineHeight: 16
    )
    
    /// 小号标签字体 - 用于辅助标签
    static let labelSmall = TypographyStyle(
        size: 10,
        weight: .medium,
        lineHeight: 12
    )
}

// MARK: - 字体排版样式模型
/// 字体排版样式模型，包含字体大小、粗细和行高属性
struct TypographyStyle {
    /// 字体大小
    let size: CGFloat
    /// 字体粗细
    let weight: Font.Weight
    /// 行高
    let lineHeight: CGFloat
    
    /// 创建 SwiftUI Font 对象
    var font: Font {
        .system(size: size, weight: weight)
    }
}
