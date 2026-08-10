import SwiftUI
import Nuke

// The profile share card — a story-ready 9:16 composition (rendered at
// 1080×1920 via ImageRenderer @3x) built for the growth loop: white ground,
// monochrome brand, ONE accent stolen from the user's avatar, the avatar
// INLINE in the leading-aligned lock-up (a glyph in the sentence — the
// brand's alignment), and The Host as the composition's terminal
// character: large, bled off the bottom-right corner, facing left so his
// gaze returns into the card. Three hierarchy tiers, hard cap (hero
// lock-up / Pop Score support line / baseline signature) — and no
// button-shaped CTA: a button on a static image is a false affordance;
// the reference share cards (Wrapped, Replay, Strava) all sign off with
// a plain text lockup. Shared as an IMAGE; the link is the set text.

struct ProfileShareCard: View {
    let handle: String
    /// Per-reaction Pop Score distribution — rendered as the app's own
    /// segmented monochrome bar + emoji legend (PopScoreView's language at
    /// card scale). Empty (or all-zero) hides the block.
    let popScore: [Reaction: Int]
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
                // Fixed top interval pins the hero in the upper third — a
                // flexible spacer let it drift to dead center.
                Spacer().frame(height: 96)

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

                if !nonZeroReactions.isEmpty {
                    popScoreBlock
                        .padding(.top, 18)
                }

                // The gap between the hero block and the signature is the
                // card's LARGEST interval — shaped whitespace, not trapped.
                Spacer()

                // Tier-3 signature: one baseline, no button chrome (a
                // button shape on a static image is a false affordance no
                // reference share card uses — the URL as set text carries
                // the CTA, Wrapped-style).
                // Signature trails bottom-right — the deliberate counter-
                // edge to the leading axis — while The Host holds the
                // bottom-left corner in his natural stance.
                HStack {
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("download now")
                            .font(.custom("ZalandoSansExpanded-Regular", size: 14))
                            .fontWeight(.heavy)
                            .foregroundStyle(.black)
                        Text("onboardapp.org")
                            .font(.custom("ZalandoSansSemiExpanded-Regular", size: 13))
                            .fontWeight(.medium)
                            .foregroundStyle(.black.opacity(0.45))
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)

            // The Host as the Z-pattern's terminal character — promoted to
            // compositional imagery (Duolingo's mascot pattern): large,
            // bled off the bottom-right corner so the frame holds him, and
            // FACING LEFT so his gaze returns the eye into the card.
            // Bleed calibrated so BOTH identity features survive the crop
            // (eye top-right of the mirrored figure, notch on his left,
            // pointing into the card) — v4 cropped him to fragments.
            // Bottom-LEFT terminal, natural right-facing stance — his gaze
            // and notch point into the card from the left, no mirror needed.
            HostFigure(eye: .happy)
                .frame(width: 122)
                .offset(x: -2, y: 30)
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    /// Reactions with votes, in the canonical order.
    private var nonZeroReactions: [Reaction] {
        Reaction.allCases.filter { (popScore[$0] ?? 0) > 0 }
    }

    /// The app's Pop Score distribution at card scale: label, segmented
    /// monochrome capsule bar (same ink ramp as PopScoreView), emoji legend.
    /// One grouped support unit — tier 2, quiet.
    private var popScoreBlock: some View {
        let total = max(1, popScore.values.reduce(0, +))
        let barWidth: CGFloat = 190
        return VStack(alignment: .leading, spacing: 7) {
            Text("Pop Score")
                .font(.custom("ZalandoSansSemiExpanded-Regular", size: 13))
                .fontWeight(.semibold)
                .foregroundStyle(.black.opacity(0.45))
            HStack(spacing: 2) {
                ForEach(nonZeroReactions, id: \.self) { reaction in
                    Rectangle()
                        .fill(segmentInk(for: reaction))
                        .frame(width: max(3, barWidth * CGFloat(popScore[reaction] ?? 0) / CGFloat(total)))
                }
            }
            .frame(width: barWidth, height: 8)
            .clipShape(Capsule())
            HStack(spacing: 14) {
                ForEach(nonZeroReactions, id: \.self) { reaction in
                    HStack(spacing: 4) {
                        Text(reaction.emoji)
                            .font(.system(size: 13))
                        Text("\(popScore[reaction] ?? 0)")
                            .font(.custom("ZalandoSansSemiExpanded-Regular", size: 13))
                            .fontWeight(.semibold)
                            .foregroundStyle(.black.opacity(0.5))
                    }
                }
            }
        }
    }

    /// PopScoreView's monochrome ramp, in explicit ink (the card is always
    /// on white; hierarchy styles would need an environment).
    private func segmentInk(for reaction: Reaction) -> Color {
        switch reaction {
        case .like: .black
        case .dislike: .black.opacity(0.55)
        case .laugh: .black.opacity(0.32)
        case .hug: .black.opacity(0.16)
        }
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
    static func render(profile: Profile, popScore: [Reaction: Int]) async -> UIImage? {
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
    ProfileShareCard(handle: "maya.c", popScore: [.like: 89, .laugh: 12, .hug: 21], accent: Color(red: 0.72, green: 0.31, blue: 0.18))
}

#Preview("No pop score, neutral") {
    ProfileShareCard(handle: "leokp", popScore: [:], accent: Color(white: 0.35))
}
