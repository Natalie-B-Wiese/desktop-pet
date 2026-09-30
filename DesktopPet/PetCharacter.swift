import Foundation

/// A pet's look: its pixel-art image and what its recolorable parts are called.
///
/// In the image, pure red, green and blue pixels are the three recolorable parts (slots 0, 1, 2);
/// every other color is fixed. A part the image doesn't use is simply hidden in Customize.
/// Every image is drawn on the same 24×24 grid, with the head in the same place.
/// To add a character (say, a dog), add its PNG to Resources and an entry to `all`.
struct PetCharacter: Identifiable, Equatable {
    let id: String
    /// The PNG's name in the app bundle, without ".png".
    let imageName: String
    /// Names for the red, green and blue parts, in that order.
    let partNames: [String]
    /// Where each part's color is saved. Characters that share a part (like Body) share its color,
    /// so switching between them keeps the colors you picked.
    let partKeys: [String]

    private static let catParts = ["Body", "Accents", "Eyes"]
    private static let catKeys = ["main", "secondary", "detail"]

    static let tuxedo = PetCharacter(id: "tuxedo", imageName: "cat tuxedo", partNames: catParts, partKeys: catKeys)
    static let calico = PetCharacter(id: "calico", imageName: "cat calico", partNames: catParts, partKeys: catKeys)
    static let colorpoint = PetCharacter(id: "colorpoint", imageName: "cat colorpoint", partNames: catParts, partKeys: catKeys)
    static let tortie = PetCharacter(id: "tortie", imageName: "cat tortie", partNames: catParts, partKeys: catKeys)
    /// An odd-eyed van: each eye gets its own color.
    static let van = PetCharacter(
        id: "van", imageName: "cat van",
        partNames: ["Body", "Eye1", "Eye2"], partKeys: ["main", "eye1", "eye2"]
    )

    /// In the order Customize's arrows cycle through them.
    static let all = [tuxedo, calico, colorpoint, tortie, van]

    static func withID(_ id: String?) -> PetCharacter? {
        all.first { $0.id == id }
    }
}
