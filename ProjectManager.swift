//
//  ProjectManager.swift
//  SewingCAD
//

import Foundation
import AppKit

class ProjectManager: ObservableObject {
    @Published var currentProject: ProjectData? = nil
    @Published var projectURL: URL? = nil
    @Published var activePartID: UUID? = nil

    static let shared = ProjectManager()

    // MARK: - プロジェクト新規作成（保存先を即選択）
    func newProject(name: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.title = "プロジェクトの保存先を選択"
            panel.nameFieldStringValue = "\(name).scadproj"
            panel.canCreateDirectories = true
            // ← allowedContentTypesを削除、拡張子を名前に含める
            
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    completion(false)
                    return
                }
                
                // パネルのURLを直接フォルダとして使う（appendingPathExtensionしない）
                let folderURL = url
                
                do {
                    try FileManager.default.createDirectory(
                        at: folderURL,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    print("フォルダ作成成功: \(folderURL)")
                } catch {
                    print("フォルダ作成失敗: \(error)")
                    completion(false)
                    return
                }
                
                let project = ProjectData(name: name)
                self.currentProject = project
                self.projectURL = folderURL
                self.activePartID = nil
                self.writeProject(project, to: folderURL)
                completion(true)
            }
        }
    }
    
    // MARK: - プロジェクト保存
    func saveProject() {
        print("=== saveProject called ===")
        print("currentProject: \(String(describing: currentProject?.name))")
        print("projectURL: \(String(describing: projectURL))")
        print("activePartID: \(String(describing: activePartID))")
        guard var project = currentProject else {
            print("❌ currentProject is nil → return")
            return
        }
        project.updatedAt = Date()
        currentProject = project

        if let url = projectURL {
            writeProject(project, to: url)
        } else {
            // 保存先未選択の場合はパネルを出す
            DispatchQueue.main.async {
                let panel = NSSavePanel()
                panel.title = "プロジェクトを保存"
                panel.nameFieldStringValue = project.name
                panel.canCreateDirectories = true
                panel.begin { response in
                    guard response == .OK, let url = panel.url else { return }
                    let folderURL = url.appendingPathExtension("scadproj")
                    do {
                        try FileManager.default.createDirectory(
                            at: folderURL,
                            withIntermediateDirectories: true
                        )
                        self.projectURL = folderURL
                        self.writeProject(project, to: folderURL)
                    } catch {
                        print("フォルダ作成失敗: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - プロジェクト読み込み
    func loadProject(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = "プロジェクトを開く"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    completion(false)
                    return
                }
                self.readProject(from: url, completion: completion)
            }
        }
    }

    // MARK: - パーツ追加
    func addPart(name: String, type: PatternPartType) -> PatternPart {
        let fileName = "\(UUID().uuidString).json"
        let part = PatternPart(name: name, type: type, fileName: fileName)
        currentProject?.parts.append(part)
        // プロジェクトファイルも即時更新
        if let url = projectURL, let project = currentProject {
            writeProject(project, to: url)
        }
        return part
    }

    // MARK: - パーツ削除
    func removePart(id: UUID) {
        guard let part = currentProject?.parts.first(where: { $0.id == id }) else {
            currentProject?.parts.removeAll { $0.id == id }
            return
        }
        // ファイル削除
        if let url = projectURL {
            let fileURL = url.appendingPathComponent(part.fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        currentProject?.parts.removeAll { $0.id == id }
        currentProject?.connections.removeAll {
            $0.fromPartID == id || $0.toPartID == id
        }
        // プロジェクトファイル更新
        if let url = projectURL, let project = currentProject {
            writeProject(project, to: url)
        }
    }

    // MARK: - パーツのPatternData保存
    func savePatternData(_ data: PatternData, for partID: UUID) {
        guard let url = projectURL,
              let part = currentProject?.parts.first(where: { $0.id == partID }) else {
            print("savePatternData: projectURL or part not found")
            return
        }
        let fileURL = url.appendingPathComponent(part.fileName)
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: fileURL)
            print("パーツ保存成功: \(part.name) → \(fileURL.lastPathComponent)")
        } catch {
            print("パーツ保存失敗: \(error)")
        }
    }

    // MARK: - パーツのPatternData読み込み
    func loadPatternData(for partID: UUID) -> PatternData? {
        guard let url = projectURL,
              let part = currentProject?.parts.first(where: { $0.id == partID }) else {
            return nil
        }
        let fileURL = url.appendingPathComponent(part.fileName)
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PatternData.self, from: data) else {
            print("パーツ読み込み: ファイルなし（新規） \(part.name)")
            return nil
        }
        print("パーツ読み込み成功: \(part.name)")
        return decoded
    }

    // MARK: - 接合部追加
    func addConnection(_ connection: SeamConnection) {
        currentProject?.connections.append(connection)
        if let url = projectURL, let project = currentProject {
            writeProject(project, to: url)
        }
    }

    // MARK: - 接合部削除
    func removeConnection(id: UUID) {
        currentProject?.connections.removeAll { $0.id == id }
        if let url = projectURL, let project = currentProject {
            writeProject(project, to: url)
        }
    }

    // MARK: - Private

    func writeProject(_ project: ProjectData, to folderURL: URL) {
        let indexURL = folderURL.appendingPathComponent("project.json")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let encoded = try encoder.encode(project)
                try encoded.write(to: indexURL)
                print("プロジェクト保存成功: \(folderURL.lastPathComponent)")
            } catch {
                print("プロジェクト保存失敗: \(error)")
            }
        }
    }

    private func readProject(from folderURL: URL, completion: @escaping (Bool) -> Void) {
        let indexURL = folderURL.appendingPathComponent("project.json")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: indexURL)
                let project = try JSONDecoder().decode(ProjectData.self, from: data)
                DispatchQueue.main.async {
                    self.currentProject = project
                    self.projectURL = folderURL
                    self.activePartID = project.parts.first?.id
                    completion(true)
                }
            } catch {
                print("プロジェクト読み込み失敗: \(error)")
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
}
