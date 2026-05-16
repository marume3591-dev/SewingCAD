//
//  MirrorView.swift
//  SewingCAD
//

import SwiftUI

struct MirrorView: View {
    let onConfirm: (MirrorAxis, Bool) -> Void
    let onCancel: () -> Void

    enum MirrorAxis: String, CaseIterable {
        case vertical   = "垂直軸（左右反転）"
        case horizontal = "水平軸（上下反転）"
        case line       = "選択した線を軸"
    }

    @State private var axis: MirrorAxis = .vertical
    @State private var keepOriginal: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("鏡像コピー")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("反転軸").font(.subheadline).foregroundColor(.secondary)
                ForEach(MirrorAxis.allCases, id: \.self) { a in
                    Button(action: { axis = a }) {
                        HStack {
                            Image(systemName: axis == a ? "largecircle.fill.circle" : "circle")
                            Text(a.rawValue).font(.system(size: 13))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Toggle("元のパターンを残す", isOn: $keepOriginal)
                .font(.system(size: 13))

            if axis == .line {
                Text("※ 次に軸にする線をクリックしてください")
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
            }

            Divider()

            HStack {
                Spacer()
                Button("キャンセル") { onCancel() }.buttonStyle(.bordered)
                Button("確定") { onConfirm(axis, keepOriginal) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
