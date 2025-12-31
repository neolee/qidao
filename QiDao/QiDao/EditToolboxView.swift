import SwiftUI

struct EditToolboxView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject private var langManager = LanguageManager.shared

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        GroupBox(label: Label("Edit Toolbox".localized, systemImage: "pencil.and.outline")) {
            VStack(spacing: 15) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(EditTool.allCases) { tool in
                        ToolButton(
                            tool: tool,
                            isSelected: viewModel.activeEditTool == tool,
                            action: { viewModel.activeEditTool = tool }
                        )
                    }
                }
                .padding(.vertical, 5)

                if viewModel.activeEditTool == .markLabel {
                    HStack {
                        Text("Label:".localized)
                            .font(.caption)
                        TextField("", text: $viewModel.editLabelText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.center)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Next Player:".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Button(action: { viewModel.setNextPlayer(.black) }) {
                            HStack {
                                Image(systemName: viewModel.nextColor == .black ? "largecircle.fill.circle" : "circle.fill")
                                Text("Black".localized)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(viewModel.nextColor == .black ? Color.black.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(viewModel.nextColor == .black ? .primary : .secondary)

                        Button(action: { viewModel.setNextPlayer(.white) }) {
                            HStack {
                                Image(systemName: viewModel.nextColor == .white ? "largecircle.fill.circle" : "circle")
                                Text("White".localized)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(viewModel.nextColor == .white ? Color.black.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(viewModel.nextColor == .white ? .primary : .secondary)
                    }
                }

                Divider()

                Button(action: { viewModel.deleteCurrentBranch() }) {
                    Label("Delete Branch".localized, systemImage: "trash")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(5)
        }
    }
}

struct ToolButton: View {
    let tool: EditTool
    let isSelected: Bool
    let action: () -> Void
    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tool.icon)
                    .font(.system(size: 18))
                Text(tool.label)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle()) // Make the entire area clickable
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(tool.label)
    }
}
