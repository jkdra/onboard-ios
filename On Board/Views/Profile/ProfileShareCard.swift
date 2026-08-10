import SwiftUI
import Nuke

// The profile share card — a story-ready 9:16 composition (rendered at
// 1080×1920 via ImageRenderer @3x) built for the growth loop: white ground,
// monochrome brand, ONE accent stolen from the user's avatar, The Host
// peeking from the corner per the CountdownCard watermark recipe, and a
// download CTA. Shared as an IMAGE (Instagram stories et al.); the app
// link is burned in as the CTA line.

struct ProfileShareCard: View {
    let handle: String
    let popScore: Int?
    /// Prominent avatar color, or the neutral fallback when the avatar is
    /// missing/monochrome. See UIImage.prominentColor.
    let accent: Color

    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            Color.white

            // Host watermark — CountdownCard recipe: bottom-corner anchor,
            // hung past the edge, 12% ink, clipped by the card bounds.
            // ~30% of card width — bigger than the CountdownCard's ~19%
            // (a share card is a poster, not a feed tile) but not so big
            // he crowds the CTA.
            HostFigure()
                .frame(width: 110)
                .opacity(0.12)
                .offset(x: 20, y: 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("@\(handle)")
                    .font(.custom("ZalandoSansExpanded-Regular", size: 40))
                    .fontWeight(.heavy)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                // One line each — a mid-phrase wrap ("is On / Board.")
                // reads like a mistake at display scale.
                Text("is On Board.")
                    .font(.custom("ZalandoSansExpanded-Regular", size: 40))
                    .fontWeight(.heavy)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Are you?")
                    .font(.custom("ZalandoSansExpanded-Regular", size: 40))
                    .fontWeight(.heavy)
                    .foregroundStyle(.black)
                    .lineLimit(1)

                if let popScore, popScore > 0 {
                    Text("Pop Score · \(popScore)")
                        .font(.custom("ZalandoSansSemiExpanded-Regular", size: 17))
                        .fontWeight(.semibold)
                        .foregroundStyle(.black.opacity(0.55))
                        .padding(.top, 14)
                }

                Spacer()
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text("download now")
                        .font(.custom("ZalandoSansExpanded-Regular", size: 17))
                        .fontWeight(.heavy)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.black))
                    Text("onboardapp.org")
                        .font(.custom("ZalandoSansSemiExpanded-Regular", size: 13))
                        .fontWeight(.medium)
                        .foregroundStyle(.black.opacity(0.4))
                        .padding(.leading, 4)
                }
            }
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }
}

/// Renders the card to a shareable UIImage: fetches the avatar (cache-warm
/// via the profile screen), derives the accent, renders @3x → 1080×1920.
@MainActor
enum ProfileShareCardRenderer {
    static func render(profile: Profile, popScore: Int?) async -> UIImage? {
        var accent = Color(white: 0.35) // the "darker gray" fallback
        if let urlString = profile.avatarUrl,
           let url = URL(string: urlString),
           let response = try? await ImagePipeline.shared.imageTask(with: url).response,
           let prominent = response.image.prominentColor {
            accent = Color(uiColor: prominent)
        }
        let renderer = ImageRenderer(content: ProfileShareCard(
            handle: profile.handle,
            popScore: popScore,
            accent: accent
        ))
        renderer.scale = 3
        return renderer.uiImage
    }
}

#Preview("Share card") {
    ProfileShareCard(handle: "maya.c", popScore: 128, accent: Color(red: 0.72, green: 0.31, blue: 0.18))
}

#Preview("No pop score, neutral") {
    ProfileShareCard(handle: "leokp", popScore: nil, accent: Color(white: 0.35))
}
