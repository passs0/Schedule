import SwiftUI
import AppKit
import ScheduleCore

final class ScheduleAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct ScheduleApp: App {
    @NSApplicationDelegateAdaptor(ScheduleAppDelegate.self) private var appDelegate
    @State private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup("Schedule") {
            MainWindowView(store: store)
                .tint(ScheduleTheme.accent)
        }
        .defaultSize(width: 560, height: 480)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…") {
                    NotificationCenter.default.post(name: .scheduleNewProject, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open / Import…") {
                    NotificationCenter.default.post(name: .scheduleOpenDocument, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .scheduleSaveDocument, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As…") {
                    NotificationCenter.default.post(name: .scheduleSaveDocumentAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandMenu("Task") {
                Button("New Task") {
                    NotificationCenter.default.post(name: .scheduleNewTask, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("New Milestone") {
                    NotificationCenter.default.post(name: .scheduleNewMilestone, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                Button("Indent") {
                    NotificationCenter.default.post(name: .scheduleIndentTask, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Outdent") {
                    NotificationCenter.default.post(name: .scheduleOutdentTask, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Divider()

                Button("Start After Previous Task") {
                    NotificationCenter.default.post(name: .scheduleLinkPrevious, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Add Relationship…") {
                    NotificationCenter.default.post(name: .scheduleAddDependency, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button("Toggle Inspector") {
                    NotificationCenter.default.post(name: .scheduleToggleInspector, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }
}
