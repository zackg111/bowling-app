import SwiftUI
import PhotosUI
import UIKit

/// A bowler's photo, or their initials on a color picked from their name.
struct AvatarView: View {
    let bowler: Bowler
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let data = bowler.photoData, let image = PhotoCache.image(for: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(color.gradient)
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: String {
        bowler.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    private var color: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red, .mint, .cyan]
        let hash = bowler.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return palette[hash % palette.count]
    }
}

/// Decoded bowler photos, keyed by their bytes. Lists redraw rows often, and
/// decoding every photo each time made scrolling and selecting stutter. A new
/// photo has different bytes, so it's simply a new entry.
enum PhotoCache {
    private final class Box {
        let image: UIImage?
        init(_ image: UIImage?) { self.image = image }
    }

    private static let cache: NSCache<NSNumber, Box> = {
        let cache = NSCache<NSNumber, Box>()
        cache.countLimit = 120
        return cache
    }()

    static func image(for data: Data) -> UIImage? {
        // Hash every byte: Data's own hash only looks at the first 80, and
        // JPEG headers all look alike.
        var hasher = Hasher()
        data.withUnsafeBytes { hasher.combine(bytes: $0) }
        let key = NSNumber(value: hasher.finalize())
        if let hit = cache.object(forKey: key) { return hit.image }
        let image = UIImage(data: data)?.preparingForDisplay()
        cache.setObject(Box(image), forKey: key)
        return image
    }
}

/// Picks a photo from the library and stores a downscaled copy on the bowler.
struct AvatarPicker: View {
    @Bindable var bowler: Bowler
    var size: CGFloat = 120
    @State private var item: PhotosPickerItem?
    @State private var picking = false

    var body: some View {
        VStack(spacing: 12) {
            Button { picking = true } label: {
                AvatarView(bowler: bowler, size: size)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .padding(8)
                            .glassEffect()
                    }
            }
            .buttonStyle(.plain)
            .photosPicker(isPresented: $picking, selection: $item, matching: .images)

            if bowler.photoData != nil {
                Button("Remove Photo", role: .destructive) { bowler.photoData = nil }
                    .font(.footnote)
            }
        }
        .onChange(of: item) {
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    bowler.photoData = Self.downscaled(data)
                }
                item = nil
            }
        }
    }

    static func downscaled(_ data: Data, maxSide: CGFloat = 512) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
