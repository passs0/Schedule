import SwiftUI
import ScheduleCore

struct TemplateChooserView: View {
    let isModal: Bool
    let onSelectTemplate: (ProjectTemplate) -> Void
    let onImport: () -> Void
    var onCancel: (() -> Void)? = nil

    @State private var selectedTemplate: ProjectTemplate = .hardwareProduct

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    quickActionsSection
                    templatesSection
                }
                .padding(24)
            }
            if isModal {
                Divider()
                footerBar
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to Schedule")
                    .font(.title2.weight(.semibold))
                Text("Choose an engineering template, start with a blank slate, or import an existing task list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            Button {
                onSelectTemplate(.blank)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus")
                        .font(.title3)
                        .foregroundStyle(ScheduleTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(ScheduleTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Blank Slate")
                            .font(.callout.weight(.semibold))
                        Text("Start with an empty schedule")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                onImport()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title3)
                        .foregroundStyle(ScheduleTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(ScheduleTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import Task List…")
                            .font(.callout.weight(.semibold))
                        Text("Excel (.xlsx), CSV, or MS Project XML")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engineering & Tech Templates")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(ProjectTemplate.allCases.filter { $0 != .blank }) { template in
                    templateCard(template)
                }
            }
        }
    }

    private func templateCard(_ template: ProjectTemplate) -> some View {
        let isSelected = selectedTemplate == template

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: template.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : ScheduleTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        isSelected ? ScheduleTheme.accent : ScheduleTheme.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                Spacer()

                Text(template.category.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? ScheduleTheme.accent : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (isSelected ? ScheduleTheme.accent : Color.secondary).opacity(0.12),
                        in: Capsule()
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(template.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Text(isModal ? "Double-click or Choose" : "Use Template")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ScheduleTheme.accent)
                    .opacity(isSelected || !isModal ? 1 : 0)
            }
        }
        .padding(14)
        .frame(minHeight: 132, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? ScheduleTheme.accent : Color(nsColor: .separatorColor).opacity(0.55),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(count: 2) {
            selectedTemplate = template
            onSelectTemplate(template)
        }
        .onTapGesture(count: 1) {
            selectedTemplate = template
            if !isModal {
                onSelectTemplate(template)
            }
        }
    }

    private var footerBar: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                onCancel?()
            }
            .keyboardShortcut(.cancelAction)

            Button("Choose") {
                onSelectTemplate(selectedTemplate)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
