import Foundation

/// The kinds of pet. Customize's species arrows cycle through these, shown by their icons.
enum PetSpecies: String, CaseIterable {
    case cat, dog

    /// The small pixel-art icon in the app bundle, without ".png".
    var iconName: String { "\(rawValue) icon" }

    /// This species' patterns, in the order Customize's pattern arrows cycle through them.
    var characters: [PetCharacter] { PetCharacter.all.filter { $0.species == self } }
}

/// A pet's look: its pixel-art image and what its recolorable parts are called.
///
/// In the image, pure red, green and blue pixels are the three recolorable parts (slots 0, 1, 2);
/// every other color is fixed. A part the image doesn't use is simply hidden in Customize.
/// Every image is drawn on the same 24×24 grid, with the head in the same place.
/// To add a character, add its PNG to Resources and an entry to `all`.
struct PetCharacter: Identifiable, Equatable {
    let id: String
    let species: PetSpecies
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

    /// Dogs have black eyes, so their blue part is the ears (and the beagle's saddle patch).
    private static let dogParts = ["Body", "Accents", "Ears"]
    private static let dogKeys = ["main", "secondary", "ears"]

    static let dog = PetCharacter(id: "dog", species: .dog, imageName: "dog default", partNames: dogParts, partKeys: dogKeys)
    static let beagle = PetCharacter(id: "beagle", species: .dog, imageName: "dog beagle", partNames: dogParts, partKeys: dogKeys)

    static let all = [tuxedo, calico, colorpoint, tortie, van, dog, beagle]

    private static func cat(_ id: String) -> PetCharacter {
        PetCharacter(id: id, species: .cat, imageName: "cat \(id)", partNames: catParts, partKeys: catKeys)
    }

    static func withID(_ id: String?) -> PetCharacter? {
        all.first { $0.id == id }
    }
}
