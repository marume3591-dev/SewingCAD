//
//  TextInputView.swift
//  SewingCAD
//

import SwiftUI

struct TextInputView: View {
    @Binding var text: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("テキストを入力")
                .font(.headline)

            Divider()

            TextField("テキスト", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))

            Divider()

            HStack {
                Spacer()
                Button("キャンセル") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                Button("OK") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}
