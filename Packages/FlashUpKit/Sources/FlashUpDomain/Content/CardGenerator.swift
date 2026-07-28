import Foundation

/// Derives the cards a note produces (spec §A3.1).
///
/// Pure: it computes template keys and rendered text, and assigns no identity. Attaching
/// stable uuids per (note, templateKey) is the reconciler's job in the data layer.
public enum CardGenerator {
    public static let forwardKey = "forward"
    public static let reverseKey = "reverse"
    public static let clozeKeyPrefix = "cloze:"

    public static func clozeKey(group: Int) -> String {
        "\(clozeKeyPrefix)\(group)"
    }

    public static func generate(_ note: Note) -> [CardTemplate] {
        switch note.type {
        case .basic:
            return [CardTemplate(templateKey: forwardKey, front: note.front, back: note.back ?? "")]

        case .reversed:
            let back = note.back ?? ""
            return [
                CardTemplate(templateKey: forwardKey, front: note.front, back: back),
                CardTemplate(templateKey: reverseKey, front: back, back: note.front)
            ]

        case .cloze:
            // Ascending group order keeps generation stable, so two devices computing the
            // same note produce the same list.
            return ClozeParser.groups(in: note.front).sorted().map { group in
                CardTemplate(
                    templateKey: clozeKey(group: group),
                    front: ClozeParser.render(note.front, maskGroup: group),
                    back: ClozeParser.render(note.front, maskGroup: nil),
                    extra: note.back?.isEmpty == false ? note.back : nil,
                    cloze: ClozeContext(source: note.front, group: group)
                )
            }
        }
    }

}
