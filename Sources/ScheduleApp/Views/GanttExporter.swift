import SwiftUI
import AppKit
import ScheduleCore

@MainActor
enum GanttExporter {
    static func exportPDF(viewModel: ProjectViewModel, to url: URL) throws {
        let view = GanttSlideExportView(viewModel: viewModel)
        let renderer = ImageRenderer(content: view)
        var mediaBox = CGRect(origin: .zero, size: view.totalSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        renderer.render { _, draw in
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
    }

    static func exportPNG(viewModel: ProjectViewModel, to url: URL) throws {
        let view = GanttSlideExportView(viewModel: viewModel)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let cgImage = renderer.cgImage else {
            throw CocoaError(.fileWriteUnknown)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }
}

private struct GanttSlideExportView: View {
    let viewModel: ProjectViewModel

    private let taskColWidth: CGFloat = 300
    private let rowHeight: CGFloat = 30
    private let headerHeight: CGFloat = 28
    private let titleHeight: CGFloat = 54
    private let pad: CGFloat = 20

    private var bounds: (start: CalendarDay, totalDays: Int) {
        GanttChartView.timelineBounds(for: viewModel.document)
    }

    private var dayWidth: CGFloat {
        // Fit comfortably for slides while preserving readability
        let targetTimelineWidth: CGFloat = 1040
        let natural = CGFloat(bounds.totalDays) * viewModel.dayWidth
        if natural > 1600 {
            return max(4, targetTimelineWidth / CGFloat(bounds.totalDays))
        }
        return max(10, viewModel.dayWidth)
    }

    var totalSize: CGSize {
        let rows = viewModel.visibleRows
        let timelineW = CGFloat(bounds.totalDays) * dayWidth
        let bodyH = max(120, CGFloat(rows.count) * rowHeight)
        return CGSize(
            width: pad * 2 + taskColWidth + 1 + timelineW,
            height: pad * 2 + titleHeight + headerHeight + 2 + bodyH
        )
    }

    var body: some View {
        let rows = viewModel.visibleRows
        let b = bounds
        let timelineW = CGFloat(b.totalDays) * dayWidth
        let bodyH = max(120, CGFloat(rows.count) * rowHeight)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.document.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black)

                Spacer()

                if viewModel.showCriticalPath {
                    Label("Critical Path", systemImage: "circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.red)
                        .padding(.trailing, 12)
                }

                Text("\(rows.count) items")
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            .frame(height: titleHeight)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Task")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.65))
                        .padding(.horizontal, 10)
                        .frame(width: taskColWidth, height: headerHeight, alignment: .leading)
                        .background(Color(white: 0.96))

                    Rectangle().fill(Color.black.opacity(0.12)).frame(width: 1, height: headerHeight)

                    Canvas { context, size in
                        GanttChartView.drawTimelineHeader(
                            context: &context,
                            size: size,
                            start: b.start,
                            totalDays: b.totalDays,
                            dayWidth: dayWidth,
                            timeScale: viewModel.timeScale,
                            workingCalendar: viewModel.document.workingCalendar
                        )
                    }
                    .frame(width: timelineW, height: headerHeight)
                    .background(Color(white: 0.96))
                }

                Rectangle().fill(Color.black.opacity(0.14)).frame(height: 1)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            HStack(spacing: 6) {
                                Text(row.task.identifier)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Color.black.opacity(0.45))
                                    .frame(width: 34, alignment: .leading)

                                if row.depth > 0 {
                                    Spacer().frame(width: CGFloat(row.depth) * 12)
                                }

                                Text(row.task.title)
                                    .font(row.isGroup || row.task.isMilestone ? .caption.weight(.semibold) : .caption)
                                    .foregroundStyle(Color.black.opacity(0.9))
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer(minLength: 4)

                                Text(row.task.isMilestone ? "◆" : "\(row.task.durationDays)d")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(row.task.isMilestone ? ScheduleTheme.accent : Color.black.opacity(0.5))
                            }
                            .padding(.horizontal, 10)
                            .frame(width: taskColWidth, height: rowHeight)
                            .background(row.isGroup ? Color.black.opacity(0.03) : Color.clear)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.black.opacity(0.08)).frame(height: 0.5)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: taskColWidth, height: bodyH)

                    Rectangle().fill(Color.black.opacity(0.12)).frame(width: 1, height: bodyH)

                    Canvas { context, size in
                        GanttChartView.drawGanttBody(
                            context: &context,
                            size: size,
                            rows: rows,
                            start: b.start,
                            totalDays: b.totalDays,
                            dayWidth: dayWidth,
                            rowHeight: rowHeight,
                            timeScale: viewModel.timeScale,
                            workingCalendar: viewModel.document.workingCalendar,
                            selectedTaskID: nil,
                            showCriticalPath: viewModel.showCriticalPath
                        )
                    }
                    .frame(width: timelineW, height: bodyH)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(pad)
        .frame(width: totalSize.width, height: totalSize.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
