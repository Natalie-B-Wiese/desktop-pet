import Foundation

/// The kinds of pet. Customize's species arrows cycle through these, shown by their icons.
enum PetSpecies: String, CaseIterable {
    case cat, dog

    /// The small pixel-art icon in the app bundle, without ".png".
    var iconName: String { "\(rawValue) icon" }

    /// Every shape and pattern of this species, shape by shape, each in Customize's cycle order.
    var characters: [PetCharacter] { PetCharacter.all.filter { $0.species == self } }

    /// This species' body shapes, in the order Customize's shape arrows cycle through them.
    var shapes: [String] {
        characters.map(\.shape).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// The patterns drawn in one shape, in the order Customize's pattern arrows cycle through them.
    func characters(shape: String) -> [PetCharacter] { characters.filter { $0.shape == shape } }
}

/// A pet's look: its pixel-art image and what its recolorable parts are called.
/// Each one is a shape (the outline, like a dog's ears and tail) drawn in a pattern (the markings).
///
/// In the image, pure red, green and blue pixels are the three recolorable parts (slots 0, 1, 2);
/// every other color is fixed. A part the image doesn't use is simply hidden in Customize.
/// Every image is drawn on the same 24×24 grid, with the head in the same place.
/// To add a character, add its PNG to Resources and an entry to `all`.
struct PetCharacter: Identifiable, Equatable {
    let id: String
    let species: PetSpecies
    /// The body shape, like "up-stub" (ears up, stub tail). Cats have just one.
    var shape = "cat"
    /// The markings, shared across shapes, like "spots". Switching shape keeps the pattern.
    var pattern: String { id.components(separatedBy: ".")[0] }
    /// The PNG's name in the app bundle, without ".png".
    let imageName: String
    /// Names for the red, green and blue parts, in that order.
    let partNames: [String]
    /// Where each part's color is saved. Characters that share a part (like Body) share its color,
    /// so switching between them keeps the colors you picked.
    let partKeys: [String]
    /// The order Customize shows the parts in, as slots (0 red, 1 green, 2 blue).
    var partOrder = [0, 1, 2]

    private static let catParts = ["Body", "Accents", "Eyes"]
    private static let catKeys = ["main", "secondary", "detail"]

    static let tuxedo = cat("tuxedo")
    static let calico = cat("calico")
    static let colorpoint = cat("colorpoint")
    static let tortie = cat("tortie")
    /// An odd-eyed van: each eye gets its own color. The blue eye is on the left of the image,
    /// so it's Eye1 and is listed before the green one, matching the eyes' positions.
    static let van = PetCharacter(
        id: "van", species: .cat, imageName: "cat van",
        partNames: ["Body", "Eye2", "Eye1"], partKeys: ["main", "eye2", "eye1"], partOrder: [0, 2, 1]
    )

    /// Dogs have black eyes, so their blue part is something else: the default dog's ears,
    /// or the spots' patch and the brindle's stripes. These save blue as "ears", so switching
    /// patterns keeps its color.
    private static let dogKeys = ["main", "secondary", "ears"]

    /// Dog shapes, in cycle order: ears down or up, with a long or stub tail. The first is the original dog.
    static let dogShapes = ["down-long", "down-stub", "up-long", "up-stub"]

    /// Each dog pattern in every shape. Images are "dog <shape> <pattern>.png" and IDs "<pattern>.<shape>".
    static let dogs: [PetCharacter] = dogShapes.flatMap { shape in
        [
            dog("dog", image: "default", shape: shape, parts: ["Body", "Accents", "Ears"]),
            dog("spots", shape: shape, parts: markedParts),
            dog("brindle", shape: shape, parts: markedParts),
            // The mask's red is the head and its blue is the body, so blue saves as "main" and is listed
            // first, keeping the body's color when switching from another dog.
            PetCharacter(
                id: "mask.\(shape)", species: .dog, shape: shape, imageName: "dog \(shape) mask",
                partNames: ["Head", "Accents", "Body"], partKeys: ["ears", "secondary", "main"], partOrder: [2, 0, 1]
            ),
        ]
    }

    static let all = [tuxedo, calico, colorpoint, tortie, van] + dogs

    private static let markedParts = ["Body", "Accents", "Markings"]

    private static func dog(_ pattern: String, image: String? = nil, shape: String, parts: [String]) -> PetCharacter {
        PetCharacter(
            id: "\(pattern).\(shape)", species: .dog, shape: shape,
            imageName: "dog \(shape) \(image ?? pattern)", partNames: parts, partKeys: dogKeys
        )
    }

    private static func cat(_ id: String) -> PetCharacter {
        PetCharacter(id: id, species: .cat, imageName: "cat \(id)", partNames: catParts, partKeys: catKeys)
    }

    /// Dogs saved before shapes existed have IDs like "spots"; those are the original "down-long" shape.
    static func withID(_ id: String?) -> PetCharacter? {
        guard let id else { return nil }
        return all.first { $0.id == id } ?? all.first { $0.id == "\(id).\(dogShapes[0])" }
    }
}
