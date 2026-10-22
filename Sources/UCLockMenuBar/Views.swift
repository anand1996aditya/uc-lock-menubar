import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: LockModel
    var staticMode: Bool = false
    @State private var showSettings = false
    @State private var selectedActivity: Activity?

    var body: some View {
        VStack(spacing: 0) {
            headerCard
            Divider()
            if model.needsSetup {
                setupPrompt
            } else {
                if let doorbell = model.pendingDoorbell {
                    pendingBanner(doorbell)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                activityList
            }
            Divider()
            footer
        }
        .frame(width: 392, height: staticMode ? nil : 566)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $selectedActivity) { activity in
            PhotoViewer(activity: activity)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.device.name)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(2)
                    if let battery = model.device.battery {
                        batteryPill(battery)
                    }
                }
                Spacer(minLength: 0)
            }
            unlockSummary
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color.orange.opacity(0.16),
                                              Color.yellow.opacity(0.06),
                                              Color.clear],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var unlockSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let unlock = model.lastUnlock {
                Text("LAST UNLOCK · \(unlock.timeText)")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Text(model.lastUnlockPerson ?? unlock.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let method = model.lastUnlockMethod {
                    Text(method)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("STATUS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Text(model.statusLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var artwork: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.20))
                .frame(width: 116, height: 116)
                .blur(radius: 26)
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color.gray.opacity(0.10), Color.gray.opacity(0.03)],
                                     startPoint: .top, endPoint: .bottom))
            if let url = model.device.artworkURL, let cached = ImageCache.shared.image(for: url) {
                Image(nsImage: cached).resizable().scaledToFit().padding(6)
            } else if let url = model.device.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    default: Image(systemName: "lock.rectangle.stack.fill")
                            .font(.system(size: 30)).foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            } else {
                Image(systemName: "lock.rectangle.stack.fill")
                    .font(.system(size: 30)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 86, height: 128)
    }

    private func batteryPill(_ level: Int) -> some View {
        let color: Color = level <= 20 ? .red : (level <= 50 ? .orange : .green)
        let symbol: String = level <= 20 ? "battery.25" : (level <= 50 ? "battery.50" : "battery.100")
        return HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
            Text("\(level)%")
                .font(.system(size: 12, weight: .semibold))
            if model.device.batteryCritical {
                Text("· replace")
                    .font(.system(size: 10))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func pendingBanner(_ activity: Activity) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Door bell rung")
                    .font(.system(size: 13, weight: .semibold))
                Text(activity.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if activity.imageURL != nil {
                Button("View photo") { selectedActivity = activity }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent activity")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if staticMode {
                VStack(spacing: 0) {
                    ForEach(model.activities.prefix(5)) { activity in
                        ActivityRow(activity: activity) {
                            if activity.imageURL != nil { selectedActivity = activity }
                        }
                        Divider().padding(.leading, 16)
                    }
                }
                .padding(.bottom, 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.activities) { activity in
                            ActivityRow(activity: activity) {
                                if activity.imageURL != nil { selectedActivity = activity }
                            }
                            Divider().padding(.leading, 16)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private var setupPrompt: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "key.fill").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Add your session token").font(.system(size: 15, weight: .semibold))
            Text("Open Settings and paste the bearer token from the Urban Company app session.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let updated = model.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text(model.errorMessage ?? "Not updated yet")
                    .font(.system(size: 10))
                    .foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Text("Refresh")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(model.isRefreshing ? Color.secondary.opacity(0.4) : Color.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .help("Refresh now")
            Button {
                showSettings = true
            } label: {
                Text("Settings")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quit UC Lock")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ActivityRow: View {
    let activity: Activity
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let url = activity.imageURL, let cached = ImageCache.shared.image(for: url) {
                Image(nsImage: cached)
                    .resizable().scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let url = activity.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color.gray.opacity(0.12)
                            Image(systemName: "person.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let avatar = Family.avatar(for: activity) {
                Image(nsImage: avatar)
                    .resizable().scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.10))
                    Image(systemName: activity.isUnlock ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 46, height: 46)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(rowSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if activity.imageURL != nil {
                Image(systemName: "photo")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var rowSubtitle: String {
        if activity.group == "Today" || activity.group.isEmpty {
            return activity.subtitle
        }
        return "\(activity.group) · \(activity.subtitle)"
    }
}

struct PhotoViewer: View {
    let activity: Activity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title).font(.system(size: 15, weight: .semibold))
                    Text(activity.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            if let url = activity.imageURL, let cached = ImageCache.shared.image(for: url) {
                Image(nsImage: cached).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let url = activity.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    default: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(width: 560, height: 620)
    }
}

struct SettingsView: View {
    @ObservedObject var model: LockModel
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var deviceId = ""
    @State private var applianceId = ""
    @State private var saved = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session").font(.system(size: 16, weight: .semibold))
            Text("The app uses the same bearer token as the Urban Company app. The token is stored with owner-only permissions.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Bearer token", text: $token)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Device id", text: $deviceId).textFieldStyle(.roundedBorder)
                TextField("Appliance id", text: $applianceId).textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
            if saved {
                Text("Saved.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !error.isEmpty {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .padding(18)
        .frame(width: 470)
        .onAppear {
            token = model.config.token
            deviceId = model.config.deviceId
            applianceId = model.config.applianceId
        }
    }

    private func save() {
        error = ""
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            error = "Paste a valid bearer token before saving."
            return
        }
        let cleanDevice = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAppliance = applianceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanDevice.isEmpty && !Config.isValidIdentifier(cleanDevice) {
            error = "Device id should be 8-32 hex characters."
            return
        }
        if !cleanAppliance.isEmpty && !Config.isValidIdentifier(cleanAppliance) {
            error = "Appliance id should be 8-32 hex characters."
            return
        }
        var updated = model.config
        updated.token = cleanToken
        if !cleanDevice.isEmpty { updated.deviceId = cleanDevice }
        if !cleanAppliance.isEmpty { updated.applianceId = cleanAppliance }
        model.save(updated)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
    }
}
