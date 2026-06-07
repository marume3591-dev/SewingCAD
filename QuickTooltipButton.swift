//
//  QuickTooltipButton.swift
//  SewingCAD
//
//  ホバー時にツールバー下のヒント行へ通知するだけのシンプル版
//  クリック干渉なし
//

import SwiftUI

struct QuickTooltipButton<Label: View>: View {
    let action: () -> Void
    let tooltip: String
    let isDisabled: Bool
    let label: () -> Label

    /// ツールバー全体で共有するヒント文字列
    @Binding var hintText: String

    init(action: @escaping () -> Void,
         tooltip: String,
         isDisabled: Bool = false,
         hintText: Binding<String>,
         @ViewBuilder label: @escaping () -> Label) {
        self.action     = action
        self.tooltip    = tooltip
        self.isDisabled = isDisabled
        self._hintText  = hintText
        self.label      = label
    }

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1.0)
        .onHover { hovering in
            hintText = hovering ? tooltip : ""
        }
    }
}
