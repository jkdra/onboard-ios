import SwiftUI
import Nuke

// The profile share card — a story-ready 9:16 composition (rendered at
// 1080×1920 via ImageRenderer @3x) built for the growth loop: white ground,
// monochrome brand, ONE accent stolen from the user's avatar, the avatar
// INLINE in the leading-aligned lock-up (a glyph in the sentence — the
// brand's alignment), and The Host as a full-figure cameo
// presenting the download CTA (a corner-crop watermark read as "rounded
// rect with a dot" — his identity is the eye AND the mouth notch, so he
// appears whole). Shared as an IMAGE (Instagram stories et al.); the app
// link is burned in as the CTA line.

struct ProfileShareCard: View {
    let handle: String
    let popScore: Int?
    /// Prominent avatar color, or the neutral fallback when the avatar is
    /// missing/monochrome. See UIImage.prominentColor.
    let accent: Color
    /// The avatar itself; nil renders the monogram fallback (handle initial
    /// on the accent), so avatarless users still get a composed card.
    var avatar: UIImage? = nil

    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            Color.white

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 48)

                // Leading-aligned lock-up (the brand's alignment), with the
                // avatar INLINE — a glyph in the sentence, sized to the
                // display line and baseline-seated, not a badge floating
                // above the words.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        avatarCircle
                            .frame(width: 44, height: 44)
                        Text("@\(handle)")
                            .font(.custom("ZalandoSansExpanded-Regular", size: 34))
                            .fontWeight(.heavy)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    // One line each — a mid-phrase wrap reads like a mistake
                    // at display scale.
                    Text("is On Board.")
                        .font(.custom("ZalandoSansExpanded-Regular", size: 34))
                        .fontWeight(.heavy)
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Are you?")
                        .font(.custom("ZalandoSansExpanded-Regular", size: 34))
                        .fontWeight(.heavy)
                        .foregroundStyle(.black.opacity(0.35))
                        .lineLimit(1)
                }

                if let popScore, popScore > 0 {
                    Text("Pop Score · \(popScore)")
                        .font(.custom("ZalandoSansSemiExpanded-Regular", size: 16))
                        .fontWeight(.semibold)
                        .foregroundStyle(.black.opacity(0.55))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.black.opacity(0.06)))
                        .padding(.top, 16)
                }

                Spacer()

                // The Host presents the CTA — full figure, full strength,
                // his computed shadow doing the grounding.
                HStack(alignment: .bottom, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("download now")
                            .font(.custom("ZalandoSansExpanded-Regular", size: 17))
                            .fontWeight(.heavy)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(.black))
                        Text("onboardapp.org")
                            .font(.custom("ZalandoSansSemiExpanded-Regular", size: 13))
                            .fontWeight(.medium)
                            .foregroundStyle(.black.opacity(0.4))
                            .padding(.leading, 4)
                    }
                    Spacer(minLength: 0)
                    HostFigure(eye: .happy)
                        .frame(width: 86)
                        .padding(.trailing, 2)
                }
                .padding(.top, 12)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    @ViewBuilder
    private var avatarCircle: some View {
        if let avatar {
            Image(uiImage: avatar)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 1))
        } else {
            // Monogram fallback — accent ground, white initial.
            ZStack {
                Circle().fill(accent)
                Text(String(handle.prefix(1)).uppercased())
                    .font(.custom("ZalandoSansExpanded-Regular", size: 20))
                    .fontWeight(.heavy)
                    .foregroundStyle(.white)
            }
        }
    }
}

/// Renders the card to a shareable UIImage: fetches the avatar (cache-warm
/// via the profile screen), derives the accent, renders @3x → 1080×1920.
@MainActor
enum ProfileShareCardRenderer {
    static func render(profile: Profile, popScore: Int?) async -> UIImage? {
        var accent = Color(white: 0.35) // the "darker gray" fallback
        var avatar: UIImage?
        if let urlString = profile.avatarUrl,
           let url = URL(string: urlString),
           let response = try? await ImagePipeline.shared.imageTask(with: url).response {
            avatar = response.image
            if let prominent = response.image.prominentColor {
                accent = Color(uiColor: prominent)
            }
        }
        let renderer = ImageRenderer(content: ProfileShareCard(
            handle: profile.handle,
            popScore: popScore,
            accent: accent,
            avatar: avatar
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
