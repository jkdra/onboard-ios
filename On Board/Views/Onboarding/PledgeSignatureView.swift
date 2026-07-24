//
//  PledgeSignatureView.swift
//  On Board
//
//  Second screen of the admission cover: every member signs the same pledge
//  before stepping onto the board. The draw-to-sign canvas is adapted from
//  ConfirmSignView in the old demonstrate app (quad-curve midpoint smoothing),
//  with a cleaner stroke model.
//
//  The signature itself never leaves the device — it's a moment of intent,
//  not a document. TODO(launch): persist a pledge-acceptance timestamp
//  server-side when this ships to live users, so the pledge survives an
//  app kill between admission and signing.
//

import SwiftUI

private struct SignatureStroke {
    var points: [CGPoint] = []
}

struct PledgeSignatureView: View {
    /// Called when the user signs — the parent dismisses the whole cover.
    let onSigned: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var strokes: [SignatureStroke] = []
    @State private var currentStroke = SignatureStroke()
    /// Latches on the first sign tap so a rapid double-tap can't fire
    /// `onSigned()` (and the parent's `dismiss()`) twice.
    @State private var hasSigned = false
    /// Flips true on appear to drive the pledges' staggered fade-in-up.
    @State private var pledgesRevealed = false

    private var hasSignature: Bool {
        strokes.contains { $0.points.count > 1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Text scrolls if it ever needs to; the sign box + CTA stay pinned
            // to the bottom of the screen with breathing room above them.
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("One more thing.")
                        .fontStyle(.largeTitle)
                        .fontWeight(.heavy)

                    Text("Every member makes the same promise. Sign below to pledge:")
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 18) {
                        pledgeItem(
                            index: 0,
                            icon: "person.3.fill",
                            lead: "Keep the board welcoming",
                            detail: "No harassment, hate, or tearing people down."
                        )
                        pledgeItem(
                            index: 1,
                            icon: "hand.raised.fill",
                            lead: "Keep it safe",
                            detail: "Nothing crude, harmful, or illegal."
                        )
                        pledgeItem(
                            index: 2,
                            icon: "doc.text.fill",
                            lead: "Play by the rules",
                            detail: "I agree to the Terms of Service & Privacy Policy."
                        )
                    }
                    .padding(.top, 2)
                    .onAppear { pledgesRevealed = true }

                    HStack(spacing: 6) {
                        NavigationLink("Terms of Service") { PolicyView(type: .terms) }
                        Text("·").foregroundStyle(.secondary)
                        NavigationLink("Privacy Policy") { PolicyView(type: .privacy) }
                    }
                    .fontStyle(.footnote)
                }
                .safeAreaPadding(.horizontal)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 14) {
                signatureCanvas

                Button {
                    guard !hasSigned else { return }
                    hasSigned = true
                    onSigned()
                } label: {
                    Label("Sign & step on board", systemImage: "signature")
                }
                .buttonStyle(.boardPrimary)
                .tint(.primary)
                .disabled(!hasSignature || hasSigned)
            }
            .safeAreaPadding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background(Color(.systemBackground))
        .navigationTitle("The Pledge")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    /// A prominent pledge row: a glass-chip icon that speaks to the promise,
    /// a bold lead, and a quieter detail line. Rows fade in and rise into place
    /// one after another (`index` staggers the delay) as the screen arrives.
    private func pledgeItem(index: Int, icon: String, lead: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background {
                    GlassBackground(
                        shape: Circle(),
                        fallback: AnyShapeStyle(.thinMaterial)
                    )
                    Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(lead)
                    .fontStyle(.subheadline)
                    .fontWeight(.bold)
                Text(detail)
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(pledgesRevealed ? 1 : 0)
        .offset(y: pledgesRevealed ? 0 : 14)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.45).delay(0.1 + Double(index) * 0.12),
            value: pledgesRevealed
        )
    }

    // MARK: - Signature canvas

    private var signatureCanvas: some View {
        Canvas { context, _ in
            for stroke in strokes + [currentStroke] {
                guard stroke.points.count > 1 else { continue }
                var path = Path()
                let points = stroke.points
                path.move(to: points[0])

                // Quadratic curves through midpoints, using each previous
                // point as the control — the smoothing from the original
                // ConfirmSignView.
                var previous = points[0]
                for index in 1..<points.count {
                    let current = points[index]
                    let mid = CGPoint(x: (previous.x + current.x) / 2,
                                      y: (previous.y + current.y) / 2)
                    if index == 1 {
                        path.addLine(to: mid)
                    } else {
                        path.addQuadCurve(to: mid, control: previous)
                    }
                    previous = current
                }
                path.addLine(to: points[points.count - 1])

                context.stroke(
                    path,
                    with: .color(.primary),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(height: 170)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    currentStroke.points.append(value.location)
                }
                .onEnded { _ in
                    strokes.append(currentStroke)
                    currentStroke = SignatureStroke()
                }
        )
        .background {
            // Same glass material as the app's text fields — this reads as a
            // "you can touch this" surface, not a flat panel.
            GlassBackground(
                shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                fallback: AnyShapeStyle(.thinMaterial)
            )
            // Sign-here rule sits behind the drawing layer, so the ink lands
            // on top of the line the way it would on paper.
            signatureLine
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1.5)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                strokes = []
                currentStroke = SignatureStroke()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .fontStyle(.headline)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
            .opacity(hasSignature ? 1 : 0)
            .disabled(!hasSignature)
            .accessibilityLabel("Clear signature")
        }
        .accessibilityIdentifier("SignatureCanvas")
        .accessibilityLabel("Signature area")
        .accessibilityHint("Draw your signature to sign the pledge")
    }

    /// The sign-here rule near the bottom of the box: a rounded-tip line with
    /// a bold cross sitting just ABOVE it at the leading edge, the way a paper
    /// form marks where a signature lands. The rule stays under the ink, like
    /// pen on paper.
    private var signatureLine: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(.leading, 2)
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 2)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }
}

#Preview {
    NavigationStack {
        PledgeSignatureView {}
    }
}
