import Combine
import SwiftUI

struct FocusView: View {
    @Environment(AppModel.self) private var model
    let openTask: (TaskItem) -> Void
    @State private var remaining = 25 * 60
    @State private var running = false
    @State private var selectedMinutes = 25
    @State private var ambience = "Brown noise"
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                PageHeader(eyebrow: "One thing at a time", title: "Focus", subtitle: "A quieter place to make meaningful progress.")

                VStack(spacing: 19) {
                    Label("Notifications silenced", systemImage: "moon.zzz.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.white.opacity(0.08), in: Capsule())
                    Text(formatTime(remaining))
                        .font(.system(size: 68, weight: .semibold, design: .monospaced))
                        .tracking(-5)
                    ProgressView(value: Double(selectedMinutes * 60 - remaining), total: Double(selectedMinutes * 60))
                        .tint(MorrowTheme.apricot)
                    if let task = model.focusTask {
                        VStack(spacing: 4) {
                            Text(task.title).font(.subheadline.bold())
                            Text("\(task.project) · \(task.energy.rawValue) energy").font(.caption).foregroundStyle(.white.opacity(0.52))
                        }
                    }
                    HStack(spacing: 14) {
                        roundButton(symbol: "arrow.counterclockwise") { resetTimer() }
                        Button { running.toggle() } label: {
                            Image(systemName: running ? "pause.fill" : "play.fill")
                                .font(.title3.bold()).foregroundStyle(MorrowTheme.ink)
                                .frame(width: 58, height: 58)
                                .background(MorrowTheme.apricot, in: Circle())
                        }
                        roundButton(symbol: "forward.end.fill") { model.chooseNextFocusTask(); resetTimer() }
                    }
                }
                .foregroundStyle(.white)
                .padding(24)
                .background(MorrowTheme.forest, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                Picker("Session length", selection: $selectedMinutes) {
                    Text("15 min").tag(15)
                    Text("25 min").tag(25)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedMinutes) { _, newValue in remaining = newValue * 60; running = false }

                VStack(spacing: 12) {
                    SectionTitle(title: "Focus queue", count: min(3, model.openTasks.count))
                    TaskListCard(tasks: Array(model.openTasks.prefix(3)), onOpen: { task in
                        model.startFocus(task)
                        openTask(task)
                    })
                }

                SectionTitle(title: "Soundscape")
                HStack(spacing: 10) {
                    ForEach([("Brown noise", "waveform"), ("Café", "cup.and.saucer.fill"), ("Rain", "cloud.rain.fill")], id: \.0) { item in
                        Button { ambience = item.0 } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: item.1).foregroundStyle(MorrowTheme.forest)
                                Text(item.0).font(.caption.bold()).foregroundStyle(MorrowTheme.ink)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(ambience == item.0 ? MorrowTheme.forestSoft : Color.white, in: RoundedRectangle(cornerRadius: 17))
                            .overlay { RoundedRectangle(cornerRadius: 17).stroke(ambience == item.0 ? MorrowTheme.forest.opacity(0.45) : MorrowTheme.divider) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .background(MorrowTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { _ in
            guard running else { return }
            if remaining > 0 { remaining -= 1 } else { running = false; remaining = selectedMinutes * 60 }
        }
    }

    private func formatTime(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    private func resetTimer() { running = false; remaining = selectedMinutes * 60 }
    private func roundButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 42, height: 42).background(.white.opacity(0.09), in: Circle()) }
    }
}
