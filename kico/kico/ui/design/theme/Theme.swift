//
//  Theme.swift
//  ios
//
//  Created by TAO DAI on 2025/6/28.
//

import SwiftUI
import Combine

// MARK: - 主题协议
/// 定义应用程序主题的协议，包含颜色和字体排版属性
protocol Theme {
    // MARK: - 颜色属性
    /// 主要颜色
    var primary: Color { get }
    /// 主要颜色上的内容颜色
    var onPrimary: Color { get }
    /// 主要容器颜色
    var primaryContainer: Color { get }
    /// 主要容器上的内容颜色
    var onPrimaryContainer: Color { get }
    /// 次要颜色
    var secondary: Color { get }
    /// 次要颜色上的内容颜色
    var onSecondary: Color { get }
    /// 次要容器颜色
    var secondaryContainer: Color { get }
    /// 次要容器上的内容颜色
    var onSecondaryContainer: Color { get }
    /// 第三颜色
    var tertiary: Color { get }
    /// 第三颜色上的内容颜色
    var onTertiary: Color { get }
    /// 第三容器颜色
    var tertiaryContainer: Color { get }
    /// 第三容器上的内容颜色
    var onTertiaryContainer: Color { get }
    /// 错误颜色
    var error: Color { get }
    /// 错误颜色上的内容颜色
    var onError: Color { get }
    /// 错误容器颜色
    var errorContainer: Color { get }
    /// 错误容器上的内容颜色
    var onErrorContainer: Color { get }
    /// 背景颜色
    var background: Color { get }
    /// 背景上的内容颜色
    var onBackground: Color { get }
    /// 表面颜色
    var surface: Color { get }
    /// 表面上的内容颜色
    var onSurface: Color { get }
    /// 表面变体颜色
    var surfaceVariant: Color { get }
    /// 表面变体上的内容颜色
    var onSurfaceVariant: Color { get }
    /// 轮廓线颜色
    var outline: Color { get }
    /// 轮廓线变体颜色
    var outlineVariant: Color { get }
    /// 遮罩颜色
    var scrim: Color { get }
    /// 反向表面颜色
    var inverseSurface: Color { get }
    /// 反向表面上的内容颜色
    var inverseOnSurface: Color { get }
    /// 反向主要颜色
    var inversePrimary: Color { get }
    /// 暗淡表面颜色
    var surfaceDim: Color { get }
    /// 明亮表面颜色
    var surfaceBright: Color { get }
    /// 最低容器表面颜色
    var surfaceContainerLowest: Color { get }
    /// 低容器表面颜色
    var surfaceContainerLow: Color { get }
    /// 容器表面颜色
    var surfaceContainer: Color { get }
    /// 高容器表面颜色
    var surfaceContainerHigh: Color { get }
    /// 最高容器表面颜色
    var surfaceContainerHighest: Color { get }

    /// 主要颜色 - 中等对比度
    var primaryMediumContrast: Color { get }
    /// 主要颜色上的内容颜色 - 中等对比度
    var onPrimaryMediumContrast: Color { get }
    /// 主要容器颜色 - 中等对比度
    var primaryContainerMediumContrast: Color { get }
    /// 主要容器上的内容颜色 - 中等对比度
    var onPrimaryContainerMediumContrast: Color { get }
    /// 次要颜色 - 中等对比度
    var secondaryMediumContrast: Color { get }
    /// 次要颜色上的内容颜色 - 中等对比度
    var onSecondaryMediumContrast: Color { get }
    /// 次要容器颜色 - 中等对比度
    var secondaryContainerMediumContrast: Color { get }
    /// 次要容器上的内容颜色 - 中等对比度
    var onSecondaryContainerMediumContrast: Color { get }
    /// 第三颜色 - 中等对比度
    var tertiaryMediumContrast: Color { get }
    /// 第三颜色上的内容颜色 - 中等对比度
    var onTertiaryMediumContrast: Color { get }
    /// 第三容器颜色 - 中等对比度
    var tertiaryContainerMediumContrast: Color { get }
    /// 第三容器上的内容颜色 - 中等对比度
    var onTertiaryContainerMediumContrast: Color { get }
    /// 错误颜色 - 中等对比度
    var errorMediumContrast: Color { get }
    /// 错误颜色上的内容颜色 - 中等对比度
    var onErrorMediumContrast: Color { get }
    /// 错误容器颜色 - 中等对比度
    var errorContainerMediumContrast: Color { get }
    /// 错误容器上的内容颜色 - 中等对比度
    var onErrorContainerMediumContrast: Color { get }
    /// 背景颜色 - 中等对比度
    var backgroundMediumContrast: Color { get }
    /// 背景上的内容颜色 - 中等对比度
    var onBackgroundMediumContrast: Color { get }
    /// 表面颜色 - 中等对比度
    var surfaceMediumContrast: Color { get }
    /// 表面上的内容颜色 - 中等对比度
    var onSurfaceMediumContrast: Color { get }
    /// 表面变体颜色 - 中等对比度
    var surfaceVariantMediumContrast: Color { get }
    /// 表面变体上的内容颜色 - 中等对比度
    var onSurfaceVariantMediumContrast: Color { get }
    /// 轮廓线颜色 - 中等对比度
    var outlineMediumContrast: Color { get }
    /// 轮廓线变体颜色 - 中等对比度
    var outlineVariantMediumContrast: Color { get }
    /// 遮罩颜色 - 中等对比度
    var scrimMediumContrast: Color { get }
    /// 反向表面颜色 - 中等对比度
    var inverseSurfaceMediumContrast: Color { get }
    /// 反向表面上的内容颜色 - 中等对比度
    var inverseOnSurfaceMediumContrast: Color { get }
    /// 反向主要颜色 - 中等对比度
    var inversePrimaryMediumContrast: Color { get }
    /// 暗淡表面颜色 - 中等对比度
    var surfaceDimMediumContrast: Color { get }
    /// 明亮表面颜色 - 中等对比度
    var surfaceBrightMediumContrast: Color { get }
    /// 最低容器表面颜色 - 中等对比度
    var surfaceContainerLowestMediumContrast: Color { get }
    /// 低容器表面颜色 - 中等对比度
    var surfaceContainerLowMediumContrast: Color { get }
    /// 容器表面颜色 - 中等对比度
    var surfaceContainerMediumContrast: Color { get }
    /// 高容器表面颜色 - 中等对比度
    var surfaceContainerHighMediumContrast: Color { get }
    /// 最高容器表面颜色 - 中等对比度
    var surfaceContainerHighestMediumContrast: Color { get }

    /// 主要颜色 - 高对比度
    var primaryHighContrast: Color { get }
    /// 主要颜色上的内容颜色 - 高对比度
    var onPrimaryHighContrast: Color { get }
    /// 主要容器颜色 - 高对比度
    var primaryContainerHighContrast: Color { get }
    /// 主要容器上的内容颜色 - 高对比度
    var onPrimaryContainerHighContrast: Color { get }
    /// 次要颜色 - 高对比度
    var secondaryHighContrast: Color { get }
    /// 次要颜色上的内容颜色 - 高对比度
    var onSecondaryHighContrast: Color { get }
    /// 次要容器颜色 - 高对比度
    var secondaryContainerHighContrast: Color { get }
    /// 次要容器上的内容颜色 - 高对比度
    var onSecondaryContainerHighContrast: Color { get }
    /// 第三颜色 - 高对比度
    var tertiaryHighContrast: Color { get }
    /// 第三颜色上的内容颜色 - 高对比度
    var onTertiaryHighContrast: Color { get }
    /// 第三容器颜色 - 高对比度
    var tertiaryContainerHighContrast: Color { get }
    /// 第三容器上的内容颜色 - 高对比度
    var onTertiaryContainerHighContrast: Color { get }
    /// 错误颜色 - 高对比度
    var errorHighContrast: Color { get }
    /// 错误颜色上的内容颜色 - 高对比度
    var onErrorHighContrast: Color { get }
    /// 错误容器颜色 - 高对比度
    var errorContainerHighContrast: Color { get }
    /// 错误容器上的内容颜色 - 高对比度
    var onErrorContainerHighContrast: Color { get }
    /// 背景颜色 - 高对比度
    var backgroundHighContrast: Color { get }
    /// 背景上的内容颜色 - 高对比度
    var onBackgroundHighContrast: Color { get }
    /// 表面颜色 - 高对比度
    var surfaceHighContrast: Color { get }
    /// 表面上的内容颜色 - 高对比度
    var onSurfaceHighContrast: Color { get }
    /// 表面变体颜色 - 高对比度
    var surfaceVariantHighContrast: Color { get }
    /// 表面变体上的内容颜色 - 高对比度
    var onSurfaceVariantHighContrast: Color { get }
    /// 轮廓线颜色 - 高对比度
    var outlineHighContrast: Color { get }
    /// 轮廓线变体颜色 - 高对比度
    var outlineVariantHighContrast: Color { get }
    /// 遮罩颜色 - 高对比度
    var scrimHighContrast: Color { get }
    /// 反向表面颜色 - 高对比度
    var inverseSurfaceHighContrast: Color { get }
    /// 反向表面上的内容颜色 - 高对比度
    var inverseOnSurfaceHighContrast: Color { get }
    /// 反向主要颜色 - 高对比度
    var inversePrimaryHighContrast: Color { get }
    /// 暗淡表面颜色 - 高对比度
    var surfaceDimHighContrast: Color { get }
    /// 明亮表面颜色 - 高对比度
    var surfaceBrightHighContrast: Color { get }
    /// 最低容器表面颜色 - 高对比度
    var surfaceContainerLowestHighContrast: Color { get }
    /// 低容器表面颜色 - 高对比度
    var surfaceContainerLowHighContrast: Color { get }
    /// 容器表面颜色 - 高对比度
    var surfaceContainerHighContrast: Color { get }
    /// 高容器表面颜色 - 高对比度
    var surfaceContainerHighHighContrast: Color { get }
    /// 最高容器表面颜色 - 高对比度
    var surfaceContainerHighestHighContrast: Color { get }
    
    // MARK: - 字体排版属性
    /// 大号显示字体
    var displayLarge: TypographyStyle { get }
    /// 中号显示字体
    var displayMedium: TypographyStyle { get }
    /// 小号显示字体
    var displaySmall: TypographyStyle { get }
    /// 大号标题字体
    var headlineLarge: TypographyStyle { get }
    /// 中号标题字体
    var headlineMedium: TypographyStyle { get }
    /// 小号标题字体
    var headlineSmall: TypographyStyle { get }
    /// 大号标题字体
    var titleLarge: TypographyStyle { get }
    /// 中号标题字体
    var titleMedium: TypographyStyle { get }
    /// 小号标题字体
    var titleSmall: TypographyStyle { get }
    /// 大号正文字体
    var bodyLarge: TypographyStyle { get }
    /// 中号正文字体
    var bodyMedium: TypographyStyle { get }
    /// 小号正文字体
    var bodySmall: TypographyStyle { get }
    /// 大号标签字体
    var labelLarge: TypographyStyle { get }
    /// 中号标签字体
    var labelMedium: TypographyStyle { get }
    /// 小号标签字体
    var labelSmall: TypographyStyle { get }
    
}

// MARK: - 主题管理器
/// 管理应用程序主题的类，负责根据系统颜色方案更新当前主题
class ThemeManager: ObservableObject {
    /// 当前主题，初始为浅色主题
    @Published var currentTheme: Theme = LightTheme()
    
    /// 根据系统颜色方案更新主题
    /// - Parameter colorScheme: 系统颜色方案
    func updateTheme(for colorScheme: ColorScheme) {
        switch colorScheme {
            case .light:
                currentTheme = LightTheme() // 浅色模式用浅色主题
            case .dark:
                currentTheme = DarkTheme() // 深色模式用深色主题
            @unknown default:
                currentTheme = LightTheme()
        }
    }
}

// MARK: - 主题视图修饰符
/// 主题视图修饰符，用于在视图中应用主题
struct ThemeModifier: ViewModifier {
    /// 系统颜色方案环境变量
    @Environment(\.colorScheme) var colorScheme
    /// 主题管理器对象
    @ObservedObject var themeManager: ThemeManager
    
    /// 修饰符的主体实现
    /// - Parameter content: 被修饰的内容
    /// - Returns: 修饰后的内容
    func body(content: Content) -> some View {
        content
            .onChange(of: colorScheme) {
                themeManager.updateTheme(for: colorScheme)
            }
            .onAppear {
                themeManager.updateTheme(for: colorScheme)
            }
    }
}

// MARK: - 视图扩展
extension View {
    /// 应用主题修饰符
    /// - Parameter themeManager: 主题管理器实例
    /// - Returns: 应用主题后的视图
    func applyTheme(_ themeManager: ThemeManager) -> some View {
        self.modifier(ThemeModifier(themeManager: themeManager))
    }
}
